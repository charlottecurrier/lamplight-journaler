#!/usr/bin/env python3
"""Checks that App/PrivacyInfo.xcprivacy covers the APIs the code uses.

Apple makes an app say why it uses a few APIs (settings storage, file dates, the time since boot, free disk space,
the keyboards in use). An upload to App Store Connect is flagged when the app uses one and doesn't say. This looks
for those APIs in App/ and Sources/ and fails when one is used but not declared with a reason.

It cannot tell you the right reason. Apple lists them at
https://developer.apple.com/documentation/bundleresources/describing-use-of-required-reason-api

    python3 tools/check_privacy_manifest.py [repo folder]
"""
import plistlib
import re
import sys
from pathlib import Path

CATEGORIES = {
    "NSPrivacyAccessedAPICategoryUserDefaults": r"\bUserDefaults\b|@AppStorage|\bNSUserDefaults\b",
    "NSPrivacyAccessedAPICategoryFileTimestamp": (
        r"contentModificationDate|creationDateKey|contentAccessDate|attributeModificationDate|fileModificationDate"
        r"|fileCreationDate|NSFileModificationDate|NSFileCreationDate|\.modificationDate\b|\bf?l?stat\(|getattrlist"
    ),
    "NSPrivacyAccessedAPICategorySystemBootTime": r"systemUptime|mach_absolute_time|mach_continuous_time|kern\.boottime",
    "NSPrivacyAccessedAPICategoryDiskSpace": (
        r"volumeAvailableCapacity|volumeTotalCapacity|systemFreeSize|\bNSFileSystemFreeSize\b|\bNSFileSystemSize\b"
        r"|\bstatfs\(|\bstatvfs\("
    ),
    "NSPrivacyAccessedAPICategoryActiveKeyboards": r"activeInputModes",
}


def code_lines(path: Path):
    """The lines of a Swift file with comments taken out, so a mention in a note doesn't count."""
    for number, line in enumerate(path.read_text(encoding="utf-8", errors="replace").splitlines(), 1):
        line = re.sub(r"//.*$", "", line)
        if line.strip():
            yield number, line


def main(root: Path) -> int:
    manifest = root / "App" / "PrivacyInfo.xcprivacy"
    if not manifest.is_file():
        print(f"Missing {manifest.relative_to(root)}.")
        return 1
    try:
        declared = plistlib.loads(manifest.read_bytes())
    except Exception as error:  # a plist that doesn't parse is a plist Xcode won't use
        print(f"{manifest.relative_to(root)} can't be read: {error}")
        return 1

    reasons = {
        item.get("NSPrivacyAccessedAPIType"): item.get("NSPrivacyAccessedAPITypeReasons") or []
        for item in declared.get("NSPrivacyAccessedAPITypes", [])
    }
    problems = []
    for folder in ("App", "Sources"):
        for path in sorted((root / folder).rglob("*.swift")):
            for number, line in code_lines(path):
                for category, pattern in CATEGORIES.items():
                    if re.search(pattern, line) and not reasons.get(category):
                        problems.append((category, f"{path.relative_to(root)}:{number}: {line.strip()}"))

    if declared.get("NSPrivacyTracking") is not False:
        problems.append(("NSPrivacyTracking", "NSPrivacyTracking should be false. Lamplight doesn't track."))

    if problems:
        print("The privacy manifest (App/PrivacyInfo.xcprivacy) is missing something the code uses:")
        for category, where in problems:
            print(f"  {category}\n    {where}")
        return 1
    print("Privacy manifest covers: " + (", ".join(sorted(reasons)) or "nothing"))
    return 0


if __name__ == "__main__":
    sys.exit(main(Path(sys.argv[1]) if len(sys.argv) > 1 else Path(__file__).resolve().parent.parent))
