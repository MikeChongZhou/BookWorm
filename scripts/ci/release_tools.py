"""GitHub runner release metadata, credentials staging, and artifact packaging."""
import base64
import hashlib
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import zipfile

ROOT = Path(__file__).resolve().parents[2]
PLATFORMS = ('android', 'macos', 'windows')


def spec(platform):
    data = json.loads((ROOT / 'release/platforms.json').read_text())
    value = data[platform]
    if not re.fullmatch(r'\d+\.\d+\.\d+', value['version']) or not isinstance(value['build'], int) or value['build'] < 1:
        raise ValueError('Invalid release version')
    if not re.fullmatch(r'apps-build\d+', data['release_tag']):
        raise ValueError('Invalid release tag')
    suffix = {'android': 'Android-test-signed.apk', 'macos': 'macOS.zip', 'windows': 'Windows-x64.zip'}[platform]
    return {**value, 'tag': data['release_tag'], 'asset': f"BookWorm-{value['version']}-build{value['build']}-{suffix}"}


def staging():
    folder = Path(os.environ['RUNNER_TEMP']) / 'bookworm-release-secrets'
    folder.mkdir(mode=0o700, exist_ok=True)
    return folder


def secret(name):
    value = os.environ.get(name, '')
    if not value:
        raise ValueError(f'Required GitHub Actions secret is missing: {name}')
    return value


def binary_secret(name, filename):
    target = staging() / filename
    target.write_bytes(base64.b64decode(secret(name), validate=True))
    target.chmod(0o600)
    return target


def configure(platform):
    names = {'android': 'CLOUD_CONFIG_ANDROID', 'macos': 'CLOUD_CONFIG_APPLE', 'windows': 'CLOUD_CONFIG_WINDOWS'}
    data = json.loads(secret(names[platform]))
    if not isinstance(data, dict) or not data or any(not isinstance(v, str) for v in data.values()):
        raise ValueError('Cloud build configuration must contain string parameters')
    target = ROOT / 'cloud-config.release.json'
    target.write_text(json.dumps(data), encoding='utf-8')
    target.chmod(0o600)
    if platform == 'android':
        path = binary_secret('ANDROID_KEYSTORE_BASE64', 'android.keystore')
        for name in ('ANDROID_KEYSTORE_PASSWORD', 'ANDROID_KEY_PASSWORD', 'ANDROID_KEY_ALIAS'):
            secret(name)
        with open(os.environ['GITHUB_ENV'], 'a', encoding='utf-8') as env:
            env.write(f'BOOKWORM_ANDROID_KEYSTORE={path}\n')
    if platform == 'macos':
        binary_secret('MACOS_P12_BASE64', 'macos.p12')
        binary_secret('MACOS_PROFILE_BASE64', 'bookworm.provisionprofile')
        secret('MACOS_P12_PASSWORD')


def package(platform):
    meta = spec(platform)
    output = ROOT / 'dist' / meta['asset']
    output.parent.mkdir(exist_ok=True)
    if platform == 'android':
        shutil.copyfile(ROOT / 'build/app/outputs/flutter-apk/app-release.apk', output)
    elif platform == 'windows':
        folder = ROOT / 'build/windows/x64/runner/Release'
        if not (folder / 'bookworm.exe').is_file():
            raise ValueError('Windows executable is missing')
        with zipfile.ZipFile(output, 'w', zipfile.ZIP_DEFLATED) as archive:
            for file in folder.rglob('*'):
                if file.is_file():
                    archive.write(file, file.relative_to(folder))
    else:
        raise ValueError('macOS packages must use the signing script')
    print(f'Prepared {output.name}')


def finalize():
    paths = [ROOT / 'dist' / spec(p)['asset'] for p in PLATFORMS]
    for path in paths:
        if not path.is_file() or path.stat().st_size < 10000:
            raise ValueError(f'Missing release artifact: {path.name}')
    sums = []
    for path in paths:
        with path.open('rb') as stream:
            hasher = hashlib.sha256()
            for chunk in iter(lambda: stream.read(1024 * 1024), b''):
                hasher.update(chunk)
            digest = hasher.hexdigest()
        sums.append(f'{digest}  {path.name}')
    (ROOT / 'dist/SHA256SUMS.txt').write_text('\n'.join(sums) + '\n')
    notes = ['三个平台的附件均由本次 GitHub Actions 工作流编译生成。', '',
             '包含 History 统计、书源网站、兼容 Melo 模型网址与自动最远进度同步。', '',
             '| 平台 | 版本 | 安装说明 |', '|---|---|---|']
    descriptions = {'android': 'Release 模式，沿用现有测试签名，可覆盖同签名旧包',
                    'macos': 'Developer ID 签名，未公证；解压后放入 Applications',
                    'windows': '未签名便携包；完整解压后运行 bookworm.exe'}
    for platform in PLATFORMS:
        meta = spec(platform)
        notes.append(f"| {platform} | {meta['version']} ({meta['build']}) | {descriptions[platform]} |")
    notes += ['', '安装包校验值见 SHA256SUMS.txt。Windows 为 CI 编译验证，未完成 Windows 实机验收。',
              'iOS 保持已上传 TestFlight 的 1.0.7（9），本次不重新分发。']
    (ROOT / 'dist/RELEASE_NOTES.md').write_text('\n'.join(notes), encoding='utf-8')


def cleanup():
    folder = Path(os.environ['RUNNER_TEMP']) / 'bookworm-release-secrets'
    keychain = folder / 'signing.keychain-db'
    if sys.platform == 'darwin' and keychain.exists():
        subprocess.run(['security', 'delete-keychain', str(keychain)], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    if folder.exists():
        shutil.rmtree(folder)
    (ROOT / 'cloud-config.release.json').unlink(missing_ok=True)


def main():
    action = sys.argv[1]
    if action == 'finalize':
        finalize()
    elif action == 'cleanup':
        cleanup()
    else:
        platform = sys.argv[2]
        if platform not in PLATFORMS:
            raise ValueError('Invalid release platform')
        if action == 'meta':
            meta = spec(platform)
            with open(os.environ['GITHUB_OUTPUT'], 'a', encoding='utf-8') as output:
                for name in ('version', 'build', 'tag', 'asset'):
                    output.write(f'{name}={meta[name]}\n')
        elif action == 'configure':
            configure(platform)
        elif action == 'package':
            package(platform)
        else:
            raise ValueError('Invalid command')


if __name__ == '__main__':
    main()
