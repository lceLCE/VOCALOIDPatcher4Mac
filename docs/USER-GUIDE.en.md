# Full user guide

Current source documentation, updated 2026-11-20. [Home](../README.en.md) · [中文完整说明](USER-GUIDE.md)

- [Compatibility and tools](#compatibility-and-tools)
- [Build and install](#build-and-install)
- [Daily launch and language](#daily-launch-and-language)
- [Note operations](#note-operations)
- [Piano-roll display and artwork](#piano-roll-display-and-artwork)
- [Project conversion](#project-conversion)
- [Saving](#saving)
- [Spectrum and waveform options](#spectrum-and-waveform-options)
- [Files and settings](#files-and-settings)
- [Update and restore](#update-and-restore)
- [Standalone mode](#standalone-mode)
- [Troubleshooting](#troubleshooting)
- [Verification and contributions](#verification-and-contributions)

## Compatibility and tools

This is a source-only trial port, not an editor or voice-bank package. The verified target is an Apple Silicon Mac running macOS 15+ and a working VOCALOID7 Editor 7.0.0 native executable with full SHA-256:

```text
eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92
```

Intel and other editor builds are unverified. The digest covers the complete executable, including its universal container. With direct installation, the outer executable is a bootstrap; check the untouched native image instead:

```sh
editor_app='/Applications/VOCALOID7 Editor.app'
if [ -d "$editor_app/Contents/Resources/Native/VOCALOID7 Editor.app" ]; then
  editor_app="$editor_app/Contents/Resources/Native/VOCALOID7 Editor.app"
fi
shasum -a 256 "$editor_app/Contents/MacOS/VOCALOID7 Editor"
```

A version label alone is insufficient. Use [ADAPTING](ADAPTING.md) for another target; never bypass the digest check to run unverified private interfaces.

Install Git, zsh, Xcode Command Line Tools and uv. Python 3.12 and exact dependencies are provisioned locally by setup.command. The initial download needs network access. Installation retains full app backups and converter environments, so allow additional disk space.

Apple documents Command Line Tools installation [here](https://developer.apple.com/documentation/xcode/installing-the-command-line-tools/). If not already installed:

```sh
xcode-select --install
```

Verify `xcrun --find clang` and `git --version`. Install uv using its [official instructions](https://docs.astral.sh/uv/getting-started/installation/); existing Homebrew users can run `brew install uv`. Reopen Terminal and verify `uv --version`. No global Python package installation is needed.

## Build and install

Use a writable local directory, preferably outside cloud-managed folders:

```sh
git clone https://github.com/lceLCE/VOCALOIDPatcher4Mac.git
cd VOCALOIDPatcher4Mac
./build.command
./conversion/setup.command
./check.command
```

The build produces `VOCALOIDPatcher.dylib`, `VOCALOID7 Patcher.app` and `VOCALOIDPatcherBootstrap`. Setup creates conversion/.venv; checks exercise native and converter behavior. All commands must finish successfully before installation. GitHub's source ZIP is also buildable; ZIP downloads do not support `git pull`.

Save projects and quit V7 completely, then install once from the repository root:

```sh
conversion/.venv/bin/python install.py install
```

The success output identifies the app, original backup and installed payload. Open the existing editor icon and check for the `VOCALOID Patcher` menu. For a nonstandard location:

```sh
conversion/.venv/bin/python install.py install --app '/other/local/path/VOCALOID7 Editor.app'
```

Use the same path for restore. Restore before moving the app. Do not run the entire workflow with sudo: settings and payload are scoped to the current user. The target directory must be writable by the installing account.

The installer validates the target and signature, preserves a complete original backup and checks the prepared signed bundle before replacement. Native executable bytes remain unchanged. [INSTALLING](INSTALLING.md) explains the structure, local signature and recovery record. No activation code or system security setting is changed.

## Daily launch and language

After direct installation, open the normal `VOCALOID7 Editor.app` icon. No Terminal, source checkout or separate launcher is required for daily use. Opening the internal Native app or a backup directly bypasses the outer patch-loading entry.

Use **VOCALOID Patcher → Interface language** to select simplified Chinese, traditional Chinese, English, Japanese or Spanish. The choice persists. Some system file-picker UI follows the macOS language; dynamic views may update on refresh/reopen. Static coverage is not proof that every runtime string has been manually reviewed.

## Note operations

Open a project and select notes in the current part's piano roll before using lyric replacement, duration quantization or Swing/Shuffle. Harmony uses all notes in the active part when nothing is selected.

Confirmed jobs edit the project in a native transaction. Use the editor's Undo to reverse the last operation. Failures attempt to roll back that transaction. Finish any other staged edit before retrying a rejected job.

### Replace selected-note lyrics

Enter a nonempty string such as `la`. Every selected note receives that same text. This is not automatic syllable distribution across notes; an empty string cancels the job.

### Quantize durations

Enter `grid ticks,strength percent`, using an ASCII comma:

| Example | Meaning |
| --- | --- |
| `120,100` | Sixteenth-note duration grid |
| `240,100` | Eighth-note duration grid |
| `120,50` | Move durations halfway toward their quantized targets |

A quarter note is 480 ticks. Grid is an integer from 1 to 1920; strength is 0–100. The default attempts to read the native grid. This changes durations, retaining note starts; the quantized target is at least one grid unit. Midpoints round to even.

### Generate harmony

Enter `root MIDI,scale steps,track mode`; default `60,2,1`:

| Field | Values |
| --- | --- |
| Root | MIDI 0–127; e.g. 60=C, 62=D, 65=F. Uses the major diatonic scale rooted there |
| Steps | `2` through `7`, or `-2` through `-7`; positive up, negative down |
| Track mode | `1` creates a new track; `0` tries another singing track with no overlap in the part's time range, then creates one if necessary |

**2 means two diatonic steps, C→E: a third, not a second.** For an in-scale starting note, 2/3/4/5/6/7 produce a third/fourth/fifth/sixth/seventh/octave.

Examples: `60,2,1` creates an upper third in C major; `60,-2,1` a lower third; `60,7,1` an upper octave. Octaves retain chromatic offsets. One interval is generated per invocation. New tracks inherit the source type and voice bank. Output is limited to MIDI 0–127; non-scale notes are mapped to a nearby scale position, so audition the result. Separate minor/custom scales and simultaneous interval selection are not provided.

### Swing and Shuffle

Eighth-note and sixteenth-note versions are available. Swing distributes the pair approximately 60:40; Shuffle uses approximately 2:1. Both selected-note starts and durations are mapped. Each invocation edits again; Undo before trying a different setting if you want the original timing.

## Piano-roll display and artwork

Under **Piano roll and artwork** (钢琴窗与立绘):

| Option | Behavior |
| --- | --- |
| Note pitch names | Draws labels when a note is sufficiently large; MIDI 60 uses VOCALOID's C3 convention. Zoom in if labels are absent |
| Other-track notes | Shows note outlines from other singing tracks |
| Skip muted tracks | Filters those outlines by track mute state |
| Vertically centered lyrics | Changes native text placement |
| Rounded notes | Changes note drawing |

Display switches persist and do not alter note data.

For custom artwork, select a singing track with a voice bank, open the piano roll and keep the native voice-image display toggle enabled. Choose **Select image or video for current voice bank…**, then adjust:

| Setting | Range |
| --- | --- |
| Size | 32–1024 in the menu's pixel units; visible-area limits still apply |
| Opacity | 0–100% |
| Horizontal position | 0% left, 100% right |
| Vertical position | 0% top, 100% bottom |

A new record defaults to size 220, opacity 90%, bottom-right. Settings are keyed by voice-bank identity. PNG, animated GIF and H.264 MP4 were exercised; other media depend on system decoders. Video loops silently. The file path is stored, not embedded in the project: reselect a file if it moves. Clear current-bank artwork to remove the mapping and restore native drawing. A global artwork visibility toggle is available.

## Project conversion

Use **Project format conversion** (工程格式转换). The pinned local converter is LibreSVIP 2.9.2. Setup downloads dependencies; conversion itself is local. Native editor network behavior is unchanged.

### Import

Choose **Import other project format…**, select a file, configure options or leave `{}`, optionally enable Chinese-to-pinyin, then convert. The editor opens a new unsaved document; save it to a new VPRX destination. The source file is not overwritten.

GUI imports default to AI singing tracks, using the current voice metadata when compatible. Missing source voices can trigger the native mapping dialog. VPR/VPRX with empty options and no pinyin use a native byte-for-byte copy to preserve track types and voices.

### Export and subtitles

With a project open, choose **Export other project format…** and specify the extension in the destination name, e.g. `song.svp`, `song.ustx` or `song.lrc`. The bridge serializes a native snapshot without changing the active document's file identity. The destination must differ from the current project. GUI export can replace an existing target following the save panel's replacement confirmation.

| Direction | Extensions |
| --- | --- |
| Read/write | `ustx` `ust` `svp` `s5p` `vsq` `vsqx` `vpr` `ccs` `tssln` `acep` `vvproj` `ppsf` `dv` `tlpx` `tlp` `svip` `ds` `aisp` `y77` `vog` `musicxml` `json` `ufdata` `mid` |
| Write-only subtitles | `lrc` `srt` `ass` |
| Additional import | `vprx` |
| Aliases | `xml`/`mxl` use MusicXML; `midi` uses MIDI. MXL can be exported as a compressed container |

There are 27 converter entries; VPRX and aliases are additional. The converter does not write VPRX: save it through the editor.

### Options and pinyin

**View format options…** accepts an extension such as `ust`, `svp` or `vpr` and shows the pinned converter's fields, types and defaults. Input JSON belongs to the source reader; output JSON belongs to the target writer. For a GUI import into V7 the target writer is VPR. Use `{}` for defaults, valid JSON double quotes, no comments or unknown fields.

UST defaults to Shift-JIS. For Chinese UST, use the following in input options when reading, or output options when writing:

```json
{"encoding":"UTF-8"}
```

Reset options to `{}` before switching formats if old fields no longer apply. Options and pinyin state are reused within the current process and reset on restart.

The pinyin checkbox transforms lyrics during conversion, not by rewriting the source in place. Read converter warnings and inspect/audition the result in its target software. Lossless V7-only synthesis controls, complex curves and all metadata have not been established.

If completion reports an audio sidecar directory, retain it with the exported project. Embedded VPR/VPRX accompaniment may be extracted beside the destination; deleting the returned directory breaks those references.

## Saving

**Save project copy…** writes a separate VPRX snapshot. Normal Save and Save As remain native editor actions.

**Autosave…** enables an interval from 1 to 120 minutes; click the checked entry again to disable it. To change the interval, disable and re-enable. The setting persists.

Autosave writes back the currently identifiable document only when it has an existing `.vprx` URL and unsaved changes. Save new/imported documents manually first. Modal dialogs, save sheets, staged edits or an in-flight autosave cause a skip; the timer may wait until interaction completes. Multiple open documents are not all saved in a batch. Use snapshots or Save As for separate copies.

## Spectrum and waveform options

**Live output spectrum** opens/hides its panel. Play a project that actually generates audio. Closing the panel stops observation. This observes the editor's own output, without system recording permission, rather than all system audio.

Under **Layout and waveform** (布局与波形):

| Option | Purpose |
| --- | --- |
| V6 dark toolbar/titlebar | Applies the adapted toolbar palette; disabling restores the original colors |
| Waveform opacity | 0–100%, display only |
| SV-style waveform | Uses shared group baselines with native Mac amplitude scaling |
| Limit synthesis-preview refresh to 30 fps | Coalesces preview redraws while preserving the final refresh, not a global editor/audio FPS limit |
| Release idle heap memory | Asks the allocator to return already-idle pages; zero MB is possible and active PCM is not all discarded |

These display/waveform settings persist. Incomplete rendering can temporarily use native waveform display. Inspector relocation was removed after real layout regressions and is not offered in the current menu.

## Files and settings

Direct installation uses `~/Library/Application Support/VOCALOIDPatcher/`:

| Relative path | Content |
| --- | --- |
| `VOCALOID7/` | Dylib, maps, converter and local Python environment |
| `VOCALOID7/settings.plist` | Language and autosave interval |
| `VOCALOID7/drawing-settings.plist` | Piano-roll display switches |
| `VOCALOID7/artwork-settings.json` | Per-bank media paths and appearance |
| `VOCALOID7/native-options.json` | Toolbar, waveform and preview settings |
| `backups/<id>/` | Complete original app, and possibly a previous payload |
| `install-records/` | Absolute app/backup paths and restore hashes |
| `installer/` | Recovery script and compatibility header |

Use Finder's Go to Folder (`⌘⇧G`) to locate them. Quit before editing settings; for a reset, rename the relevant settings file to `.bak` and restart. Retain backups and installation records; do not move or edit them to bypass verification.

The installed copy no longer needs the source checkout, but the uv-managed Python runtime remains part of converter operation. Standalone settings live beside the patcher instead, separately from installed settings.

## Update and restore

### Update the patcher

Save and quit V7. Restore with the old checkout or the installed self-contained recovery files first. Then, in a Git clone:

```sh
git pull --ff-only
./build.command
./conversion/setup.command
./check.command
conversion/.venv/bin/python install.py install
```

Reopen the original icon to confirm. Pulling/building source does not update the installed payload automatically. Reinstallation attempts to carry forward the four settings files; retain media at their existing paths.

### Update the editor

Restore before updating/reinstalling the editor. A changed native digest requires renewed adaptation, not reuse of the old private addresses. An editor update may replace the direct-launch integration.

### Restore the original app

Quit completely and run from the source root:

```sh
conversion/.venv/bin/python install.py restore
```

Without the checkout:

```sh
"$HOME/Library/Application Support/VOCALOIDPatcher/VOCALOID7/conversion/.venv/bin/python" \
  "$HOME/Library/Application Support/VOCALOIDPatcher/installer/install.py" restore
```

Append the same `--app '…/VOCALOID7 Editor.app'` for a custom installation. Restore verifies both the current installed state and backup. External replacement, updates, moves or damaged backups can prevent automatic restore; preserve the app, records and backup for inspection rather than forcing hashes or overwriting changes.

Restore retains settings, backups and Python files. After verifying successful recovery and retaining needed copies, manage extra disk usage manually in Finder.

## Standalone mode

After build/setup, use `./启动.command` or the generated `VOCALOID7 Patcher.app`. This mode needs the complete source/patcher directory and must be used for each launch. Only an editor without direct installation bypasses the patcher when opened normally. Standalone mode leaves the app untouched; installed mode backs up/replaces its outer bundle. Avoid concurrent duplicate editor instances.

## Troubleshooting

| Symptom | Action |
| --- | --- |
| Translation disappeared | Check for the Patcher menu; confirm the outer original icon, current user and installed payload. Internal Native/backup apps bypass loading. Old standalone mode needs its own entry each time |
| Patcher menu exists, wrong language | Select simplified Chinese or your preferred language, check settings-directory write access and reopen the view/app |
| Unsupported executable | Check full native SHA-256, not only the version label; use the adaptation guide |
| Modified entry / existing install record | Restore the existing installation before reinstalling |
| Editor must be closed | Save and quit using the application menu; the installer will not kill it |
| uv / clang missing | Install uv/Command Line Tools, reopen Terminal, verify `uv --version` / `xcrun --find clang` |
| Permission denied | Use writable app/source locations; do not change the entire workflow to sudo and a different user's support directory |
| FinderInfo/resource-fork signing error | Use a valid local original app outside sync-managed locations; do not disable signing/system security |
| Missing dylib/components | Inspect the complete installed support directory; restore before reinstalling |
| Converter initialization failed | Check uv/network; run the installed `VOCALOID7/conversion/setup.command` if rebuilding its environment is needed |
| Conversion option/encoding error | Reset the relevant JSON to `{}`, query options, use UTF-8 for Chinese UST |
| Missing voice bank | Map to an installed voice in the native dialog; formats do not install voice banks |
| Artwork absent | Select a singing track, enable native image/custom-art toggles, check the media path and reselect if moved |
| Pitch labels absent | Enable the switch and zoom notes large enough |
| Autosave absent | Manually save as VPRX first, enable its timer and confirm edits; dialogs/staged jobs delay saving and multiple documents need separate management |
| Flat spectrum | Check actual playback/synthesis output and mute state |
| Restore refused | Preserve records/backup and inspect whether the app was moved, replaced or updated |

## Verification and contributions

[VALIDATION](VALIDATION.md) separates historical real-editor tests, synthetic checks and remaining gaps. 27 exports and 24 readable-format roundtrips cover representative inputs, not every field or target-editor behavior.

Remaining gaps include Intel, AU/VST hosts, Inspector relocation, multiple harmony intervals, several Windows-specific performance patches and complex lossless V7 parameter conversion. New builds/features require their own runtime evidence.

Report OS/CPU, editor version, full native digest, installation mode, minimal reproduction and sanitized errors. Never upload credentials, activation information, proprietary editor/voice banks, private projects, backups or complete local path records. See [ADAPTING](ADAPTING.md), [LICENSE](../LICENSE) and [NOTICE](../NOTICE.md).
