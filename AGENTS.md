# Project instructions

Use small, focused changes and native macOS APIs. This is an Objective-C arm64 port, built with Apple clang and zsh; conversion uses Python 3.12, uv and pinned LibreSVIP dependencies. Native sources are in the repository root, localization/ holds maps and their generator, conversion/ holds the subprocess bridge.

Read MEMORY.md and docs/ADAPTING.md before changing private editor integration. Keep executable digest checks enabled. Never treat changing the digest as a verified port: re-establish classes, object ivars, Swift calling conventions and each address for the target executable. Do not add unsupported feature switches or claim Windows parity. Inspector-right is not implemented after failed real UI regression.

Build: ./build.command. Set up converters: ./conversion/setup.command. Full checks: ./check.command. Regenerate translations: python3 localization/build_maps.py --app '/path/to/VOCALOID7 Editor.app'. Test private hooks only on a separate app copy and synthetic projects. Do not commit vendor binaries, voice banks, project files, credentials, local environments, generated app bundles or personal settings. Preserve GPL-3.0 and upstream attribution.

Record durable decisions in MEMORY.md and update docs/VALIDATION.md with the scope of verification. Compilation and mock checks do not prove runtime behavior.
