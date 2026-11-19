# macOS translation maps

Run `python3 localization/build_maps.py` from the delivered package root.
The script reads the pinned resources in `upstream/translations/` and the installed editor's localization resources. It only writes this directory's `maps/` folder.

`<language>.json` maps exact English UI strings to a translation. `<language>.keys.json` maps macOS `Localizable.strings` resource keys to translated values. `ja-to-zh-Hans.json` provides Japanese resource text aliases for an editor whose current locale is Japanese. `coverage.json` records counts and source commit. The generator also creates uppercase aliases for short native inspector headings.

All five resource maps cover the 589 keys in the inspected macOS 7.0.0 Base `Localizable.strings`. Of these, 488 match upstream English text directly. The supplementary 101 entries include unchanged module identifiers and Mac-specific messages. English preserves the native source, Japanese uses the installed Japanese resource, simplified Chinese and Spanish have explicit supplements, and the traditional Chinese supplement derives from the Chinese wording using traditional characters. Each locale's main string map also includes Japanese source aliases, allowing the runtime to change languages without requiring original English labels.

`nib_strings.py` resolves the compiled nib's `NSKey` and `NSDev` object references without instantiating views. On the inspected 7.0.0 application, all 48 nib archives passed object, key and value table boundary checks. The generator paired 229 native English nib strings with Japanese translations, then checked all 254 entries in the 27 Japanese nib `.strings` files. Every entry containing Japanese kana or CJK characters has a simplified Chinese alias. The unavailable-voice dialog's explanatory paragraph is included.

Build checks preserve all printf and .NET format fields and resource URLs. No upstream entries were rejected for a placeholder mismatch. The source app is read-only. These are static coverage counts. They do not establish runtime translation coverage or visual layout correctness. Nib titles are applied through runtime UI traversal using the exact text map. Labels rendered directly by SwiftUI or custom drawing require verification in the main native integration.

`port-ui.json` contains reviewed UI strings from Patcher, Rendering, NativeOptions, FormatBridge and Spectrum. Every record has the five locale values. `build_maps.py` incorporates the catalog into each flat runtime dictionary and validates formatting fields. The runtime translates these strings at explicit UI construction sites. Dynamic templates must be translated before formatting or appending data. The catalog includes equivalent newline forms for the conversion templates where applicable. Language names use their autonyms.

Upstream translation resources are reused under GPL-3.0 from https://github.com/IzumiiKonata/VOCALOIDPatcher at the commit recorded in `maps/coverage.json`. Preserve the repository's LICENSE and notices when distributing these maps.
