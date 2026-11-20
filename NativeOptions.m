#import "Compatibility.h"
#import "UIStrings.h"
#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#import <objc/runtime.h>
#import <mach-o/dyld.h>
#import <objc/message.h>
#include <float.h>
#include <limits.h>
#import <QuartzCore/QuartzCore.h>
#include <malloc/malloc.h>

static BOOL VPWaveSupported;
static intptr_t VPWaveSlide;
static CGFloat VPWaveOpacity = 1;
static BOOL VPSVEnabled;
static _Thread_local BOOL VPSVNativeWave;

static void VPWaveStrokeColor(CGContextRef context, CGFloat red, CGFloat green, CGFloat blue, CGFloat alpha) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0) - VPWaveSlide;
    // The native piano-roll drawRenderedWave function has this single stroke-color call.
    // Other CoreGraphics consumers keep their original colors and transparency.
    if (caller == VP_PC_WAVE_COLOR && VPWaveSupported) {
        alpha *= VPWaveOpacity;
        VPSVNativeWave = YES;
    }
    CGContextSetRGBStrokeColor(context, red, green, blue, alpha);
}

__attribute__((used)) static struct { const void *replacement; const void *original; }
VPWaveInterpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)VPWaveStrokeColor, (const void *)CGContextSetRGBStrokeColor
};

static id VPNativeObjectIvar(id object, const char *name) {
    if (!object) return nil;
    Ivar ivar = class_getInstanceVariable(object_getClass(object), name);
    if (!ivar) return nil;
    void *pointer = NULL;
    memcpy(&pointer, (__bridge const void *)object + ivar_getOffset(ivar), sizeof(pointer));
    return (__bridge id)pointer;
}

static BOOL VPNativeSupported(void) {
    NSData *bytes = [NSData dataWithContentsOfFile:VPActualExecutablePath()
                                         options:NSDataReadingMappedIfSafe error:nil];
    if (!bytes || bytes.length > UINT_MAX) return NO;
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger i = 0; i < sizeof(digest); i++) [hex appendFormat:@"%02x", digest[i]];
    return [hex isEqualToString:VP_EDITOR_SHA256];
}

static void VPNativeInvalidatePiano(NSView *view) {
    if ([NSStringFromClass(view.class) isEqualToString:@"VOCALOID7_Editor.VEPianoRollBodyView"]) view.needsDisplay = YES;
    for (NSView *child in view.subviews) VPNativeInvalidatePiano(child);
}

typedef struct { int64_t value; } VPSVTick;
@protocol VPSVNote <NSObject>
- (NSInteger)noteNumber;
@end
@protocol VPSVPart <NSObject>
- (NSUInteger)numNote;
- (id<VPSVNote>)note:(NSUInteger)index;
- (BOOL)hasValidRenderedWave;
@end
extern CGRect VPRenderingNoteRect(NSView *view, id note);

@interface VPSVCache : NSObject
@property NSData *baselines;
@property NSUInteger generation;
@property NSInteger rawState;
@end
@implementation VPSVCache
@end

static NSMapTable<id, VPSVCache *> *VPSVCaches;
static NSUInteger VPSVGeneration;
static const void *(*VPSVOriginalScore)(id, SEL, NSInteger);
static NSView *VPSVView;
static CGFloat VPSVReferenceTop, VPSVRowHeight;
static NSInteger VPSVReferencePitch, VPSVFramePitch, VPSVFrameBaseline;
static BOOL VPSVGeometryValid, VPSVFrameValid;

typedef struct {
    CGFloat x, nativeCenter, center, top, bottom;
    NSInteger baseline;
    BOOL valid;
} VPSVColumn;
static VPSVColumn VPSVCurrent, VPSVPrevious, VPSVHistory[24];
static NSUInteger VPSVHistoryCount;
static CGFloat VPSVBoundaryX, VPSVBoundaryOldCenter;
static NSInteger VPSVBoundaryBaseline;
static BOOL VPSVHasBoundary;
static uint64_t VPSVRemappedColumns;
uint64_t VPWaveformRemappedColumns(void) { return VPSVRemappedColumns; }

