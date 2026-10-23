#!/usr/bin/env python3
"""Draws the paper texture choices and a preview sheet to compare them.

    python3 tools/make_textures.py --preview <dir>   # writes dark.png and light.png contact sheets
    python3 tools/make_textures.py --write           # writes the tiles into the asset catalog

Each texture is a faint overlay tile that repeats over the page. They change brightness only, never hue,
so they stay readable through amber lenses. Needs numpy and Pillow.
"""
import argparse
import sys
from pathlib import Path

import numpy as np
from PIL import Image, ImageDraw, ImageFont

sys.path.insert(0, str(Path(__file__).resolve().parent))
import make_assets as base  # noqa: E402

TILE = base.TILE


# ---------- helpers ----------

def blur_xy(a, sx, sy):
    """Wrapping Gaussian blur with a different width across and down."""
    f = np.fft.fftfreq(a.shape[0])
    fx, fy = np.meshgrid(f, f)
    kernel = np.exp(-2 * (np.pi ** 2) * ((sx ** 2) * (fx ** 2) + (sy ** 2) * (fy ** 2)))
    return np.real(np.fft.ifft2(np.fft.fft2(a) * kernel))


def noise(rng, sigma):
    return base.normalize(base.blur_wrap(rng.normal(size=(TILE, TILE)), sigma)) if sigma else base.normalize(
        rng.normal(size=(TILE, TILE)))


def lit(height, strength=1.0):
    """Shade a height map as if lit from the top left, so bumps look raised."""
    gx = (np.roll(height, -1, axis=1) - np.roll(height, 1, axis=1)) / 2
    gy = (np.roll(height, -1, axis=0) - np.roll(height, 1, axis=0)) / 2
    return base.normalize(-(gx + gy) * strength)


def coords():
    y, x = np.mgrid[0:TILE, 0:TILE].astype(float)
    return x, y


# ---------- the textures: each returns a field, light flecks where positive and dark where negative ----------

def cotton(rng):
    """Fine, soft grain like good notebook paper."""
    return 0.55 * noise(rng, 0) + 0.7 * noise(rng, 0.9) + 0.25 * noise(rng, 9)


def laid(rng):
    """Faint lines running both ways, like laid stationery."""
    x, y = coords()
    cloud = noise(rng, 18)
    lines = np.sin(2 * np.pi * y / 8) * (0.7 + 0.3 * cloud)
    chain = np.exp(-(((x % 128) - 64) ** 2) / (2 * 1.6 ** 2))
    return 0.45 * noise(rng, 0) + 0.45 * noise(rng, 1.0) + 0.55 * lines + 0.9 * chain - 0.2


def linen(rng):
    """Woven thread, like the cloth on a bound book."""
    x, y = coords()
    across = noise(rng, 0) * 0 + base.normalize(blur_xy(rng.normal(size=(TILE, TILE)), 5.0, 0.55))
    down = base.normalize(blur_xy(rng.normal(size=(TILE, TILE)), 0.55, 5.0))
    weave = np.sin(2 * np.pi * x / 8) * np.sin(2 * np.pi * y / 8) > 0
    threads = np.where(weave, across, down)
    return 0.9 * threads + 0.3 * noise(rng, 0.8) + 0.2 * noise(rng, 14)


