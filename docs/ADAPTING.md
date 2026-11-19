# Adapting to another editor build

This guide describes the integration boundaries that must be established on your own installed target. It does not claim that another version is supported. Keep every digest gate in place. A changed hash permits private pointer reads and code calls; it is the final output of verification, not a compatibility fix by itself.

## 1. Identify and isolate the target

Use a separate copy and synthetic projects, with another copy of those projects before saving. Record the editor marketing version, executable SHA-256, CPU slices, macOS version and toolchain. Do not commit editor binaries, voice banks, personal projects or raw resource/analysis dumps.

```sh
mkdir -p adaptation-work
editor_app='/Applications/VOCALOID7 Editor.app'
editor_executable="$editor_app/Contents/MacOS/VOCALOID7 Editor"
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$editor_app/Contents/Info.plist"
shasum -a 256 "$editor_executable"
xcrun lipo -archs "$editor_executable"
xcrun nm -arch arm64 -nm "$editor_executable" > adaptation-work/symbols.txt
xcrun otool -arch arm64 -ov "$editor_executable" > adaptation-work/objc-metadata.txt
```

If symbols are absent or insufficient, establish the required behavior through appropriate local analysis and runtime evidence. Symbol absence is not proof of interface absence. Keep large analysis files outside the repository history. An authenticated working editor remains necessary; this project does not implement activation or voice-bank licensing.

## 2. Re-establish object and method contracts

Review these source modules in full before installing hooks:

| Module | Integration boundary |
| --- | --- |
| Patcher.m | `VOCALOID7_Editor.VEDocument`, `VESequence`, model protocols, note transactions, grid storage, save and menu lifecycle |
| Rendering.m | Piano-roll geometry, Objective-C drawing encodings, lyric/rounded-note call sites, active-window ownership, custom-tab drawing, voice artwork outlets |
| NativeOptions.m | Exact waveform and preview caller PCs, score representation, native view color fields, invalidation notifications |
| Spectrum.m | Native AudioUnit initialization/render-notify lifecycle and float32 buffer format |
| FormatBridge.m | Native document snapshots, active AI voice metadata, imported-document identity and save destinations |
| Launcher.m | Full executable digest, local converter environment, loader path and process environment |

The verified document route is `NSDocumentController` / window controller → `VEDocument.sequence` → `VESequence.vsmSequence`, `activePart`, `activeTrack`. The helpers read known strong object-reference ivars using runtime offsets. Check that each ivar is still an object reference of the expected type. A matching field name is not enough to safely read arbitrary Swift value storage.

Validate each Objective-C method encoding and return convention used by the protocols and swizzles. In particular, note ticks are one `int64_t`, mutation methods return BOOL, `drawRect:` takes CGRect by value, and transactions use commit/rollback/notify. Recheck native grid encoding instead of assuming the old byte layout. Confirm save behavior, dirty state and asynchronous sheet behavior; do not replace normal serialization with an inferred VSM save method.

The current geometry calls are arm64 Swift ABI entry points: note-rect uses x0 for note, x1/x2 for ticks, x20 for self, and returns CGRect in d0–d3; local-X uses x0 for tick, x20 for self and returns d0. They are expressed with clang `swiftcall` / `swift_context`. Re-derive these conventions for the target; do not call an address based only on a similar symbol name.

## 3. Update the compatibility inventory

[Compatibility.h](../Compatibility.h) is the single source for the target version, digest and private code addresses. Class names, ivar names, protocols, notification semantics and the grid layout remain explicit at their use sites and must also be reviewed.

| Constants | Meaning |
| --- | --- |
| `VP_EDITOR_VERSION`, `VP_EDITOR_SHA256` | Marketing version and SHA-256 of the complete installed executable |
| `VP_ADDR_NOTE_RECT`, `VP_ADDR_LOCAL_X` | Unslid Swift function entry addresses |
| `VP_PC_LYRIC_POINT`, `VP_PC_LYRIC_RECT` | Return PCs used to scope lyric centering |
| `VP_PC_NOTE_RECT_1` … `4`, `VP_PC_NOTE_FILL_1` … `3` | Return PCs used to scope rounded-note drawing |
| `VP_PC_WAVE_COLOR` | Waveform stroke-color caller |
| `VP_PC_WAVE_VERTICAL`, `VP_PC_WAVE_CONNECT_1` / `2` | Waveform path callers |
| `VP_PC_PREVIEW_REDRAW_1` … `3` | Preview redraw callers to coalesce, leaving native data processing intact |

Function entries and caller return PCs are different. Locate and inspect the actual call instruction and the instruction immediately following it. Do not copy an address from a disassembly comment without confirming which one the code compares. The constants are virtual addresses in the arm64 slice before ASLR. Add the `MH_EXECUTE` image slide for function calls; subtract it from observed caller PCs for comparisons. Under injection, image zero can be the patch dylib. `check_dyld.c` guards this exact failure.

The current source supports one verified profile. For an initial new-target branch, update that profile only after establishing its contracts, and document the old target no longer supported by that branch. Supporting multiple builds requires a deliberate per-digest mapping of all dependencies; a collection of accepted hashes sharing unverified addresses is not valid support.

## 4. Rebuild and verify

Run the three build/setup/check commands in [BUILDING](BUILDING.md). Regenerate translation maps against the target if its resources changed, inspect coverage and preserve printf placeholders. Use a named isolated app copy via `VOCALOID_EDITOR_APP` to run the newly built launcher.

Before claiming support, record real editor evidence for:

1. Loader acceptance for the target and rejection of an unsupported executable; native menus and language switches, including NSMenu titles.
2. Synthetic multi-track notes: lyric replacement, quantization at different grids, Swing/Shuffle and harmony; save/reopen and exact note-value checks; undo removes only the last transaction.
3. Multiple open documents and background-window redraw: pitch labels/ghosts/centering must belong to the correct window. Check mute filtering and scrolling/zooming.
4. Waveform modes, incomplete rendering, part switches, cache invalidation and final preview refresh; no crashes when toggling drawing.
5. PNG/GIF/video artwork, playback loop, opacity/position, cancellation and native-image restoration. Verify actual video motion, not only a poster frame.
6. Playback spectrum, right-only and opposite-phase stereo, stop/start and closing the spectrum window.
7. Converter export and native import, singer mapping, preserved source identity, unsaved imported identity, output collision protection and extracted audio lifetime.
8. Timed autosave to an existing VPRX, inactive editor, modal/async save sheets, uncommitted editing and an unsaved new document. Confirm the actual disk sequence, not only a successful return code.
9. Unchanged native layout when opening Browser, changing Inspector content, resizing and using file panels. Inspector relocation is deliberately absent after failed runtime tests; passing mocks did not justify keeping it.

State failures and untested features explicitly in your contribution. The historical verification in [VALIDATION](VALIDATION.md) applies to the original target, not automatically to your changes. Never distribute proprietary binaries or personal test projects as evidence; attach concise results, toolchain and target identifiers instead.
