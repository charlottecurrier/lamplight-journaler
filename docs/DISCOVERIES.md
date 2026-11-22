# Discoveries

Things learned while working on Lamplight that the code doesn't say. Read the part that matches what you are about to
change. Add to it when you learn something that would have saved you time.

Each finding says how it was checked:

- **Verified in CI** means a run in the Mac job showed it. The run is named.
- **From a web page** means someone's page said so, and the link is given. Third-party pages are marked.
- **Unverified** means a guess or a figure that disagrees between sources. Replace it when you can check.

Dates are when the finding was made. Today's date when this was written: 2026-11-20.

## The iPhone Duo

Apple's first foldable. Announced 9 September 2026, shipping from October on iOS 27.1.

**What it is** (web pages and Apple's developer page):

- Two displays. The outer one is 5.4 inch and is compact width in portrait, like any iPhone. The inner one is 7.6 inch and
  is regular width and regular height, like an iPad. ([Apple's spec page](https://www.apple.com/ie/iphone-duo/specs/),
  [devclass](https://devclass.com/devops/2026/09/16/apple-iphone-duo-makes-developers-think-in-folds/5296425))
- It has Touch ID, not Face ID. ([spec summary](https://www.91mobiles.com/apple-iphone-duo-price-in-india?ty=specs))
- **Apple's page, "Preparing your app for iPhone Duo"**
  ([developer.apple.com](https://developer.apple.com/documentation/technologyoverviews/preparing-your-app-for-iphone-duo)),
  read 2026-11-20. It says:
  - Size views relative to their container, not to fixed iPhone sizes. Track `horizontalSizeClass` and
    `verticalSizeClass`. Don't use `userInterfaceIdiom` or the interface orientation for layout.
  - Content moves between the displays as the device opens, closes, partly folds and rotates.
  - Check every view, sheet and popover in each pose. Look for controls hidden in the fold.
  - **Navigation bars, toolbars and tab bars can appear vertically along the side**, on the outer display when closed and on
    some inner-display views when open. In a split view the sidebar and content bars stay horizontal and the detail view's
    bars go vertical. Use `.toolbar` on `NavigationStack` or `NavigationSplitView`, not custom bars. Give toolbar items an
    icon and a title. Put Back or Close first and Done in the pinned trailing group.
  - Reserved regions: the fold (a "division", active when partly open) and the camera (an "occlusion"). In SwiftUI, read
    `GeometryProxy.reservedRegions`.
  - Build with the latest Xcode to use the whole screen. With Xcode 26 or earlier the app doesn't extend under the status
    bar and camera. The page gives no deadline and doesn't mention an iOS 17 minimum.
  - `ArrangementView` splits space between two views for the pose. It says to "evaluate whether" it helps, so it is
    optional, and not to put one inside a split view, list or scroll view.
- A third-party article says builds must use the Xcode 27 SDK by April 2027
  ([hackernoon](https://hackernoon.com/stop-ignoring-the-crease-ship-your-ios-app-for-iphone-duo-before-the-april-2027-deadline)).
  **Unverified.** Apple's page names no date.

**What the Duo simulator showed** (verified in CI, 2026-11-20, `Duo` workflow on PR #38, Xcode 27.1, iOS 27.2 runtime):

- The simulator starts on the **outer display**. The app's window is **466 x 678 points**, which matches the blog figure
  for the outer display. The test runner's `UIScreen` said 386 x 678.
- The app's own content is laid out about **382 to 386 points wide**. The rest, on the right (from about x = 394), is a
  vertical strip where the system put the toolbar buttons: Back (399, 179), Settings (402, 240) and Search (399, 611). This
  is the vertical toolbar Apple's page describes. The strip is about 72 points wide.
- Lamplight's own bottom bar (`CompactBar`, a custom bar) sits inside the 386 points: Journal at x 6, Today 80, New Entry 164,
  Calendar 228, More 302, each 74 wide and 48 tall. **No button stuck out past the window.** It is not a system tab bar, so
  it doesn't move to the side.
- The list screen showed no clipping. The editor page's and the sideways page's facts were saved as text and pictures in the
  `duo-screens` artifact but were not printed in the log. Read them there.
- All 6 UI tests passed on the Duo, including the second-new-entry test. The first run crashed while the test runner
  started, because the simulator had only just been asked to boot. Booting it first with `xcrun simctl bootstatus -b`,
  then waiting 20 seconds, fixed it. A fresh boot on the runner printed "Data Migration Failed" and still worked. The UI test
  step took about 19 minutes, so expect a Duo run to take close to half an hour.

**Not known yet:**

- **How to unfold the simulator from a script.** Apple's page only says to test in the simulator. The Simulator window has
  open, close, rotate and fold buttons. A [forum thread](https://developer.apple.com/forums/thread/847883) asks for a
  command-line or UI-test way and has no answer. `xcrun simctl help` lists nothing for posture. So CI can only see the
  outer display. For the inner display, use a size class override in a hosted test (as `NewEntryNavigationTests` do) and
  look at it by hand on a device or in Xcode's simulator.
- The inner display's point size. Blogs say 626 x 890, corrected to 669 x 951. Unverified.

**What the CI runner has** (verified in CI, 2026-11-20, probe PR #37, since closed):

- Label `xcode-27` (also `xcode-27-xlarge`). Apple silicon only. macOS 27.0.1.
- Xcode 27.0, 27.1 (the default) and 27.2 are installed. iOS 27.0, 27.1 and 27.2 simulators are installed.
- An **iPhone Duo** simulator exists on iOS 27.1 and on 27.2.
- The existing `macos-26` label has Xcode 26.6, which is what `app.yml` builds with.

**What it means for Lamplight** (reading the code and the run, **unverified on a device**):

- The app builds with Xcode 27.1 and runs on the Duo simulator. That is verified.
- Few places read the size class (`MainView`, `EntryList`), and most fixed sizes are small controls. The screens already
  adapt, so most of the work is checking, not rewriting.
- The lock's text now names what the device has. `Settings.swift` had "Face ID" in fixed text in two places. They use
  `LockManager.methodName` and `biometryName` now, and with neither Face ID nor Touch ID the "if it doesn't work"
  sentence is left out. Checked by reading and by the Mac build. **Not seen on a Duo.**
- The editor page's toolbar has many buttons (photo, place, format, Done). On the outer display the detail view's toolbar
  goes vertical, in a strip about 72 points wide and 678 high. Check that all of them fit and that Done is last in the
  trailing group. This is the first thing to look at in the artifact's page pictures.
- Folding or unfolding changes the size class while the app runs, and the split view collapses or opens. The phone bug
  below was exactly this kind of change: a page torn down for a moment cost the new, empty entry.
  `NewEntryNavigationTests.testFoldingAndUnfoldingKeepsThePageBeingWritten` types into a new entry in the wide layout,
  then switches the size class narrow, wide and narrow. The page stayed open and the words stayed on it and in the
  journal (passed in the Mac job on Xcode 27.1, 2026-11-22, two runs). It is a size class override in a hosted view, not
  a real fold, and it doesn't check the caret.
- At about 630 to 670 points wide, the three-column split view (sidebar 230 to 320, list from 340) leaves little for the
  page. Look at the pictures before changing widths.
- Apple prefers system tab bars and toolbars to custom bars. Moving `CompactBar` to a `TabView` would let it follow the
  device to the side. That is a navigation change, so it needs its own tests and review.

**Why it looked like a phone app on a real Duo** (2026-11-22): the TestFlight workflow still built with Xcode 26.6 on
the `macos-26` runner. The Duo work up to then had only added tests and notes. On the device, the open inner screen
showed Lamplight in a small phone-sized window with a zoom button, with the phone's bottom bar. `testflight.yml` and
`app.yml` now run on `xcode-27`. **Unverified on a device** until a new TestFlight build is installed.

**The UI tests on the `xcode-27` runner** (2026-11-22): three Mac runs in a row went wrong in the UI tests, each a
different way, and no check of ours failed. On the iPad, "Failed to terminate com.forageandjump.lamplight". On the iPad,
a hang starting a test until the job ran out of time. On the phone, `testASecondEntryStaysOpen` sat for minutes looking
for the Done button. That run's spindump (in the `screens` artifact) shows the app's main thread idle in its run loop,
so the app was not hung: the test tools were. The runner is a 3-core, 7 GB machine, and `app.yml` left the unit tests'
simulator running while the UI tests used another. The Duo job runs one simulator and passed three times out of
three. So `app.yml` now shuts down every simulator before each run (`xcrun simctl shutdown all`), and each UI test has
a five-minute limit so a hang fails one test and keeps the pictures. **That guess was wrong, or not enough.** The next run, with one simulator at a time, went wrong
again: on the iPad the UI test stalled tapping the page of its first entry, and a hosted test
(`testASecondEntryStaysOpenInTheIPadsLayout`, "The first entry wasn't finished") failed in a run whose tests took 781
seconds where they had taken about 460. The spindump again shows the app idle, and the saved screen shows the page open
with the keyboard up. Two things the passing Duo job does that `app.yml` didn't: it starts the simulator and waits for
it (`simctl bootstatus -b`, then 20 seconds) before testing, and its simulator is on iOS 27.1 or 27.2, not 27.0.
`app.yml` now does the first, and `pick_simulator.py` now prefers Xcode's own system, then the nearest newer one, so
the phone and iPad run on 27.2. **Also guesses.** If the runs still go wrong, the next thing to try is a job of their
own for the UI tests.

**Status:** pictures of the Duo run are in the `duo-screens` artifact of the run (14 days). `ScreenFactsTests` now skip
on every simulator but the Duo. Next: read the editor page facts, look at the open Duo on the device after a TestFlight
build, then decide about the bottom bar and the layout.

## The phone's second new entry closed at once (fixed)

**Symptom:** on an iPhone, the first new entry after a restart worked. Every one after that opened, flashed "Choose an
entry", and dropped back to the list. After Done or after swiping back, the same. Not on iPad.

**Cause** (verified in CI, PR #26): setting `selectedEntryID` and `compactColumn` together made the phone's navigation
remove the new page straight after it opened. The editor's `onDisappear` then called `finishEditing`, which drops an
unwritten entry. The page found no entry and its placeholder closed it.

**What was tried**, each in its own test on the phone layout:

| Way of showing the page | Result |
| --- | --- |
| selection, then column (the old code) | fails |
| selection only | fails |
| column, then selection | fails |
| selection, then column a turn later | fails |
| **column now, selection a turn later** | **passes** |

That last one is `MainView.open`. The rule is in `CLAUDE.md`.

**Tried and did not help:**

- Waiting 120 ms before `finishEditing`, in case the editor was only rebuilt. It was not rebuilt, so the entry was lost
  anyway. Reverted.
- A guard in `onClose` so a late close from an old page couldn't close a new one. SwiftUI updates the detail view in
  place with the newest closure, so the guard would have passed the late close. Never shipped.

**How it was found:**

- `NewEntryNavigationTests` host the real `MainView` in a phone layout (size class override, and the Mac job also runs
  them on a real iPhone simulator) and start entries with `.lamplightNewEntry` and finish them with
  `.lamplightFinishEntry`.
- `NavTrace` records each step (begin, selection, column, editor appeared and went away, finish) and the failing tests
  print it. The trace showed the editor going away with no navigation event before it.
- In a test, wait with `Task.sleep`, not by spinning the run loop. Spinning stops the model's own tasks from running, and
  the journal never finished opening.
- A unit test can't tap a SwiftUI button. Use a notification that runs the same action, or the UI tests.

## The editor

These are in the `CLAUDE.md` rules. Here is why:

- Edits made through `Coordinator.apply` skip UIKit's own scroll to the caret, so `keepCaretInView` does it.
- The text view's caret rectangle includes the space before and after a paragraph, so the caret hung above headings and
  section titles. `MarkdownUITextView.caretRect` trims it.
- Setting `UITextView.typingAttributes` scrolls the page away and back a moment later. The typing style is now set when
  something is typed, and only when it changed.
- Restyling all the text on each caret move throws away the layout and moves the page. Only the lines the caret leaves and
  enters are restyled.
- `scrollRectToVisible` is clamped by a content size that lags, so the offset is worked out by hand.

## iCloud and files

- `NSFileCoordinator` reads can wait on iCloud for ever. `BoundedWait` stops waiting after a time, and after three
  failures in a row it pauses new reads for 20 seconds. A read that failed is not an empty one: never write a default
  over something that could not be read.

## Photos

- The picker lists photos by day. Which photos belong to a day is `PhotoDays` and `PhotoDayGrouper` in Core, tested on
  Linux. The model reads through `PhotoListing`, so tests use a fake list.
- **The real-library tests cannot run in the Mac job.** The simulator shows the Photos permission as granted (the
  `kTCCServicePhotos` row is there) but the test app still reads "not decided". Tried: granting before and after the
  install, and ad hoc signing. `PhotoLibraryTests` skip there. They run in Xcode once the app has been allowed to read
  Photos.
- PhotoKit video code can't be run in CI: the simulator has no iCloud Photos. Say it is untested until tried on a device.

## CI and the repository

- A skipped test looks like a pass. The Mac job prints the skipped count. `-quiet` hides failure text, so the job reads
  the `.xcresult` with `xcresulttool` to print failures and totals.
- Mac minutes were ten times as costly while the repository was private, and are free while it is public. If it goes
  private again, take the trigger off `app.yml` for anything but code changes.
- The repository was renamed to `lamplight-journaler`. The tools still reach it as `day-one` (checked 2026-11-20), but
  the Claude GitHub App was not installed on it, so PR events did not arrive on their own. Check a PR's state by hand
  until it is installed.
- A new Linux session starts without the Swift toolchain or XcodeGen. Swift 6.1.x for Ubuntu 24.04 comes from
  download.swift.org, and XcodeGen builds from its GitHub source with `swift build -c release --product xcodegen`. The
  scratchpad can be cleared between sessions, so don't count on it.
- When XcodeGen isn't available, a new Swift file can be added to `Lamplight.xcodeproj` by hand (a file reference, a
  build file, the group entry and the sources phase), but the next real `xcodegen` run will give it new IDs. This was done
  for `ScreenFactsTests.swift`. Regenerate when you can.
- The UI tests start the whole app with launch arguments, which UserDefaults reads as preferences (`-storage.mode local`
  and so on), so the app needs no test code. Their pictures and the screen tree are kept as artifacts for 14 days.
- You can't look at an artifact's pictures from the agent tools. Read the text instead: the tests print sizes and the
  screen tree. The person can open the pictures from the run's page.

## Apple developer program and TestFlight

Steps are in `docs/TESTFLIGHT.md`. What was checked:

- From Apple's pages: $99 a year. An individual enrolls with a legal name on the Apple Account. Up to 10,000 external
  testers. External testing needs Beta App Review for the first build and a beta description and feedback email. A build
  lasts 90 days.
- **Unverified:** that a build installed from Xcode lasts a year on the paid membership. Apple's pages don't say.
- **Unverified:** the privacy manifest's reason codes (`CA92.1`, `C617.1`, `3B52.1`). Apple's upload email will say if
  one is wrong.
- The team is set in `project.yml` as `DEVELOPMENT_TEAM`, not in Xcode, because regenerating the project overwrites
  Xcode's choice.
