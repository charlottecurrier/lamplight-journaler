#!/usr/bin/env python3
"""Prints the ID of a simulator to run tests on.

    python3 tools/pick_simulator.py iPad
    python3 tools/pick_simulator.py iPhone
    python3 tools/pick_simulator.py Duo

"iPhone" never picks the folding iPhone Duo, which has a layout of its own: ask for "Duo" to get it.

Of the simulators that fit, the newest system that is not newer than the installed Xcode's own is used. A simulator
with a newer system than Xcode was made for may not start. If none is that old, the oldest is used.
The list of simulators is read from `xcrun simctl`, or from a file given as the second argument, for trying it out.
"""
import json
import re
import subprocess
import sys


def version(text):
    """(27, 1) from "com.apple.CoreSimulator.SimRuntime.iOS-27-1" or from "27.1"."""
    found = re.search(r"(\d+)[-.](\d+)(?:[-.](\d+))?\s*$", text)
    return tuple(int(part) for part in found.groups(default="0")) if found else (0, 0, 0)


def fits(name, kind):
    is_duo = "Duo" in name
    if kind == "Duo":
        return is_duo
    return name.startswith(kind) and not is_duo


def pick(runtimes, kind, newest_allowed):
    """`runtimes` is simctl's map of runtime name to devices. Returns (udid, name, runtime) or None."""
    choices = []
    for runtime, devices in runtimes.items():
        if "iOS" not in runtime:
            continue
        for device in devices:
            if device.get("isAvailable", True) and fits(device.get("name", ""), kind):
                choices.append((version(runtime), device["name"], device["udid"], runtime))
    if not choices:
        return None
    # Sorted by system, then by name, so the same model is picked on every run.
    choices.sort()
    allowed = [choice for choice in choices if newest_allowed is None or choice[0] <= newest_allowed]
    chosen = allowed[-1] if allowed else choices[0]
    return chosen[2], chosen[1], chosen[3]


def xcode_sdk():
    try:
        text = subprocess.run(
            ["xcodebuild", "-version", "-sdk", "iphonesimulator", "SDKVersion"],
            capture_output=True, text=True, check=True,
        ).stdout.strip()
    except (OSError, subprocess.CalledProcessError):
        return None
    return version(text) if text else None


def main():
    if len(sys.argv) not in (2, 3) or sys.argv[1] not in ("iPad", "iPhone", "Duo"):
        sys.exit("usage: pick_simulator.py iPad|iPhone|Duo [simctl-list.json]")
    kind = sys.argv[1]
    if len(sys.argv) == 3:
        listing = json.load(open(sys.argv[2]))
        newest = None
    else:
        raw = subprocess.run(
            ["xcrun", "simctl", "list", "devices", "available", "-j"], capture_output=True, text=True, check=True
        ).stdout
        listing = json.loads(raw)
        newest = xcode_sdk()
    found = pick(listing.get("devices", {}), kind, newest)
    if not found:
        sys.exit(f"No {kind} simulator found")
    udid, name, runtime = found
    print(f"{name} on {runtime.split('.')[-1]}", file=sys.stderr)
    print(udid)


if __name__ == "__main__":
    main()
