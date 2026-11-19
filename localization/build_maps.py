#!/usr/bin/env python3
"""Build GPL-3.0 translation maps from the pinned Windows patcher resources.

Native keyed strings are extracted with plutil. Only translation resources are
read. Application bundles are never written by this tool.
"""

import argparse
from collections import Counter
import json
from pathlib import Path
import re
import subprocess
import xml.etree.ElementTree as ET

from nib_strings import localized_nib_strings


HERE = Path(__file__).resolve().parent
UPSTREAM = HERE.parent / "upstream"
if not UPSTREAM.is_dir():
    UPSTREAM = HERE.parents[1] / "VOCALOIDPatcher"
LANGUAGES = {
    "en": "English.xml",
    "zh-Hans": "中文 (简体).xml",
    "zh-Hant": "中文 (繁體).xml",
    "ja": "日本語.xml",
    "es": "Español.xml",
}
# Restrict matches to actual printf fields. A literal percent in help text is
# not a field, and reordering explicitly numbered fields is legitimate.
PRINTF = re.compile(r"%(?:\d+\$)?[-+#0 ]*(?:\d+|\*)?(?:\.\d+)?(?:hh|ll|[hlLqztj])?[@diuoxXfFeEgGaAcCsSp]")
DOTNET = re.compile(r"\{\d+(?:[^{}]*)\}")


def fields(text):
    return Counter(PRINTF.findall(text) + DOTNET.findall(text))


def load_strings(path):
    result = subprocess.run(
        ["plutil", "-convert", "json", "-o", "-", str(path)],
        check=True, capture_output=True, text=True,
    )
    return json.loads(result.stdout)


def load_xml(path):
    return {item.attrib["name"]: item.findtext("value", "")
            for item in ET.parse(path).getroot().findall("data")}


def write_json(path, value):
    path.write_text(json.dumps(value, ensure_ascii=False, indent=2) + "\n")


