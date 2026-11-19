#import "Spectrum.m"
NSString *VPTranslateStaticUIString(NSString *text) { return text; }
#include <assert.h>

int main(void) {
  atomic_store(&VPSpectrumEnabled, true);
  atomic_store(&VPFloat32Output, true);
  float left[4] = {0, 0, 0, 0}, right[4] = {1, 0.5, -1, 0};
  struct {
    UInt32 count;
    AudioBuffer buffers[2];
  } stereo = {2, {{1, sizeof(left), left}, {1, sizeof(right), right}}};
  AudioUnitRenderActionFlags flags = kAudioUnitRenderAction_PostRender;
  assert(VPObserveAudio(NULL, &flags, NULL, 0, 4, (AudioBufferList *)&stereo) ==
         noErr);
  assert(atomic_load(&VPSampleCount) == 4);
  for (unsigned i = 0; i < 4; i++) {
    uint32_t bits = atomic_load(&VPSamples[i][1]);
    float actual;
    memcpy(&actual, &bits, sizeof(actual));
    assert(fabsf(actual - right[i]) < 0.00001f);
  }
  left[0] = 1;
  right[0] = -1;
  VPObserveAudio(NULL, &flags, NULL, 0, 1, (AudioBufferList *)&stereo);
  uint32_t a = atomic_load(&VPSamples[4][0]), b = atomic_load(&VPSamples[4][1]);
  float capturedLeft, capturedRight;
  memcpy(&capturedLeft, &a, 4);
  memcpy(&capturedRight, &b, 4);
  assert(capturedLeft == 1 && capturedRight == -1);
  flags = kAudioUnitRenderAction_PreRender;
  VPObserveAudio(NULL, &flags, NULL, 0, 4, (AudioBufferList *)&stereo);
  assert(atomic_load(&VPSampleCount) == 5);
  atomic_store(&VPSpectrumEnabled, false);
  flags = kAudioUnitRenderAction_PostRender;
  VPObserveAudio(NULL, &flags, NULL, 0, 4, (AudioBufferList *)&stereo);
  assert(atomic_load(&VPSampleCount) == 5);
  puts("PASS stereo-right and opposite-phase capture, pre-render filtering, "
       "disabled observer");
  return 0;
}
