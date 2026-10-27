#!/usr/bin/env python3
"""Reads a Day One JSON export and prints what is in it, as counts. It never prints entry text, titles, tag
names or place names, so the output is safe to paste into a chat. Journal file names are printed.

    python3 tools/dayone_inspect.py ~/Downloads/Journal.zip
    python3 tools/dayone_inspect.py ~/Downloads/Journal          # an unzipped export folder

The point is to check Lamplight's data model against a real export before writing the importer.
"""
import argparse
import json
import os
import re
import sys
import zipfile
from collections import Counter

MOMENT = re.compile(r"!?\[[^\]]*\]\(dayone-moment:/{1,2}(?:(video|audio|pdfAttachment)/)?([^)]+)\)")


class Source:
    """The export, as a folder or a zip: a list of names and a way to read each one."""

    def __init__(self, path):
        self.zip = None
        self.root = path
        if os.path.isfile(path) and path.lower().endswith(".zip"):
            self.zip = zipfile.ZipFile(path)
            self.names = [n for n in self.zip.namelist() if not n.endswith("/")]
        elif os.path.isdir(path):
            self.names = []
            for base, _, files in os.walk(path):
                for f in files:
                    self.names.append(os.path.relpath(os.path.join(base, f), path))
        elif os.path.isfile(path) and path.lower().endswith(".json"):
            self.root = os.path.dirname(path) or "."
            self.names = [os.path.basename(path)]
        else:
            sys.exit("Give a Day One export: a .zip, an unzipped folder, or a .json file.")

    def read(self, name):
        if self.zip:
            return self.zip.read(name)
        with open(os.path.join(self.root, name), "rb") as handle:
            return handle.read()


def top_folder(name):
    parts = name.replace("\\", "/").split("/")
    return parts[-2] if len(parts) > 1 else ""


def inspect_journal(name, data, media):
    doc = json.loads(data)
    entries = doc.get("entries", [])
    print(f"\n== {name}")
    print(f"metadata: {doc.get('metadata')}")
    print(f"top-level keys: {sorted(doc.keys())}")
    print(f"entries: {len(entries)}")

    keys, loc_keys, weather_keys, photo_keys = Counter(), Counter(), Counter(), Counter()
    photo_types, markers, text_shape = Counter(), Counter(), Counter()
    uuid_lengths, zones = Counter(), set()
    dates, empty, uuids, dupes = [], 0, set(), 0
    photo_ids, referenced = set(), set()
    missing_files = 0
    inline_photos = 0

    for entry in entries:
        keys.update(entry.keys())
        loc_keys.update((entry.get("location") or {}).keys())
        weather_keys.update((entry.get("weather") or {}).keys())
        uuid = entry.get("uuid", "")
        uuid_lengths[len(uuid)] += 1
        if uuid in uuids:
            dupes += 1
        uuids.add(uuid)
        if entry.get("creationDate"):
            dates.append(entry["creationDate"])
        if entry.get("timeZone"):
            zones.add(entry["timeZone"])

        for photo in entry.get("photos") or []:
            photo_keys.update(photo.keys())
            photo_types[photo.get("type", "?")] += 1
            photo_ids.add(photo.get("identifier"))
            wanted = f"{photo.get('md5')}.{photo.get('type')}"
            if "photos" in media and wanted not in media["photos"]:
                missing_files += 1

        text = entry.get("text") or ""
        if not text.strip() and not entry.get("photos"):
            empty += 1
        for kind, identifier in MOMENT.findall(text):
            markers[kind or "photo"] += 1
            if not kind:
                referenced.add(identifier)
                inline_photos += 1
        for line in text.split("\n"):
            stripped = line.strip()
            if re.match(r"^#{1,6} ", stripped):
                text_shape["heading lines"] += 1
            if re.match(r"^[-*+] \[[ xX]\]", stripped):
                text_shape["checklist lines"] += 1
            elif re.match(r"^([-*+]|\d+[.)]) ", stripped):
                text_shape["list lines"] += 1
            if stripped.startswith(">"):
                text_shape["quote lines"] += 1
            if stripped.startswith("```"):
                text_shape["code fence lines"] += 1
            if re.match(r"^\|.*\|$", stripped):
                text_shape["table-looking lines"] += 1
            if re.match(r"^(-{3,}|\*{3,}|_{3,})$", stripped):
                text_shape["divider lines"] += 1
        text_shape["backslash escapes"] += len(re.findall(r"\\[!-/:-@\[-`{-~]", text))
        text_shape["entries with \\r"] += 1 if "\r" in text else 0

    print(f"empty entries (no text, no photos): {empty}")
    print(f"duplicate uuids: {dupes}; uuid lengths: {dict(uuid_lengths)}")
    if dates:
        print(f"creationDate range: {min(dates)} to {max(dates)}")
    print(f"distinct time zones: {len(zones)}; all look like names with a slash: {all('/' in z for z in zones)}")
    print("\nentry fields (how many entries have each):")
    for key, count in sorted(keys.items()):
        print(f"  {key}: {count}")
    if loc_keys:
        print(f"\nlocation fields: {dict(sorted(loc_keys.items()))}")
    if weather_keys:
        print(f"weather fields: {dict(sorted(weather_keys.items()))}")
    if photo_keys:
        print(f"\nphoto fields: {dict(sorted(photo_keys.items()))}")
        print(f"photo types: {dict(photo_types)}")
        print(f"photo files missing from the photos folder: {missing_files}")
        print(f"inline photo markers: {inline_photos}; photos in entries: {len(photo_ids)}; "
              f"markers with no matching photo entry: {len(referenced - photo_ids)}; "
              f"photos never placed inline: {len(photo_ids - referenced)}")
    if markers:
        print(f"inline media markers by kind: {dict(markers)}")

    starred = sum(1 for e in entries if e.get("starred"))
    pinned = sum(1 for e in entries if e.get("isPinned"))
    tagged = [e for e in entries if e.get("tags")]
    all_tags = {t for e in tagged for t in e["tags"]}
    print(f"\nstarred: {starred}; pinned: {pinned}; all-day: {sum(1 for e in entries if e.get('isAllDay'))}")
    print(f"entries with tags: {len(tagged)}; distinct tags: {len(all_tags)}")
    print(f"entries with location: {sum(1 for e in entries if e.get('location'))}; "
          f"with weather: {sum(1 for e in entries if e.get('weather'))}")
    for kind in ("audios", "videos", "pdfAttachments"):
        print(f"entries with {kind}: {sum(1 for e in entries if e.get(kind))}")
    print(f"entries with richText: {sum(1 for e in entries if e.get('richText'))}")
    print("\ntext shapes:")
    for key, count in sorted(text_shape.items()):
        print(f"  {key}: {count}")


def main():
    parser = argparse.ArgumentParser(description=__doc__, formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument("path")
    args = parser.parse_args()

    source = Source(os.path.expanduser(args.path))
    media = {}
    for name in source.names:
        folder = top_folder(name)
        if folder in ("photos", "videos", "audios", "pdfs"):
            media.setdefault(folder, set()).add(os.path.basename(name))
    print("media folders:", {folder: len(files) for folder, files in sorted(media.items())} or "none found")

    journals = [n for n in source.names if n.lower().endswith(".json")]
    if not journals:
        sys.exit("No .json file found in the export.")
    for name in sorted(journals):
        try:
            inspect_journal(name, source.read(name), media)
        except (ValueError, UnicodeDecodeError, AttributeError) as error:
            print(f"\n== {name}\nnot a Day One journal file: {error}")


if __name__ == "__main__":
    main()
