# Attribution and licensing

This macOS port is distributed under GNU GPL version 3; see LICENSE.

It is based on [IzumiiKonata/VOCALOIDPatcher](https://github.com/IzumiiKonata/VOCALOIDPatcher), pinned at commit `e3208fd798d432ae1bf1141bf8f741fbd6fac30f`. The upstream algorithm behavior and translation resources are reused/adapted. The files under upstream/translations/ are copied from that project; its license is preserved as upstream/LICENSE and its revision as upstream/REVISION. Preserve upstream notices when redistributing derivatives.

The native macOS modules, bridge, build/check scripts and adaptation documentation are included as source under the repository license. The native implementation uses macOS system frameworks.

[LibreSVIP](https://github.com/SoulMelody/LibreSVIP) 2.9.2 is an external MIT-licensed dependency, restored through pinned Python package requirements. Its dependency packages retain their respective licenses. No local environment or compiled dependency is committed here.

VOCALOID editor executables and voice banks are not included or licensed by this repository. Developers supply their own installed editor and voice banks to validate runtime adaptations. This is an independent community port.
