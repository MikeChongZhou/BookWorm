"""Sign only the BookWorm app on an ephemeral GitHub macOS runner."""
import os
from pathlib import Path
import plistlib
import secrets
import shutil
import subprocess

from release_tools import ROOT, staging, spec


def run(args):
    value = subprocess.run(args, stdout=subprocess.PIPE, stderr=subprocess.PIPE)
    if value.returncode:
        # Credential-bearing security command lines must never be printed.
        raise RuntimeError(f'{Path(args[0]).name} failed with exit code {value.returncode}')
    return value.stdout


def main():
    folder = staging()
    keychain = folder / 'signing.keychain-db'
    password = secrets.token_urlsafe(32)
    run(['security', 'create-keychain', '-p', password, str(keychain)])
    run(['security', 'set-keychain-settings', '-lut', '21600', str(keychain)])
    run(['security', 'unlock-keychain', '-p', password, str(keychain)])
    run(['security', 'import', str(folder / 'macos.p12'), '-P', os.environ['MACOS_P12_PASSWORD'],
         '-k', str(keychain), '-T', '/usr/bin/codesign', '-T', '/usr/bin/security'])
    run(['security', 'set-key-partition-list', '-S', 'apple-tool:,apple:,codesign:', '-s', '-k', password, str(keychain)])
    run(['security', 'list-keychains', '-d', 'user', '-s', str(keychain)])
    meta = spec('macos')
    app = ROOT / 'build/macos/Build/Products/Release/BookWorm.app'
    info = plistlib.loads((app / 'Contents/Info.plist').read_bytes())
    if info['CFBundleIdentifier'] != 'com.fairyphoenix.bookworm' or info['CFBundleShortVersionString'] != meta['version'] or str(info['CFBundleVersion']) != str(meta['build']):
        raise ValueError('App identifier or version does not match the release manifest')
    profile_path = folder / 'bookworm.provisionprofile'
    profile = plistlib.loads(run(['security', 'cms', '-D', '-i', str(profile_path)]))['Entitlements']
    if profile.get('com.apple.application-identifier') != 'DA6DVPSL36.com.fairyphoenix.bookworm':
        raise ValueError('Signing profile must be dedicated to BookWorm')
    entitlements = plistlib.loads((ROOT / 'macos/Runner/Release.entitlements').read_bytes())
    for name in ('com.apple.application-identifier', 'com.apple.developer.team-identifier'):
        entitlements[name] = profile[name]
    if entitlements['com.apple.developer.ubiquity-container-identifiers'] != profile['com.apple.developer.ubiquity-container-identifiers']:
        raise ValueError('iCloud container does not match BookWorm')
    entitlements['keychain-access-groups'] = ['DA6DVPSL36.com.fairyphoenix.bookworm']
    entitlements['com.apple.developer.icloud-container-environment'] = 'Production'
    ent_file = folder / 'release.entitlements'
    ent_file.write_bytes(plistlib.dumps(entitlements))
    shutil.copyfile(profile_path, app / 'Contents/embedded.provisionprofile')
    identity = 'Developer ID Application: Chong Zhou (DA6DVPSL36)'
    def sign(path, options=()):
        run(['codesign', '--force', '--timestamp', '--options', 'runtime', '--keychain', str(keychain),
             '--sign', identity, *options, str(path)])
    for path in sorted(app.rglob('*.dylib'), key=lambda p: len(p.parts), reverse=True):
        if not path.is_symlink():
            sign(path)
    for path in sorted(app.rglob('*.framework'), key=lambda p: len(p.parts), reverse=True):
        sign(path)
    sign(app, ['--entitlements', str(ent_file)])
    run(['codesign', '--verify', '--deep', '--strict', str(app)])
    output = ROOT / 'dist' / meta['asset']
    output.parent.mkdir(exist_ok=True)
    run(['ditto', '-c', '-k', '--sequesterRsrc', '--keepParent', str(app), str(output)])
    print(f'Signed and packaged {output.name}')


if __name__ == '__main__':
    main()
