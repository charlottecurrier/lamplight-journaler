#!/usr/bin/env python3
"""Generates the app's image assets: paper grain tiles, app icon, and color sets.

Everything is drawn from code so it can be tuned and regenerated:

    python3 tools/make_assets.py

Writes into App/Resources/Assets.xcassets. Needs numpy and Pillow.
"""
import json
import re
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFilter

ROOT = Path(__file__).resolve().parent.parent
CATALOG = ROOT / "App" / "Resources" / "Assets.xcassets"
PALETTE_SWIFT = ROOT / "App" / "Theme" / "Palette.swift"

TILE = 512  # pixels. Shipped as @2x, so it covers 256 points before repeating.


# ---------- helpers ----------

def write_json(path: Path, data):
    path.parent.mkdir(parents=True, exist_ok=True)
    path.write_text(json.dumps(data, indent=2) + "\n")


def palette():
    found = re.findall(
        r"static let (\w+) = Pair\(light: 0x([0-9A-Fa-f]{6}), dark: 0x([0-9A-Fa-f]{6})\)",
        PALETTE_SWIFT.read_text(),
    )
    return {n: {"light": int(l, 16), "dark": int(d, 16)} for n, l, d in found}


def color_json(hex_value):
    r, g, b = (hex_value >> 16) & 255, (hex_value >> 8) & 255, hex_value & 255
    return {
        "color-space": "srgb",
        "components": {"red": f"{r/255:.3f}", "green": f"{g/255:.3f}", "blue": f"{b/255:.3f}", "alpha": "1.000"},
    }


def write_colorset(name, light, dark):
    write_json(CATALOG / f"{name}.colorset" / "Contents.json", {
        "colors": [
            {"idiom": "universal", "color": color_json(light)},
            {
                "appearances": [{"appearance": "luminosity", "value": "dark"}],
                "idiom": "universal",
                "color": color_json(dark),
            },
        ],
        "info": {"author": "xcode", "version": 1},
    })


# ---------- paper grain ----------

def blur_wrap(a, sigma):
    """Gaussian blur that wraps around the edges, so the tile repeats without seams."""
    n = a.shape[0]
    f = np.fft.fftfreq(n)
    fx, fy = np.meshgrid(f, f)
    kernel = np.exp(-2 * (np.pi ** 2) * (sigma ** 2) * (fx ** 2 + fy ** 2))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def normalize(a):
    a = a - a.mean()
    return a / (a.std() + 1e-9)


def fibers(rng, count=1400):
    """Short, faint curved strokes like fibers in paper. Wraps at the edges."""
    canvas = np.zeros((TILE, TILE))
    for _ in range(count):
        x, y = rng.uniform(0, TILE, 2)
        angle = rng.uniform(0, np.pi)
        length = rng.uniform(8, 38)
        bend = rng.normal(0, 0.035)
        strength = rng.uniform(0.4, 1.0) * rng.choice([-1, 1])
        for step in range(int(length)):
            angle += bend
            x += np.cos(angle)
            y += np.sin(angle)
            canvas[int(y) % TILE, int(x) % TILE] += strength
    return blur_wrap(canvas, 0.7)


def grain_field(seed):
    rng = np.random.default_rng(seed)
    fine = normalize(rng.normal(size=(TILE, TILE)))
    medium = normalize(blur_wrap(rng.normal(size=(TILE, TILE)), 1.4))
    cloud = normalize(blur_wrap(rng.normal(size=(TILE, TILE)), 22))
    fiber = normalize(fibers(rng))
    return 0.50 * fine + 0.55 * medium + 0.35 * cloud + 0.55 * fiber


def smoothstep(edge0, edge1, x):
    t = np.clip((x - edge0) / (edge1 - edge0), 0, 1)
    return t * t * (3 - 2 * t)


def grain_tile(mode):
    """RGBA tile. Dark theme gets faint light flecks, light theme gets faint dark flecks."""
    field = grain_field(seed=7 if mode == "dark" else 11)
    if mode == "dark":
        color, strength, max_alpha = (255, 236, 205), smoothstep(0.3, 2.6, field), 0.075
    else:
        color, strength, max_alpha = (70, 48, 24), smoothstep(0.3, 2.6, -field), 0.085
    alpha = (strength * max_alpha * 255).astype(np.uint8)
    rgba = np.zeros((TILE, TILE, 4), dtype=np.uint8)
    rgba[..., 0], rgba[..., 1], rgba[..., 2] = color
    rgba[..., 3] = alpha
    return Image.fromarray(rgba, "RGBA")


