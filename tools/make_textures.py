"""Regenerate Media/Textures/. Needs Pillow.

    python tools/make_textures.py
"""
import os
import struct
import sys

from PIL import Image, ImageDraw

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
OUT = os.path.join(ROOT, 'Media', 'Textures')
SUPERSAMPLE = 8
STROKE_32 = 4 / 32


def stroke(draw, n, points, width):
    pts = [(x * n, y * n) for x, y in points]
    w = width * n
    draw.line(pts, fill=255, width=round(w))
    r = w / 2
    for x, y in pts:
        draw.ellipse((x - r, y - r, x + r, y + r), fill=255)


# The 16 px icons are drawn in whole pixels from here on. A straight stroke that straddles a
# pixel row comes out as two grey rows instead of one white one.
def box(draw, x0, y0, x1, y1):
    s = SUPERSAMPLE
    draw.rectangle((x0 * s, y0 * s, x1 * s - 1, y1 * s - 1), fill=255)


def disc(draw, cx, cy, r):
    s = SUPERSAMPLE
    draw.ellipse(((cx - r) * s, (cy - r) * s, (cx + r) * s - 1, (cy + r) * s - 1), fill=255)


def ring(draw, x0, y0, x1, y1):
    s = SUPERSAMPLE
    draw.ellipse((x0 * s, y0 * s, x1 * s - 1, y1 * s - 1), outline=255, width=2 * s)


def check(d, n):
    stroke(d, n, [(0.22, 0.52), (0.42, 0.72), (0.78, 0.32)], STROKE_32)


def chevron_down(d, n):
    stroke(d, n, [(0.28, 0.40), (0.50, 0.62), (0.72, 0.40)], STROKE_32)


def chevron_right(d, n):
    stroke(d, n, [(0.40, 0.28), (0.62, 0.50), (0.40, 0.72)], STROKE_32)


def close(d, n):
    stroke(d, n, [(0.28, 0.28), (0.72, 0.72)], STROKE_32)
    stroke(d, n, [(0.72, 0.28), (0.28, 0.72)], STROKE_32)


def slider_thumb(d, n):
    d.rectangle((0, 0, n - 1, n - 1), fill=255)


def icon_general(d, _):
    for y, knob in ((4, 5), (8, 11), (12, 7)):
        box(d, 1, y - 1, 15, y + 1)
        disc(d, knob, y, 2.5)


def icon_tracker(d, _):
    for y in (4, 8, 12):
        box(d, 1, y - 1, 3, y + 1)
        box(d, 5, y - 1, 15, y + 1)


def icon_appearance(d, _):
    s = SUPERSAMPLE
    ring(d, 1, 1, 15, 15)
    d.pieslice((1 * s, 1 * s, 15 * s - 1, 15 * s - 1), -90, 90, fill=255)


def icon_about(d, _):
    ring(d, 1, 1, 15, 15)
    box(d, 7, 4, 9, 6)
    box(d, 7, 7, 9, 12)


def icon_discord(d, _):
    s = SUPERSAMPLE
    d.rounded_rectangle((1 * s, 2 * s, 15 * s - 1, 12 * s - 1), radius=3 * s, outline=255, width=2 * s)
    d.polygon([(4 * s, 11 * s), (4 * s, 15 * s), (8 * s, 11 * s)], fill=255)


TEXTURES = [
    ('check', 32, check),
    ('chevron-down', 32, chevron_down),
    ('chevron-right', 32, chevron_right),
    ('close', 32, close),
    ('slider-thumb', 16, slider_thumb),
    ('icon-general', 16, icon_general),
    ('icon-tracker', 16, icon_tracker),
    ('icon-appearance', 16, icon_appearance),
    ('icon-about', 16, icon_about),
    ('icon-discord', 16, icon_discord),
]


def render(size, shape):
    n = size * SUPERSAMPLE
    mask = Image.new('L', (n, n), 0)
    shape(ImageDraw.Draw(mask), n)
    # Every pixel stays white and only alpha carries the shape, so filtering at any draw size
    # never blends a dark edge in from the transparent area.
    img = Image.new('RGBA', (size, size), (255, 255, 255, 0))
    img.putalpha(mask.resize((size, size), Image.Resampling.BOX))
    return img


def problems_in(path, size):
    b = open(path, 'rb').read()
    id_len, cmap_type, img_type = b[0], b[1], b[2]
    w, h = struct.unpack('<HH', b[12:16])
    bpp, desc = b[16], b[17]
    out = []
    if cmap_type != 0 or img_type != 2:
        out.append('not uncompressed true-color (type %d)' % img_type)
    if bpp != 32 or desc & 0x0F != 8:
        out.append('not 32-bit with 8 alpha bits (%d bpp, %d alpha)' % (bpp, desc & 0x0F))
    if (w, h) != (size, size) or w & (w - 1) or h & (h - 1):
        out.append('size %dx%d, wanted %dx%d power of two' % (w, h, size, size))
    if len(b) < 18 + id_len + w * h * 4:
        out.append('truncated pixel data')
    return out


def main():
    os.makedirs(OUT, exist_ok=True)
    bad = 0
    for name, size, shape in TEXTURES:
        path = os.path.join(OUT, name + '.tga')
        render(size, shape).save(path, format='TGA', rle=False)
        problems = problems_in(path, size)
        bad += len(problems)
        print('%-20s %2dx%-2d %s' % (name + '.tga', size, size, '; '.join(problems) or 'ok'))
    return 1 if bad else 0


if __name__ == '__main__':
    sys.exit(main())
