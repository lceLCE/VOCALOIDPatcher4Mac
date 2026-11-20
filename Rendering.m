#import "Compatibility.h"
#import "UIStrings.h"
#import <AppKit/AppKit.h>
#import <AVFoundation/AVFoundation.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <objc/message.h>
#import <mach-o/dyld.h>
#import <UniformTypeIdentifiers/UniformTypeIdentifiers.h>
#include <stdint.h>
extern NSDocument *VPCurrentDocument(void) __attribute__((weak_import));

static NSDocument *VPArtSelectDocument(NSDocument *current, NSDocument *windowDocument, NSArray *documents) {
    for (id candidate in @[current ?: NSNull.null, windowDocument ?: NSNull.null, documents.lastObject ?: NSNull.null]) {
        if ([NSStringFromClass([candidate class]) isEqualToString:@"VOCALOID7_Editor.VEDocument"]) return candidate;
    }
    return nil;
}

static NSDocument *VPArtDocument(void) {
    NSDocument *shared = VPCurrentDocument ? VPCurrentDocument() : nil;
    if ([NSStringFromClass(shared.class) isEqualToString:@"VOCALOID7_Editor.VEDocument"]) return shared;
    NSDocumentController *controller = NSDocumentController.sharedDocumentController;
    return VPArtSelectDocument(controller.currentDocument, NSApp.mainWindow.windowController.document, controller.documents);
}

static NSDocument *VPDrawDocument(NSView *view) {
    NSDocument *owner = view.window.windowController.document;
    if ([NSStringFromClass(owner.class) isEqualToString:@"VOCALOID7_Editor.VEDocument"]) return owner;
    return VPArtDocument();
}

// These object ivars were observed in the pinned editor. The executable digest
// gate prevents reading a layout from a different build with the same version.
static id VPArtObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    void *pointer = NULL;
    memcpy(&pointer, (__bridge const void *)object + ivar_getOffset(ivar), sizeof(pointer));
    return (__bridge id)pointer;
}

BOOL VPSupportedEditor(void) {
    NSString *version = [NSBundle.mainBundle objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
    if (![version isEqualToString:VP_EDITOR_VERSION]) return NO;
    NSData *bytes = [NSData dataWithContentsOfFile:VPActualExecutablePath()
                                         options:NSDataReadingMappedIfSafe error:nil];
    if (!bytes || bytes.length > UINT_MAX) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++) [hex appendFormat:@"%02x", digest[index]];
    return [hex isEqualToString:VP_EDITOR_SHA256];
}

static id VPArtTrack(void) {
    NSDocument *document = VPArtDocument();
    id model = VPArtObjectIvar(document, "sequence");
    return VPArtObjectIvar(model, "activeTrack");
}

static NSString *VPArtBankID(void) {
    id track = VPArtTrack();
    SEL selector = NSSelectorFromString(@"voiceBankID");
    if (![track respondsToSelector:selector]) return nil;
    id bank = ((id (*)(id, SEL))objc_msgSend)(track, selector);
    return [bank isKindOfClass:NSString.class] ? bank : nil;
}

static NSView *VPArtPianoView(NSView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"VOCALOID7_Editor.VEPianoRollBodyView"]) return view;
    for (NSView *child in view.subviews) {
        NSView *found = VPArtPianoView(child);
        if (found) return found;
    }
    return nil;
}

typedef struct { int64_t value; } VPDrawTick;
@protocol VPDrawNote
- (NSInteger)noteNumber;
- (VPDrawTick)absPosTick;
- (VPDrawTick)absEndTick;
- (NSString *)lyric;
- (NSString *)phonemes;
@end
@protocol VPDrawPart <NSObject>
- (NSUInteger)numNote;
- (id<VPDrawNote>)note:(NSUInteger)index;
- (VPDrawTick)absPosTick;
- (void *)unwrap;
@end
@protocol VPDrawTrack
- (NSUInteger)numPart;
- (id)part:(NSUInteger)index;
- (BOOL)isChannelMute;
@end
@protocol VPDrawSequence <NSObject>
- (NSUInteger)numTrack;
- (id)track:(NSUInteger)index;
@end

#if defined(__arm64__)
// Disassembly of the hash-pinned function establishes x0 = note, x1/x2 =
// absolute ticks, x20 = self, and d0..d3 = CGRect. swift_context expresses that
// ABI directly without interpreting a Swift value or vtable layout.
typedef CGRect (*VPDrawRectFunction)(
    id note, int64_t begin, int64_t end, id context __attribute__((swift_context))) __attribute__((swiftcall));
static VPDrawRectFunction VPDrawRect;
// localXFrom(tick:) uses x0 for tick, x20 for self, and d0 for the result.
typedef CGFloat (*VPDrawXFunction)(int64_t tick, id context __attribute__((swift_context))) __attribute__((swiftcall));
static VPDrawXFunction VPDrawX;
#endif
static void (*VPOriginalDraw)(id, SEL, NSRect);
static BOOL VPShowPitchNames;
static BOOL VPShowGhostNotes;
static BOOL VPSkipMutedGhosts = YES;
static BOOL VPCenteredLyrics;
static BOOL VPRoundedNotes;
static _Thread_local BOOL VPNativeDrawScope;
static NSArray<NSDictionary *> *VPDrawLabels;
static NSHashTable<NSView *> *VPArtSuppressedViews;
static void (*VPOriginalNativeArtDraw)(id, SEL, NSRect);
static intptr_t VPDrawSlide;
extern void VPWaveBeginNativeDraw(NSView *view) __attribute__((weak_import));
extern void VPWaveEndNativeDraw(void) __attribute__((weak_import));
extern NSString *VPTranslateStaticUIString(NSString *text) __attribute__((weak_import));
static _Thread_local BOOL VPStaticTabDrawScope;
static void (*VPOriginalBrowserTabDraw)(id, SEL, NSRect);
static void (*VPOriginalTabDraw)(id, SEL, NSRect);
static BOOL VPDrawTestLogging;
static NSString *VPDrawTestProjectPath;
static BOOL VPCenteredPathLogged[4];

