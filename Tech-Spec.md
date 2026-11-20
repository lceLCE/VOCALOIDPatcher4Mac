# Source release design

Keep the existing five native modules and the current zsh/Python toolchain. Compatibility.h owns the verified target version, executable digest and private code addresses. Launcher and injected modules use the same target constants. The command launcher invokes the compiled app launcher, avoiding a separate hash policy.

The repository keeps generated translation maps so building the verified target does not require proprietary SDKs or extracting editor resources. The generator and pinned upstream translations remain available for regeneration against a locally installed app. Converter dependencies are restored with uv into an ignored environment. build.command and check.command remain the single build and verification entry points.

Tests cover existing algorithms and integration guards; macOS editor/voicebank runtime tests remain a contributor responsibility because vendor software is not redistributable. No CI pipeline or automatic binary release is introduced in this initial publication.

## Native app entry point

Build Launcher.m twice: standalone and embedded (VP_EMBEDDED). Embedded mode locates the complete, unchanged editor app under Contents/Resources/Native/VOCALOID7 Editor.app and loads the patch from user Application Support/VOCALOIDPatcher/VOCALOID7. The installed outer app preserves the original Info.plist, icon and bundle identifier; its entry point is the native bootstrap. Keeping the full vendor bundle intact preserves its Info.plist-bound signature and relative resource/framework paths. Original vendor executable bytes and private addresses are unchanged. Digest guards use _NSGetExecutablePath to validate the running executable.

Mutable converter/settings live outside the signed bundles. Installation prepares and signs a complete outer app before replacement, with an independently verified complete original backup and a recovery record. The same-directory bundle swap rolls back if verification fails. Restore checks the current installed hashes and original backup before replacing anything. No global environment or system security setting is changed.
