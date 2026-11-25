#!/usr/bin/env python3
"""Generate the iOS app icon PNGs from the Android launcher icon geometry.

The Android launcher icon (ic_launcher.xml) is a dark navy square with a
white warning triangle and a navy exclamation mark. This script redraws
that design at 1024x1024 and resizes it to every size the AppIcon
appiconset needs.

Usage:
    python3 ios/Scripts/generate-icons.py [output-dir]
Default output dir is the AppIcon.appiconset next to the CheckpointAlerts
sources. Requires Pillow (pip install pillow).

The PNGs are build artifacts, not committed: the GitHub Actions workflow
runs this script before building, and a Mac user runs it once after
checking the project out.
"""
import os
import sys

from PIL import Image, ImageDraw

NAVY = (0x14, 0x30, 0x4D, 255)
WHITE = (255, 255, 255, 255)

# Viewport of the Android vector (108x108).
VIEW = 108.0
# Triangle: base (21,81)-(87,81), apex (54,24).
TRIANGLE = [(21, 81), (87, 81), (54, 24)]
# Exclamation mark, navy, cut out of the triangle:
# bar x51-57, y48-60; dot x51-57, y66-72.
BAR = (51, 48, 57, 60)
DOT = (51, 66, 57, 72)

SIZES = [
    ("Icon-20.png", 20),
    ("Icon-20@2x.png", 40),
    ("Icon-20@3x.png", 60),
    ("Icon-29.png", 29),
    ("Icon-29@2x.png", 58),
    ("Icon-29@3x.png", 87),
    ("Icon-40.png", 40),
    ("Icon-40@2x.png", 80),
    ("Icon-40@3x.png", 120),
    ("Icon-60@2x.png", 120),
    ("Icon-60@3x.png", 180),
    ("Icon-76.png", 76),
    ("Icon-76@2x.png", 152),
    ("Icon-83.5@2x.png", 167),
    ("Icon-1024.png", 1024),
]


def draw_icon(size):
    img = Image.new("RGBA", (size, size), NAVY)
    d = ImageDraw.Draw(img)
    s = size / VIEW

    def pt(x, y):
        return (x * s, y * s)

    d.polygon([pt(x, y) for x, y in TRIANGLE], fill=WHITE)
    d.rectangle([pt(BAR[0], BAR[1]), pt(BAR[2], BAR[3])], fill=NAVY)
    d.rectangle([pt(DOT[0], DOT[1]), pt(DOT[2], DOT[3])], fill=NAVY)
    return img


def main():
    out_dir = sys.argv[1] if len(sys.argv) > 1 else os.path.join(
        os.path.dirname(os.path.abspath(__file__)),
        "..", "CheckpointAlerts", "Assets.xcassets", "AppIcon.appiconset")
    os.makedirs(out_dir, exist_ok=True)
    base = draw_icon(1024)
    for name, size in SIZES:
        if size == 1024:
            out = base
        else:
            out = base.resize((size, size), Image.LANCZOS)
        out.save(os.path.join(out_dir, name))
        print(f"wrote {name} ({size}x{size})")
    print(f"icons in {out_dir}")


if __name__ == "__main__":
    main()
