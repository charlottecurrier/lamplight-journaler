#!/usr/bin/env python3
"""Gives the pictures exported from a test run the names the tests gave them.

    xcrun xcresulttool export attachments --path Run.xcresult --output-path <dir>
    python3 tools/name_test_pictures.py <dir>

The export names each file by a long ID and lists the real names in manifest.json. This renames each file to
"<test> - <name>.png" and says how many pictures there are. If a test left a text file (what it saw when it couldn't
find something), the first one is printed, since the log is the quickest place to read it.
"""
import json
import os
import re
import sys

PICTURES = (".png", ".jpg", ".jpeg", ".heic")


def rename(out):
    manifest = os.path.join(out, "manifest.json")
    if not os.path.exists(manifest):
        return
    for test in json.load(open(manifest)):
        for item in test.get("attachments", []):
            old = os.path.join(out, item.get("exportedFileName", ""))
            name = item.get("suggestedHumanReadableName") or ""
            if not os.path.isfile(old) or not name:
                continue
            stem, ext = os.path.splitext(name)
            # The suggested name ends with a number and a long ID. Keep the part the test wrote.
            stem = re.sub(r"_\d+_[0-9A-Fa-f-]{36}$", "", stem)
            test_name = (test.get("testIdentifier") or "").split("/")[-1].replace("()", "")
            new = os.path.join(out, re.sub(r"[^A-Za-z0-9 ._-]", "", f"{test_name} - {stem}{ext or '.png'}"))
            if not os.path.exists(new):
                os.rename(old, new)


def main():
    if len(sys.argv) != 2 or not os.path.isdir(sys.argv[1]):
        sys.exit("usage: name_test_pictures.py <folder of exported attachments>")
    out = sys.argv[1]
    rename(out)
    files = os.listdir(out)
    print(f"{len([f for f in files if f.lower().endswith(PICTURES)])} pictures in {out}")
    trees = sorted(f for f in files if f.endswith(".txt"))
    if trees:
        print(f"--- {trees[0]} ---")
        print(open(os.path.join(out, trees[0]), errors="replace").read()[:20000])


if __name__ == "__main__":
    main()
