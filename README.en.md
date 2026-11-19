# VOCALOIDPatcher4Mac

Native macOS trial port of [IzumiiKonata/VOCALOIDPatcher](https://github.com/IzumiiKonata/VOCALOIDPatcher), licensed under GPL-3.0. Includes the Objective-C implementation, translation sources, pinned local format converter, build scripts and regression checks.

**Verified target: Apple Silicon, macOS 15+, one specific VOCALOID7 Editor 7.0.0 executable. This is not complete Windows feature parity.** The loader checks the full executable digest. A matching marketing version alone is insufficient.

Install Xcode Command Line Tools, [uv](https://github.com/astral-sh/uv), and your own VOCALOID7 Editor, then:

```sh
git clone https://github.com/lceLCE/VOCALOIDPatcher4Mac.git
cd VOCALOIDPatcher4Mac
./build.command
./conversion/setup.command
./check.command
./启动.command
```

The default editor path is `/Applications/VOCALOID7 Editor.app`. Keep the generated launcher app and dylib beside localization/ and conversion/. Quit any existing editor before launching. The original editor files are not modified; launch the editor normally to run without the patcher.

Features include five-language UI/menu translation, piano-roll overlays, custom still/GIF/video artwork, lyric/quantization/harmony/swing jobs, project/subtitle conversion, pinyin, timed VPRX save, output spectrum and waveform options. AU/VST hosts, Intel, Inspector relocation and several Windows performance patches remain unsupported. Foreign-format conversion does not establish lossless V7 synthesis controls.

Read [BUILDING](docs/BUILDING.md) and the English [ADAPTING guide](docs/ADAPTING.md) before changing targets. [Compatibility.h](Compatibility.h) is the central inventory of verified version/digest/code addresses. Updating its hash without re-establishing the ABI is unsafe and does not make a working port. The repository includes no vendor editor, voice banks, local environment, binaries or personal projects.

See [validation scope](docs/VALIDATION.md), [license](LICENSE), and [attribution](NOTICE.md).
