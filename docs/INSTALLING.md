# Direct app launch / 原图标直接启动

[完整中文使用说明](USER-GUIDE.md) · [Full English user guide](USER-GUIDE.en.md)

This optional installation makes the existing `/Applications/VOCALOID7 Editor.app` icon load the patcher. Daily use needs neither Terminal nor a separate app launcher. Source builders run the following once after build/setup/check, with the editor closed:

```sh
conversion/.venv/bin/python install.py install
```

A different app copy can be selected with `--app '/path/to/VOCALOID7 Editor.app'`. The exact executable digest must match Compatibility.h. The installer refuses unsupported/modified targets and a running editor; it never stops a process or silently discards unsaved work.

## What installation changes

- A complete original bundle is copied into `~/Library/Application Support/VOCALOIDPatcher/backups/<id>/` and verified before replacement. A local recovery record records the backup and installed hashes.
- The outer app keeps its original Info.plist, icon, bundle identifier and document declarations. Its native entry point loads the patch and execs the original editor.
- The complete unchanged native app is retained inside `Contents/Resources/Native/VOCALOID7 Editor.app`. This preserves the original executable bytes, its Info.plist-bound signature, frameworks and resources. The installer verifies its original SHA-256 again after staging.
- The outer app receives a local ad-hoc signature. Both the outer and inner bundles are checked with `codesign --verify --deep --strict` before the prepared app replaces the target. This is a local modification, not a newly vendor-notarized distribution.
- Mutable maps, converter environment and patch settings live at `~/Library/Application Support/VOCALOIDPatcher/VOCALOID7`. No workspace folder or standalone launcher is needed afterwards. The installer also places a small recovery script and compatibility header in the adjacent installer/ directory.

No editor activation code, system-wide DYLD environment, Gatekeeper or SIP setting is modified. Keep the installation on the verified user/machine: the payload is installed for the current user, and the launcher supports arm64/macOS15+. Other users require their own payload. Editor updates may replace the integration; restore first and revalidate/reinstall for a matching build.

## Restore

Quit the editor, then run:

```sh
conversion/.venv/bin/python install.py restore
```

Alternatively, using the self-contained recovery files left by installation:

```sh
"$HOME/Library/Application Support/VOCALOIDPatcher/VOCALOID7/conversion/.venv/bin/python" \
  "$HOME/Library/Application Support/VOCALOIDPatcher/installer/install.py" restore
```

Restoration verifies the installed hashes and backup, then restores the entire original app. If the installed app was updated or externally changed, it refuses to overwrite it; inspect the recorded backup instead. Settings and backups are retained. Do not open the nested native app directly: doing so bypasses the outer loading entry point.

## Verification scope

The original target was installed, launched through its normal Finder icon, fully quit, and launched through that icon again in a new process; Chinese menus and synthetic project opening passed. The original executable digest stayed unchanged. A separate copy was installed and restored successfully. Failure checks cover unsupported targets, rejecting restore while running, and rolling back a failed bundle swap. No vendor app or personal project is committed to the repository.
