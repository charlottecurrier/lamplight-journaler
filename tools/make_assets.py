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

def app_icon(size=1024):
    """A window with a round top, lit from inside, in a dark wall. Lamplight, seen from outside at night."""
    s = size * 2  # draw large, shrink at the end for smooth edges
    top, bottom = (34, 25, 19), (14, 10, 8)
    ramp = np.linspace(0, 1, s)[:, None, None]
    wall = np.array(top)[None, None, :] * (1 - ramp) + np.array(bottom)[None, None, :] * ramp
    base = Image.fromarray(np.broadcast_to(wall, (s, s, 3)).astype(np.uint8)).convert("RGBA")

    # The light the window throws on the wall around it.
    glow = Image.new("RGBA", (s, s), (0, 0, 0, 0))
    cx, cy, r = s * 0.5, s * 0.52, s * 0.40
    ImageDraw.Draw(glow).ellipse([cx - r, cy - r, cx + r, cy + r], fill=(227, 154, 98, 90))
    base = Image.alpha_composite(base, glow.filter(ImageFilter.GaussianBlur(s * 0.12)))

    # The window: a half circle on a rectangle.
    w, h = s * 0.40, s * 0.58
    x0, y0 = s * 0.5 - w / 2, s * 0.22
    arch = Image.new("L", (s, s), 0)
    ad = ImageDraw.Draw(arch)
    ad.ellipse([x0, y0, x0 + w, y0 + w], fill=255)
    ad.rectangle([x0, y0 + w / 2, x0 + w, y0 + h], fill=255)

    # Inside it, pale where the lamp is and amber toward the frame.
    yy = np.linspace(0, 1, s)[:, None]
    xx = np.linspace(0, 1, s)[None, :]
    t = np.clip(np.sqrt((xx - 0.5) ** 2 + ((yy - 0.60) * 0.8) ** 2) / 0.30, 0, 1)[..., None]
    warm = np.array([255, 236, 200]) * (1 - t) + np.array([214, 132, 74]) * t
    base = Image.composite(Image.fromarray(warm.astype(np.uint8)).convert("RGBA"), base, arch)

    # Its bars and sill.
    d = ImageDraw.Draw(base)
    bar, thick = (58, 38, 24, 255), int(s * 0.016)
    d.line([(s * 0.5, y0), (s * 0.5, y0 + h)], fill=bar, width=thick)
    d.line([(x0, y0 + h * 0.56), (x0 + w, y0 + h * 0.56)], fill=bar, width=thick)
    d.rounded_rectangle(
        [x0 - s * 0.035, y0 + h, x0 + w + s * 0.035, y0 + h + s * 0.035], radius=s * 0.01, fill=(74, 52, 36, 255)
    )

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
