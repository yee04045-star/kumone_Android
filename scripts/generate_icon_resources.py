"""Regenerate Android launcher and bound splash resources (requires Pillow).
Original PNGs remain in assets/icons; no image-generation service is used.
"""
from pathlib import Path
from PIL import Image, ImageDraw, ImageOps, ImageChops

ROOT = Path(__file__).resolve().parents[1]
RES = ROOT / 'tooling/android_overlay/app/src/main/res'
CHOICES = ['frost', 'crystal', 'pastel', 'pink', 'emerald', 'clearblue', 'crystalblue', 'redpink', 'clearredpink']
DENSITIES = {'mdpi': 48, 'hdpi': 72, 'xhdpi': 96, 'xxhdpi': 144, 'xxxhdpi': 192}

for key in CHOICES:
    image = Image.open(ROOT / f'assets/icons/{key}.png').convert('RGBA')
    for density, size in DENSITIES.items():
        folder = RES / f'mipmap-{density}'
        folder.mkdir(parents=True, exist_ok=True)
        image.resize((size, size), Image.Resampling.LANCZOS).save(folder / f'ic_{key}.png')
        if key == 'frost':
            for legacy in ['ic_launcher', 'ic_launcher_round']:
                image.resize((size, size), Image.Resampling.LANCZOS).save(folder / f'{legacy}.png')
    # Android 12+ masks splash icons inside a circle; keep the full square art
    # inside the safe zone rather than letting the treble clef be cropped.
    splash = Image.new('RGBA', (432, 432))
    # Match album-art rounded rectangles. Supersample the mask for smooth edges;
    # retain the existing 280px art / 432px canvas and its safe-zone placement.
    inset = ImageOps.fit(image, (1120, 1120), method=Image.Resampling.LANCZOS)
    mask = Image.new('L', inset.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, 1119, 1119), radius=128, fill=255)
    inset.putalpha(ImageChops.multiply(inset.getchannel('A'), mask))
    inset = inset.resize((280, 280), Image.Resampling.LANCZOS)
    splash.alpha_composite(inset, (76, 76))
    folder = RES / 'drawable-nodpi'
    folder.mkdir(parents=True, exist_ok=True)
    splash.save(folder / f'splash_{key}.png')

for qualifier, dark in [('values', False), ('values-night', True),
                         ('values-v31', False), ('values-night-v31', True)]:
    folder = RES / qualifier
    folder.mkdir(parents=True, exist_ok=True)
    color = '#111318' if dark else '#EFF4FB'
    themes = []
    for key in CHOICES:
        name = key.capitalize()
        extra = ''
        if 'v31' in qualifier:
            extra = f'''<item name="android:windowSplashScreenBackground">{color}</item>
        <item name="android:windowSplashScreenAnimatedIcon">@drawable/splash_{key}</item>
        <item name="android:windowSplashScreenAnimationDuration">300</item>'''
        themes.append(f'''    <style name="Launch{name}" parent="@android:style/Theme.Light.NoTitleBar">
        <item name="android:windowBackground">@drawable/launch_{key}</item>
        <item name="android:windowLightStatusBar">{'false' if dark else 'true'}</item>
        {extra}
    </style>''')
    (folder / 'icon_themes.xml').write_text('<resources>\n' + '\n'.join('\n'.join(line.rstrip() for line in theme.splitlines()) for theme in themes) + '\n</resources>\n', encoding='utf-8')

for key in CHOICES:
    folder = RES / 'drawable'
    folder.mkdir(parents=True, exist_ok=True)
    (folder / f'launch_{key}.xml').write_text(f'''<layer-list xmlns:android="http://schemas.android.com/apk/res/android">
    <item android:drawable="@color/splash_background" />
    <item android:width="216dp" android:height="216dp" android:gravity="center"
        android:drawable="@drawable/splash_{key}" />
</layer-list>
''', encoding='utf-8')
for folder, color in [('values', '#EFF4FB'), ('values-night', '#111318')]:
    (RES / folder / 'splash_colors.xml').write_text(
        f'<resources><color name="splash_background">{color}</color></resources>\n', encoding='utf-8')
