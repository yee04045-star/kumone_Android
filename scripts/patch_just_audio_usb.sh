#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if [ ! -f .dart_tool/package_config.json ]; then
  echo "Missing .dart_tool/package_config.json. Run flutter pub get first." >&2
  exit 1
fi

JUST_AUDIO_ROOT="$(python3 - <<'PY'
import json
from pathlib import Path
from urllib.parse import urlparse, unquote

cfg_path = Path('.dart_tool/package_config.json').resolve()
cfg = json.loads(cfg_path.read_text())

for p in cfg['packages']:
    if p['name'] != 'just_audio':
        continue

    uri = p['rootUri']
    parsed = urlparse(uri)

    if parsed.scheme == 'file':
        # package_config.json commonly contains file:/... or file:///... URIs.
        # Do not treat the URI as a relative filesystem path.
        path = unquote(parsed.path)
        if parsed.netloc and parsed.netloc not in ('', 'localhost'):
            path = f"//{parsed.netloc}{path}"
        root = Path(path).resolve()
    else:
        # rootUri can also be relative to package_config.json.
        root = (cfg_path.parent / unquote(uri)).resolve()

    print(root)
    break
else:
    raise SystemExit('just_audio package not found')
PY
)"

JAVA_ROOT="$JUST_AUDIO_ROOT/android/src/main/java"
CPP_ROOT="$JUST_AUDIO_ROOT/android/src/main/cpp"
mkdir -p "$JAVA_ROOT/com/ryanheise/just_audio" "$CPP_ROOT"

cp tooling/just_audio_usb/java/com/ryanheise/just_audio/KumoneUsb*.java "$JAVA_ROOT/com/ryanheise/just_audio/"
cp tooling/just_audio_usb/cpp/usb_audio_output.cpp "$CPP_ROOT/usb_audio_output.cpp"
cp tooling/just_audio_usb/cpp/usb_audio_output.h "$CPP_ROOT/usb_audio_output.h"
cp tooling/just_audio_usb/cpp/CMakeLists.txt "$CPP_ROOT/CMakeLists.txt"

AUDIO_PLAYER="$JAVA_ROOT/com/ryanheise/just_audio/AudioPlayer.java"
python3 - "$AUDIO_PLAYER" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()
needle='new DefaultRenderersFactory(context)'
patched='new KumoneUsbRenderersFactory(context)'
if patched in s:
    pass
else:
    count=s.count(needle)
    if count != 1:
        raise SystemExit(f'Expected exactly one DefaultRenderersFactory constructor, found {count}')
    s=s.replace(needle, patched, 1)
p.write_text(s)
PY

BUILD_FILE="$JUST_AUDIO_ROOT/android/build.gradle.kts"
python3 - "$BUILD_FILE" <<'PY'
from pathlib import Path
import sys
p=Path(sys.argv[1])
s=p.read_text()

# just_audio 0.10.6 itself declares `minSdk = 16`. The NDK refuses to
# configure an external native build below API 21, so normalize every minSdk
# declaration in this plugin module to 21. This also repairs a previously
# patched cache that may contain two defaultConfig blocks. The app module's
# own minSdk is unchanged.
import re
if re.search(r'(?m)^\s*minSdk\s*=\s*\d+\s*$', s):
    s=re.sub(r'(?m)^(\s*minSdk\s*=\s*)\d+(\s*)$', r'\g<1>21\g<2>', s)
elif re.search(r'(?m)^\s*minSdkVersion\s+\d+\s*$', s):
    s=re.sub(r'(?m)^(\s*minSdkVersion\s+)\d+(\s*)$', r'\g<1>21\g<2>', s)
else:
    marker='android {\n'
    replacement=(
        'android {\n'
        '    defaultConfig {\n'
        '        minSdk = 21\n'
        '    }\n'
    )
    if marker not in s:
        raise SystemExit('android block not found in just_audio build.gradle.kts')
    s=s.replace(marker,replacement,1)

# Verify that no legacy API 16 floor remains in the plugin build file.
mins=re.findall(r'(?m)^\s*minSdk(?:Version)?\s*(?:=)?\s*(\d+)', s)
if mins and any(int(v) < 21 for v in mins):
    raise SystemExit(f'just_audio minSdk still below 21: {mins}')

if 'src/main/cpp/CMakeLists.txt' not in s:
    marker='android {\n'
    replacement=(
        'android {\n'
        '    externalNativeBuild {\n'
        '        cmake { path = file("src/main/cpp/CMakeLists.txt") }\n'
        '    }\n'
    )
    if marker not in s:
        raise SystemExit('android block not found in just_audio build.gradle.kts')
    s=s.replace(marker,replacement,1)

p.write_text(s)
PY

echo "just_audio USB direct-output patch applied to: $JUST_AUDIO_ROOT"
