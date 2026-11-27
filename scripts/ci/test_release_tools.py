import contextlib
import hashlib
import io
import json
import os
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch
import zipfile

import release_tools as release


class ReleaseTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name)
        self.addCleanup(self.temp.cleanup)
        self.root_patch = patch.object(release, 'ROOT', self.root)
        self.root_patch.start()
        self.addCleanup(self.root_patch.stop)
        (self.root / 'release').mkdir()
        self.manifest = {'release_tag': 'apps-build10', **{
            p: {'version': '1.0.7', 'build': 10} for p in (*release.PLATFORMS, 'ios')}}
        (self.root / 'release/platforms.json').write_text(json.dumps(self.manifest))

    def test_missing_artifact_prevents_release_notes(self):
        (self.root / 'dist').mkdir()
        with self.assertRaises(ValueError):
            release.finalize()
        self.assertFalse((self.root / 'dist/RELEASE_NOTES.md').exists())

    def test_windows_archive_preserves_runtime_and_nested_assets(self):
        folder = self.root / 'build/windows/x64/runner/Release'
        (folder / 'data').mkdir(parents=True)
        (folder / 'bookworm.exe').write_bytes(b'executable')
        (folder / 'data/flutter_assets').write_bytes(b'assets')
        with contextlib.redirect_stdout(io.StringIO()):
            release.package('windows')
        with zipfile.ZipFile(self.root / 'dist' / release.spec('windows')['asset']) as archive:
            self.assertEqual(set(archive.namelist()), {'bookworm.exe', 'data/flutter_assets'})

    def test_checksums_cover_exact_three_packages(self):
        (self.root / 'dist').mkdir()
        for platform in release.PLATFORMS:
            (self.root / 'dist' / release.spec(platform)['asset']).write_bytes(platform.encode() * 10000)
        release.finalize()
        lines = (self.root / 'dist/SHA256SUMS.txt').read_text().splitlines()
        self.assertEqual(len(lines), 3)
        for line in lines:
            digest, name = line.split('  ')
            self.assertEqual(digest, hashlib.sha256((self.root / 'dist' / name).read_bytes()).hexdigest())

    def test_missing_config_fails_without_printing_values(self):
        with patch.dict(os.environ, {}, clear=True), self.assertRaises(ValueError):
            release.configure('android')
        self.assertFalse((self.root / 'cloud-config.release.json').exists())


if __name__ == '__main__':
    unittest.main()
