#import "../FormatBridge.m"
NSString *VPTranslateStaticUIString(NSString *text) { return text; }
NSDocument *VPCurrentDocument(void) { return nil; }
#import <assert.h>

@interface VPTestVoice : NSObject <VPFormatVoiceTrack>
@property BOOL ai;
@end
@implementation VPTestVoice
- (BOOL)isAi { return self.ai; }
- (NSString *)voiceBankID { return self.ai ? @"BXHPECHANDRW3XEL" : @"legacy-bank"; }
- (NSString *)voiceName { return self.ai ? @"asa" : @"legacy-voice"; }
@end

int main(void) {
    @autoreleasepool {
        VPTestVoice *voice = [VPTestVoice new];
        voice.ai = YES;
        NSDictionary *provided = @{};
        NSDictionary *defaults = VPFormatImportOptions(provided, voice);
        assert([defaults[@"is_ai_singer"] isEqual:@YES]);
        assert([defaults[@"default_comp_id"] isEqual:@"BXHPECHANDRW3XEL"]);
        assert([defaults[@"default_singer_name"] isEqual:@"asa"]);
        assert(provided.count == 0);
        NSDictionary *legacy = VPFormatImportOptions(@{@"is_ai_singer":@NO}, voice);
        assert([legacy[@"is_ai_singer"] isEqual:@NO]);
        assert(!legacy[@"default_comp_id"]);
        NSDictionary *custom = @{@"is_ai_singer":@NO, @"default_comp_id":@"custom-bank", @"default_singer_name":@"custom-voice"};
        assert([VPFormatImportOptions(custom, voice) isEqualToDictionary:custom]);
        voice.ai = NO;
        NSDictionary *modern = VPFormatImportOptions(@{}, voice);
        assert([modern[@"is_ai_singer"] isEqual:@YES] && !modern[@"default_comp_id"]);
        NSDictionary *matchingLegacy = VPFormatImportOptions(@{@"is_ai_singer":@NO}, voice);
        assert([matchingLegacy[@"default_comp_id"] isEqual:@"legacy-bank"]);
        assert([VPFormatImportOptions(@{}, nil)[@"is_ai_singer"] isEqual:@YES]);
        VPFormatBridge *bridge = [VPFormatBridge new];
        bridge.inputOptions = @"{}";
        bridge.outputOptions = @"{}";
        NSArray *exportArguments = [bridge argumentsFrom:[NSURL fileURLWithPath:@"/tmp/source.vprx"]
            to:[NSURL fileURLWithPath:@"/tmp/output.vpr"] overwrite:NO outputOptions:bridge.outputOptions];
        NSUInteger index = [exportArguments indexOfObject:@"--output-options"];
        assert([exportArguments[index + 1] isEqual:@"{}"]);
        NSData *json = [NSJSONSerialization dataWithJSONObject:defaults options:0 error:nil];
        [NSFileHandle.fileHandleWithStandardOutput writeData:json];
    }
    return 0;
}
