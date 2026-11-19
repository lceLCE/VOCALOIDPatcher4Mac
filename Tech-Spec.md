# Source release design

Keep the existing five native modules and the current zsh/Python toolchain. Compatibility.h owns the verified target version, executable digest and private code addresses. Launcher and injected modules use the same target constants. The command launcher invokes the compiled app launcher, avoiding a separate hash policy.

The repository keeps generated translation maps so building the verified target does not require proprietary SDKs or extracting editor resources. The generator and pinned upstream translations remain available for regeneration against a locally installed app. Converter dependencies are restored with uv into an ignored environment. build.command and check.command remain the single build and verification entry points.

Tests cover existing algorithms and integration guards; macOS editor/voicebank runtime tests remain a contributor responsibility because vendor software is not redistributable. No CI pipeline or automatic binary release is introduced in this initial publication.