static VPSVCache *VPSVBuildCache(id scores) {
    NSInteger count = ((NSInteger (*)(id, SEL))objc_msgSend)(scores, @selector(numScores));
    NSInteger state = ((NSInteger (*)(id, SEL))objc_msgSend)(scores, @selector(rawState));
    if (count <= 0 || count > 4000000) return nil;
    VPSVCache *cached = [VPSVCaches objectForKey:scores];
    if (cached && cached.generation == VPSVGeneration && cached.rawState == state &&
        cached.baselines.length == (NSUInteger)count * sizeof(int32_t)) return cached;
    NSMutableData *data = [NSMutableData dataWithLength:(NSUInteger)count * sizeof(int32_t)];
    int32_t *values = data.mutableBytes;
    NSInteger groupStart = -1, minimum = 0, maximum = 0;
    for (NSInteger index = 0; index < count; index++) {
        values[index] = INT_MIN;
        const float *score = VPSVOriginalScore(scores, @selector(scoreAtIndex:), index);
        if (!score || !isfinite(score[0]) || score[0] == -FLT_MAX) continue;
        float key = (score[0] + 6900.0f) / 100.0f;
        if (key < 0 || key > 127) continue;
        NSInteger pitch = (NSInteger)key;
        values[index] = (int32_t)pitch;
        if (groupStart < 0) { groupStart = index; minimum = pitch; maximum = pitch; continue; }
        NSInteger nextMinimum = MIN(minimum, pitch), nextMaximum = MAX(maximum, pitch);
        if (nextMaximum - nextMinimum <= 7) { minimum = nextMinimum; maximum = nextMaximum; continue; }
        for (NSInteger frame = groupStart; frame < index; frame++)
            if (values[frame] != INT_MIN) values[frame] = (int32_t)minimum;
        groupStart = index; minimum = pitch; maximum = pitch;
    }
    if (groupStart >= 0) for (NSInteger frame = groupStart; frame < count; frame++)
        if (values[frame] != INT_MIN) values[frame] = (int32_t)minimum;
    cached = [VPSVCache new]; cached.baselines = data;
    cached.generation = VPSVGeneration; cached.rawState = state;
    [VPSVCaches setObject:cached forKey:scores];
    return cached;
}

static const void *VPSVReadScore(id scores, SEL selector, NSInteger frame) {
    const float *score = VPSVOriginalScore(scores, selector, frame);
    if (!VPSVNativeWave || !VPSVEnabled || !VPSVGeometryValid) return score;
    VPSVFrameValid = NO;
    VPSVCache *cache = VPSVBuildCache(scores);
    if (!cache || frame < 0 || (NSUInteger)frame >= cache.baselines.length / sizeof(int32_t) ||
        !score || !isfinite(score[0]) || score[0] == -FLT_MAX) return score;
    int32_t baseline = ((const int32_t *)cache.baselines.bytes)[frame];
    float pitch = (score[0] + 6900.0f) / 100.0f;
    if (baseline == INT_MIN || pitch < 0 || pitch > 127) return score;
    VPSVFramePitch = (NSInteger)pitch; VPSVFrameBaseline = baseline;
    VPSVFrameValid = YES;
    return score;
}

void VPWaveBeginNativeDraw(NSView *view) {
    VPSVView = view; VPSVNativeWave = NO; VPSVGeometryValid = NO; VPSVFrameValid = NO;
    VPSVCurrent.valid = NO; VPSVPrevious.valid = NO;
    VPSVHistoryCount = 0; VPSVHasBoundary = NO;
    if (!VPSVEnabled || !VPWaveSupported) return;
    NSDocument *document = view.window.windowController.document;
    id model = VPNativeObjectIvar(document, "sequence");
    id<VPSVPart> part = VPNativeObjectIvar(model, "activePart");
    if (![part respondsToSelector:@selector(numNote)] || ![part numNote] || ![part hasValidRenderedWave]) return;
    id<VPSVNote> note = [part note:0];
    CGRect rect = VPRenderingNoteRect(view, note);
    if (!isfinite(rect.origin.y) || !isfinite(rect.size.height) || rect.size.height <= 0) return;
    // The pinned native rectOf implementation returns rowTop+1 and rowHeight-2.
    VPSVReferenceTop = rect.origin.y - 1;
    VPSVRowHeight = rect.size.height + 2;
    VPSVReferencePitch = [note noteNumber];
    VPSVGeometryValid = YES;
}
void VPWaveEndNativeDraw(void) {
    VPSVNativeWave = NO; VPSVGeometryValid = NO; VPSVFrameValid = NO; VPSVView = nil;
}

