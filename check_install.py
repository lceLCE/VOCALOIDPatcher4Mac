#!/usr/bin/env python3
"""Focused installer failure checks; no proprietary app or user file is changed."""
import hashlib
from pathlib import Path
import plistlib
import tempfile
import install

with tempfile.TemporaryDirectory(prefix='vocaloid-install-check-') as directory:
    root = Path(directory)
    app = root / 'Unsupported.app'
    (app / 'Contents/MacOS').mkdir(parents=True)
    (app / 'Contents/Info.plist').write_bytes(plistlib.dumps({'CFBundleExecutable': install.EDITOR}))
    executable = app / 'Contents/MacOS' / install.EDITOR
    executable.write_bytes(b'unsupported executable')
    before = install.digest(executable)
    try:
        install.install(app, root / 'backups')
        raise AssertionError('Unsupported executable accepted')
    except ValueError as error:
        assert 'Unsupported editor' in str(error)
    assert install.digest(executable) == before
    assert not (root / 'backups').exists()

    current = root / 'Current.app'
    prepared = root / 'Prepared.app'
    current.mkdir()
    prepared.mkdir()
    (current / 'marker').write_text('original')
    (prepared / 'marker').write_text('replacement')
    original_verify = install.verify_app
    def fail_verification(_):
        raise RuntimeError('simulated signature verification failure')
    install.verify_app = fail_verification
    try:
        try:
            install.replace_app(current, prepared)
            raise AssertionError('Failed verification accepted')
        except RuntimeError:
            assert (current / 'marker').read_text() == 'original'
    finally:
        install.verify_app = original_verify

assert len(install.expected_digest()) == hashlib.sha256().digest_size * 2
print('PASS unsupported-target rejection and failed-swap rollback')