static void VPDrawNativeArt(NSView *view, SEL selector, NSRect dirty) {
    if (![VPArtSuppressedViews containsObject:view]) VPOriginalNativeArtDraw(view, selector, dirty);
}

static void VPDrawBrowserTabs(NSView *view, SEL selector, NSRect dirty) {
    BOOL previous = VPStaticTabDrawScope;
    VPStaticTabDrawScope = YES;
    @try { VPOriginalBrowserTabDraw(view, selector, dirty); }
    @finally { VPStaticTabDrawScope = previous; }
}
static void VPDrawTabs(NSView *view, SEL selector, NSRect dirty) {
    BOOL previous = VPStaticTabDrawScope;
    VPStaticTabDrawScope = YES;
    @try { VPOriginalTabDraw(view, selector, dirty); }
    @finally { VPStaticTabDrawScope = previous; }
}

static IMP VPReplaceOwnedDraw(Class viewClass, IMP replacement) {
    unsigned count = 0;
    Method *methods = class_copyMethodList(viewClass, &count);
    IMP original = NULL;
    for (unsigned index = 0; index < count; index++) {
        Method method = methods[index];
        if (method_getName(method) == @selector(drawRect:) &&
            strcmp(method_getTypeEncoding(method), "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16") == 0) {
            original = method_setImplementation(method, replacement);
            break;
        }
    }
    free(methods);
    return original;
}

static NSString *VPTranslatedTabString(NSString *text) {
    if (VPStaticTabDrawScope && !VPNativeDrawScope && VPTranslateStaticUIString)
        return VPTranslateStaticUIString(text) ?: text;
    return text;
}
static NSAttributedString *VPTranslatedTabAttributedString(NSAttributedString *text) {
    if (!VPStaticTabDrawScope || VPNativeDrawScope || !VPTranslateStaticUIString) return text;
    NSString *translated = VPTranslatedTabString(text.string);
    if ([translated isEqualToString:text.string]) return text;
    NSMutableAttributedString *result = [text mutableCopy];
    [result replaceCharactersInRange:NSMakeRange(0, result.length) withString:translated];
    return result;
}

static BOOL VPStoredBoolean(NSDictionary *settings, NSString *key, BOOL fallback) {
    id value = settings[key];
    return [value isKindOfClass:NSNumber.class] && CFGetTypeID((__bridge CFTypeRef)value) == CFBooleanGetTypeID()
        ? [value boolValue] : fallback;
}

static void (*VPStringPointOriginal)(id, SEL, NSPoint, NSDictionary *);
static void (*VPStringRectOriginal)(id, SEL, NSRect, NSDictionary *);
static void (*VPAttributedPointOriginal)(id, SEL, NSPoint);
static void (*VPAttributedRectOriginal)(id, SEL, NSRect);

static void VPLogCentered(NSUInteger path, NSString *text, uintptr_t caller, CGFloat originalY,
                          NSRect noteRect, CGFloat textHeight, BOOL adjusted, CGFloat resultY) {
    if (!VPDrawTestLogging || !VPNativeDrawScope || !VPCenteredLyrics || VPCenteredPathLogged[path]) return;
    NSString *currentPath = VPArtDocument().fileURL.path;
    if (![[currentPath stringByResolvingSymlinksInPath] isEqualToString:VPDrawTestProjectPath]) return;
    VPCenteredPathLogged[path] = YES;
    NSArray *names = @[@"NSStringPoint", @"NSStringRect", @"AttributedPoint", @"AttributedRect"];
    NSLog(@"VP_CENTER_TEST path=%@ returnPC=0x%llx text=%@ originalY=%.2f noteY=%.2f noteHeight=%.2f textHeight=%.2f adjusted=%d resultY=%.2f",
          names[path], (unsigned long long)(caller-VPDrawSlide), text, originalY,
          noteRect.origin.y, noteRect.size.height, textHeight, adjusted, resultY);
}

static NSRect VPMatchingTextRect(NSString *text, NSPoint point, uintptr_t returnAddress) {
    if (!VPNativeDrawScope || !VPCenteredLyrics || !text.length) return NSZeroRect;
    uintptr_t caller = returnAddress-VPDrawSlide;
    // These two call sites are NSString drawInRect:withAttributes: inside the
    // native lyric-only and lyric/phoneme paths. Their text may include the
    // editor's own phoneme punctuation, so geometry identifies the note there.
    BOOL nativeLyric = caller == VP_PC_LYRIC_POINT || caller == VP_PC_LYRIC_RECT;
    for (NSDictionary *entry in VPDrawLabels) {
        if (!nativeLyric && ![text isEqualToString:entry[@"lyric"]] && ![text isEqualToString:entry[@"phonemes"]]) continue;
        NSRect rect = [entry[@"rect"] rectValue];
        if (point.x >= NSMinX(rect)-2 && point.x <= NSMaxX(rect)+2 &&
            point.y >= NSMinY(rect)-rect.size.height && point.y <= NSMaxY(rect)+rect.size.height) return rect;
    }
    return NSZeroRect;
}