static void VPSVGhost(CGContextRef context, CGFloat x, CGFloat center, CGFloat top, CGFloat bottom,
                     CGFloat opacity, BOOL connect, CGFloat previousTop, CGFloat previousBottom) {
    if (opacity <= 0) return;
    CGContextSaveGState(context);
    CGContextSetAlpha(context, opacity);
    CGContextBeginPath(context);
    CGContextMoveToPoint(context, x, center + top);
    CGContextAddLineToPoint(context, x, center + bottom);
    if (connect) {
        CGContextMoveToPoint(context, x - 1, center + previousTop);
        CGContextAddLineToPoint(context, x, center + top);
        CGContextMoveToPoint(context, x - 1, center + previousBottom);
        CGContextAddLineToPoint(context, x, center + bottom);
    }
    CGContextStrokePath(context);
    CGContextRestoreGState(context);
}

typedef struct { CGMutablePathRef path; BOOL mapPrevious; } VPSVPathMap;
static void VPSVMapPath(void *context, const CGPathElement *element) {
    VPSVPathMap *map = context;
    CGPoint points[3];
    NSUInteger count = element->type == kCGPathElementAddCurveToPoint ? 3 :
        (element->type == kCGPathElementAddQuadCurveToPoint ? 2 :
        (element->type == kCGPathElementCloseSubpath ? 0 : 1));
    for (NSUInteger index = 0; index < count; index++) {
        points[index] = element->points[index];
        VPSVColumn column = map->mapPrevious && points[index].x < VPSVCurrent.x - 0.5 ? VPSVPrevious : VPSVCurrent;
        points[index].y += column.center - column.nativeCenter;
    }
    switch (element->type) {
        case kCGPathElementMoveToPoint: CGPathMoveToPoint(map->path, NULL, points[0].x, points[0].y); break;
        case kCGPathElementAddLineToPoint: CGPathAddLineToPoint(map->path, NULL, points[0].x, points[0].y); break;
        case kCGPathElementAddQuadCurveToPoint: CGPathAddQuadCurveToPoint(map->path, NULL, points[0].x, points[0].y, points[1].x, points[1].y); break;
        case kCGPathElementAddCurveToPoint: CGPathAddCurveToPoint(map->path, NULL, points[0].x, points[0].y, points[1].x, points[1].y, points[2].x, points[2].y); break;
        case kCGPathElementCloseSubpath: CGPathCloseSubpath(map->path); break;
    }
}

