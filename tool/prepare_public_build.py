#!/usr/bin/env python3
"""Tavern edition: prepare a build from public sources only.

1. Downloads spine_flutter 4.2.36 from pub.dev into packages/spine_flutter
   (the original author's customised runtime is not in the repository).
2. Applies tool/apply_spine_face_deform_patch.py and
   tool/apply_spine_tavern_compat_patch.py.
3. Creates every asset directory declared in pubspec.yaml that is missing,
   because the private character assets are git-ignored.

Usage (from the project root): python tool/prepare_public_build.py
Idempotent; an existing packages/spine_flutter is reused.
"""

import io
import re
import subprocess
import sys
import tarfile
import urllib.request
from pathlib import Path

SPINE_VERSION = '4.2.36'
ROOT = Path(__file__).resolve().parent.parent


def fetch_spine() -> None:
    target = ROOT / 'packages' / 'spine_flutter'
    if (target / 'pubspec.yaml').exists():
        print(f'Reusing {target}')
        return
    url = f'https://pub.dev/api/archives/spine_flutter-{SPINE_VERSION}.tar.gz'
    print(f'Downloading {url}')
    data = urllib.request.urlopen(url, timeout=120).read()
    target.mkdir(parents=True, exist_ok=True)
    with tarfile.open(fileobj=io.BytesIO(data), mode='r:gz') as archive:
        archive.extractall(target)


def patch_spine() -> None:
    for script in ('apply_spine_face_deform_patch.py', 'apply_spine_tavern_compat_patch.py'):
        subprocess.run([sys.executable, str(ROOT / 'tool' / script)], cwd=ROOT, check=True)


def create_asset_dirs() -> None:
    pubspec = (ROOT / 'pubspec.yaml').read_text(encoding='utf-8')
    block = pubspec.split('\n  assets:\n', 1)[1]
    created = 0
    for line in block.splitlines():
        match = re.match(r'^    - (\S+)$', line)
        if not match:
            if line.strip() and not line.startswith('    -'):
                break
            continue
        entry = match.group(1)
        if not entry.endswith('/'):
            continue
        path = ROOT / entry
        if not path.exists():
            path.mkdir(parents=True, exist_ok=True)
            created += 1
    print(f'Asset directories ready ({created} created).')


def windows_icon() -> None:
    # *.ico is git-ignored upstream; generate it from the tracked PNG source.
    icon = ROOT / 'windows' / 'runner' / 'resources' / 'app_icon.ico'
    if icon.exists():
        return
    try:
        from PIL import Image, ImageOps
    except ImportError:
        print('Pillow missing; skip Windows icon (pip install pillow).')
        return
    source = Image.open(ROOT / 'assets/branding/app_icon_source.png').convert('RGBA')
    square = ImageOps.fit(source, (256, 256), Image.Resampling.LANCZOS)
    icon.parent.mkdir(parents=True, exist_ok=True)
    square.save(icon, sizes=[(s, s) for s in (16, 24, 32, 48, 64, 128, 256)])
    print(f'Generated {icon}')


if __name__ == '__main__':
    windows_icon()
    fetch_spine()
    patch_spine()
    create_asset_dirs()
