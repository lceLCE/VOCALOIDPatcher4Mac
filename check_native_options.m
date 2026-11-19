// Standalone checks for the native implementation. This process never opens the editor.
#include "NativeOptions.m"
NSString *VPTranslateStaticUIString(NSString *text) { return text; }
#include <assert.h>

CGRect VPRenderingNoteRect(NSView *view, id note) {
    (void)view;
    (void)note;
    return CGRectZero;
}

@interface VPTestScores : NSObject
@property NSInteger count;
@property NSInteger rawState;
@property NSMutableData *data;
- (NSInteger)numScores;
@end
@implementation VPTestScores
- (NSInteger)numScores { return self.count; }
@end

static const void *VPTestReadScore(id object, SEL selector, NSInteger index) {
    (void)selector;
    return (const float *)[(VPTestScores *)object data].bytes + index;
}
static unsigned VPTestDisplayCount;
static void VPTestDisplay(id object, SEL selector, BOOL value) {
    (void)object;
    (void)selector;
    if (value) VPTestDisplayCount++;
}

static void VPTestGrouping(void) {
    float input[] = {-900, -700, -FLT_MAX, -500, -100, -500, -FLT_MAX, -1000};
    int32_t expected[] = {60, 60, INT_MIN, 60, 64, 64, INT_MIN, 59};
    VPTestScores *scores = [VPTestScores new];
    scores.count = 8;
    scores.data = [NSMutableData dataWithBytes:input length:sizeof(input)];
    VPSVOriginalScore = VPTestReadScore;
    VPSVCaches = [NSMapTable weakToStrongObjectsMapTable];
    VPSVCache *first = VPSVBuildCache(scores);
    assert(first && first.baselines.length == sizeof(expected));
    assert(memcmp(first.baselines.bytes, expected, sizeof(expected)) == 0);
    assert(VPSVBuildCache(scores) == first);
    scores.rawState++;
    assert(VPSVBuildCache(scores) != first);
    VPSVCache *second = VPSVBuildCache(scores);
    VPSVGeneration++;
    assert(VPSVBuildCache(scores) != second);
    scores.count = 4000001;
    assert(VPSVBuildCache(scores) == nil);
}

static void VPTestPreviewCoalescing(void) {
    NSView *view = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 400, 300)];
    VPOriginalNeedsDisplay = VPTestDisplay;
    VPPreviewBudgets = [NSMapTable weakToStrongObjectsMapTable];
    VPTestDisplayCount = 0;
    VPPreviewSuppressed = 0;
    VPQueuePreview(view);
    assert(VPTestDisplayCount == 1);
    for (unsigned i = 0; i < 30; i++) VPQueuePreview(view);
    assert(VPTestDisplayCount == 1 && VPPreviewSuppressed == 30);
    assert([VPPreviewBudgets objectForKey:view].pending);
    VPFlushPreview(view);
    assert(VPTestDisplayCount == 2 && ![VPPreviewBudgets objectForKey:view].pending);
    VPFlushPreview(view);
    assert(VPTestDisplayCount == 2);
}

int main(void) {
    @autoreleasepool {
        VPTestGrouping();
        VPTestPreviewCoalescing();
        puts("PASS SV grouping/invalidation/limit, preview coalescing/final flush");
    }
}