static void VPStringPoint(id text, SEL selector, NSPoint point, NSDictionary *attributes) {
    text = VPTranslatedTabString(text);
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    CGFloat originalY = point.y, height = 0;
    NSRect rect = VPMatchingTextRect(text, point, caller);
    BOOL adjusted = NO;
    if (!NSIsEmptyRect(rect) || (VPDrawTestLogging && VPNativeDrawScope && VPCenteredLyrics)) {
        height = [(NSString *)text sizeWithAttributes:attributes].height;
        if (!NSIsEmptyRect(rect) && height <= rect.size.height) { point.y = NSMidY(rect)-height/2; adjusted = YES; }
    }
    VPLogCentered(0, text, caller, originalY, rect, height, adjusted, point.y);
    VPStringPointOriginal(text, selector, point, attributes);
}
static void VPStringRect(id text, SEL selector, NSRect drawingRect, NSDictionary *attributes) {
    text = VPTranslatedTabString(text);
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    CGFloat originalY = drawingRect.origin.y, height = 0;
    NSRect rect = VPMatchingTextRect(text, drawingRect.origin, caller);
    BOOL adjusted = NO;
    if (!NSIsEmptyRect(rect) || (VPDrawTestLogging && VPNativeDrawScope && VPCenteredLyrics)) {
        height = [(NSString *)text sizeWithAttributes:attributes].height;
        if (!NSIsEmptyRect(rect) && height <= rect.size.height) {
            drawingRect.size.height = height;
            drawingRect.origin.y = NSMidY(rect)-height/2;
            adjusted = YES;
        }
    }
    VPLogCentered(1, text, caller, originalY, rect, height, adjusted, drawingRect.origin.y);
    VPStringRectOriginal(text, selector, drawingRect, attributes);
}
static void VPAttributedPoint(id text, SEL selector, NSPoint point) {
    text = VPTranslatedTabAttributedString(text);
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    CGFloat originalY = point.y, height = 0;
    NSRect rect = VPMatchingTextRect([(NSAttributedString *)text string], point, caller);
    BOOL adjusted = NO;
    if (!NSIsEmptyRect(rect) || (VPDrawTestLogging && VPNativeDrawScope && VPCenteredLyrics)) {
        height = [(NSAttributedString *)text size].height;
        if (!NSIsEmptyRect(rect) && height <= rect.size.height) { point.y = NSMidY(rect)-height/2; adjusted = YES; }
    }
    VPLogCentered(2, [(NSAttributedString *)text string], caller, originalY, rect, height, adjusted, point.y);
    VPAttributedPointOriginal(text, selector, point);
}
static void VPAttributedRect(id text, SEL selector, NSRect drawingRect) {
    text = VPTranslatedTabAttributedString(text);
    uintptr_t caller = (uintptr_t)__builtin_return_address(0);
    CGFloat originalY = drawingRect.origin.y, height = 0;
    NSRect rect = VPMatchingTextRect([(NSAttributedString *)text string], drawingRect.origin, caller);
    BOOL adjusted = NO;
    if (!NSIsEmptyRect(rect) || (VPDrawTestLogging && VPNativeDrawScope && VPCenteredLyrics)) {
        height = [(NSAttributedString *)text size].height;
        if (!NSIsEmptyRect(rect) && height <= rect.size.height) {
            drawingRect.size.height = height;
            drawingRect.origin.y = NSMidY(rect)-height/2;
            adjusted = YES;
        }
    }
    VPLogCentered(3, [(NSAttributedString *)text string], caller, originalY, rect, height, adjusted, drawingRect.origin.y);
    VPAttributedRectOriginal(text, selector, drawingRect);
}

static void VPFillNoteRect(CGContextRef context, CGRect rect) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0)-VPDrawSlide;
    BOOL noteCall = caller == VP_PC_NOTE_RECT_1 || caller == VP_PC_NOTE_RECT_2 ||
                    caller == VP_PC_NOTE_RECT_3 || caller == VP_PC_NOTE_RECT_4;
    if (noteCall && VPNativeDrawScope && VPRoundedNotes) {
        CGFloat radius = MIN(3, MIN(rect.size.width, rect.size.height)/2);
        CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
        CGContextAddPath(context, path);
        CGContextFillPath(context);
        CGPathRelease(path);
    } else CGContextFillRect(context, rect);
}
static void VPAddNoteRect(CGContextRef context, CGRect rect) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0)-VPDrawSlide;
    BOOL noteCall = caller == VP_PC_NOTE_FILL_1 || caller == VP_PC_NOTE_FILL_2 || caller == VP_PC_NOTE_FILL_3;
    if (noteCall && VPNativeDrawScope && VPRoundedNotes) {
        CGFloat radius = MIN(3, MIN(rect.size.width, rect.size.height)/2);
        CGPathRef path = CGPathCreateWithRoundedRect(rect, radius, radius, NULL);
        CGContextAddPath(context, path);
        CGPathRelease(path);
    } else CGContextAddRect(context, rect);
}
// Dyld excludes the image containing each replacement from its own interpose,
// allowing the fallback above to call the original CoreGraphics function.
__attribute__((used, section("__DATA,__interpose")))
static const struct { const void *replacement; const void *original; } VPDrawInterpose[] = {
    {(const void *)VPFillNoteRect, (const void *)CGContextFillRect},
    {(const void *)VPAddNoteRect, (const void *)CGContextAddRect}
};

CGRect VPRenderingNoteRect(NSView *view, id<VPDrawNote> note) {
#if defined(__arm64__)
    if (VPDrawRect && note) return VPDrawRect(note, [note absPosTick].value, [note absEndTick].value, view);
#endif
    return CGRectZero;
}

static BOOL VPDrawValidRect(CGRect rect) {
    return isfinite(rect.origin.x) && isfinite(rect.origin.y) && isfinite(rect.size.width) &&
           isfinite(rect.size.height) && rect.size.width > 0 && rect.size.height > 0;
}

typedef struct {
    BOOL valid;
    int64_t begin;
    int64_t end;
} VPDrawTickWindow;
static NSCache<NSValue *, NSDictionary *> *VPPartCoverage;
static void (*VPOriginalCoverageUpdate)(id, SEL, id);
static id VPPartCoverageWindowObserver;

