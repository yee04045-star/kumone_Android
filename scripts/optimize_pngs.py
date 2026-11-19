"""Losslessly optimize tracked PNG assets/resources; requires Pillow.
Never changes dimensions or RGBA pixels; writes only smaller encodings.
"""
from io import BytesIO
from pathlib import Path
from PIL import Image

root = Path(__file__).resolve().parents[1]
before = after = count = 0
for folder in [root / 'assets', root / 'tooling/android_overlay/app/src/main/res']:
    for path in folder.rglob('*.png'):
        original = path.read_bytes()
        with Image.open(BytesIO(original)) as image:
            pixels = image.convert('RGBA').tobytes()
            output = BytesIO()
            image.save(output, format='PNG', optimize=True, compress_level=9)
            optimized = output.getvalue()
            with Image.open(BytesIO(optimized)) as check:
                assert check.size == image.size and check.convert('RGBA').tobytes() == pixels
        before += len(original)
        if len(optimized) < len(original):
            path.write_bytes(optimized)
            count += 1
        after += path.stat().st_size
print(f'{count} PNGs optimized; {before:,} -> {after:,} bytes; saved {before-after:,} bytes')
