# Lamplight

A calm journal for writing at the end of the day. Made for iPad first, works on iPhone too.

- **Private.** Locks with Face ID, falls back to your device passcode. Hides itself in the app switcher.
- **Yours.** Entries are plain Markdown files and photos in a folder you pick in iCloud Drive. No account, no server.
- **Quiet.** A warm, dark "lamp" theme with paper grain, tuned for reading through amber blue-blocking lenses. No notifications, no prompts, no AI.

## What it does

- Timeline of entries with photo thumbnails, grouped by month. Search. Tap the text of an entry to edit it where you tapped.
- **On This Day.** A strip at the top of the journal, and its own screen.
- **Streak.** Days in a row, longest streak, and the last seven days. A "new day starts at" setting keeps a 12:30 AM entry in yesterday's streak.
- **Opens to a new entry.** If you haven't written yet today, opening the app starts a new page with your templates offered on it. Nothing is saved until you type, so backing out leaves nothing behind. You can turn this off in Settings.
- **Writing.** Markdown shows as you type. `#` and a space makes a heading. `**bold**`, `*italic*`, `~~strike~~`, `==highlight==`, bullets, numbered lists, tappable checklists, quotes, dividers, links and code all work. The symbols hide when your cursor leaves the line. A bar above the keyboard has the same things as buttons, and typing `/` lists commands. Focus mode hides everything but the text.
- **Templates.** A template is a page you write once, in the same editor as an entry: headings, prompts, checklists. A new entry starts with a copy of it. On an empty page your templates are listed (the ones you use most first). Tap one and its page fills in. A journal can have a default template that fills in by itself. When you tap Done, template headings you left empty are removed. Anything you wrote is kept. You can also add a template to an entry you already started. No built-in prompts. You write your own.
- **Calendar.** A month view with a dot on days you wrote.
- **Multiple journals.**
- **Places.** Pick Home, or search for a place. No GPS, no location permission.
- **Photos.** Add several per entry. Tap for full screen, pinch to zoom.
- **Recently Deleted.** Swipe an entry left to delete it. Deleted entries stay for 30 days.

## Open it on your iPad

You need a Mac with Xcode 16 or newer, and your Apple ID. A free Apple account is enough.

1. Open `Lamplight.xcodeproj`.
2. Click the **Lamplight** project, then the **Lamplight** target, then **Signing & Capabilities**.
3. Pick your **Team** (your Apple ID). If Xcode says the bundle identifier is taken, change `com.forageandjump.lamplight` to something unique to you.
4. Plug in your iPad and choose it at the top of Xcode. Press **Run**.
5. First time only: on the iPad turn on **Settings → Privacy & Security → Developer Mode**. After the first install, trust your Apple ID in **Settings → General → VPN & Device Management**.

**Free account catch:** apps installed with a free account stop opening after 7 days. Press Run in Xcode again to renew. Your entries are not affected, because they live in your iCloud Drive folder and not inside the app.

## Try it with sample data

On day one there's nothing to show in On This Day and the streak is empty. To see them working, make a sample journal:

```
python3 tools/make_sample_journal.py ~/Desktop
```

That makes `~/Desktop/Lamplight/` with about 65 made-up entries, photos, two journals and two templates. It includes a 12-day streak that ended yesterday and entries on today's date from 1, 2 and 3 years ago. Copy the `Lamplight` folder into the iCloud Drive folder you chose, then pull down on the list. Delete the sample entries when you're done. It needs Python with Pillow (`pip3 install pillow`).

## Sync between iPad and iPhone

1. On the iPad, at first launch, tap **Choose a Folder**. In the Files app, open iCloud Drive and pick or create a folder, like "Journal".
2. On the iPhone, install the app the same way and choose **the same folder**.
3. iCloud Drive does the syncing. The app re-reads the folder when you open it, and when you pull down on the list.

Tip: in the Files app, press and hold your journal folder and choose **Keep Downloaded**. Then iCloud won't swap photos for online-only stubs when storage runs low. Lamplight does wait for stubs to download, but this is faster.

If you switch folders later (Settings → Storage), your entries are copied into the new folder. The old folder is left as it was.

## What's in your folder

```
Lamplight/
  settings.json
  Journals/<id>.json
  Templates/<id>.json
  Entries/<id>/entry.md
  Entries/<id>/photos/<id>.jpg
  Recently Deleted/<id>/…
```

One file per entry, journal and template, so two devices rarely touch the same file. If they do edit the same entry at once, the newest version stays and the other is kept as a second entry. Nothing is dropped.

An entry looks like this and opens in any text editor, including Obsidian:

```
---
id: "5B0C3C4E-…"
journal: "00000000-0000-4000-8000-000000000001"
created: "2026-10-17T21:14:03.000Z"
modified: "2026-10-17T21:30:41.000Z"
timezone: "America/Los_Angeles"
location: {"home":true,"lat":45.5,"lon":-122.6,"name":"Home"}
photos: [{"file":"7A1F….jpg","h":1600,"id":"7A1F…","w":2400}]
---

## What went well today?

The light in the kitchen.
```

## Project layout

| Path | What's there |
| --- | --- |
| `Sources/JournalCore/` | Logic with no screens: file format, storage, streaks, On This Day, templates. Built and tested on Linux. |
| `Tests/JournalCoreTests/` | 169 tests. Run with `swift test`, or in Xcode with ⌘U. |
| `App/` | The SwiftUI app. |
| `App/Editor/` | The text editor: live Markdown styling, the bar above the keyboard, focus mode. |
| `App/Theme/Palette.swift` | Every color, in one place. |
| `tools/check_palette.py` | Checks contrast and draws `docs/palette-preview.png`, including a look through amber lenses. |
| `tools/make_assets.py` | Draws the paper textures and app icon. |
| `project.yml` | The Xcode project definition (XcodeGen). |

If you add or remove Swift files, regenerate the project: `brew install xcodegen`, then `xcodegen`.

## Honest status

- The core logic (everything in `Sources/JournalCore`) is tested. 169 tests pass.
- **The screens have never been compiled or run.** They were written without Xcode. Expect a few compile errors on the first build. They should be small. Send me the messages and I'll fix them.
- The amber-lens colors were checked with a simulation, not real lenses. If something is hard to read, tell me which screen. Colors are all in `Palette.swift`.

See `docs/DECISIONS.md` for the choices I made on your behalf, and what's left out.
