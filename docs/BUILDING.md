# Building from source / 源码构建

## Requirements

- Apple Silicon Mac running macOS 15 or newer.
- Xcode Command Line Tools with an SDK supporting the APIs used here; `xcrun --find clang` must succeed.
- Git, zsh and uv. Python 3.12 is provisioned by uv if needed.
- An installed editor is needed to run the patcher. A proprietary SDK is not needed to compile it. Prepared translation maps are included, so compilation and the synthetic regression suite do not need editor resource extraction.

## Build and check

From the repository root:

```sh
./build.command
./conversion/setup.command
./check.command
```

The native build uses Apple clang, ARC, `-arch arm64`, deployment target macOS 15.0 and `-Wall -Wextra -Werror`. It links only system frameworks. Outputs are `VOCALOIDPatcher.dylib` and `VOCALOID7 Patcher.app`. They are ignored by Git. Conversion dependencies are restored from the exact versions in `conversion/requirements.txt`; no Python packages are installed globally. Tests create `.check-build/` and `conversion/validation.json` locally.

The checks cover native menu translation, rounding/harmony, stereo capture, drawing settings and visible ranges, cache invalidation, waveform grouping, preview throttling, import defaults, dyld executable selection and representative format conversions. They do not launch the proprietary editor and cannot prove a new editor ABI. Follow [ADAPTING](ADAPTING.md) for runtime verification.

## Run

For direct launches from the existing editor icon, use the one-time [installation](INSTALLING.md) after build/setup/check. The steps below describe optional standalone mode.

Quit the running editor, then use `./启动.command` or double-click the generated app. `启动.command` delegates to the same compiled launcher, so both use `Compatibility.h` rather than separate version/hash checks.

For a separate test copy or nonstandard installation:

```sh
VOCALOID_EDITOR_APP='/path/to/VOCALOID7 Editor.app' ./启动.command
```

The entire repository directory must remain together. The launcher finds the dylib and converter relative to its parent directory and executes the editor with `DYLD_INSERT_LIBRARIES`. It does not rewrite or re-sign the editor. Do not disable system security to bypass an unsupported loading configuration; investigate the actual target and document any inability to load it.

The first launch sets up the converter if its local Python is missing. For predictable startup, run setup explicitly as above. Network access is used to obtain dependencies; project conversion itself is local. Settings and per-voice media paths are written beside the patcher and are ignored by Git. The directory therefore needs to be writable.

## Translation regeneration

```sh
python3 localization/build_maps.py --app '/Applications/VOCALOID7 Editor.app'
```

This reads the locally installed editor's resources and the pinned translations under upstream/. It writes localization/maps/ only; it never modifies the app. Review differences and placeholder coverage before committing. Prebuilt maps remain usable without regeneration for the verified target.

## Reproducibility boundaries

Exact converter versions are pinned. The native compiler/SDK are supplied by the developer, so byte-identical native binaries are not promised. Intel requires a separately derived ABI and loading implementation; changing `-arch` alone is insufficient. The launcher's digest is over the complete native editor executable, including its universal container, not a thinned slice. In direct-install mode this is the executable in the nested, unchanged native app.