def write_imageset(name, image):
    folder = CATALOG / f"{name}.imageset"
    folder.mkdir(parents=True, exist_ok=True)
    image.save(folder / f"{name}@2x.png")
    write_json(folder / "Contents.json", {
        "images": [{"idiom": "universal", "filename": f"{name}@2x.png", "scale": "2x"}],
        "info": {"author": "xcode", "version": 1},
    })


# ---------- app icon ----------

def lerp(a, b, t):
    return tuple(round(x + (y - x) * t) for x, y in zip(a, b))


def app_icon(size=1024):
    s = size * 2  # draw large, shrink at the end for smooth edges
    top, bottom = (43, 32, 25), (21, 16, 12)
    base = Image.new("RGB", (s, s))
    px = ImageDraw.Draw(base)
    for y in range(s):
        px.line([(0, y), (s, y)], fill=lerp(top, bottom, y / s))

    # Lamp glow behind the page.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy, r = s * 0.5, s * 0.42, s * 0.5
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(227, 154, 98, 150))
    glow = glow.filter(ImageFilter.GaussianBlur(s * 0.12))
    base = Image.alpha_composite(base.convert("RGBA"), glow)

    # The page: cream, slightly turned, with soft shadow and a few ruled lines.
    pw, ph = int(s * 0.50), int(s * 0.62)
    page = Image.new("RGBA", (pw, ph), (0, 0, 0, 0))
    pd = ImageDraw.Draw(page)
    pd.rounded_rectangle([0, 0, pw - 1, ph - 1], radius=int(s * 0.03), fill=(241, 228, 204, 255))
    margin = int(pw * 0.14)
    for i in range(6):
        y = int(ph * 0.22 + i * ph * 0.115)
        pd.line([(margin, y), (pw - margin - (int(pw * 0.25) if i == 5 else 0), y)], fill=(196, 176, 142, 255), width=int(s * 0.006))
    pd.ellipse([margin, int(ph * 0.09), margin + int(s * 0.03), int(ph * 0.09) + int(s * 0.03)], fill=(194, 107, 52, 255))
    page = page.rotate(5, expand=True, resample=Image.BICUBIC)

    # Pad the shadow canvas so the blur isn't cut off at the page's edges.
    pad = int(s * 0.08)
    mask = Image.new("L", (page.width + 2 * pad, page.height + 2 * pad), 0)
    mask.paste(page.getchannel("A"), (pad, pad))
    mask = mask.filter(ImageFilter.GaussianBlur(s * 0.025)).point(lambda v: int(v * 0.6))
    shadow = Image.new("RGBA", mask.size, (8, 5, 3, 0))
    shadow.putalpha(mask)

    ox, oy = (s - page.width) // 2, int(s * 0.17)
    base.alpha_composite(shadow, (ox - pad + int(s * 0.012), oy - pad + int(s * 0.03)))
    base.alpha_composite(page, (ox, oy))

    icon = base.convert("RGB").resize((size, size), Image.LANCZOS)
    # A touch of grain so it matches the app.
    grain = grain_tile("dark").resize((size, size), Image.LANCZOS)
    icon = Image.alpha_composite(icon.convert("RGBA"), grain).convert("RGB")
    return icon


def write_app_icon():
    folder = CATALOG / "AppIcon.appiconset"
    folder.mkdir(parents=True, exist_ok=True)
    app_icon().save(folder / "icon-1024.png")
    write_json(folder / "Contents.json", {
        "images": [{"filename": "icon-1024.png", "idiom": "universal", "platform": "ios", "size": "1024x1024"}],
        "info": {"author": "xcode", "version": 1},
    })


if __name__ == "__main__":
    pal = palette()
    write_json(CATALOG / "Contents.json", {"info": {"author": "xcode", "version": 1}})
    write_colorset("AccentColor", pal["accent"]["light"], pal["accent"]["dark"])
    write_colorset("LaunchBackground", pal["page"]["light"], pal["page"]["dark"])
    write_imageset("PaperGrainDark", grain_tile("dark"))
    write_imageset("PaperGrainLight", grain_tile("light"))
    write_app_icon()
    print(f"Wrote assets to {CATALOG.relative_to(ROOT)}")
