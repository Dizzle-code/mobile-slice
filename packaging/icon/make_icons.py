"""Renders the app icon for Windows (.ico) and macOS (AppIcon PNGs) from the same pixel cube
as the Android launcher icon (app/android/app/src/main/res/drawable/ic_launcher_foreground.xml).

    python packaging/icon/make_icons.py

Every glyph pixel becomes an exact block of screen pixels (nearest neighbour), so the icon stays crisp.
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw

ROOT = Path(__file__).resolve().parents[2]
VECTOR = ROOT / "app/android/app/src/main/res/drawable/ic_launcher_foreground.xml"
BACKGROUND = (0x1B, 0x1B, 0x2F, 255)
SHADOW = (0x0D, 0x0D, 0x18, 255)
DOT = (0x2A, 0x2A, 0x48, 255)


def glyph():
    """(x, y, w, h, rgba) rectangles in the 18x18 glyph grid of the Android vector."""
    text = VECTOR.read_text(encoding="utf-8")
    rects = []
    for color, data in re.findall(r'fillColor="#([0-9A-Fa-f]{6})" android:pathData="([^"]+)"', text):
        rgba = tuple(int(color[i:i + 2], 16) for i in (0, 2, 4)) + (255,)
        for x, y, w in re.findall(r"M(\d+),(\d+)h(\d+)v1h-\d+z", data):
            rects.append((int(x), int(y), int(w), 1, rgba))
    if not rects:
        sys.exit(f"no pixels found in {VECTOR}")
    return rects


def render(size, rects, rounded):
    """Square icon: dark pixel tile with stepped corners, dot grid, the cube centered on it."""
    # Draw on a 24-cell grid (the 16-cell cube fills two thirds), then scale up with nearest neighbour.
    cells = 24
    img = Image.new("RGBA", (cells, cells), (0, 0, 0, 0))
    d = ImageDraw.Draw(img)
    inset = 1 if rounded else 0
    # Tile with one-step corners and a hard shadow below, like PixelPanel.
    d.rectangle([inset + 1, inset + 1, cells - 2 - inset, cells - 1 - inset], fill=SHADOW)
    d.rectangle([inset, inset + 1, cells - 1 - inset, cells - 2 - inset], fill=SHADOW)
    d.rectangle([inset + 1, inset, cells - 2 - inset, cells - 3 - inset], fill=BACKGROUND)
    d.rectangle([inset, inset + 1, cells - 1 - inset, cells - 4 - inset], fill=BACKGROUND)
    if size >= 48:
        for gy in range(inset + 2, cells - 3 - inset, 4):
            for gx in range(inset + 2, cells - 1 - inset, 4):
                d.point((gx, gy), fill=DOT)
    # The glyph spans x 2..16 and y 2..18 of an 18-cell box; center it on the tile.
    xs = [x for x, _, w, _, _ in rects] + [x + w for x, _, w, _, _ in rects]
    ys = [y for _, y, _, h, _ in rects] + [y + h for _, y, _, h, _ in rects]
    gw, gh = max(xs) - min(xs), max(ys) - min(ys)
    scale = 1
    ox = (cells - gw * scale) // 2 - min(xs) * scale
    oy = (cells - 2 - gh * scale) // 2 - min(ys) * scale
    for x, y, w, h, rgba in rects:
        d.rectangle([ox + x * scale, oy + y * scale, ox + (x + w) * scale - 1, oy + (y + h) * scale - 1], fill=rgba)
    big = img.resize((cells * 64, cells * 64), Image.NEAREST)
    return big.resize((size, size), Image.NEAREST if size % cells == 0 else Image.LANCZOS)


def main():
    rects = glyph()
    # Windows: one .ico with the sizes Explorer and the taskbar ask for.
    ico = ROOT / "app/windows/runner/resources/app_icon.ico"
    base = render(256, rects, rounded=False)
    base.save(ico, sizes=[(16, 16), (24, 24), (32, 32), (48, 48), (64, 64), (128, 128), (256, 256)])
    # macOS: the sizes listed in AppIcon.appiconset/Contents.json. macOS icons keep a margin around the tile.
    mac = ROOT / "app/macos/Runner/Assets.xcassets/AppIcon.appiconset"
    for size in (16, 32, 64, 128, 256, 512, 1024):
        canvas = Image.new("RGBA", (size, size), (0, 0, 0, 0))
        inner = round(size * 0.82)
        tile = render(inner, rects, rounded=True)
        canvas.alpha_composite(tile, ((size - inner) // 2, (size - inner) // 2))
        canvas.save(mac / f"app_icon_{size}.png")
    # Preview for the web page and the README.
    render(512, rects, rounded=False).save(ROOT / "packaging/icon/icon_512.png")
    print("ok:", ico, mac)


if __name__ == "__main__":
    main()
