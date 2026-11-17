# Lamplight

An iPad-first (also iPhone) SwiftUI journal. Entries are Markdown files in a folder the person picks in iCloud Drive. Read `README.md` for the product and `docs/DECISIONS.md` for why things are the way they are.

## Layout

- `Sources/JournalCore/` has all logic that doesn't need a screen: file format, storage, streaks, On This Day, templates. Plain Swift, builds and tests on Linux.
- `App/` is the SwiftUI app. `App/Support` is the model and platform code. `App/Editor` is the UITextView editor (styling, format bar). `App/Views` is the screens. `App/Theme` is colors and paper styling.
- Core and App are compiled into **one module** (the app target), so Core code needs no `public` and App code needs no `import JournalCore`. `Package.swift` exists only so Core can be tested without Xcode.
- `Tests/JournalCoreTests` runs everywhere. `Tests/EditorTests` and `Tests/AppTests` need UIKit and run only in Xcode and in the Mac job. EditorTests type into the real editor in a simulator, which is how editor bugs get reproduced without a device. AppTests check the photo picker. `DayPhotoPickerTests` run it over a `FakeListing` (the picker reads its photos through `PhotoListing`), so the day layout is checked on every run. `PhotoLibraryTests` put photos with known dates into the simulator's real Photos library, and they **skip in the Mac job**: the simulator shows the Photos permission as granted, but the test app still reads it as not decided (tried: grant before and after install, ad hoc signing), so don't count them as run there. They run in Xcode once the app has been allowed to read Photos. `QuietScreenPictureTests` take pictures of the loading screen and the empty pages, which tapping can't reach, and the Mac job keeps them in the `screens` artifact under `Pages`: look at them when one of those screens changes. `NewEntryNavigationTests` host the real `MainView` in a phone's layout and an iPad's and start an entry with the `.lamplightNewEntry` notification (the same action as the New Entry buttons), because a unit test can't tap a SwiftUI button.
- `Tests/UITests` is a separate target, `LamplightUITests`, with its own scheme. It starts the whole app in a simulator and taps it (XCUITest), on a phone and an iPad, and saves a picture of the screen at each step. It runs only in Xcode and the Mac job. The app is started with launch arguments that set its preferences for that run (`-storage.mode local`, `-prefs.onboardingComplete YES`, and so on), so it needs no test code inside the app. Entries pile up across tests, so don't count them.
- `Lamplight.xcodeproj` is generated from `project.yml` by XcodeGen and committed. After adding or removing Swift files, regenerate it (see below).

## Commands

```
swift test                                   # Core tests (needs a Swift toolchain)
LAMPLIGHT_SAMPLE_DIR=<dir> swift test --filter SampleFolderTests   # checks tools/make_sample_journal.py output
xcodegen                                     # regenerate Lamplight.xcodeproj (set USER=anyname on Linux)
tools/typecheck_support.sh                   # type-checks App/Support (model, storage) against iOS stand-ins on Linux
python3 tools/check_palette.py               # contrast checks, writes docs/palette-preview.png
python3 tools/check_privacy_manifest.py      # fails if the code uses an API Apple wants a reason for that App/PrivacyInfo.xcprivacy doesn't list
python3 tools/bump_build.py                  # raises the build number (project.yml and the Xcode project) before a TestFlight upload
python3 tools/make_assets.py                 # redraws the first texture, icon and color sets
python3 tools/make_textures.py --preview <dir>   # contact sheets of every texture; --write redraws their tiles
python3 tools/make_sample_journal.py <dir>   # sample data for trying the app
python3 tools/dayone_inspect.py <export>     # counts what a Day One export holds (zip, folder or .json). Never prints text
```

On Linux, a Swift toolchain can be downloaded from `download.swift.org` (Ubuntu 24.04, Swift 6.1.x worked) and XcodeGen can be built from its GitHub source with `swift build -c release --product xcodegen`.

## What can and can't be verified without a Mac

- Verified in CI-less environments: everything in `Sources/JournalCore` (274 tests, including the Markdown engine, every editing rule and the picture-line rules), the model and storage code in `App/Support` (type-checked against stand-ins by `tools/typecheck_support.sh`), the Python tools, the project structure. `ImageTools`, `PlaceSearcher`, `AppPrefs` and `Theme` are read-checked only.
- **Not compilable on Linux:** all SwiftUI/UIKit code in `App/`. Review it by reading. Check every call against the declarations in Core and `AppModel` before assuming it compiles.

## CI

GitHub Actions runs two workflows on pull requests. After a push, look at the PR's checks before saying the work is done. The repository is public, so its history, PRs, logs and test pictures can be read by anyone: never commit a secret or real journal text.

- `.github/workflows/core.yml` (Linux, every PR and every push to `main`): `swift test` with the sample journal, `tools/typecheck_support.sh`, `tools/check_palette.py`, `tools/check_privacy_manifest.py`, and a syntax check of the Python tools.
- `.github/workflows/app.yml` (macOS, only PRs that change `App/`, `Sources/`, `Tests/`, `project.yml`, the Xcode project or `Package.swift`): builds the app and runs the tests in the iPad simulator. This is the only place the SwiftUI and UIKit code in `App/` is compiled outside Xcode, so it can find errors the Linux harness can't. A last step runs `NewEntryNavigationTests` again on an iPhone simulator, so the phone's layout is a real phone's. Then the UI tests run on a phone and an iPad simulator, and their pictures are kept as the `screens` artifact of the run for 14 days. Look at them when a screen changes. Mac minutes are free while the repo is public. If it goes private again they count ten times, and the trigger should come out. A run's pictures and screen recordings can be downloaded and looked at: on a failure, look at them before guessing.

