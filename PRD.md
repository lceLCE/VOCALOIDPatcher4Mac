# Public source release

## Objective
Publish the stable macOS port to lceLCE/VOCALOIDPatcher4Mac so contributors can build it and investigate adaptations to their own editor builds.

## Acceptance
- Public main branch contains all native sources, translation generator and inputs, locked converter dependencies, tests and GPL attribution.
- A clean clone builds without local workspace paths or prebuilt proprietary artifacts.
- Documentation distinguishes the verified arm64 7.0.0 target from unverified adaptations and lists known missing features.
- Document every private address, version check, ABI dependency and required real-editor validation.
- Run strict native build, regression checks, converter checks and translation regeneration from the publication checkout; verify the remote commit after push.

## Scope and constraints
Publish source only; do not bundle VOCALOID, voice banks, local Python environments, personal settings or investigation dumps. Do not change repository visibility or publish a binary release. Publishing this source does not establish support for additional versions or CPU architectures.

## Tasks
Prepare source checkout; centralize target constants; document build and adaptation; validate from a clean source tree; inspect the staged content; commit and push; verify remote files and license.

## Direct launch installation (2026-11-20)

Clicking the existing VOCALOID7 app icon, or opening its projects, must load the Chinese patch without a separate launcher or terminal. Preserve the native executable bytes and app identity, use a checked native bootstrap at the existing application entry point with the untouched native app preserved inside, install mutable payload in the current user's Application Support directory, and retain a complete restorable original bundle. Do not change licensing code, Gatekeeper, SIP or system-wide DYLD settings. First validate on a separate app copy, then test normal opening, quit/reopen, and a synthetic project. The source digest gates remain in force.
