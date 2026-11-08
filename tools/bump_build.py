#!/usr/bin/env python3
"""Raises the build number by one, or sets it to the number you give.

TestFlight and the App Store refuse an upload whose build number is not higher than every earlier upload of the same
version. The number is in two places that have to agree: project.yml, and the generated Xcode project. This changes
both, so you don't need XcodeGen.

    python3 tools/bump_build.py          # 3 becomes 4
    python3 tools/bump_build.py 10       # sets it to 10
"""
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
YML = ROOT / "project.yml"
PBX = ROOT / "Lamplight.xcodeproj" / "project.pbxproj"


def main(argv) -> int:
    yml = YML.read_text(encoding="utf-8")
    pbx = PBX.read_text(encoding="utf-8")

    in_yml = re.findall(r'^(\s*CURRENT_PROJECT_VERSION:\s*)"(\d+)"', yml, flags=re.M)
    in_pbx = re.findall(r"CURRENT_PROJECT_VERSION = (\d+);", pbx)
    if len(in_yml) != 1 or not in_pbx:
        print("Couldn't find the build number in project.yml and the Xcode project.")
        return 1
    current = in_yml[0][1]
    if set(in_pbx) != {current}:
        print(f"The build number is {current} in project.yml but {sorted(set(in_pbx))} in the Xcode project. "
              "Run xcodegen first so they agree.")
        return 1

    if len(argv) > 1:
        if not argv[1].isdigit() or int(argv[1]) < 1:
            print("The build number has to be a whole number, 1 or more.")
            return 1
        new = str(int(argv[1]))
    else:
        new = str(int(current) + 1)

    yml = re.sub(r'^(\s*CURRENT_PROJECT_VERSION:\s*)"\d+"', lambda m: f'{m.group(1)}"{new}"', yml, flags=re.M)
    pbx = re.sub(r"CURRENT_PROJECT_VERSION = \d+;", f"CURRENT_PROJECT_VERSION = {new};", pbx)
    YML.write_text(yml, encoding="utf-8")
    PBX.write_text(pbx, encoding="utf-8")
    print(f"Build number {current} -> {new}")
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv))