static void VPSVStroke(CGContextRef context) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0) - VPWaveSlide;
    BOOL vertical = caller == VP_PC_WAVE_VERTICAL;
    BOOL connecting = caller == VP_PC_WAVE_CONNECT_1 || caller == VP_PC_WAVE_CONNECT_2;
    if (!VPSVNativeWave || !VPSVEnabled || !VPSVGeometryValid || !VPSVFrameValid ||
        (!vertical && !connecting)) { CGContextStrokePath(context); return; }
    CGPathRef original = CGContextCopyPath(context);
    if (!original) { CGContextStrokePath(context); return; }
    if (vertical) {
        VPSVRemappedColumns++;
        if (VPSVRemappedColumns == 1 && getenv("VOCALOID_PATCHER_TEST_PROJECT")) NSLog(@"VP_TEST SV waveform first mapped column, pitch=%ld baseline=%ld rowHeight=%.2f", (long)VPSVFramePitch, (long)VPSVFrameBaseline, VPSVRowHeight);
        CGRect bounds = CGPathGetBoundingBox(original);
        VPSVPrevious = VPSVCurrent;
        VPSVCurrent = (VPSVColumn){.x = bounds.origin.x,
            .nativeCenter = VPSVReferenceTop + (VPSVReferencePitch - VPSVFramePitch + 0.5) * VPSVRowHeight,
            .center = VPSVReferenceTop + (VPSVReferencePitch - VPSVFrameBaseline + 3.5) * VPSVRowHeight,
            .baseline = VPSVFrameBaseline, .valid = YES};
        VPSVCurrent.top = CGRectGetMinY(bounds) - VPSVCurrent.nativeCenter;
        VPSVCurrent.bottom = CGRectGetMaxY(bounds) - VPSVCurrent.nativeCenter;
    }
    BOOL adjacent = VPSVPrevious.valid && fabs(VPSVPrevious.x + 1 - VPSVCurrent.x) < 0.01;
    if (connecting && (!adjacent || VPSVPrevious.baseline != VPSVCurrent.baseline)) {
        CGContextBeginPath(context); CGPathRelease(original); return;
    }
    CGMutablePathRef remapped = CGPathCreateMutable();
    VPSVPathMap mapping = {remapped, connecting};
    CGPathApply(original, &mapping, VPSVMapPath);
    CGContextBeginPath(context); CGContextAddPath(context, remapped); CGContextStrokePath(context);
    CGPathRelease(remapped); CGPathRelease(original);
    if (!vertical) return;
    if (adjacent && VPSVPrevious.baseline != VPSVCurrent.baseline) {
        VPSVBoundaryX = VPSVCurrent.x; VPSVBoundaryOldCenter = VPSVPrevious.center;
        VPSVBoundaryBaseline = VPSVCurrent.baseline; VPSVHasBoundary = YES;
        for (NSUInteger offset = 0; offset < VPSVHistoryCount; offset++) {
            VPSVColumn column = VPSVHistory[VPSVHistoryCount - 1 - offset];
            if (column.baseline != VPSVPrevious.baseline || fabs(column.x + offset + 1 - VPSVCurrent.x) > 0.01) break;
            CGFloat alpha = 1 - (VPSVCurrent.x - 1 - column.x) / 24.0;
            VPSVGhost(context, column.x, VPSVCurrent.center, column.top, column.bottom, alpha, NO, 0, 0);
        }
    }
    if (VPSVHasBoundary && VPSVCurrent.baseline == VPSVBoundaryBaseline && VPSVCurrent.x < VPSVBoundaryX + 24) {
        CGFloat alpha = 1 - (VPSVCurrent.x - VPSVBoundaryX) / 24.0;
        VPSVGhost(context, VPSVCurrent.x, VPSVBoundaryOldCenter, VPSVCurrent.top, VPSVCurrent.bottom,
                  alpha, adjacent && VPSVCurrent.x > VPSVBoundaryX, VPSVPrevious.top, VPSVPrevious.bottom);
    }
    if (VPSVHistoryCount == 24) { memmove(VPSVHistory, VPSVHistory + 1, sizeof(VPSVColumn) * 23); VPSVHistoryCount--; }
    VPSVHistory[VPSVHistoryCount++] = VPSVCurrent;
}
__attribute__((used)) static struct { const void *replacement; const void *original; }
VPSVStrokeInterpose __attribute__((section("__DATA,__interpose"))) = {
    (const void *)VPSVStroke, (const void *)CGContextStrokePath
};

@interface VPPreviewBudget : NSObject
@property CFTimeInterval lastFlush;
@property BOOL pending;
@property BOOL scheduled;
@end
@implementation VPPreviewBudget
@end
static BOOL VPPreviewThrottling;
static NSMapTable<NSView *, VPPreviewBudget *> *VPPreviewBudgets;
static void (*VPOriginalNeedsDisplay)(id, SEL, BOOL);
static uint64_t VPPreviewSuppressed;
uint64_t VPPreviewCoalescedRequests(void) { return VPPreviewSuppressed; }

static void VPFlushPreview(NSView *view) {
    VPPreviewBudget *budget = [VPPreviewBudgets objectForKey:view];
    if (!budget.pending) return;
    budget.pending = NO;
    budget.lastFlush = CACurrentMediaTime();
    VPOriginalNeedsDisplay(view, @selector(setNeedsDisplay:), YES);
}
static void VPQueuePreview(NSView *view) {
    VPPreviewBudget *budget = [VPPreviewBudgets objectForKey:view];
    if (!budget) { budget = [VPPreviewBudget new]; [VPPreviewBudgets setObject:budget forKey:view]; }
    CFTimeInterval now = CACurrentMediaTime();
    if (now - budget.lastFlush >= 1.0 / 30) {
        budget.lastFlush = now; budget.pending = NO;
        VPOriginalNeedsDisplay(view, @selector(setNeedsDisplay:), YES);
        return;
    }
    VPPreviewSuppressed++; budget.pending = YES;
    if (budget.scheduled) return;
    budget.scheduled = YES;
    __weak NSView *weakView = view;
    dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)((1.0 / 30 - (now - budget.lastFlush)) * NSEC_PER_SEC)),
                   dispatch_get_main_queue(), ^{
        NSView *currentView = weakView;
        budget.scheduled = NO;
        if (currentView) VPFlushPreview(currentView);
    });
}

