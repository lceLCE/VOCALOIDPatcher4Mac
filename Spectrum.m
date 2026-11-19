#import "UIStrings.h"
#import <Accelerate/Accelerate.h>
#import <AppKit/AppKit.h>
#import <AudioUnit/AudioUnit.h>
#include <stdatomic.h>
#include <stdint.h>

#define VP_RING 8192
static _Atomic(uint32_t) VPSamples[VP_RING][2];
static _Atomic(uint64_t) VPSampleCount;
static _Atomic(bool) VPSpectrumEnabled;
static _Atomic(bool) VPFloat32Output;
static _Atomic(double) VPOutputSampleRate;
static AudioUnit VPOutputUnit;

// The render thread only copies atomic sample bits. FFT and drawing run on the
// main thread.
static OSStatus VPObserveAudio(void *context, AudioUnitRenderActionFlags *flags,
                               const AudioTimeStamp *time, UInt32 bus,
                               UInt32 frames, AudioBufferList *buffers) {
  (void)context;
  (void)time;
  (void)bus;
  if (!atomic_load_explicit(&VPSpectrumEnabled, memory_order_relaxed) ||
      !(*flags & kAudioUnitRenderAction_PostRender) ||
      (*flags & kAudioUnitRenderAction_PostRenderError) || !buffers ||
      !buffers->mNumberBuffers)
    return noErr;
  if (!atomic_load_explicit(&VPFloat32Output, memory_order_relaxed))
    return noErr;
  uint64_t count = atomic_load_explicit(&VPSampleCount, memory_order_relaxed);
  for (UInt32 i = 0; i < frames; i++) {
    float samples[2] = {0, 0};
    UInt32 channelCount = 0;
    for (UInt32 b = 0; b < buffers->mNumberBuffers && channelCount < 2; b++) {
      AudioBuffer buffer = buffers->mBuffers[b];
      UInt32 channels = buffer.mNumberChannels;
      if (!buffer.mData || !channels ||
          i >= buffer.mDataByteSize / (sizeof(float) * channels))
        continue;
      const float *data = buffer.mData;
      for (UInt32 c = 0; c < channels && channelCount < 2; c++) {
        float value = data[i * channels + c];
        samples[channelCount++] = isfinite(value) ? value : 0;
      }
    }
    if (channelCount == 1)
      samples[1] = samples[0];
    for (unsigned channel = 0; channel < 2; channel++) {
      uint32_t bits;
      memcpy(&bits, &samples[channel], sizeof(bits));
      atomic_store_explicit(&VPSamples[(count + i) % VP_RING][channel], bits,
                            memory_order_relaxed);
    }
  }
  atomic_store_explicit(&VPSampleCount, count + frames, memory_order_release);
  return noErr;
}
static OSStatus VPInitializeUnit(AudioUnit unit) {
  OSStatus result = AudioUnitInitialize(unit);
  if (result != noErr)
    return result;
  AudioComponentDescription description = {0};
  AudioComponent component = AudioComponentInstanceGetComponent(unit);
  if (AudioComponentGetDescription(component, &description) != noErr ||
      description.componentType != kAudioUnitType_Output)
    return result;
  AudioStreamBasicDescription format = {0};
  UInt32 size = sizeof(format);
  if (AudioUnitGetProperty(unit, kAudioUnitProperty_StreamFormat,
                           kAudioUnitScope_Input, 0, &format, &size) != noErr)
    return result;
  // Initialization happens while rendering is stopped. The standalone editor
  // has one output device.
  if (VPOutputUnit)
    AudioUnitRemoveRenderNotify(VPOutputUnit, VPObserveAudio, NULL);
  atomic_store(&VPFloat32Output,
               format.mFormatID == kAudioFormatLinearPCM &&
                   (format.mFormatFlags & kAudioFormatFlagIsFloat) &&
                   !(format.mFormatFlags & kAudioFormatFlagIsBigEndian) &&
                   format.mBitsPerChannel == 32);
  atomic_store(&VPOutputSampleRate, format.mSampleRate);
  VPOutputUnit = unit;
  AudioUnitAddRenderNotify(unit, VPObserveAudio, NULL);
  return result;
}
static OSStatus VPUninitializeUnit(AudioUnit unit) {
  if (unit == VPOutputUnit) {
    AudioUnitRemoveRenderNotify(unit, VPObserveAudio, NULL);
    VPOutputUnit = NULL;
  }
  return AudioUnitUninitialize(unit);
}
__attribute__((used)) static struct {
  const void *replacement;
  const void *original;
} VPInterpose[] __attribute__((section("__DATA,__interpose"))) = {
    {(const void *)VPInitializeUnit, (const void *)AudioUnitInitialize},
    {(const void *)VPUninitializeUnit, (const void *)AudioUnitUninitialize}};

