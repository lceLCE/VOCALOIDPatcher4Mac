#import <AppKit/AppKit.h>
#include <assert.h>

#import "Rendering.m"
void VPWaveBeginNativeDraw(NSView *view) { (void)view; }
void VPWaveEndNativeDraw(void) {}
NSString *VPTranslateStaticUIString(NSString *text) { return [text isEqualToString:@"WEB"] ? @"网页" : text; }
NSDocument *VPCurrentDocument(void) { return nil; }

@interface VPInheritedTabCheck : NSView
@end
@implementation VPInheritedTabCheck
@end

int main(int argc, const char *argv[]) {
    @autoreleasepool {
        assert(argc == 2);
        Class documentClass = objc_allocateClassPair(NSDocument.class, "VOCALOID7_Editor.VEDocument", 0);
        assert(documentClass);
        objc_registerClassPair(documentClass);
        NSDocument *first = [[documentClass alloc] init];
        NSDocument *second = [[documentClass alloc] init];
        NSDocument *unrelated = [NSDocument new];
        assert(VPArtSelectDocument(first, second, @[second]) == first);
        assert(VPArtSelectDocument(nil, second, @[first]) == second);
        assert(VPArtSelectDocument(unrelated, second, @[first]) == second);
        assert(VPArtSelectDocument(nil, nil, @[first]) == first);
        assert(VPArtSelectDocument(nil, nil, @[unrelated]) == nil);
        assert(VPArtSelectDocument(nil, nil, @[]) == nil);
        assert(VPStoredBoolean(@{@"flag": @YES}, @"flag", NO));
        assert(!VPStoredBoolean(@{@"flag": @NO}, @"flag", YES));
        assert(!VPStoredBoolean(@{@"flag": @1}, @"flag", NO));
        assert(VPStoredBoolean(@{@"flag": @"false"}, @"flag", YES));
        assert([VPTranslatedTabString(@"WEB") isEqualToString:@"WEB"]);
        VPStaticTabDrawScope = YES;
        assert([VPTranslatedTabString(@"WEB") isEqualToString:@"网页"]);
        NSDictionary *attributes = @{NSForegroundColorAttributeName: NSColor.redColor};
        NSAttributedString *styled = [[NSAttributedString alloc] initWithString:@"WEB" attributes:attributes];
        NSAttributedString *translated = VPTranslatedTabAttributedString(styled);
        assert([translated.string isEqualToString:@"网页"]);
        assert([[translated attributesAtIndex:0 effectiveRange:NULL] isEqualToDictionary:attributes]);
        VPNativeDrawScope = YES;
        assert([VPTranslatedTabString(@"WEB") isEqualToString:@"WEB"]);
        VPNativeDrawScope = NO;
        VPStaticTabDrawScope = NO;
        IMP sharedDraw = method_getImplementation(class_getInstanceMethod(NSView.class, @selector(drawRect:)));
        assert(VPReplaceOwnedDraw(VPInheritedTabCheck.class, (IMP)VPDrawTabs) == NULL);
        assert(method_getImplementation(class_getInstanceMethod(NSView.class, @selector(drawRect:))) == sharedDraw);
        VPArtwork *artwork = [VPArtwork new];
        artwork.drawingSettingsPath = [NSString stringWithUTF8String:argv[1]];
        artwork.enabled = NO;
        VPShowPitchNames = YES;
        VPShowGhostNotes = NO;
        VPSkipMutedGhosts = YES;
        VPCenteredLyrics = YES;
        VPRoundedNotes = NO;
        [artwork saveDrawingSettings];
        NSDictionary *saved = [NSDictionary dictionaryWithContentsOfFile:artwork.drawingSettingsPath];
        assert(saved.count == 6);
        assert(VPStoredBoolean(saved, @"pitchNames", NO));
        assert(!VPStoredBoolean(saved, @"ghostNotes", YES));
        assert(VPStoredBoolean(saved, @"centeredLyrics", NO));
        assert(!VPStoredBoolean(saved, @"roundedNotes", YES));
        assert(!VPStoredBoolean(saved, @"artworkEnabled", YES));
        VPArtSuppressedViews = [NSHashTable weakObjectsHashTable];
        NSView *native = [[NSView alloc] initWithFrame:NSMakeRect(0, 0, 100, 100)];
        native.hidden = NO;
        [artwork suppressNativeView:native];
        assert([VPArtSuppressedViews containsObject:native]);
        assert(!native.hidden);
        [artwork suppressNativeView:nil];
        assert(![VPArtSuppressedViews containsObject:native]);
        assert(!native.hidden);
        [NSFileManager.defaultManager removeItemAtPath:artwork.drawingSettingsPath error:nil];
        puts("Drawing settings and reversible native-art suppression checks passed.");
    }
    return 0;
}
