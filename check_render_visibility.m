// Compile this file as a standalone executable. It never opens VOCALOID.
#import "Rendering.m"
#include <assert.h>

NSDocument *VPCurrentDocument(void) { return nil; }
NSString *VPTranslateStaticUIString(NSString *text) { return text; }
void VPWaveBeginNativeDraw(NSView *view) { (void)view; }
void VPWaveEndNativeDraw(void) {}

@interface VPVisibilityNote : NSObject <VPDrawNote>
@property int64_t begin;
@property int64_t end;
@end
@implementation VPVisibilityNote
- (VPDrawTick)absPosTick { return (VPDrawTick){self.begin}; }
- (VPDrawTick)absEndTick { return (VPDrawTick){self.end}; }
- (NSInteger)noteNumber { return 60; }
- (NSString *)lyric { return @"a"; }
- (NSString *)phonemes { return @"a"; }
@end

@interface VPVisibilityPart : NSObject <VPDrawPart>
@property NSArray<VPVisibilityNote *> *notes;
@property NSUInteger reads;
@property int64_t origin;
@end
@implementation VPVisibilityPart
- (NSUInteger)numNote { return self.notes.count; }
- (id<VPDrawNote>)note:(NSUInteger)index { self.reads++; return self.notes[index]; }
- (VPDrawTick)absPosTick { return (VPDrawTick){self.origin}; }
- (void *)unwrap { return (__bridge void *)self; }
@end

static VPVisibilityNote *VPTestNote(int64_t begin, int64_t end) {
    VPVisibilityNote *note = [VPVisibilityNote new];
    note.begin = begin;
    note.end = end;
    return note;
}
static unsigned VPForwardedUpdates;
static void VPForwardUpdate(id object, SEL selector, id notification) {
    (void)object;
    (void)selector;
    (void)notification;
    VPForwardedUpdates++;
}

int main(void) {
    @autoreleasepool {
        VPDrawTickWindow window = VPDrawTicksForPixels(NSMakeRect(105, 0, 100, 300), 5, 1);
        assert(window.valid && window.begin == 98 && window.end == 202);
        assert(VPDrawIntervalOverlaps(-100, 1000, window));
        assert(VPDrawIntervalOverlaps(98, 98, window));
        assert(VPDrawIntervalOverlaps(202, 203, window));
        assert(!VPDrawIntervalOverlaps(10, 97, window));
        assert(!VPDrawIntervalOverlaps(203, 500, window));
        assert(!VPDrawTicksForPixels(NSMakeRect(0, 0, 100, 100), 5, 0).valid);
        assert(!VPDrawTicksForPixels(NSMakeRect(0, 0, 100, 100), NAN, 1).valid);
        VPDrawTickWindow negative = VPDrawTicksForPixels(NSMakeRect(-105, 0, 100, 100), 5, 1);
        assert(negative.valid && negative.begin < 0 && negative.end < 0);
        VPPartCoverage = [NSCache new];
        VPVisibilityPart *offscreen = [VPVisibilityPart new];
        offscreen.notes = @[VPTestNote(5000, 5100), VPTestNote(5200, 5300)];
        assert(!VPPartMayOverlapWindow(offscreen, window));
        assert(offscreen.reads == 2);
        for (unsigned frame = 0; frame < 100; frame++) assert(!VPPartMayOverlapWindow(offscreen, window));
        assert(offscreen.reads == 2);
        VPVisibilityPart *overlapping = [VPVisibilityPart new];
        // Deliberately unsorted and overlapping. A long early note crosses the whole window.
        overlapping.notes = @[VPTestNote(150, 300), VPTestNote(-100, 1000), VPTestNote(10, 50)];
        assert(VPPartMayOverlapWindow(overlapping, window));
        assert(VPNoteMayOverlapWindow(overlapping.notes[0], window));
        assert(VPNoteMayOverlapWindow(overlapping.notes[1], window));
        assert(!VPNoteMayOverlapWindow(overlapping.notes[2], window));
        offscreen.notes[0].begin = 150;
        offscreen.notes[0].end = 200;
        VPOriginalCoverageUpdate = VPForwardUpdate;
        VPCoverageSequenceUpdate(nil, @selector(sequenceUpdate:), nil);
        assert(VPForwardedUpdates == 1);
        assert(VPPartMayOverlapWindow(offscreen, window));
        assert(offscreen.reads == 4);
        offscreen.origin++;
        assert(VPPartMayOverlapWindow(offscreen, window));
        assert(offscreen.reads == 6);
        puts("PASS visible tick margin/negative positions/boundaries, unsorted overlaps/long crossing notes, offscreen cache reuse, edit and part-move invalidation");
    }
}