def leather(rng):
    """Small raised pebbles with fine creases between them."""
    cell = 14
    cells = TILE // cell  # 36 cells; 36 * 14 = 504, so use a size that divides evenly
    cell = TILE // cells
    jx, jy = rng.uniform(0.1, 0.9, (cells, cells)), rng.uniform(0.1, 0.9, (cells, cells))
    x, y = coords()
    cx, cy = (x // cell).astype(int), (y // cell).astype(int)
    d1 = np.full((TILE, TILE), 1e9)
    d2 = np.full((TILE, TILE), 1e9)
    for dx in (-1, 0, 1):
        for dy in (-1, 0, 1):
            ix, iy = (cx + dx) % cells, (cy + dy) % cells
            px = (cx + dx + jx[ix, iy]) * cell
            py = (cy + dy + jy[ix, iy]) * cell
            d = np.hypot(x - px, y - py)
            d2 = np.where(d < d1, d1, np.minimum(d2, d))
            d1 = np.minimum(d1, d)
    groove = base.smoothstep(0, 0.12 * cell, d2 - d1)
    height = groove * (1 - 0.45 * np.clip(d1 / cell, 0, 1))
    height = base.blur_wrap(height, 0.8)
    return 1.1 * lit(height, 1.0) + 0.25 * noise(rng, 0.8) + 0.15 * noise(rng, 12)


def wash(rng):
    """Soft cloudy patches, like handmade paper, with almost no fine grain."""
    return 0.9 * noise(rng, 26) + 0.55 * noise(rng, 8) + 0.12 * noise(rng, 0.9)


def tooth(rng):
    """Raised, bumpy surface like cold-press watercolor paper."""
    height = noise(rng, 1.7) + 0.6 * noise(rng, 4.5) + 0.25 * noise(rng, 0.8)
    return 1.2 * lit(height, 1.0) + 0.2 * noise(rng, 14)


def dots(rng):
    """A dot grid like a bullet journal, over a fine paper grain."""
    x, y = coords()
    gx, gy = (x % 64) - 32, (y % 64) - 32
    dot = np.exp(-(gx ** 2 + gy ** 2) / (2 * 1.5 ** 2))
    return 0.45 * noise(rng, 0) + 0.5 * noise(rng, 1.0) + 3.2 * dot - 0.1


def fibers(rng):
    """The first texture: speckle and short fibers."""
    return base.grain_field(seed=7)


# id, title, field function, signed (light and dark flecks) or one sided, strength on dark, strength on light
TEXTURES = [
    ("fibers", "Fibers", fibers, False, 0.075, 0.085),
    ("cotton", "Cotton", cotton, True, 0.060, 0.070),
    ("laid", "Laid", laid, True, 0.090, 0.095),
    ("linen", "Linen", linen, True, 0.080, 0.085),
    ("leather", "Leather", leather, True, 0.050, 0.060),
    ("wash", "Wash", wash, True, 0.040, 0.050),
    ("tooth", "Tooth", tooth, True, 0.055, 0.065),
    ("dots", "Dot grid", dots, True, 0.130, 0.140),
]


def overlay(texture_id, mode):
    """RGBA tile for a texture. Positive values are lighter flecks, negative are darker."""
    spec = next(t for t in TEXTURES if t[0] == texture_id)
    _, _, make, signed, dark_strength, light_strength = spec
    if texture_id == "fibers":
        return base.grain_tile(mode)
    field = make(np.random.default_rng(sum(map(ord, texture_id))))
    f = np.clip(field / 2.6, -1, 1)
    strength = dark_strength if mode == "dark" else light_strength
    light = (255, 236, 205) if mode == "dark" else (255, 251, 240)
    shadow = (0, 0, 0) if mode == "dark" else (70, 48, 24)
    rgba = np.zeros((TILE, TILE, 4), dtype=np.uint8)
    positive = f > 0
    rgba[..., :3] = np.where(positive[..., None], light, shadow)
    # On a dark page only the lighter flecks show much, so the darker ones are kept gentle.
    weight = np.where(positive, 1.0, 0.7)
    rgba[..., 3] = (np.abs(f) * strength * weight * 255).astype(np.uint8)
    return Image.fromarray(rgba, "RGBA")


# ---------- preview sheet ----------

def font(size, bold=False):
    name = "DejaVuSerif-Bold.ttf" if bold else "DejaVuSerif.ttf"
    for folder in ("/usr/share/fonts/truetype/dejavu", "/Library/Fonts"):
        path = Path(folder) / name
        if path.exists():
            return ImageFont.truetype(str(path), size)
    return ImageFont.load_default()


def swatch(texture_id, title, mode, pal, width=480, height=330):
    page = pal["page"][mode]
    ink = pal["ink"][mode]
    secondary = pal["inkSecondary"][mode]
    accent = pal["accent"][mode]

    def rgb(v):
        return ((v >> 16) & 255, (v >> 8) & 255, v & 255)

    image = Image.new("RGBA", (width, height), rgb(page) + (255,))
    if texture_id != "none":
        tile = overlay(texture_id, mode)
        for ty in range(0, height, TILE):
            for tx in range(0, width, TILE):
                image.alpha_composite(tile, (tx, ty))
    draw = ImageDraw.Draw(image)
    draw.text((26, 22), title.upper(), font=font(13, True), fill=rgb(accent))
    draw.text((26, 54), "Thursday, October 22", font=font(25, True), fill=rgb(ink))
    draw.text((26, 96), "9:14 PM", font=font(14), fill=rgb(secondary))
    body = ["Walked home the long way. The lamps were", "on already and the air smelled like rain.",
            "I want to remember how quiet it was."]
    for i, line in enumerate(body):
        draw.text((26, 138 + i * 30), line, font=font(16), fill=rgb(ink))
    draw.text((26, 252), "What was hard?", font=font(19, True), fill=rgb(ink))
    draw.text((26, 286), "Not much. Dinner ran late.", font=font(16), fill=rgb(secondary))
    return image.convert("RGB")


def sheet(mode, pal, columns=3):
    items = [("none", "Plain")] + [(t[0], t[1]) for t in TEXTURES]
    swatches = [swatch(i, t, mode, pal) for i, t in items]
    w, h = swatches[0].size
    rows = -(-len(swatches) // columns)
    gap = 14
    out = Image.new("RGB", (columns * w + (columns + 1) * gap, rows * h + (rows + 1) * gap), (0, 0, 0))
    for index, image in enumerate(swatches):
        out.paste(image, (gap + (index % columns) * (w + gap), gap + (index // columns) * (h + gap)))
    return out


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--preview", metavar="DIR")
    parser.add_argument("--write", action="store_true")
    args = parser.parse_args()
    pal = base.palette()
    if args.preview:
        folder = Path(args.preview)
        folder.mkdir(parents=True, exist_ok=True)
        sheet("dark", pal).save(folder / "dark.png")
        sheet("light", pal).save(folder / "light.png")
        print(f"Wrote previews to {folder}")
    if args.write:
        for texture_id, _, _, _, _, _ in TEXTURES:
            if texture_id == "fibers":
                continue  # shipped as PaperGrain by make_assets.py
            name = "Paper" + texture_id.capitalize()
            base.write_imageset(name + "Dark", overlay(texture_id, "dark"))
            base.write_imageset(name + "Light", overlay(texture_id, "light"))
        print(f"Wrote textures to {base.CATALOG.relative_to(base.ROOT)}")


if __name__ == "__main__":
    main()