static void VPBudgetNeedsDisplay(NSView *view, SEL selector, BOOL value) {
    uintptr_t caller = (uintptr_t)__builtin_return_address(0) - VPWaveSlide;
    BOOL renderingPreview = caller == VP_PC_PREVIEW_REDRAW_1 || caller == VP_PC_PREVIEW_REDRAW_2 || caller == VP_PC_PREVIEW_REDRAW_3;
    if (!VPPreviewThrottling || !value || !renderingPreview) {
        VPOriginalNeedsDisplay(view, selector, value);
        return;
    }
    VPQueuePreview(view);
}

static IMP VPSVNoticeOriginals[5];
static SEL VPSVNoticeSelectors[5];
static void VPSVNotice(id object, SEL selector, id notification) {
    VPSVGeneration++;
    for (NSUInteger index = 0; index < 5; index++) if (selector == VPSVNoticeSelectors[index]) {
        ((void (*)(id, SEL, id))VPSVNoticeOriginals[index])(object, selector, notification);
        if (index >= 2) VPFlushPreview(object);
        return;
    }
}

@interface VPNativeOptions : NSObject
@property NSMapTable<NSView *, id> *originalColors;
@property NSMapTable<NSWindow *, NSDictionary *> *originalWindows;
@property BOOL darkToolbar;
@property NSString *settingsPath;
@property NSTimer *timer;
@end