static VPDrawTickWindow VPDrawTicksForPixels(NSRect visible, CGFloat origin, CGFloat pixelsPerTick) {
    VPDrawTickWindow result = {0};
    if (!isfinite(origin) || !isfinite(pixelsPerTick) || pixelsPerTick <= 0 || NSIsEmptyRect(visible)) return result;
    // Keep a small stroke/rounding margin. Final rectangle intersection remains authoritative.
    double begin = floor((NSMinX(visible) - 2 - origin) / pixelsPerTick);
    double end = ceil((NSMaxX(visible) + 2 - origin) / pixelsPerTick);
    if (!isfinite(begin) || !isfinite(end) || begin <= (double)INT64_MIN || end >= (double)INT64_MAX) return result;
    return (VPDrawTickWindow){YES, (int64_t)begin, (int64_t)end};
}
static VPDrawTickWindow VPDrawVisibleTicks(NSView *view, NSRect visible) {
#if defined(__arm64__)
    if (VPDrawX) {
        CGFloat origin = VPDrawX(0, view);
        CGFloat quarter = VPDrawX(480, view);
        return VPDrawTicksForPixels(visible, origin, (quarter - origin) / 480);
    }
#endif
    return (VPDrawTickWindow){0};
}
static BOOL VPDrawIntervalOverlaps(int64_t begin, int64_t end, VPDrawTickWindow window) {
    return !window.valid || (begin <= window.end && end >= window.begin);
}
static BOOL VPNoteMayOverlapWindow(id<VPDrawNote> note, VPDrawTickWindow window) {
    return !window.valid || VPDrawIntervalOverlaps([note absPosTick].value, [note absEndTick].value, window);
}
static BOOL VPPartMayOverlapWindow(id<VPDrawPart> part, VPDrawTickWindow window) {
    if (!window.valid || !VPPartCoverage || ![part respondsToSelector:@selector(unwrap)]) return YES;
    NSUInteger count = [part numNote];
    if (!count) return NO;
    void *identity = [part unwrap];
    if (!identity) return YES;
    NSValue *key = [NSValue valueWithPointer:identity];
    int64_t origin = [part absPosTick].value;
    NSDictionary *coverage = [VPPartCoverage objectForKey:key];
    if (!coverage || [coverage[@"count"] unsignedIntegerValue] != count || [coverage[@"origin"] longLongValue] != origin) {
        // Use actual note intervals. Older or imported data can extend beyond a part's declared duration.
        int64_t begin = INT64_MAX, end = INT64_MIN;
        for (NSUInteger index = 0; index < count; index++) {
            id<VPDrawNote> note = [part note:index];
            begin = MIN(begin, [note absPosTick].value);
            end = MAX(end, [note absEndTick].value);
        }
        coverage = @{@"begin": @(begin), @"end": @(end), @"count": @(count), @"origin": @(origin)};
        [VPPartCoverage setObject:coverage forKey:key];
    }
    return VPDrawIntervalOverlaps([coverage[@"begin"] longLongValue], [coverage[@"end"] longLongValue], window);
}
static void VPCoverageSequenceUpdate(id object, SEL selector, id notification) {
    [VPPartCoverage removeAllObjects];
    VPOriginalCoverageUpdate(object, selector, notification);
}

static void VPDrawExtras(NSView *view, SEL selector, NSRect dirty) {
    NSRect visible = NSIntersectionRect(dirty, view.visibleRect);
    VPDrawTickWindow ticks = VPDrawVisibleTicks(view, visible);
    if (VPCenteredLyrics) {
        NSDocument *document = VPDrawDocument(view);
        id model = VPArtObjectIvar(document, "sequence");
        id<VPDrawPart> activePart = VPArtObjectIvar(model, "activePart");
        NSMutableArray *labels = [NSMutableArray array];
        NSUInteger noteCount = [activePart respondsToSelector:@selector(numNote)] ? [activePart numNote] : 0;
        for (NSUInteger i = 0; i < noteCount; i++) {
            id<VPDrawNote> note = [activePart note:i];
            if (!VPNoteMayOverlapWindow(note, ticks)) continue;
            CGRect rect = VPRenderingNoteRect(view, note);
            if (VPDrawValidRect(rect) && NSIntersectsRect(rect, dirty))
                [labels addObject:@{@"lyric": [note lyric] ?: @"", @"phonemes": [note phonemes] ?: @"", @"rect": [NSValue valueWithRect:rect]}];
        }
        VPDrawLabels = labels;
    }
    VPNativeDrawScope = YES;
    if (VPWaveBeginNativeDraw) VPWaveBeginNativeDraw(view);
    @try { VPOriginalDraw(view, selector, dirty); }
    @finally {
        if (VPWaveEndNativeDraw) VPWaveEndNativeDraw();
        VPNativeDrawScope = NO;
        VPDrawLabels = nil;
    }
    if (!VPShowPitchNames && !VPShowGhostNotes) return;
    NSDocument *document = VPDrawDocument(view);
    id model = VPArtObjectIvar(document, "sequence");
    id<VPDrawPart> activePart = VPArtObjectIvar(model, "activePart");
    if (![activePart respondsToSelector:@selector(numNote)]) return;
    if (NSIsEmptyRect(visible)) return;
    [NSGraphicsContext saveGraphicsState];
    NSRectClip(visible);
    if (VPShowGhostNotes) {
        id<VPDrawSequence> sequence = VPArtObjectIvar(model, "vsmSequence");
        id activeTrack = VPArtObjectIvar(model, "activeTrack");
        if ([sequence respondsToSelector:@selector(numTrack)]) {
            [[NSColor colorWithCalibratedWhite:0.8 alpha:0.28] setStroke];
            for (NSUInteger trackIndex = 0; trackIndex < [sequence numTrack]; trackIndex++) {
                id<VPDrawTrack> track = [sequence track:trackIndex];
                if ([(id)track isEqual:activeTrack] || ![(id)track respondsToSelector:NSSelectorFromString(@"voiceBankID")] ||
                    (VPSkipMutedGhosts && [track isChannelMute])) continue;
                for (NSUInteger partIndex = 0; partIndex < [track numPart]; partIndex++) {
                    id<VPDrawPart> part = [track part:partIndex];
                    if (![(id)part respondsToSelector:@selector(numNote)] || !VPPartMayOverlapWindow(part, ticks)) continue;
                    NSUInteger noteCount = [part numNote];
                    for (NSUInteger noteIndex = 0; noteIndex < noteCount; noteIndex++) {
                        id<VPDrawNote> note = [part note:noteIndex];
                        if (!VPNoteMayOverlapWindow(note, ticks)) continue;
                        CGRect rect = VPRenderingNoteRect(view, note);
                        if (!VPDrawValidRect(rect) || !NSIntersectsRect(rect, visible)) continue;
                        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:NSInsetRect(rect, 0.5, 0.5)
                                                                           xRadius:2 yRadius:2];
                        path.lineWidth = 1;
                        [path stroke];
                    }
                }
            }
        }
    }
    if (VPShowPitchNames) {
        NSArray *names = @[@"C", @"C#", @"D", @"D#", @"E", @"F", @"F#", @"G", @"G#", @"A", @"A#", @"B"];
        NSDictionary *attributes = @{NSFontAttributeName: [NSFont monospacedSystemFontOfSize:9 weight:NSFontWeightRegular],
            NSForegroundColorAttributeName: [NSColor colorWithCalibratedWhite:1 alpha:0.85]};
        NSUInteger noteCount = [activePart numNote];
        for (NSUInteger index = 0; index < noteCount; index++) {
            id<VPDrawNote> note = [activePart note:index];
            if (!VPNoteMayOverlapWindow(note, ticks)) continue;
            CGRect rect = VPRenderingNoteRect(view, note);
            NSInteger pitch = [note noteNumber];
            if (pitch < 0 || pitch > 127 || !VPDrawValidRect(rect) || rect.size.width < 34 ||
                rect.size.height < 11 || !NSIntersectsRect(rect, visible)) continue;
            // Match upstream VOCALOID's octave convention (MIDI 60 = C3).
            NSString *label = [NSString stringWithFormat:@"%@%ld", names[pitch % 12], (long)(pitch/12-2)];
            NSSize size = [label sizeWithAttributes:attributes];
            NSPoint position = NSMakePoint(NSMaxX(rect)-size.width-3, NSMidY(rect)-size.height/2);
            [label drawAtPoint:position withAttributes:attributes];
        }
    }
    [NSGraphicsContext restoreGraphicsState];
}

