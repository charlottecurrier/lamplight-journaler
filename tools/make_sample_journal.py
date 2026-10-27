#!/usr/bin/env python3
"""Writes a sample journal folder so you can try On This Day, streaks, photos and templates on day one.

    python3 tools/make_sample_journal.py ~/Desktop

makes ~/Desktop/Lamplight/. Put that folder inside its own iCloud Drive folder (say "Journal Demo") and choose
"Journal Demo" in the app. Everything in it is made up.

Do NOT drag it into a folder that already holds your real journal: Finder offers to replace the folder
with the same name, and that deletes your entries.

What you get:
  - a 12-day streak that ended yesterday, so tonight's entry keeps it going
  - entries on today's date 1, 2 and 3 years ago, with photos, for On This Day
  - about 3 years of scattered entries, two journals, two templates, a Home place

The files use the same format the app writes (see README.md). Needs Pillow.
"""
import json
import math
import random
import sys
import uuid
import zlib
from datetime import datetime, timedelta, timezone
from pathlib import Path

from PIL import Image, ImageDraw, ImageFilter

DEFAULT_JOURNAL = "00000000-0000-4000-8000-000000000001"
DREAMS_JOURNAL = "00000000-0000-4000-8000-0000000000D2"
EVENING_TEMPLATE = "00000000-0000-4000-8000-0000000000E1"
GRATITUDE_TEMPLATE = "00000000-0000-4000-8000-0000000000E2"

ZONE = "America/Los_Angeles"
ZONE_OFFSET = timedelta(hours=-7)  # close enough for sample data

HOME = {"home": True, "lat": 45.5152, "lon": -122.6784, "name": "Home"}
PLACES = [
    {"name": "Mount Tabor Park", "lat": 45.5118, "lon": -122.5952},
    {"name": "Powell's Books", "lat": 45.5230, "lon": -122.6815},
    {"name": "Cannon Beach", "lat": 45.8918, "lon": -123.9615},
]

SMALL_THINGS = [
    "Slow morning. Coffee on the porch and nowhere to be.",
    "A long walk after dinner. The air smelled like rain.",
    "Fixed the squeaky drawer. Small wins count.",
    "Called my sister. We talked for an hour and it felt short.",
    "Too many meetings. Cooked something simple and went to bed early.",
    "Read for two hours. The book is finally getting good.",
    "Rain all day. Soup, a blanket, and the quiet kind of tired.",
    "Tried a new route home and found a bakery I never noticed.",
    "Not much happened. I'm writing it down anyway.",
    "The light at 5 PM was unreal. Stopped on the sidewalk just to look.",
]

DREAMS = [
    "I was in my grandmother's kitchen but the windows looked out over the ocean.",
    "A train that never stopped. Everyone on it knew me, nobody spoke.",
    "Flying low over a field of tall grass. It felt easy, like swimming.",
]

EVENING_QUESTIONS = ["What went well today?", "What was hard?", "What am I looking forward to?"]
EVENING_ANSWERS = [
    ["The light in the kitchen this afternoon.", "Not much. A slow start.", "Saturday. Nothing planned."],
    ["Finished the thing I'd been putting off.", "Staying focused after lunch.", "A long bath and an early night."],
    ["A good conversation with a friend.", "Feeling behind on email.", "Fresh bread tomorrow."],
]


def iso(dt: datetime) -> str:
    return dt.astimezone(timezone.utc).strftime("%Y-%m-%dT%H:%M:%S.000Z")


def json_value(value) -> str:
    return json.dumps(value, ensure_ascii=False, separators=(",", ":"), sort_keys=True)


