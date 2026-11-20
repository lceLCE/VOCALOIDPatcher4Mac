#import "Compatibility.h"
#import <AppKit/AppKit.h>
#import <CommonCrypto/CommonDigest.h>
#include <unistd.h>

static int VPLaunchFailure(NSString *message) {
  [NSApplication sharedApplication];
  NSAlert *alert = [NSAlert new];
  alert.messageText = @"VOCALOID7 Patcher";
  alert.informativeText = message;
  [alert runModal];
  return 1;
}

int main(int argc, char *argv[]) {
  (void)argc;
  @autoreleasepool {
#if defined(VP_EMBEDDED)
    NSString *app = NSBundle.mainBundle.bundlePath;
    NSString *support = [NSFileManager.defaultManager URLsForDirectory:NSApplicationSupportDirectory
                                                           inDomains:NSUserDomainMask].firstObject.path;
    NSString *root = [support stringByAppendingPathComponent:@"VOCALOIDPatcher/VOCALOID7"];
#else
    NSString *root =
        NSBundle.mainBundle.bundleURL.URLByDeletingLastPathComponent.path;
    const char *configured = getenv("VOCALOID_EDITOR_APP");
    NSString *app = configured ? [NSString stringWithUTF8String:configured]
                               : @"/Applications/VOCALOID7 Editor.app";
#endif
    NSString *nativeApp = [app stringByAppendingPathComponent:@"Contents/Resources/Native/VOCALOID7 Editor.app"];
    if ([NSFileManager.defaultManager fileExistsAtPath:nativeApp]) app = nativeApp;
    NSString *executable =
        [app stringByAppendingPathComponent:@"Contents/MacOS/VOCALOID7 Editor"];
    NSData *bytes = [NSData dataWithContentsOfFile:executable
                                           options:NSDataReadingMappedIfSafe
                                             error:nil];
    if (!bytes || bytes.length > UINT_MAX)
      return VPLaunchFailure(
          @"无法读取 VOCALOID7 Editor，请检查应用安装位置。");
    unsigned char digest[CC_SHA256_DIGEST_LENGTH];
    CC_SHA256(bytes.bytes, (CC_LONG)bytes.length, digest);
    NSMutableString *hex = [NSMutableString string];
    for (NSUInteger index = 0; index < sizeof(digest); index++)
      [hex appendFormat:@"%02x", digest[index]];
    if (![hex isEqualToString:VP_EDITOR_SHA256])
      return VPLaunchFailure([NSString stringWithFormat:@"此构建适配已验证的 VOCALOID7 Editor %@。当前编辑器构建不同，需要更新补丁适配。", VP_EDITOR_VERSION]);
    NSString *library =
        [root stringByAppendingPathComponent:@"VOCALOIDPatcher.dylib"];
    if (![NSFileManager.defaultManager fileExistsAtPath:library])
      return VPLaunchFailure(@"补丁动态库缺失，请保留完整交付目录。");
    NSString *python =
        [root stringByAppendingPathComponent:@"conversion/.venv/bin/python"];
    if (![NSFileManager.defaultManager isExecutableFileAtPath:python]) {
      NSTask *setup = [NSTask new];
      setup.executableURL = [NSURL fileURLWithPath:@"/bin/zsh"];
      setup.arguments = @[ [root
          stringByAppendingPathComponent:@"conversion/setup.command"] ];
      NSError *error = nil;
      if (![setup launchAndReturnError:&error])
        return VPLaunchFailure(error.localizedDescription);
      [setup waitUntilExit];
      if (setup.terminationStatus != 0)
        return VPLaunchFailure(@"格式转换环境初始化失败。请运行 "
                               @"conversion/setup.command 查看具体错误。");
    }
    unsetenv("VOCALOID_PATCHER_TEST_PROJECT");
    setenv("VOCALOID_PATCHER_ROOT", root.fileSystemRepresentation, 1);
    setenv("DYLD_INSERT_LIBRARIES", library.fileSystemRepresentation, 1);
    argv[0] = (char *)executable.fileSystemRepresentation;
    execv(executable.fileSystemRepresentation, argv);
    return VPLaunchFailure(@"VOCALOID7 Editor 启动失败。");
  }
}