static void VPArtAlert(NSString *message) {
    NSAlert *alert = [NSAlert new];
    alert.messageText = VPUIString(@"声库立绘");
    alert.informativeText = message;
    [alert runModal];
}

// The overlay has no input surface, so it cannot intercept note editing.
@interface VPArtOverlay : NSView
@end
@implementation VPArtOverlay
- (NSView *)hitTest:(NSPoint)point { return nil; }
- (BOOL)acceptsFirstResponder { return NO; }
@end

@interface VPArtwork : NSObject
@property NSString *settingsPath;
@property NSString *drawingSettingsPath;
@property NSMutableDictionary *banks;
@property VPArtOverlay *overlay;
@property NSImageView *imageView;
@property AVPlayerLayer *videoLayer;
@property AVPlayer *player;
@property id videoObserver;
@property NSString *loadedPath;
@property NSTimer *timer;
@property BOOL enabled;
@property NSMenuItem *enabledItem;
@property (weak) NSView *suppressedNativeView;
@property NSString *lastDiagnosticState;
@property BOOL diagnosticTestActive;
@end

@implementation VPArtwork
- (void)logArtworkState:(NSString *)reason document:(NSDocument *)document hasBank:(BOOL)hasBank
             hasMapping:(BOOL)hasMapping piano:(NSView *)piano native:(NSView *)native toggle:(NSButton *)toggle {
    if (!VPDrawTestLogging) return;
    if (document) self.diagnosticTestActive = [[document.fileURL.path stringByResolvingSymlinksInPath] isEqualToString:VPDrawTestProjectPath];
    if (!self.diagnosticTestActive) return;
    NSString *state = [NSString stringWithFormat:@"reason=%@ docClass=%@ bank=%d mapped=%d piano=%d native=%d buttonState=%ld pianoHidden=%d nativeHidden=%d enabled=%d overlayHidden=%d overlayFrame=%@",
        reason, NSStringFromClass(document.class) ?: @"nil", hasBank, hasMapping, piano != nil, native != nil,
        toggle ? (long)toggle.state : -1L, piano.hiddenOrHasHiddenAncestor, native.hiddenOrHasHiddenAncestor,
        self.enabled, self.overlay.hidden, NSStringFromRect(self.overlay.frame)];
    if (![state isEqualToString:self.lastDiagnosticState]) {
        NSLog(@"VP_ART_TEST %@", state);
        self.lastDiagnosticState = state;
    }
}
- (void)toggleDrawing:(NSMenuItem *)sender {
    BOOL *flags[] = {&VPShowPitchNames, &VPShowGhostNotes, &VPSkipMutedGhosts, &VPCenteredLyrics, &VPRoundedNotes};
    BOOL *flag = flags[sender.tag];
    *flag = !*flag;
    sender.state = *flag ? NSControlStateValueOn : NSControlStateValueOff;
    [self saveDrawingSettings];
    for (NSWindow *window in NSApp.windows) [VPArtPianoView(window.contentView) setNeedsDisplay:YES];
}
- (void)saveDrawingSettings {
    NSDictionary *settings = @{@"pitchNames": @(VPShowPitchNames), @"ghostNotes": @(VPShowGhostNotes),
        @"skipMutedGhosts": @(VPSkipMutedGhosts), @"centeredLyrics": @(VPCenteredLyrics),
        @"roundedNotes": @(VPRoundedNotes), @"artworkEnabled": @(self.enabled)};
    NSError *error = nil;
    NSData *data = [NSPropertyListSerialization dataWithPropertyList:settings
        format:NSPropertyListXMLFormat_v1_0 options:0 error:&error];
    if (!data || ![data writeToFile:self.drawingSettingsPath options:NSDataWritingAtomic error:&error])
        VPArtAlert(VPUIString(@"无法保存绘制设置，请检查补丁目录的写入权限。"));
}
- (void)suppressNativeView:(NSView *)view {
    if (view == self.suppressedNativeView) return;
    NSView *previous = self.suppressedNativeView;
    if (previous) {
        [VPArtSuppressedViews removeObject:previous];
        [previous setNeedsDisplay:YES];
        [previous.superview setNeedsDisplayInRect:previous.frame];
    }
    self.suppressedNativeView = view;
    if (view) {
        [VPArtSuppressedViews addObject:view];
        [view setNeedsDisplay:YES];
        [view.superview setNeedsDisplayInRect:view.frame];
    }
}
- (void)saveSettings {
    NSData *data = [NSJSONSerialization dataWithJSONObject:self.banks options:NSJSONWritingPrettyPrinted error:nil];
    NSError *error = nil;
    if (!data || ![data writeToFile:self.settingsPath options:NSDataWritingAtomic error:&error]) {
        VPArtAlert(VPUIString(@"无法保存立绘设置，请检查补丁目录的写入权限。"));
    }
}
- (NSMutableDictionary *)currentSettings {
    NSString *bank = VPArtBankID();
    if (!bank.length) { VPArtAlert(VPUIString(@"请先在编辑器中选中一个声库轨道。")); return nil; }
    NSMutableDictionary *settings = [self.banks[bank] mutableCopy];
    if (!settings) settings = [@{@"size": @220, @"opacity": @0.9, @"x": @1, @"y": @1} mutableCopy];
    self.banks[bank] = settings;
    return settings;
}
- (void)clearMedia {
    [self.player pause];
    if (self.videoObserver) [[NSNotificationCenter defaultCenter] removeObserver:self.videoObserver];
    self.videoObserver = nil;
    [self.videoLayer removeFromSuperlayer];
    self.videoLayer = nil;
    self.player = nil;
    [self.imageView removeFromSuperview];
    self.imageView = nil;
    self.loadedPath = nil;
}
- (BOOL)loadMedia:(NSString *)path {
    [self clearMedia];
    if (![NSFileManager.defaultManager fileExistsAtPath:path]) return NO;
    // AppKit can decode a movie poster as NSImage; route movies to AVPlayer first.
    BOOL isMovie = [[UTType typeWithFilenameExtension:path.pathExtension] conformsToType:UTTypeMovie];
    NSImage *image = isMovie ? nil : [[NSImage alloc] initWithContentsOfFile:path];
    if (image) {
        self.imageView = [[NSImageView alloc] initWithFrame:self.overlay.bounds];
        self.imageView.image = image;
        self.imageView.imageScaling = NSImageScaleProportionallyUpOrDown;
        self.imageView.animates = YES;
        self.imageView.autoresizingMask = NSViewWidthSizable | NSViewHeightSizable;
        [self.overlay addSubview:self.imageView];
    } else {
        AVURLAsset *asset = [AVURLAsset URLAssetWithURL:[NSURL fileURLWithPath:path] options:nil];
        if (![asset isPlayable]) return NO;
        self.player = [AVPlayer playerWithPlayerItem:[AVPlayerItem playerItemWithAsset:asset]];
        self.player.muted = YES;
        self.videoLayer = [AVPlayerLayer playerLayerWithPlayer:self.player];
        self.videoLayer.videoGravity = AVLayerVideoGravityResizeAspect;
        self.overlay.wantsLayer = YES;
        [self.overlay.layer addSublayer:self.videoLayer];
        __weak VPArtwork *weakSelf = self;
        self.videoObserver = [[NSNotificationCenter defaultCenter]
            addObserverForName:AVPlayerItemDidPlayToEndTimeNotification object:self.player.currentItem
            queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *__unused notification) {
                VPArtwork *strongSelf = weakSelf;
                [strongSelf.player seekToTime:kCMTimeZero completionHandler:^(BOOL finished) {
                    if (finished && !strongSelf.overlay.hidden) [strongSelf.player play];
                }];
            }];
    }
    self.loadedPath = path;
    return YES;
}
- (void)refresh:(id)sender {
    NSString *bank = VPArtBankID();
    NSDictionary *settings = bank ? self.banks[bank] : nil;
    NSString *path = settings[@"path"];
    NSDocument *document = VPArtDocument();
    NSWindow *window = document.windowControllers.firstObject.window;
    NSView *piano = VPArtPianoView(window.contentView);
    NSView *main = piano;
    while (main && ![NSStringFromClass(main.class) isEqualToString:@"VOCALOID7_Editor.VEMusicalEditorMainView"])
        main = main.superview;
    NSView *nativeArt = VPArtObjectIvar(main, "voiceBankImageView");
    NSButton *nativeToggle = VPArtObjectIvar(main, "voiceBankImageViewToggleButton");
    BOOL nativeVisible = [nativeArt isKindOfClass:NSView.class] && !nativeArt.hiddenOrHasHiddenAncestor;
    if ([nativeToggle isKindOfClass:NSButton.class]) nativeVisible = nativeVisible && nativeToggle.state != NSControlStateValueOff;
    if (!self.enabled || !path.length || !piano || piano.hiddenOrHasHiddenAncestor || !nativeVisible || !VPOriginalNativeArtDraw) {
        self.overlay.hidden = YES;
        [self.player pause];
        [self suppressNativeView:nil];
        [self logArtworkState:@"hidden" document:document hasBank:bank.length > 0 hasMapping:path.length > 0
                        piano:piano native:nativeArt toggle:nativeToggle];
        return;
    }
    if (self.overlay.superview != piano) {
        [self.overlay removeFromSuperview];
        [piano addSubview:self.overlay positioned:NSWindowAbove relativeTo:nil];
    }
    if (![self.loadedPath isEqualToString:path] && ![self loadMedia:path]) {
        self.overlay.hidden = YES;
        [self suppressNativeView:nil];
        [self logArtworkState:@"media-unavailable" document:document hasBank:bank.length > 0 hasMapping:path.length > 0
                        piano:piano native:nativeArt toggle:nativeToggle];
        return;
    }
    [self suppressNativeView:nativeArt];
    NSRect visible = piano.visibleRect;
    CGFloat size = MIN([settings[@"size"] doubleValue], MIN(visible.size.width, visible.size.height));
    size = MAX(0, size);
    CGFloat x = visible.origin.x + (visible.size.width-size)*[settings[@"x"] doubleValue];
    CGFloat yFraction = [settings[@"y"] doubleValue];
    CGFloat y = visible.origin.y + (visible.size.height-size)*(piano.isFlipped ? yFraction : 1-yFraction);
    self.overlay.frame = NSMakeRect(x, y, size, size);
    self.overlay.alphaValue = [settings[@"opacity"] doubleValue];
    self.videoLayer.frame = self.overlay.bounds;
    self.overlay.hidden = NO;
    if (self.player.rate == 0) [self.player play];
    [self logArtworkState:@"shown" document:document hasBank:bank.length > 0 hasMapping:path.length > 0
                    piano:piano native:nativeArt toggle:nativeToggle];
}
- (void)choose:(id)sender {
    NSMutableDictionary *settings = [self currentSettings];
    if (!settings) return;
    NSOpenPanel *panel = [NSOpenPanel openPanel];
    panel.canChooseDirectories = NO;
    panel.allowsMultipleSelection = NO;
    panel.allowedContentTypes = @[UTTypeImage, UTTypeMovie];
    panel.message = VPUIString(@"为当前声库选择图片、GIF 或视频");
    if ([panel runModal] != NSModalResponseOK) return;
    NSString *path = panel.URL.path;
    if (![self loadMedia:path]) { VPArtAlert(VPUIString(@"无法读取所选图片或视频。")); return; }
    settings[@"path"] = path;
    self.enabled = YES;
    self.enabledItem.state = NSControlStateValueOn;
    [self saveSettings];
    [self saveDrawingSettings];
    [self refresh:nil];
}
- (void)toggle:(NSMenuItem *)sender {
    self.enabled = !self.enabled;
    sender.state = self.enabled ? NSControlStateValueOn : NSControlStateValueOff;
    [self saveDrawingSettings];
    [self refresh:nil];
}
- (void)reset:(id)sender {
    NSString *bank = VPArtBankID();
    if (!bank.length) return;
    [self.banks removeObjectForKey:bank];
    [self clearMedia];
    [self saveSettings];
    [self refresh:nil];
}
- (void)adjust:(NSMenuItem *)sender {
    NSMutableDictionary *settings = [self currentSettings];
    if (!settings) return;
    NSArray *keys = @[@"size", @"opacity", @"x", @"y"];
    NSArray *titles = @[VPUIString(@"立绘大小（32–1024 像素）"), VPUIString(@"立绘不透明度（0–100%）"),
                        VPUIString(@"水平位置（0%=左，100%=右）"), VPUIString(@"垂直位置（0%=上，100%=下）")];
    NSString *key = keys[sender.tag];
    double factor = sender.tag ? 100 : 1;
    NSAlert *alert = [NSAlert new];
    alert.messageText = titles[sender.tag];
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 300, 24)];
    field.stringValue = [NSString stringWithFormat:@"%.0f", [settings[key] doubleValue]*factor];
    alert.accessoryView = field;
    [alert addButtonWithTitle:VPUIString(@"确定")];
    [alert addButtonWithTitle:VPUIString(@"取消")];
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSScanner *scanner = [NSScanner scannerWithString:field.stringValue];
    double value;
    double minimum = sender.tag ? 0 : 32, maximum = sender.tag ? 100 : 1024;
    if (![scanner scanDouble:&value] || !scanner.isAtEnd || !isfinite(value) || value < minimum || value > maximum) {
        VPArtAlert(VPUIString(@"请输入范围内的数字。"));
        return;
    }
    settings[key] = @(value/factor);
    [self saveSettings];
    [self refresh:nil];
}
@end

