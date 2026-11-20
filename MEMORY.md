# Maintainer memory

- Public source prepared 2026-11-20 from the stable macOS trial, based on IzumiiKonata/VOCALOIDPatcher commit e3208fd798d432ae1bf1141bf8f741fbd6fac30f. GPL-3.0.
- Verified target: VOCALOID7 Editor 7.0.0, Apple Silicon, macOS 15+. Private integration is pinned to executable SHA-256 eb9440ffedc2bcd00f897dab57007767d59a64032e7489c0cf1a5546c1d0ba92.
- With DYLD injection image zero can be the patcher. Locate MH_EXECUTE when computing the main executable slide.
- Native NSDocument save actions via the responder chain did not reliably save the custom editor. Timed save uses NSDocument.saveToURL with completion and reentry protection, plus sheet/modal/staged-operation guards. Native writeToURL creates VPRX snapshots.
- NSImage can decode an MP4 poster; route UTTypeMovie through AVPlayer for actual video playback. Spectrum combines stereo FFT powers so opposite-phase channels do not cancel.
- Translate NSMenu.title as well as NSMenuItem.title. Lock translation map publication and background lookup.
- Inspector-right repeatedly failed real editor layout despite passing AppKit mocks. Removed from this stable source, including its layout hooks. Do not reintroduce without real UI evidence.
- Standalone arm64 only. AU/VST integration, several Windows-specific performance optimizations and multi-interval harmony UI remain incomplete. Foreign-format V7 synthesis controls have not been proven lossless.

- Publication checkout: strict native build, complete native/converter suite (27 exports / 24 readable roundtrips), shell syntax checks, and exact translation-map regeneration passed on 2026-11-20. Compatibility constants were centralized without changing their verified values. The shell launcher now delegates to the compiled launcher. No new editor version has been declared supported.

- Direct launch installation (2026-11-20): the original app icon now runs an in-bundle native entry point; an intact native app is nested under Contents/Resources/Native/VOCALOID7 Editor.app. Keeping the full native bundle was required for deep signature verification; renaming only the vendor binary or changing its Info.plist binding failed verification and was not installed. Vendor executable digest remains the original value. Mutable payload/recovery tools live in the current user's Application Support/VOCALOIDPatcher directory.
- Tested a complete backup restoration on a separate app copy, running-process rejection, unsupported-target rejection and failed-swap rollback. Installed original app passed deep/strict signature validation, normal Finder-icon launch, full quit/relaunch in a new process, and synthetic project opening with Chinese UI. No activation or system security settings changed. Cloud document folders can re-add forbidden FinderInfo metadata; installation staging/backups use local app/support locations.
