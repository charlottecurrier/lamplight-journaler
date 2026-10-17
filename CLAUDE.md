# Lamplight

An iPad-first (also iPhone) SwiftUI journal. Entries are Markdown files in a folder the person picks in iCloud Drive. Read `README.md` for the product and `docs/DECISIONS.md` for why things are the way they are.

## Layout

- `Sources/JournalCore/` has all logic that doesn't need a screen: file format, storage, streaks, On This Day, templates. Plain Swift, builds and tests on Linux.
- `App/` is the SwiftUI app. `App/Support` is the model and platform code. `App/Views` is the screens. `App/Theme` is colors and paper styling.
- Core and App are compiled into **one module** (the app target), so Core code needs no `public` and App code needs no `import JournalCore`. `Package.swift` exists only so Core can be tested without Xcode.
- `Lamplight.xcodeproj` is generated from `project.yml` by XcodeGen and committed. After adding or removing Swift files, regenerate it (see below).

## Commands

```
swift test                                   # Core tests (needs a Swift toolchain)
LAMPLIGHT_SAMPLE_DIR=<dir> swift test --filter SampleFolderTests   # checks tools/make_sample_journal.py output
xcodegen                                     # regenerate Lamplight.xcodeproj (set USER=anyname on Linux)
python3 tools/check_palette.py               # contrast checks, writes docs/palette-preview.png
python3 tools/make_assets.py                 # redraws textures, icon and color sets
python3 tools/make_sample_journal.py <dir>   # sample data for trying the app
```

On Linux, a Swift toolchain can be downloaded from `download.swift.org` (Ubuntu 24.04, Swift 6.1.x worked) and XcodeGen can be built from its GitHub source with `swift build -c release --product xcodegen`.

## What can and can't be verified without a Mac

- Verified in CI-less environments: everything in `Sources/JournalCore` (64 tests), `App/Support/Formatting.swift` (it only needs Foundation), the Python tools, the project structure.
- **Not compilable on Linux:** all SwiftUI/UIKit code in `App/`. Review it by reading. Check every call against the declarations in Core and `AppModel` before assuming it compiles.

## Rules that matter

- **Never lose the person's writing.** Entries autosave, deletes go to Recently Deleted, removed photos are kept, switching folders copies and never overwrites, conflicting edits keep both versions. Don't add a code path that discards text.
- **One file per entry/journal/template.** Don't add shared files that two devices will both rewrite. `settings.json` is the single exception and is tiny.
- **File access goes through `FileAccess`.** The app uses `CoordinatedFileAccess` (NSFileCoordinator, needed for iCloud Drive). Tests use `PlainFileAccess`. Never call `FileManager` directly on journal files from the app.
- **Colors only from `Palette.swift`**, as `Pair(light:dark:)` lines in that exact shape (the Python tools parse them). The person reads through amber blue-blocking lenses. Differences must be in brightness, not hue. No blues or purples. Re-run `tools/check_palette.py` after any change.
- **Swift 5 language mode, iOS 17 minimum.** Use `@MainActor in` on `Task` created in views.
- **Plain, quiet UI copy.** Short sentences. No exclamation marks, no cheering, no prompts or suggestions for what to write. The person asked for no AI, reminders or suggested prompts.
- The `EntryFile` header values are JSON. Splitting text on `"\n"` must be done on bytes (Swift treats `\r\n` as one character).
