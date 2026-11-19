#import "Patcher.m"
#include <assert.h>
#include <fenv.h>

BOOL VPSupportedEditor(void) { return NO; }
NSMenu *installRendering(NSString *root) { (void)root;return nil; }
NSMenu *installConversion(NSString *root) { (void)root;return nil; }
NSMenu *installNativeOptions(NSString *root) { (void)root;return nil; }
NSMenuItem *installSpectrum(void) { return nil; }

int main(void) {
    [NSApplication sharedApplication];
    VPTranslations = @{@"文件": @"File", @"打开": @"Open"};
    NSMenu *menu = [[NSMenu alloc] initWithTitle:@"文件"];
    NSMenuItem *open = [[NSMenuItem alloc] initWithTitle:@"打开" action:nil keyEquivalent:@""];
    [menu addItem:open];
    VPTranslateMenu(menu);
    assert([menu.title isEqualToString:@"File"] && [open.title isEqualToString:@"Open"]);
    assert(VPRoundToEven(2.5)==2);
    assert(VPRoundToEven(3.5)==4);
    assert(VPRoundToEven(-2.5)==-2);
    int rounding=fegetround();fesetround(FE_DOWNWARD);
    assert(VPRoundToEven(2.5)==2 && VPRoundToEven(3.5)==4);
    fesetround(rounding);
    for(NSInteger pitch=0;pitch<128;pitch++) {
        assert(VPHarmonyPitch(pitch,60,7)==pitch+12);
        assert(VPHarmonyPitch(pitch,60,-7)==pitch-12);
    }
    assert(VPHarmonyPitch(60,60,2)==64);
    assert(VPHarmonyPitch(62,60,2)==65);
    assert(VPHarmonyPitch(64,60,2)==67);
    assert(VPHarmonyPitch(62,60,-2)==59);
    puts("PASS native menu and item language switching, midpoint-to-even rounding and chromatic octave preservation");
    return 0;
}