- `.github/workflows/testflight.yml` (macOS, only when started by hand): archives the app, signs it with an App Store Connect API key kept in repository secrets, and uploads it to TestFlight. The build number is the UTC date and time, passed on the command line, so nothing is committed. Setup is in `docs/TESTFLIGHT.md`. Don't give it a trigger.

## Rules that matter

- **Review screen changes before calling a PR ready.** A PR that changes `App/Views`, `App/Editor` or navigation gets an independent review (the `code-review` skill) before the person is told it is ready. Fix what is real, and say in the PR what was found and what was left. CI passing is not enough: it doesn't tap through the screens.

- **A page is brought to the front by `MainView.open`.** On a phone it shows the page first and chooses the entry one turn later. Setting `selectedEntryID` and `compactColumn` together made every new entry after the first close at once: the editor was built and taken away, and the unwritten entry went with it. Don't set the two together for a phone. `NewEntryNavigationTests` covers it, and prints `NavTrace`'s step log when one fails.

- **Never lose the person's writing.** Entries autosave, deletes go to Recently Deleted, removed photos are kept, switching folders copies and never overwrites, conflicting edits keep both versions. Don't add a code path that discards text.
- **A read or listing that failed is not an empty one.** `CoordinatedFileAccess` gives up on reads and listings after a time (`BoundedWait`) instead of waiting on iCloud for ever, so they can fail, and after a few in a row it stops starting new ones for a while. `LibraryLocator.resolveRoot` and `Library.prepare` throw when they can't list a folder. They never guess a folder, and never write a first journal over one that couldn't be read. Don't write a default over something you failed to read. Writes are never given up on.
- **One file per entry/journal/template.** Don't add shared files that two devices will both rewrite. `settings.json` is the single exception and is tiny.
- **File access goes through `FileAccess`.** The app uses `CoordinatedFileAccess` (NSFileCoordinator, needed for iCloud Drive). Tests use `PlainFileAccess`. Never call `FileManager` directly on journal files from the app.
- **Colors only from `Palette.swift`**, as `Pair(light:dark:)` lines in that exact shape (the Python tools parse them). The person reads through amber blue-blocking lenses. Differences must be in brightness, not hue. No blues or purples. Re-run `tools/check_palette.py` after any change.
- **Swift 5 language mode, iOS 17 minimum.** Use `@MainActor in` on `Task` created in views.
- **Plain, quiet UI copy.** Short sentences. No exclamation marks, no cheering, no prompts or suggestions for what to write. The person asked for no AI, reminders or suggested prompts.
- **Editing rules live in Core, not in the editor.** `MarkdownEngine` (line and inline analysis), `MarkdownEditing` (Return, Space, Backspace, Tab, format commands), `SlashCommand` and `EditorText` are pure Swift on UTF-16 offsets and are unit tested. `App/Editor` only applies their `TextEdit`s to the `UITextView`. Add a test in Core before changing a rule.
- **A photo in the text is a line of its own: `![](photos/NAME.jpg)`.** `MediaLine` (Core) keeps it that way. `MarkdownEditing.intercept` and `Coordinator.apply` send every edit through `MediaLine.repaired`, and `Coordinator.changed` runs `MediaLine.separated` after each change. The editor hides that line's text and draws the photo in its place (`RuleLayoutManager`). Don't add an edit path that skips them. The header's `photos` list stays the registry of an entry's photos, so a photo not named in the text still shows above it.
- **The editor makes some edits itself.** Return, Backspace, Tab and format commands go through `Coordinator.apply`, in place of the text view's own typing, so the text view doesn't scroll to them. `keepCaretInView` does that after each one, and `MarkdownUITextView.caretRect` trims the caret to the text, because a heading or section title has space above it that the text view counts as part of the line. Don't add an edit path that skips either. `EditorCaretTests` covers both. Moving the caret restyles only the lines it leaves and enters (`MarkdownStyler.restyle(lines:)`), never the whole text: styling all of the text again throws away the text view's layout and moves the page by itself. `EditorNavigationTests` covers that.
- **A video is a photo with a link.** A video stays in the Photos library. Its still frame is saved as an ordinary photo, on a `![](photos/NAME.jpg)` line like any other, and `PhotoRef.video` (a `VideoLink`) says where the video is. So everything that handles photos handles a video's frame, and only drawing the play mark (`RuleLayoutManager`), the viewer (`LinkedVideoPage`) and `VideoLibrary` know about video. Don't copy video files into the journal folder without asking. PhotoKit code can't be run in CI: the simulator has no iCloud Photos, so say plainly that it is untested until it has been tried on a device.
- **The photo picker needs Photos access, and must work without it.** `DayPhotoPicker` lists photos by day from the library, so it needs `NSPhotoLibraryUsageDescription` and the person's permission. With no access, or limited access, it must still offer the system's `PhotosPicker`, which needs none. Which photos belong to a day is `PhotoDays` and `PhotoDayGrouper` in Core, tested on Linux. Don't read the library on launch: it is read only when the sheet is open.
- **The privacy manifest lists what the app uses.** `App/PrivacyInfo.xcprivacy` gives Apple a reason for each "required reason" API: UserDefaults, file dates, time since boot, free disk space, active keyboards. Using a new one without adding its reason gets an upload flagged. `tools/check_privacy_manifest.py` catches it in CI, but it can't pick the reason. Lamplight collects nothing and doesn't track, and the manifest says so. Sharing steps are in `docs/TESTFLIGHT.md`.
- **Editor text is not file text.** The editor shows `•`, `☐` and `☑` for list markers. `EditorText.fromMarkdown` and `toMarkdown` convert at the load and save boundary. Never write editor text to disk or read file text into the editor without converting.
- The `EntryFile` header values are JSON. Splitting text on `"\n"` must be done on bytes (Swift treats `\r\n` as one character).