def make_photo(path: Path, seed: int, size=(1600, 1200)):
    """A soft, warm abstract 'photo': sky gradient, a glow, and a few shapes. Different per seed."""
    rng = random.Random(seed)
    w, h = size
    top = tuple(rng.randint(30, 90) for _ in range(3))
    bottom = (rng.randint(150, 235), rng.randint(90, 170), rng.randint(40, 110))
    img = Image.new("RGB", size)
    px = ImageDraw.Draw(img)
    for y in range(h):
        t = y / h
        px.line([(0, y), (w, y)], fill=tuple(int(a + (b - a) * t) for a, b in zip(top, bottom)))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    gd = ImageDraw.Draw(glow)
    cx, cy, r = rng.randint(w // 4, 3 * w // 4), rng.randint(h // 4, h // 2), rng.randint(120, 260)
    gd.ellipse([cx - r, cy - r, cx + r, cy + r], fill=(255, 226, 170, 210))
    glow = glow.filter(ImageFilter.GaussianBlur(60))
    img = Image.alpha_composite(img.convert("RGBA"), glow).convert("RGB")
    px = ImageDraw.Draw(img)
    base = h * rng.uniform(0.62, 0.78)
    for layer in range(3):
        shade = tuple(int(c * (0.35 - layer * 0.08)) for c in bottom)
        points = [(0, h)]
        for x in range(0, w + 40, 40):
            y = base + layer * 60 + math.sin(x / (170 + layer * 40) + seed + layer) * (40 + layer * 12)
            points.append((x, y))
        points.append((w, h))
        px.polygon(points, fill=shade)
    path.parent.mkdir(parents=True, exist_ok=True)
    img.filter(ImageFilter.GaussianBlur(1.2)).save(path, "JPEG", quality=82)
    return w, h


def write_entry(root: Path, *, when: datetime, journal: str, body: str, photos=0, place=None, template=None, seed=0):
    entry_id = str(uuid.UUID(int=random.Random(f"{when.isoformat()}{seed}").getrandbits(128), version=4)).upper()
    folder = root / "Entries" / entry_id
    refs = []
    for i in range(photos):
        photo_id = str(uuid.UUID(int=random.Random(f"{entry_id}-{i}").getrandbits(128), version=4)).upper()
        name = f"{photo_id}.jpg"
        w, h = make_photo(folder / "photos" / name, seed=zlib.crc32(f"{entry_id}-{i}".encode()) & 0xFFFF)
        refs.append({"file": name, "h": h, "id": photo_id, "w": w})
    lines = [
        "---",
        f"id: {json_value(entry_id)}",
        f"journal: {json_value(journal)}",
        f"created: {json_value(iso(when))}",
        f"modified: {json_value(iso(when + timedelta(minutes=12)))}",
        f"timezone: {json_value(ZONE)}",
    ]
    if template:
        lines.append(f"template: {json_value(template)}")
    if place:
        lines.append(f"location: {json_value(place)}")
    if refs:
        lines.append(f"photos: {json_value(refs)}")
    # About one entry in nine is a favorite, so the Favorites screen has something to show.
    if zlib.crc32(entry_id.encode()) % 9 == 0:
        lines.append("favorite: true")
    lines += ["---", ""]
    folder.mkdir(parents=True, exist_ok=True)
    (folder / "entry.md").write_text("\n".join(lines) + "\n" + body, encoding="utf-8")


def evening_body(rng: random.Random) -> str:
    answers = rng.choice(EVENING_ANSWERS)
    return "\n\n".join(f"## {q}\n\n{a}" for q, a in zip(EVENING_QUESTIONS, answers)) + "\n"


def main(out_dir: Path):
    rng = random.Random(42)
    root = out_dir / "Lamplight"
    if root.exists():
        sys.exit(f"{root} already exists. Remove it first so nothing is overwritten.")
    now = datetime.now(timezone.utc).astimezone(timezone(ZONE_OFFSET))
    created = iso(now - timedelta(days=900))

    for journal_id, name, color, order in [
        (DEFAULT_JOURNAL, "Journal", "ember", 0),
        (DREAMS_JOURNAL, "Dreams", "sage", 1),
    ]:
        path = root / "Journals" / f"{journal_id}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({
            "id": journal_id, "name": name, "colorKey": color, "sortOrder": order, "createdAt": created[:19] + "Z",
        }, indent=2, sort_keys=True), encoding="utf-8")

    for template_id, name, questions, order in [
        (EVENING_TEMPLATE, "Evening check-in", EVENING_QUESTIONS, 0),
        (GRATITUDE_TEMPLATE, "Three good things", ["First thing", "Second thing", "Third thing"], 1),
    ]:
        # A template is a page of Markdown. Each question becomes a heading with a blank line under it.
        template_body = "".join(f"## {question}\n\n" for question in questions)
        path = root / "Templates" / f"{template_id}.json"
        path.parent.mkdir(parents=True, exist_ok=True)
        path.write_text(json.dumps({
            "id": template_id, "name": name, "body": template_body, "sortOrder": order,
            "createdAt": created[:19] + "Z", "modifiedAt": created[:19] + "Z",
        }, indent=2, sort_keys=True), encoding="utf-8")

    (root / "settings.json").write_text(json.dumps({"home": HOME}, indent=2, sort_keys=True), encoding="utf-8")

    def evening(day_offset: int, hour=21, minute=None) -> datetime:
        minute = rng.randint(0, 59) if minute is None else minute
        base = (now - timedelta(days=day_offset)).replace(hour=hour, minute=minute, second=7, microsecond=0)
        return base

    count = 0

    # A streak that ended yesterday.
    for offset in range(1, 13):
        with_template = offset % 3 == 0
        write_entry(
            root, when=evening(offset), journal=DEFAULT_JOURNAL,
            body=evening_body(rng) if with_template else rng.choice(SMALL_THINGS) + "\n",
            template=EVENING_TEMPLATE if with_template else None,
            place=HOME if offset % 2 else None, photos=1 if offset in (2, 7) else 0, seed=offset,
        )
        count += 1

    # Today's date in earlier years, for On This Day.
    for years in (1, 2, 3):
        try:
            when = evening(0).replace(year=now.year - years)
        except ValueError:  # Feb 29
            when = evening(0).replace(year=now.year - years, day=28)
        write_entry(
            root, when=when, journal=DEFAULT_JOURNAL,
            body=f"## What went well?\n\nA quiet one, {years} year{'s' if years > 1 else ''} before. I remember the light.\n\n"
                 "## What was hard?\n\nLetting the day end.\n",
            template=EVENING_TEMPLATE, place=rng.choice(PLACES), photos=min(years, 3), seed=100 + years,
        )
        count += 1

    # The rest of the three years, scattered.
    for _ in range(45):
        offset = rng.randint(14, 1000)
        when = evening(offset, hour=rng.randint(19, 23))
        write_entry(
            root, when=when, journal=DEFAULT_JOURNAL, body=rng.choice(SMALL_THINGS) + "\n",
            place=rng.choice([None, HOME, rng.choice(PLACES)]), photos=rng.choice([0, 0, 0, 1, 2, 4]), seed=offset,
        )
        count += 1

    for i in range(6):
        write_entry(
            root, when=evening(rng.randint(3, 500), hour=7), journal=DREAMS_JOURNAL,
            body=rng.choice(DREAMS) + "\n", seed=900 + i,
        )
        count += 1

    print(f"Wrote {count} entries, 2 journals and 2 templates to {root}")


if __name__ == "__main__":
    if len(sys.argv) != 2:
        sys.exit(__doc__)
    main(Path(sys.argv[1]).expanduser())