@implementation VPNativeOptions
- (void)setBackground:(NSView *)view color:(NSColor *)color {
    if (!view) return;
    Ivar ivar = class_getInstanceVariable(view.class, "backgroundColor");
    if (!ivar) return;
    id old = VPNativeObjectIvar(view, "backgroundColor");
    if (old && ![old isKindOfClass:NSColor.class]) return;
    if ([old isEqual:color]) return;
    if (![self.originalColors objectForKey:view]) [self.originalColors setObject:old ?: NSNull.null forKey:view];
    // The pinned Swift field is a strong NSColor reference. Use ARC for balanced ownership.
    id __strong *slot = (id __strong *)((__bridge void *)view + ivar_getOffset(ivar));
    *slot = color;
    view.needsDisplay = YES;
}
- (void)applyToView:(NSView *)view {
    NSString *name = NSStringFromClass(view.class);
    if ([name isEqualToString:@"VOCALOID7_Editor.VEMainToolbarView"] ||
        [name isEqualToString:@"VOCALOID7_Editor.VEEditorToolbarView"]) {
        NSColor *background = [NSColor colorWithCalibratedRed:0x17/255.0 green:0x18/255.0 blue:0x19/255.0 alpha:1];
        [self setBackground:view color:background];
        id toolBackground = VPNativeObjectIvar(view, "toolViewBG");
        if ([toolBackground isKindOfClass:NSView.class]) [self setBackground:toolBackground color:background];
        id tools = VPNativeObjectIvar(view, "toolView");
        if ([tools isKindOfClass:NSView.class]) [self setBackground:tools color:background];
    }
    for (NSView *child in view.subviews) [self applyToView:child];
}
- (void)refresh:(id)sender {
    (void)sender;
    if (!self.darkToolbar) return;
    for (NSDocument *document in NSDocumentController.sharedDocumentController.documents) {
        for (NSWindowController *controller in document.windowControllers) {
            NSWindow *window = controller.window;
            if (![self.originalWindows objectForKey:window]) {
                [self.originalWindows setObject:@{@"color": window.backgroundColor,
                    @"appearance": window.appearance ?: NSNull.null,
                    @"transparent": @(window.titlebarAppearsTransparent)} forKey:window];
                window.appearance = [NSAppearance appearanceNamed:NSAppearanceNameDarkAqua];
                window.titlebarAppearsTransparent = YES;
                window.backgroundColor = [NSColor colorWithCalibratedRed:0x2d/255.0 green:0x2d/255.0 blue:0x30/255.0 alpha:1];
            }
            [self applyToView:window.contentView];
        }
    }
}
- (void)restore {
    for (NSView *view in self.originalColors) {
        id color = [self.originalColors objectForKey:view];
        Ivar ivar = class_getInstanceVariable(view.class, "backgroundColor");
        if (!ivar) continue;
        id __strong *slot = (id __strong *)((__bridge void *)view + ivar_getOffset(ivar));
        *slot = color == NSNull.null ? nil : color;
        view.needsDisplay = YES;
    }
    for (NSWindow *window in self.originalWindows) {
        NSDictionary *state = [self.originalWindows objectForKey:window];
        window.backgroundColor = state[@"color"];
        window.appearance = state[@"appearance"] == NSNull.null ? nil : state[@"appearance"];
        window.titlebarAppearsTransparent = [state[@"transparent"] boolValue];
    }
    [self.originalColors removeAllObjects];
    [self.originalWindows removeAllObjects];
}
- (void)togglePreviewBudget:(NSMenuItem *)item {
    VPPreviewThrottling = !VPPreviewThrottling;
    item.state = VPPreviewThrottling ? NSControlStateValueOn : NSControlStateValueOff;
    if (!VPPreviewThrottling) for (NSView *view in VPPreviewBudgets) VPFlushPreview(view);
    [self saveSettings];
}
- (void)releaseUnusedHeap:(id)sender {
    (void)sender;
    size_t released = malloc_zone_pressure_relief(NULL, 0);
    NSAlert *alert = [NSAlert new];
    alert.messageText = VPUIString(@"已请求释放闲置堆内存");
    alert.informativeText = [NSString stringWithFormat:VPUIString(@"分配器报告本次回收 %.1f MB。"), released / (1024.0 * 1024)];
    [alert runModal];
}
- (void)toggleSVWaveform:(NSMenuItem *)item {
    VPSVEnabled = !VPSVEnabled;
    item.state = VPSVEnabled ? NSControlStateValueOn : NSControlStateValueOff;
    VPSVGeneration++;
    [self saveSettings];
    for (NSWindow *window in NSApp.windows) VPNativeInvalidatePiano(window.contentView);
}
- (void)saveSettings {
    NSData *json = [NSJSONSerialization dataWithJSONObject:@{@"darkToolbar": @(self.darkToolbar),
        @"waveformOpacity": @(VPWaveOpacity), @"svWaveform": @(VPSVEnabled), @"previewThrottling": @(VPPreviewThrottling)} options:0 error:nil];
    [json writeToFile:self.settingsPath atomically:YES];
}
- (void)waveformOpacity:(id)sender {
    (void)sender;
    NSAlert *alert = [NSAlert new];
    alert.messageText = VPUIString(@"波形不透明度（0–100%）");
    NSTextField *field = [[NSTextField alloc] initWithFrame:NSMakeRect(0, 0, 240, 24)];
    field.stringValue = [NSString stringWithFormat:@"%.0f", VPWaveOpacity * 100];
    alert.accessoryView = field;
    [alert addButtonWithTitle:VPUIString(@"确定")];
    [alert addButtonWithTitle:VPUIString(@"取消")];
    [alert.window setInitialFirstResponder:field];
    if ([alert runModal] != NSAlertFirstButtonReturn) return;
    NSScanner *scanner = [NSScanner scannerWithString:field.stringValue];
    double percent = 0;
    if (![scanner scanDouble:&percent] || !scanner.isAtEnd || !isfinite(percent) || percent < 0 || percent > 100) {
        NSAlert *error = [NSAlert new];
        error.messageText = VPUIString(@"请输入 0 到 100 的数值。");
        [error runModal];
        return;
    }
    VPWaveOpacity = percent / 100;
    [self saveSettings];
    for (NSWindow *window in NSApp.windows) VPNativeInvalidatePiano(window.contentView);
}
- (void)toggleDarkToolbar:(NSMenuItem *)item {
    self.darkToolbar = !self.darkToolbar;
    item.state = self.darkToolbar ? NSControlStateValueOn : NSControlStateValueOff;
    if (self.darkToolbar) [self refresh:nil];
    else [self restore];
    [self saveSettings];
}
@end