static VPArtwork *VPArtworkInstance;

NSMenu *installRendering(NSString *rootPath) {
    if (!VPSupportedEditor()) return nil;
    VPDrawTestLogging = getenv("VOCALOID_PATCHER_TEST_PROJECT") != NULL;
    if (VPDrawTestLogging) VPDrawTestProjectPath = [[NSString stringWithUTF8String:getenv("VOCALOID_PATCHER_TEST_PROJECT")] stringByResolvingSymlinksInPath];
#if defined(__arm64__)
    BOOL foundExecutable = NO;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const struct mach_header *header = _dyld_get_image_header(index);
        if (header && header->filetype == MH_EXECUTE) {
            VPDrawSlide = _dyld_get_image_vmaddr_slide(index);
            foundExecutable = YES;
            break;
        }
    }
    if (!foundExecutable) return nil;
#endif
    VPArtwork *artwork = [VPArtwork new];
    VPArtworkInstance = artwork;
    artwork.settingsPath = [rootPath stringByAppendingPathComponent:@"artwork-settings.json"];
    artwork.drawingSettingsPath = [rootPath stringByAppendingPathComponent:@"drawing-settings.plist"];
    NSData *drawingData = [NSData dataWithContentsOfFile:artwork.drawingSettingsPath];
    id drawingStored = drawingData ? [NSPropertyListSerialization propertyListWithData:drawingData
        options:NSPropertyListImmutable format:NULL error:nil] : nil;
    NSDictionary *drawingSettings = [drawingStored isKindOfClass:NSDictionary.class] ? drawingStored : @{};
    VPShowPitchNames = VPStoredBoolean(drawingSettings, @"pitchNames", NO);
    VPShowGhostNotes = VPStoredBoolean(drawingSettings, @"ghostNotes", NO);
    VPSkipMutedGhosts = VPStoredBoolean(drawingSettings, @"skipMutedGhosts", YES);
    VPCenteredLyrics = VPStoredBoolean(drawingSettings, @"centeredLyrics", NO);
    VPRoundedNotes = VPStoredBoolean(drawingSettings, @"roundedNotes", NO);
    artwork.enabled = VPStoredBoolean(drawingSettings, @"artworkEnabled", YES);
    NSData *data = [NSData dataWithContentsOfFile:artwork.settingsPath];
    id stored = data ? [NSJSONSerialization JSONObjectWithData:data options:NSJSONReadingMutableContainers error:nil] : nil;
    artwork.banks = [NSMutableDictionary dictionary];
    // Settings files are external input. Invalid records are ignored before any
    // values reach AppKit geometry or media APIs.
    if ([stored isKindOfClass:NSDictionary.class]) for (NSString *bank in stored) {
        NSDictionary *entry = stored[bank];
        if (![bank isKindOfClass:NSString.class] || ![entry isKindOfClass:NSDictionary.class] ||
            ![entry[@"path"] isKindOfClass:NSString.class]) continue;
        BOOL valid = YES;
        NSArray *keys = @[@"size", @"opacity", @"x", @"y"];
        for (NSString *key in keys) {
            id number = entry[key];
            if (![number isKindOfClass:NSNumber.class] || !isfinite([number doubleValue])) { valid = NO; break; }
        }
        if (!valid || [entry[@"size"] doubleValue] < 32 || [entry[@"size"] doubleValue] > 1024) continue;
        if ([entry[@"opacity"] doubleValue] < 0 || [entry[@"opacity"] doubleValue] > 1 ||
            [entry[@"x"] doubleValue] < 0 || [entry[@"x"] doubleValue] > 1 ||
            [entry[@"y"] doubleValue] < 0 || [entry[@"y"] doubleValue] > 1) continue;
        artwork.banks[bank] = [entry mutableCopy];
    }
    artwork.overlay = [[VPArtOverlay alloc] initWithFrame:NSZeroRect];
    VPArtSuppressedViews = [NSHashTable weakObjectsHashTable];
    Method nativeArtDraw = class_getInstanceMethod(NSClassFromString(@"VOCALOID7_Editor.VoiceBankImageView"), @selector(drawRect:));
    if (nativeArtDraw && strcmp(method_getTypeEncoding(nativeArtDraw), "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16") == 0)
        VPOriginalNativeArtDraw = (void (*)(id, SEL, NSRect))method_setImplementation(nativeArtDraw, (IMP)VPDrawNativeArt);
    NSMenu *menu = [[NSMenu alloc] initWithTitle:VPUIString(@"钢琴窗与立绘")];
