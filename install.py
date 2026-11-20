#!/usr/bin/env python3
"""Install a checked in-bundle entry point; retain a complete original app backup."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import plistlib
import re
import shutil
import subprocess
import uuid

ROOT = Path(__file__).resolve().parent
SUPPORT = Path.home() / 'Library/Application Support/VOCALOIDPatcher'
PAYLOAD = SUPPORT / 'VOCALOID7'
BOOTSTRAP = 'VOCALOIDPatcherBootstrap'
EDITOR = 'VOCALOID7 Editor'
NATIVE_APP = Path('Contents/Resources/Native/VOCALOID7 Editor.app')


def digest(path: Path) -> str:
    with path.open('rb') as source:
        return hashlib.file_digest(source, 'sha256').hexdigest()


def expected_digest() -> str:
    match = re.search(r'#define VP_EDITOR_SHA256 @"([0-9a-f]{64})"', (ROOT / 'Compatibility.h').read_text())
    if not match:
        raise ValueError('Compatibility.h does not define a supported executable digest')
    return match[1]


def run(*arguments: str | Path) -> None:
    subprocess.run([str(value) for value in arguments], check=True, capture_output=True, text=True)


def copy_app(source: Path, destination: Path) -> None:
    run('/usr/bin/ditto', source, destination)
    if destination.suffix == '.app':
        # Cloud/Finder metadata can be added to a new copy and invalidate signing.
        # Remove only forbidden detritus; retain quarantine and other attributes.
        for attribute in ('com.apple.FinderInfo', 'com.apple.ResourceFork'):
            run('/usr/bin/xattr', '-dr', attribute, destination)


def verify_app(app: Path) -> None:
    run('/usr/bin/codesign', '--verify', '--deep', '--strict', app)


def ensure_closed(app: Path) -> None:
    for candidate in (app, app / NATIVE_APP):
        executable = candidate / 'Contents/MacOS' / EDITOR
        if not executable.exists():
            continue
        result = subprocess.run(['/usr/sbin/lsof', '-t', str(executable)], capture_output=True, text=True)
        if result.returncode not in (0, 1):
            raise RuntimeError('Cannot establish whether the editor is closed')
        if result.stdout.strip():
            raise RuntimeError('Quit this editor before installing or restoring; no process was stopped')


def record_path(app: Path) -> Path:
    name = hashlib.sha256(str(app).encode()).hexdigest()[:20]
    return SUPPORT / 'install-records' / f'{name}.json'


def replace_app(app: Path, prepared: Path) -> None:
    """Use same-directory renames so a failed swap can restore the old bundle."""
    retired = app.parent / f'.{app.stem}-previous-{uuid.uuid4().hex}.app'
    app.rename(retired)
    try:
        prepared.rename(app)
        verify_app(app)
    except BaseException:
        if app.exists():
            shutil.rmtree(app)
        retired.rename(app)
        raise
    shutil.rmtree(retired, ignore_errors=True)


def install(app: Path, backup_dir: Path, settings_from: Path | None = None) -> dict:
    app = app.resolve(strict=True)
    ensure_closed(app)
    info_path = app / 'Contents/Info.plist'
    info = plistlib.loads(info_path.read_bytes())
    if info.get('CFBundleExecutable') != EDITOR or (app / NATIVE_APP).exists():
        raise ValueError('App entry point is already modified; restore the original app first')
    vendor = app / 'Contents/MacOS' / EDITOR
    if digest(vendor) != expected_digest():
        raise ValueError('Unsupported editor executable; no app files were changed')
    verify_app(app)
    if not (ROOT / BOOTSTRAP).is_file() or not (ROOT / 'VOCALOIDPatcher.dylib').is_file():
        raise ValueError('Run build.command before installing')
    if not (ROOT / 'conversion/.venv/bin/python').exists():
        raise ValueError('Run conversion/setup.command before installing')
    record = record_path(app)
    if record.exists():
        raise ValueError('An installation record already exists; restore it before reinstalling')
    backup = backup_dir.resolve() / uuid.uuid4().hex
    backup.mkdir(parents=True, exist_ok=False)
    original = backup / app.name
    staged = app.parent / f'.{app.stem}-prepared-{uuid.uuid4().hex}.app'
    payload_staged = SUPPORT / f'.payload-{uuid.uuid4().hex}'
    previous_payload = backup / 'previous-payload'
    payload_replaced = False
    had_payload = PAYLOAD.exists()
    try:
        copy_app(app, original)
        verify_app(original)
        (staged / 'Contents/MacOS').mkdir(parents=True)
        (staged / 'Contents/Resources/Native').mkdir(parents=True)
        copy_app(app, staged / NATIVE_APP)
        (staged / 'Contents/Info.plist').write_bytes(info_path.read_bytes())
        icon_name = info.get('CFBundleIconFile', '')
        if icon_name:
            icon = Path(icon_name).name
            if not Path(icon).suffix:
                icon += '.icns'
            shutil.copy2(app / 'Contents/Resources' / icon, staged / 'Contents/Resources' / icon)
        # Carry forward the original entry's entitlements rather than adding permissions.
        entitlement_result = subprocess.run(['/usr/bin/codesign', '-d', '--entitlements', ':-', str(app)],
                                            capture_output=True, check=True)
        entitlements = entitlement_result.stdout.strip()
        signing = ['/usr/bin/codesign', '--force', '--sign', '-', '--identifier', info['CFBundleIdentifier']]
        if entitlements:
            plistlib.loads(entitlements)
            entitlement_file = backup / 'original-entitlements.plist'
            entitlement_file.write_bytes(entitlements)
            signing += ['--entitlements', str(entitlement_file)]
        shutil.copy2(ROOT / BOOTSTRAP, staged / 'Contents/MacOS' / EDITOR)
        run(*signing, staged)
        verify_app(staged)
        if digest(staged / NATIVE_APP / 'Contents/MacOS' / EDITOR) != expected_digest():
            raise ValueError('Signing changed the vendor executable; refusing installation')
        SUPPORT.mkdir(parents=True, exist_ok=True)
        payload_staged.mkdir()
        for name in ('VOCALOIDPatcher.dylib', 'LICENSE'):
            shutil.copy2(ROOT / name, payload_staged / name)
        shutil.copytree(ROOT / 'localization/maps', payload_staged / 'localization/maps')
        (payload_staged / 'conversion').mkdir()
        for name in ('convert.py', 'requirements.txt', 'setup.command'):
            shutil.copy2(ROOT / 'conversion' / name, payload_staged / 'conversion' / name)
        copy_app(ROOT / 'conversion/.venv', payload_staged / 'conversion/.venv')
        preferences = PAYLOAD if had_payload else settings_from
        if preferences:
            for name in ('settings.plist', 'drawing-settings.plist', 'artwork-settings.json', 'native-options.json'):
                source = preferences / name
                if source.is_file():
                    shutil.copy2(source, payload_staged / name)
        if had_payload:
            copy_app(PAYLOAD, previous_payload)
            shutil.rmtree(PAYLOAD)
        payload_staged.rename(PAYLOAD)
        payload_replaced = True
        ensure_closed(app)
        metadata = {'app': str(app), 'backup': str(original), 'vendor_sha256': digest(vendor),
                    'info_sha256': digest(staged / 'Contents/Info.plist'),
                    'bootstrap_sha256': digest(staged / 'Contents/MacOS' / EDITOR),
                    'payload': str(PAYLOAD)}
        recovery = SUPPORT / 'installer'
        recovery.mkdir(exist_ok=True)
        for name in ('install.py', 'Compatibility.h'):
            shutil.copy2(ROOT / name, recovery / name)
        record.parent.mkdir(parents=True, exist_ok=True)
        # Write recovery information before swapping either bundle.
        record.write_text(json.dumps(metadata, ensure_ascii=False, indent=2) + '\n')
        try:
            replace_app(app, staged)
        except BaseException:
            record.unlink()
            raise
        return metadata
    except BaseException:
        if payload_replaced:
            shutil.rmtree(PAYLOAD)
            if had_payload:
                copy_app(previous_payload, PAYLOAD)
        elif had_payload and previous_payload.exists() and not PAYLOAD.exists():
            copy_app(previous_payload, PAYLOAD)
        raise
    finally:
        if staged.exists():
            shutil.rmtree(staged)
        if payload_staged.exists():
            shutil.rmtree(payload_staged)


def restore(app: Path) -> dict:
    app = app.resolve(strict=True)
    ensure_closed(app)
    record = record_path(app)
    metadata = json.loads(record.read_text())
    if metadata['app'] != str(app) or metadata['vendor_sha256'] != digest(app / NATIVE_APP / 'Contents/MacOS' / EDITOR):
        raise ValueError('Editor changed since installation; refusing to overwrite it')
    if metadata['info_sha256'] != digest(app / 'Contents/Info.plist') or metadata['bootstrap_sha256'] != digest(app / 'Contents/MacOS' / EDITOR):
        raise ValueError('Installed entry point changed; inspect the backup before restoring')
    original = Path(metadata['backup'])
    verify_app(original)
    if digest(original / 'Contents/MacOS' / EDITOR) != metadata['vendor_sha256']:
        raise ValueError('Original backup digest mismatch')
    staged = app.parent / f'.{app.stem}-restore-{uuid.uuid4().hex}.app'
    try:
        copy_app(original, staged)
        replace_app(app, staged)
        record.unlink()
    finally:
        if staged.exists():
            shutil.rmtree(staged)
    # Retain settings and the original backup; neither is disposable user data.
    return metadata


def main() -> None:
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('action', choices=('install', 'restore'))
    parser.add_argument('--app', type=Path, default=Path('/Applications/VOCALOID7 Editor.app'))
    parser.add_argument('--backup-dir', type=Path, default=SUPPORT / 'backups')
    parser.add_argument('--settings-from', type=Path)
    args = parser.parse_args()
    try:
        metadata = install(args.app, args.backup_dir, args.settings_from) if args.action == 'install' else restore(args.app)
    except (OSError, ValueError, RuntimeError, subprocess.CalledProcessError) as error:
        parser.exit(1, f'{error}\n')
    print(json.dumps(metadata, ensure_ascii=False, indent=2))


if __name__ == '__main__':
    main()
