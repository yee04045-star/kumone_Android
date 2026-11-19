#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$ROOT"

if ! command -v flutter >/dev/null 2>&1; then
  echo "Flutter SDK is required. This script is intended for local use or GitHub Actions."
  exit 1
fi

# Generate the Android wrapper from the installed Flutter SDK instead of
# committing a brittle Gradle/AGP wrapper that can drift between Flutter releases.
if [ ! -f android/app/src/main/AndroidManifest.xml ] || [ ! -f android/settings.gradle.kts ]; then
  TMP_DIR="$(mktemp -d)"
  trap 'rm -rf "$TMP_DIR"' EXIT
  flutter create \
    --platforms=android \
    --org im.kumone \
    --project-name kumone_flutter \
    --no-pub \
    "$TMP_DIR/kumone_flutter"
  rm -rf android
  cp -R "$TMP_DIR/kumone_flutter/android" android
  trap - EXIT
  rm -rf "$TMP_DIR"
fi

mkdir -p android/app/src/main/kotlin/im/kumone/kumone_flutter
cp tooling/android_overlay/app/src/main/kotlin/im/kumone/kumone_flutter/*.kt \
   android/app/src/main/kotlin/im/kumone/kumone_flutter/
cp tooling/android_overlay/app/src/main/AndroidManifest.xml \
   android/app/src/main/AndroidManifest.xml
mkdir -p android/app/src/main/res
# Remove Flutter's generated adaptive launcher resources so the exact Kumone
# PNG artwork below is used consistently on Android 14+ launchers.
rm -rf android/app/src/main/res/mipmap-anydpi-v26
rm -f android/app/src/main/res/drawable/ic_launcher_foreground.xml
cp -R tooling/android_overlay/app/src/main/res/. android/app/src/main/res/

# Android 14 is API 34. Flutter's current stable Android baseline is API 24+
# and the project deliberately targets SDK 35 for modern Android behavior.
python3 - <<'PY'
from pathlib import Path
p = Path('android/app/build.gradle.kts')
if p.exists():
    s = p.read_text()
    s = s.replace('targetSdk = flutter.targetSdkVersion', 'targetSdk = 35')
    s = s.replace('targetSdk flutter.targetSdkVersion', 'targetSdk 35')
    # Keep Flutter's generated minSdk when present; force API 24 otherwise.
    if 'minSdk = flutter.minSdkVersion' not in s and 'minSdkVersion flutter.minSdkVersion' not in s and 'minSdk = 24' not in s:
        s = s.replace('defaultConfig {', 'defaultConfig {\n        minSdk = 24', 1)
    p.write_text(s)
PY

if [ -f .dart_tool/package_config.json ]; then
  bash scripts/patch_just_audio_usb.sh
else
  echo "just_audio USB patch will run after flutter pub get."
fi

echo "Android wrapper prepared."