@interface VPSpectrumView : NSView
@property NSTimer *timer;
@end
@implementation VPSpectrumView {
  FFTSetup _fft;
  float _window[1024], _real[512], _imag[512], _input[1024], _power[512],
      _channelPower[512];
}
- (instancetype)initWithFrame:(NSRect)rect {
  if ((self = [super initWithFrame:rect])) {
    _fft = vDSP_create_fftsetup(10, kFFTRadix2);
    vDSP_hann_window(_window, 1024, vDSP_HANN_NORM);
    self.timer = [NSTimer scheduledTimerWithTimeInterval:1.0 / 30
                                                  target:self
                                                selector:@selector(refresh:)
                                                userInfo:nil
                                                 repeats:YES];
  }
  return self;
}
- (void)refresh:(id)sender {
  (void)sender;
  if (self.window.visible)
    self.needsDisplay = YES;
}
- (void)dealloc {
  vDSP_destroy_fftsetup(_fft);
}
- (void)drawRect:(NSRect)dirty {
  (void)dirty;
  [[NSColor colorWithWhite:0.08 alpha:1] setFill];
  NSRectFill(self.bounds);
  uint64_t count = atomic_load_explicit(&VPSampleCount, memory_order_acquire);
  if (count < 1024) {
    [VPUIString(@"播放工程后显示编辑器输出频谱")
           drawAtPoint:NSMakePoint(12, 12)
        withAttributes:@{
          NSForegroundColorAttributeName : NSColor.secondaryLabelColor
        }];
    return;
  }
  // Combine channel power after FFT, preserving opposite-phase stereo content.
  for (unsigned channel = 0; channel < 2; channel++) {
    for (unsigned i = 0; i < 1024; i++) {
      uint32_t bits = atomic_load_explicit(
          &VPSamples[(count - 1024 + i) % VP_RING][channel],
          memory_order_relaxed);
      memcpy(&_input[i], &bits, sizeof(bits));
    }
    vDSP_vmul(_input, 1, _window, 1, _input, 1, 1024);
    DSPSplitComplex split = {_real, _imag};
    vDSP_ctoz((DSPComplex *)_input, 2, &split, 1, 512);
    vDSP_fft_zrip(_fft, &split, 1, 10, FFT_FORWARD);
    _imag[0] = 0;
    vDSP_zvmags(&split, 1, _channelPower, 1, 512);
    for (unsigned bin = 0; bin < 512; bin++)
      _power[bin] = channel ? (_power[bin] + _channelPower[bin]) * 0.5f
                            : _channelPower[bin];
  }
  double sampleRate = atomic_load(&VPOutputSampleRate);
  if (!isfinite(sampleRate) || sampleRate <= 0)
    sampleRate = 44100;
  for (int band = 0; band < 32; band++) {
    double low = 30 * pow(20000.0 / 30, band / 32.0),
           high = 30 * pow(20000.0 / 30, (band + 1) / 32.0);
    unsigned begin = MAX(1, (unsigned)(low * 1024 / sampleRate)),
             end =
                 MIN(511, MAX(begin + 1, (unsigned)(high * 1024 / sampleRate)));
    float peak = 0;
    for (unsigned bin = begin; bin < end; bin++)
      peak = MAX(peak, _power[bin]);
    double db = 10 * log10(MAX(1e-12, peak / (1024.0 * 1024))),
           level = MAX(0, MIN(1, (db + 80) / 80));
    CGFloat width = (self.bounds.size.width - 24) / 32;
    [[NSColor colorWithCalibratedRed:0.15 green:0.65 blue:0.9 alpha:1] setFill];
    NSRectFill(NSMakeRect(12 + band * width, 28, width - 2,
                          level * (self.bounds.size.height - 42)));
  }
  NSDictionary *axisAttributes = @{
    NSForegroundColorAttributeName : NSColor.secondaryLabelColor,
    NSFontAttributeName : [NSFont systemFontOfSize:10]
  };
  [@"30 Hz" drawAtPoint:NSMakePoint(12, 9) withAttributes:axisAttributes];
  CGFloat middle =
      12 + (self.bounds.size.width - 24) * log(1000.0 / 30) / log(20000.0 / 30);
  [@"1 kHz" drawAtPoint:NSMakePoint(middle - 14, 9)
         withAttributes:axisAttributes];
  [@"20 kHz" drawAtPoint:NSMakePoint(self.bounds.size.width - 48, 9)
          withAttributes:axisAttributes];
}
@end
@interface VPSpectrumController : NSObject <NSWindowDelegate>
@property NSPanel *panel;
@property NSMenuItem *menuItem;
@end
@implementation VPSpectrumController
- (void)windowWillClose:(NSNotification *)notification {
  (void)notification;
  atomic_store(&VPSpectrumEnabled, false);
  self.menuItem.state = NSControlStateValueOff;
}
- (void)toggle:(NSMenuItem *)sender {
  self.menuItem = sender;
  if (self.panel.visible) {
    [self.panel orderOut:nil];
    atomic_store(&VPSpectrumEnabled, false);
    sender.state = NSControlStateValueOff;
    return;
  }
  if (!self.panel) {
    self.panel =
        [[NSPanel alloc] initWithContentRect:NSMakeRect(200, 200, 480, 220)
                                   styleMask:NSWindowStyleMaskTitled |
                                             NSWindowStyleMaskClosable |
                                             NSWindowStyleMaskResizable
                                     backing:NSBackingStoreBuffered
                                       defer:NO];
    self.panel.title = VPUIString(@"VOCALOID Patcher · 频谱");
    self.panel.contentView =
        [[VPSpectrumView alloc] initWithFrame:NSMakeRect(0, 0, 480, 220)];
    self.panel.releasedWhenClosed = NO;
    self.panel.delegate = self;
    self.panel.contentMinSize = NSMakeSize(300, 140);
  }
  atomic_store(&VPSpectrumEnabled, true);
  sender.state = NSControlStateValueOn;
  [self.panel makeKeyAndOrderFront:nil];
}
@end
NSMenuItem *installSpectrum(void) {
  static VPSpectrumController *controller;
  controller = [VPSpectrumController new];
  NSMenuItem *item =
      [[NSMenuItem alloc] initWithTitle:VPUIString(@"实时输出频谱")
                                 action:@selector(toggle:)
                          keyEquivalent:@""];
  item.target = controller;
  return item;
}