NSMenu *installNativeOptions(NSString *root) {
    if (!VPNativeSupported()) return nil;
    VPWaveSupported = NO;
    for (uint32_t index = 0; index < _dyld_image_count(); index++) {
        const struct mach_header *header = _dyld_get_image_header(index);
        if (header && header->filetype == MH_EXECUTE) {
            VPWaveSlide = _dyld_get_image_vmaddr_slide(index);
            VPWaveSupported = YES;
            break;
        }
    }
    static VPNativeOptions *options;
    options = [VPNativeOptions new];
    options.originalColors = [NSMapTable weakToStrongObjectsMapTable];
    options.originalWindows = [NSMapTable weakToStrongObjectsMapTable];
    options.settingsPath = [root stringByAppendingPathComponent:@"native-options.json"];
    NSData *stored = [NSData dataWithContentsOfFile:options.settingsPath];
    id record = stored ? [NSJSONSerialization JSONObjectWithData:stored options:0 error:nil] : nil;
    if ([record isKindOfClass:NSDictionary.class] && [record[@"darkToolbar"] isKindOfClass:NSNumber.class])
        options.darkToolbar = [record[@"darkToolbar"] boolValue];
    if ([record isKindOfClass:NSDictionary.class] && [record[@"waveformOpacity"] isKindOfClass:NSNumber.class]) {
        double value = [record[@"waveformOpacity"] doubleValue];
        if (isfinite(value) && value >= 0 && value <= 1) VPWaveOpacity = value;
    }
    if ([record isKindOfClass:NSDictionary.class] && [record[@"svWaveform"] isKindOfClass:NSNumber.class])
        VPSVEnabled = [record[@"svWaveform"] boolValue];
    if ([record isKindOfClass:NSDictionary.class] && [record[@"previewThrottling"] isKindOfClass:NSNumber.class])
        VPPreviewThrottling = [record[@"previewThrottling"] boolValue];
    VPPreviewBudgets = [NSMapTable weakToStrongObjectsMapTable];
    Method display = class_getInstanceMethod(NSView.class, @selector(setNeedsDisplay:));
    VPOriginalNeedsDisplay = (void (*)(id, SEL, BOOL))method_setImplementation(display, (IMP)VPBudgetNeedsDisplay);
    VPSVCaches = [NSMapTable weakToStrongObjectsMapTable];
    Class scores = NSClassFromString(@"ComYamahaVSM7WrapOCIVSMScoreList");
    Method score = class_getInstanceMethod(scores, @selector(scoreAtIndex:));
    if (score) VPSVOriginalScore = (const void *(*)(id, SEL, NSInteger))method_setImplementation(score, (IMP)VPSVReadScore);
    Class piano = NSClassFromString(@"VOCALOID7_Editor.VEPianoRollBodyView");
    NSArray *notifications = @[@"rendererDidStart:", @"rendererDidBlockRendering:", @"rendererDidComplete:", @"rendererDidCancel:", @"activePartDidChange:"];
    for (NSUInteger index = 0; index < notifications.count; index++) {
        SEL selector = NSSelectorFromString(notifications[index]);
        Method method = class_getInstanceMethod(piano, selector);
        if (method) { VPSVNoticeSelectors[index] = selector; VPSVNoticeOriginals[index] = method_setImplementation(method, (IMP)VPSVNotice); }
    }
    NSMenu *menu = [[NSMenu alloc] initWithTitle:VPUIString(@"布局与波形")];
    NSMenuItem *item = [[NSMenuItem alloc] initWithTitle:VPUIString(@"V6 深色工具栏与标题栏") action:@selector(toggleDarkToolbar:) keyEquivalent:@""];
    item.target = options;
    item.state = options.darkToolbar ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:item];
    NSMenuItem *opacity = [[NSMenuItem alloc] initWithTitle:VPUIString(@"波形不透明度…") action:@selector(waveformOpacity:) keyEquivalent:@""];
    opacity.target = options;
    [menu addItem:opacity];
    if (VPSVOriginalScore) {
        NSMenuItem *sv = [[NSMenuItem alloc] initWithTitle:VPUIString(@"SV 样式波形") action:@selector(toggleSVWaveform:) keyEquivalent:@""];
        sv.target = options; sv.state = VPSVEnabled ? NSControlStateValueOn : NSControlStateValueOff;
        [menu addItem:sv];
    }
    NSMenuItem *preview = [[NSMenuItem alloc] initWithTitle:VPUIString(@"合成预览刷新限制为 30 fps") action:@selector(togglePreviewBudget:) keyEquivalent:@""];
    preview.target = options; preview.state = VPPreviewThrottling ? NSControlStateValueOn : NSControlStateValueOff;
    [menu addItem:preview];
    NSMenuItem *memory = [[NSMenuItem alloc] initWithTitle:VPUIString(@"释放闲置堆内存") action:@selector(releaseUnusedHeap:) keyEquivalent:@""];
    memory.target = options; [menu addItem:memory];
    options.timer = [NSTimer scheduledTimerWithTimeInterval:1 target:options selector:@selector(refresh:) userInfo:nil repeats:YES];
    [options refresh:nil];
    return menu;
}