def build(app, destination):
    destination.mkdir(parents=True, exist_ok=True)
    english = load_xml(UPSTREAM / "translations" / LANGUAGES["en"])
    native = load_strings(app / "Contents/Resources/Base.lproj/Localizable.strings")
    supplements = json.loads((HERE / "mac-zh-Hans.json").read_text())
    common = json.loads((HERE / "common-zh-Hans.json").read_text())
    menus = json.loads((HERE / "menu-zh-Hans.json").read_text())
    extra_sources = json.loads((HERE / "native-extra-sources.json").read_text())
    port_ui = json.loads((HERE / "port-ui.json").read_text())
    for source, translations in port_ui.items():
        assert set(translations) == set(LANGUAGES), f"Incomplete port UI translation: {source}"
        assert all(fields(source) == fields(value) for value in translations.values()), source
    japanese_path = app / "Contents/Resources/ja.lproj/Localizable.strings"
    japanese_native = load_strings(japanese_path) if japanese_path.is_file() else {}
    japanese_tables = {path.stem: load_strings(path)
                       for path in (app / "Contents/Resources/ja.lproj").glob("*.strings")
                       if path.stem != "Localizable"}
    nib_pairs = []
    nib_count = 0
    for path in (app / "Contents/Resources").rglob("*.nib"):
        if not path.is_file():
            continue
        english_nib = localized_nib_strings(path)
        nib_count += 1
        japanese_nib = japanese_tables.get(path.stem, {})
        nib_pairs.extend((source, japanese_nib[key]) for key, source in english_nib.items()
                         if key in japanese_nib)
    revision = UPSTREAM / "REVISION"
    upstream_commit = revision.read_text().strip() if revision.is_file() else subprocess.check_output(
        ["git", "-C", str(UPSTREAM), "rev-parse", "HEAD"], text=True).strip()
    report = {"upstream_commit": upstream_commit,
        "native_key_count": len(native), "native_nib_count": nib_count,
        "native_nib_localization_pairs": len(nib_pairs), "port_ui_catalog_count": len(port_ui), "languages": {}}
    for language, filename in LANGUAGES.items():
        target = load_xml(UPSTREAM / "translations" / filename)
        mapping = {}
        rejected = []
        for key, source in english.items():
            translated = target.get(key)
            if translated is None or not source:
                continue
            if fields(source) != fields(translated):
                rejected.append(key)
                continue
            mapping.setdefault(source, translated)
        keys = {key: mapping[source] for key, source in native.items()
                if source in mapping}
        inherited = len(keys)
        if language == "en":
            keys = dict(native)
            mapping.update({source: source for source in common})
        elif language == "ja":
            keys = {key: japanese_native.get(key, source) for key, source in native.items()}
            mapping.update({source: japanese for source, japanese in nib_pairs})
        elif language in ("zh-Hant", "es"):
            localized_supplement = json.loads((HERE / f"mac-{language}.json").read_text())
            assert set(localized_supplement) == set(supplements)
            keys.update(localized_supplement)
        common_path = HERE / f"common-{language}.json"
        if language != "zh-Hans" and common_path.is_file():
            mapping.update(json.loads(common_path.read_text()))
        if language == "en":
            mapping.update({source: source for source in extra_sources.values()})
        elif language == "ja":
            mapping.update({source: japanese for japanese, source in extra_sources.items()})
        mapping.update({native[key]: value for key, value in keys.items()})
        for source, japanese in nib_pairs:
            if language == "en":
                mapping[source] = source
            elif re.fullmatch(r"[+\-0-9.: ]+", source):
                mapping[source] = source
        if language != "zh-Hans":
            for source, value in list(mapping.items()):
                if re.fullmatch(r"[A-Za-z][A-Za-z0-9 _/().+:-]{1,79}", source):
                    mapping.setdefault(source.upper(), source.upper() if language == "en" else value)
            aliases = {source: keys[key] for key, source in japanese_native.items()
                       if key in keys and not source.startswith(("https://", "http://"))}
            for source, japanese in nib_pairs:
                if source in mapping:
                    aliases[japanese] = mapping[source]
            for japanese, source in extra_sources.items():
                if source in mapping:
                    aliases[japanese] = mapping[source]
            for source, value in list(aliases.items()):
                if "\\n" in source:
                    aliases.setdefault(source.replace("\\n", "\n"), value)
            assert all(fields(source) == fields(value) for source, value in aliases.items())
            mapping.update(aliases)
            write_json(destination / f"ja-to-{language}.json", aliases)
        if language == "zh-Hans":
            for key, value in supplements.items():
                assert key in native, f"Unknown native key {key}"
                assert fields(native[key]) == fields(value), f"Changed placeholders {key}"
                keys[key] = value
                mapping[native[key]] = value
            mapping.update(common)
            # Native inspector nibs use uppercase section headings. Preserve
            # explicit upstream translations where they already exist, and
            # only uppercase short labels without format fields or URLs.
            for source, value in list(mapping.items()):
                if re.fullmatch(r"[A-Za-z][A-Za-z0-9 _/().+:-]{1,79}", source):
                    mapping.setdefault(source.upper(), value)
            aliases = {source: keys[key] for key, source in japanese_native.items()
                       if key in keys and not source.startswith(("https://", "http://"))}
            # Nib text is localized by Interface Builder object keys instead of
            # Localizable.strings. Resolve NSKey/NSDev references from the
            # compiled nib, then use the paired Japanese .strings value.
            for source, japanese in nib_pairs:
                if source in mapping:
                    aliases[japanese] = mapping[source]
                elif re.fullmatch(r"[+\-0-9.: ]+", source):
                    mapping[source] = source
                    aliases[japanese] = source
            for table in japanese_tables.values():
                for source in table.values():
                    if source in mapping:
                        aliases.setdefault(source, mapping[source])
            aliases.update(menus)
            aliases.update(json.loads((HERE / "mac-ja-supplement.json").read_text()))
            for source, value in list(aliases.items()):
                if "\\n" in source:
                    aliases.setdefault(source.replace("\\n", "\n"), value)
            remaining_japanese = sorted({source for table in japanese_tables.values()
                                         for source in table.values()
                                         if re.search(r"[\u3040-\u30ff\u3400-\u9fff]", source) and source not in aliases})
            assert not remaining_japanese, remaining_japanese
            assert all(fields(source) == fields(value) for source, value in aliases.items())
            report["native_japanese_nib_strings_unmapped"] = remaining_japanese
            report["native_japanese_aliases"] = len(aliases)
            write_json(destination / "ja-to-zh-Hans.json", aliases)
        # Keep URLs as resources, including localized help destinations. This
        # prevents title replacement code from accidentally changing endpoints.
        for key, source in native.items():
            if source.startswith(("https://", "http://")):
                keys[key] = source
                mapping.pop(source, None)
        # The catalog contains only reviewed patch UI labels and templates.
        # Callers translate them at UI construction sites, never via project
        # data setters, so lyrics and existing voice/track names are untouched.
        mapping.update({source: translations[language] for source, translations in port_ui.items()})
        missing = sorted(set(native) - set(keys))
        assert all(fields(source) == fields(value) for source, value in mapping.items())
        assert all(fields(native[key]) == fields(value) for key, value in keys.items())
        write_json(destination / f"{language}.json", mapping)
        write_json(destination / f"{language}.keys.json", keys)
        report["languages"][language] = {
            "string_map_count": len(mapping),
            "native_exact_upstream_matches": inherited,
            "native_keys_covered": len(keys),
            "native_keys_missing": missing,
            "native_nib_pairs_covered": sum(source in mapping for source, _ in nib_pairs),
            "port_ui_strings_covered": sum(source in mapping for source in port_ui),
            "upstream_placeholder_mismatches_skipped": rejected,
        }
    write_json(destination / "coverage.json", report)
    return report


if __name__ == "__main__":
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--app", type=Path, default=Path("/Applications/VOCALOID7 Editor.app"))
    parser.add_argument("--output", type=Path, default=HERE / "maps")
    arguments = parser.parse_args()
    report = build(arguments.app, arguments.output)
    for language, result in report["languages"].items():
        print(f"{language}: {result['native_keys_covered']}/{report['native_key_count']} native keys, "
              f"{result['string_map_count']} string entries")
