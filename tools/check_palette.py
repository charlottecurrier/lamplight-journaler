#!/usr/bin/env python3
"""Checks the app palette and draws a preview.

Reads the `Pair(light:dark:)` lines from App/Theme/Palette.swift, then:
  1. prints WCAG contrast ratios for the pairs that matter,
  2. repeats them after a rough amber blue-blocker filter,
  3. writes docs/palette-preview.png (normal on top, through amber lenses below).

The amber filter is an estimate: it keeps red, cuts green a little and blue a lot.
Real lenses vary, so treat the numbers as a guide and the result as a sanity check.

    python3 tools/check_palette.py
"""
import re
import sys
from pathlib import Path

from PIL import Image, ImageDraw, ImageFont

ROOT = Path(__file__).resolve().parent.parent
PALETTE_SWIFT = ROOT / "App" / "Theme" / "Palette.swift"
OUT = ROOT / "docs" / "palette-preview.png"

# Share of light that passes the lens, in linear RGB.
AMBER = (1.0, 0.72, 0.07)


def load_palette():
    text = PALETTE_SWIFT.read_text()
    found = re.findall(
        r"static let (\w+) = Pair\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)", text
    )
    if not found:
        sys.exit("No Pair(light:dark:) lines found in Palette.swift")
    return {name: {"light": int(l, 16), "dark": int(d, 16)} for name, l, d in found}


def rgb(hex_value):
    return ((hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255)


def to_linear(c):
    c = c / 255
    return c / 12.92 if c <= 0.04045 else ((c + 0.055) / 1.055) ** 2.4


def to_srgb(v):
    v = min(max(v, 0), 1)
    v = 12.92 * v if v <= 0.0031308 else 1.055 * v ** (1 / 2.4) - 0.055
    return round(v * 255)


def lens(color):
    return tuple(to_srgb(to_linear(c) * k) for c, k in zip(color, AMBER))


def luminance(color):
    r, g, b = (to_linear(c) for c in color)
    return 0.2126 * r + 0.7152 * g + 0.0722 * b


def contrast(a, b):
    la, lb = luminance(a), luminance(b)
    hi, lo = max(la, lb), min(la, lb)
    return (hi + 0.05) / (lo + 0.05)


# (foreground, background, minimum ratio, what it is)
CHECKS = [
    ("ink", "page", 7.0, "body text on page"),
    ("ink", "surface", 7.0, "body text on cards"),
    ("inkSecondary", "page", 4.5, "secondary text"),
    ("inkSecondary", "surface", 4.5, "secondary text on cards"),
    ("inkTertiary", "page", 4.5, "captions"),
    ("inkTertiary", "surface", 4.5, "captions on cards"),
    ("accent", "page", 4.5, "links and icons"),
    ("accent", "surface", 4.5, "links and icons on cards"),
    ("onAccent", "accent", 4.5, "button label"),
    ("sage", "page", 3.0, "streak marks"),
    ("danger", "page", 4.5, "delete actions"),
    ("line", "page", 1.2, "hairlines (decorative)"),
]


def report(palette):
    failures = 0
    for mode in ("dark", "light"):
        print(f"\n== {mode} ==   normal  | through amber lenses")
        for fg, bg, minimum, label in CHECKS:
            a, b = rgb(palette[fg][mode]), rgb(palette[bg][mode])
            plain = contrast(a, b)
            through = contrast(lens(a), lens(b))
            ok = plain >= minimum and through >= minimum
            failures += 0 if ok else 1
            print(f"  {'ok  ' if ok else 'LOW '} {label:<28} {plain:5.1f}   | {through:5.1f}   (needs {minimum})")
    return failures


def font(size, bold=False):
    names = ["DejaVuSerif-Bold.ttf" if bold else "DejaVuSerif.ttf", "DejaVuSans.ttf"]
    for name in names:
        try:
            return ImageFont.truetype(name, size)
        except OSError:
            continue
    return ImageFont.load_default()


def draw_card(d, x, y, w, h, palette, mode, filt):
    c = lambda name: filt(rgb(palette[name][mode]))
    d.rectangle([x, y, x + w, y + h], fill=c("page"))
    d.rounded_rectangle([x + 14, y + 14, x + w - 14, y + 130], radius=14, fill=c("surface"), outline=c("line"))
    d.text((x + 30, y + 26), "Friday, October 17", font=font(17, True), fill=c("ink"))
    d.text((x + 30, y + 54), "The light in the kitchen was low", font=font(14), fill=c("ink"))
    d.text((x + 30, y + 76), "and the whole house felt slow.", font=font(14), fill=c("inkSecondary"))
    d.text((x + 30, y + 104), "9:14 PM  ·  Home", font=font(12), fill=c("inkTertiary"))
    d.rounded_rectangle([x + 14, y + 146, x + 150, y + 186], radius=20, fill=c("accent"))
    d.text((x + 38, y + 157), "Save entry", font=font(14, True), fill=c("onAccent"))
    d.text((x + 168, y + 157), "12-day streak", font=font(14), fill=c("accent"))
    for i in range(7):
        cx = x + 30 + i * 26
        filled = i != 3
        d.ellipse([cx, y + 202, cx + 14, y + 216], fill=c("sage") if filled else c("line"))
    names = ["journalSage", "journalGold", "journalClay", "journalMoss", "journalStone"]
    for i, name in enumerate(names):
        cx = x + 30 + i * 26
        d.ellipse([cx, y + 232, cx + 14, y + 246], fill=c(name))
    d.text((x + 30, y + 262), "Delete", font=font(14), fill=c("danger"))


def preview(palette):
    w, h = 340, 300
    img = Image.new("RGB", (w * 2 + 3 * 16, h * 2 + 3 * 16 + 20), (128, 128, 128))
    d = ImageDraw.Draw(img)
    for row, filt in enumerate((lambda c: c, lens)):
        for col, mode in enumerate(("dark", "light")):
            draw_card(d, 16 + col * (w + 16), 16 + row * (h + 16 + 4), w, h, palette, mode, filt)
    d.text((16, img.height - 18), "top: as designed    bottom: through estimated amber lenses", font=font(11), fill=(240, 240, 240))
    OUT.parent.mkdir(exist_ok=True)
    img.save(OUT)
    print(f"\nWrote {OUT.relative_to(ROOT)}")


if __name__ == "__main__":
    palette = load_palette()
    bad = report(palette)
    preview(palette)
    print(f"\n{bad} check(s) below target" if bad else "\nAll checks pass")
    sys.exit(1 if bad else 0)
