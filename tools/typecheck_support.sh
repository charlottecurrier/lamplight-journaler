#!/usr/bin/env bash
# Type-checks the model and storage code in App/Support against stand-ins for UIKit, SwiftUI and friends,
# so mistakes show up without Xcode. It cannot check the screens in App/Views.
#
#     tools/typecheck_support.sh            # needs `swiftc` on PATH (a Linux or macOS Swift toolchain)
set -euo pipefail

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# A Swift file that isn't in the Xcode project breaks the Xcode build but not `swift test`. Catch that here.
missing=0
for file in "$ROOT"/App/*.swift "$ROOT"/App/*/*.swift "$ROOT"/Sources/JournalCore/*.swift "$ROOT"/Tests/JournalCoreTests/*.swift "$ROOT"/Tests/EditorTests/*.swift; do
  name="$(basename "$file")"
  if ! grep -q "$name in Sources" "$ROOT/Lamplight.xcodeproj/project.pbxproj"; then
    echo "Not in Lamplight.xcodeproj: $name. Run xcodegen."
    missing=1
  fi
done
[ "$missing" -eq 0 ] || exit 1

cp "$ROOT"/Sources/JournalCore/*.swift "$WORK"/
for name in AppModel StorageLocation CoordinatedFileAccess LockManager Formatting IO; do
  # SwiftUI and UIKit imports become Foundation. The rest is stood in for by tools/typecheck_stubs.swift.
  {
    echo "import Observation" # SwiftUI normally brings this in
    sed -E -e 's/^import (SwiftUI|UIKit|LocalAuthentication|MapKit)$/import Foundation/' \
           -e 's/#selector\(UIResponder\.resignFirstResponder\)/"resignFirstResponder"/' \
           "$ROOT/App/Support/$name.swift"
  } > "$WORK/$name.swift"
done
cp "$ROOT/tools/typecheck_stubs.swift" "$WORK/stubs.swift"

echo "Type-checking (Swift 5 mode)…"
swiftc -typecheck -swift-version 5 "$WORK"/*.swift
echo "OK"
