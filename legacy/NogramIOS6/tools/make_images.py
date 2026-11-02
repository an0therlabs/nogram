#!/usr/bin/env python3
"""Generates the app icon and the iOS 6 launch images into Resources/.

Without Default-568h@2x.png iOS 6 runs the app letterboxed on the iPhone 5,
so the launch images are not optional. Run from the project directory.
"""
import os
from PIL import Image, ImageDraw

OUT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "Resources")


def icon(size):
    s = 4  # supersample
    img = Image.new("RGB", (size * s, size * s))
    d = ImageDraw.Draw(img)
    top, bottom = (0x37, 0xae, 0xe2), (0x1e, 0x96, 0xc8)
    for y in range(size * s):
        t = y / (size * s - 1)
        d.line([(0, y), (size * s, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    u = size * s / 100.0
    # paper plane
    d.polygon([(22 * u, 48 * u), (78 * u, 26 * u), (68 * u, 76 * u)], fill=(255, 255, 255))
    d.polygon([(40 * u, 56 * u), (78 * u, 26 * u), (46 * u, 72 * u)], fill=(0xc8, 0xda, 0xea))
    return img.resize((size, size), Image.LANCZOS)


def launch(w, h, scale):
    img = Image.new("RGB", (w, h), (255, 255, 255))
    d = ImageDraw.Draw(img)
    status, nav, tab = 20 * scale, 44 * scale, 49 * scale
    d.rectangle([0, 0, w, status + nav], fill=(0xf7, 0xf7, 0xf7))
    d.rectangle([0, status + nav - 1, w, status + nav], fill=(0xb2, 0xb2, 0xb2))
    d.rectangle([0, h - tab, w, h], fill=(0xf7, 0xf7, 0xf7))
    d.rectangle([0, h - tab, w, h - tab], fill=(0xb2, 0xb2, 0xb2))
    return img


icon(57).save(os.path.join(OUT, "Icon.png"))
icon(114).save(os.path.join(OUT, "Icon@2x.png"))
launch(320, 480, 1).save(os.path.join(OUT, "Default.png"))
launch(640, 960, 2).save(os.path.join(OUT, "Default@2x.png"))
launch(640, 1136, 2).save(os.path.join(OUT, "Default-568h@2x.png"))