#if defined(__arm64__)
    // DYLD_INSERT_LIBRARIES can place the patch dylib at image index zero.
    // The private symbol addresses and return PCs belong to MH_EXECUTE.
    VPDrawRect = (VPDrawRectFunction)(VPDrawSlide + VP_ADDR_NOTE_RECT);
    VPDrawX = (VPDrawXFunction)(VPDrawSlide + VP_ADDR_LOCAL_X);
    Method coverageUpdate = class_getInstanceMethod(NSClassFromString(@"VOCALOID7_Editor.VESequence"), @selector(sequenceUpdate:));
    if (coverageUpdate && strcmp(method_getTypeEncoding(coverageUpdate), "v24@0:8@16") == 0) {
        VPPartCoverage = [NSCache new];
        VPOriginalCoverageUpdate = (void (*)(id, SEL, id))method_setImplementation(coverageUpdate, (IMP)VPCoverageSequenceUpdate);
        VPPartCoverageWindowObserver = [NSNotificationCenter.defaultCenter addObserverForName:NSWindowWillCloseNotification
            object:nil queue:NSOperationQueue.mainQueue usingBlock:^(NSNotification *notification) {
                (void)notification;
                [VPPartCoverage removeAllObjects];
            }];
    }
    Class pianoClass = NSClassFromString(@"VOCALOID7_Editor.VEPianoRollBodyView");
    Method drawMethod = class_getInstanceMethod(pianoClass, @selector(drawRect:));
    if (drawMethod && strcmp(method_getTypeEncoding(drawMethod), "v48@0:8{CGRect={CGPoint=dd}{CGSize=dd}}16") == 0) {
        VPOriginalDraw = (void (*)(id, SEL, NSRect))method_setImplementation(drawMethod, (IMP)VPDrawExtras);
        Method stringPoint = class_getInstanceMethod(NSString.class, @selector(drawAtPoint:withAttributes:));
        Method stringRect = class_getInstanceMethod(NSString.class, @selector(drawInRect:withAttributes:));
        Method attributedPoint = class_getInstanceMethod(NSAttributedString.class, @selector(drawAtPoint:));
        Method attributedRect = class_getInstanceMethod(NSAttributedString.class, @selector(drawInRect:));
        VPStringPointOriginal = (void *)method_setImplementation(stringPoint, (IMP)VPStringPoint);
        VPStringRectOriginal = (void *)method_setImplementation(stringRect, (IMP)VPStringRect);
        VPAttributedPointOriginal = (void *)method_setImplementation(attributedPoint, (IMP)VPAttributedPoint);
        VPAttributedRectOriginal = (void *)method_setImplementation(attributedRect, (IMP)VPAttributedRect);
        // Only replace methods declared directly on these two native classes.
        // Separate originals also keep a native super draw call non-recursive.
        VPOriginalBrowserTabDraw = (void *)VPReplaceOwnedDraw(NSClassFromString(@"VOCALOID7_Editor.VEBrowserTabView"), (IMP)VPDrawBrowserTabs);
        VPOriginalTabDraw = (void *)VPReplaceOwnedDraw(NSClassFromString(@"VOCALOID7_Editor.VETabView"), (IMP)VPDrawTabs);
        NSArray *drawingTitles = @[VPUIString(@"显示音符音高"), VPUIString(@"显示其他轨道音符"), VPUIString(@"忽略静音轨道"), VPUIString(@"歌词垂直居中"), VPUIString(@"圆角音符")];
        for (NSUInteger index = 0; index < drawingTitles.count; index++) {
            NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:drawingTitles[index] action:@selector(toggleDrawing:) keyEquivalent:@""];
            item.target = artwork;
            item.tag = index;
            BOOL values[] = {VPShowPitchNames, VPShowGhostNotes, VPSkipMutedGhosts, VPCenteredLyrics, VPRoundedNotes};
            item.state = values[index] ? NSControlStateValueOn : NSControlStateValueOff;
            [menu addItem:item];
        }
        [menu addItem:NSMenuItem.separatorItem];
    }
#endif
    NSArray *titles = @[VPUIString(@"显示立绘"), VPUIString(@"为当前声库选择图片或视频…"), VPUIString(@"大小…"), VPUIString(@"不透明度…"),
                        VPUIString(@"水平位置…"), VPUIString(@"垂直位置…"), VPUIString(@"清除当前声库立绘")];
    SEL actions[] = {@selector(toggle:), @selector(choose:), @selector(adjust:), @selector(adjust:),
                     @selector(adjust:), @selector(adjust:), @selector(reset:)};
    for (NSUInteger index = 0; index < titles.count; index++) {
        NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:titles[index] action:actions[index] keyEquivalent:@""];
        item.target = artwork;
        item.tag = index >= 2 && index <= 5 ? index-2 : 0;
        [menu addItem:item];
        if (index == 0) { artwork.enabledItem = item; item.state = artwork.enabled ? NSControlStateValueOn : NSControlStateValueOff; }
    }
    artwork.timer = [NSTimer scheduledTimerWithTimeInterval:0.3 target:artwork selector:@selector(refresh:)
                                                  userInfo:nil repeats:YES];
    return menu;
}
