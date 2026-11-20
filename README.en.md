# VOCALOIDPatcher4Mac

**[Full user guide](docs/USER-GUIDE.en.md) · [简体中文](README.md) · [Install / restore](docs/INSTALLING.md) · [Porting guide](docs/ADAPTING.md) · [Validation](docs/VALIDATION.md)**

Native macOS trial port of [IzumiiKonata/VOCALOIDPatcher](https://github.com/IzumiiKonata/VOCALOIDPatcher), using Objective-C, AppKit and a local Python converter. Licensed under [GPL-3.0](LICENSE).

After direct installation, **open the existing VOCALOID7 Editor icon normally**. Translation remains available after quitting and reopening. Terminal is needed for the initial source build/install, not daily use; a separate launcher is optional.

## Verified target

Apple Silicon, macOS 15+, one VOCALOID7 Editor 7.0.0 native executable with SHA-256:

```text
eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92
```

A matching version label alone does not establish compatibility. Other builds need the [ABI adaptation workflow](docs/ADAPTING.md); changing only a hash is insufficient. This repository contains source, maps and scripts, not an editor, voice bank or prebuilt complete app.

## First installation

Install Xcode Command Line Tools, [uv](https://docs.astral.sh/uv/getting-started/installation/) and your own working editor. See the [full guide](docs/USER-GUIDE.en.md) for prerequisites, expected results and troubleshooting.

```sh
git clone https://github.com/lceLCE/VOCALOIDPatcher4Mac.git
cd VOCALOIDPatcher4Mac
./build.command
./conversion/setup.command
./check.command
```

Save projects, quit the editor completely, and install once:

```sh
conversion/.venv/bin/python install.py install
```

Then open `/Applications/VOCALOID7 Editor.app` normally. The installer retains a complete original backup, keeps the native editor bytes unchanged and verifies bundle signatures. Runtime files and settings are copied to the current user's Application Support directory. Do not open the internal Native app or backup directly.

## Features and limits

Five-language UI/menu translation, piano-roll labels/ghost notes/rounded notes, still/GIF/video artwork, lyric/duration/harmony/swing jobs, project/subtitle conversion and pinyin, timed VPRX save, output spectrum, waveform and toolbar options. The [guide](docs/USER-GUIDE.en.md) documents each menu and its parameters.

Windows parity is incomplete: Intel, AU/VST hosts, Inspector relocation, simultaneous harmony-interval selection and several Windows-specific performance patches remain unsupported. Lossless V7 synthesis controls across foreign formats are not established.

## Update and restore

Pulling source does not update the installed copy. Quit and restore before rebuilding/reinstalling; follow the [update workflow](docs/USER-GUIDE.en.md#update-and-restore). Editor upgrades require renewed compatibility verification.

```sh
conversion/.venv/bin/python install.py restore
```

If the source checkout is gone, use the [self-contained recovery files](docs/INSTALLING.md#restore). Restore retains settings/backups and refuses to overwrite an externally changed installation.

[Build details](docs/BUILDING.md) · [Compatibility constants](Compatibility.h) · [Attribution](NOTICE.md). Contributions should include target identity, minimal reproduction and sanitized results; never upload proprietary binaries, voice banks, private projects, backups or credentials.
