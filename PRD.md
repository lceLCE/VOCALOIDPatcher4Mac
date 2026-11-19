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
