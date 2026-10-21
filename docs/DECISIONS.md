# Decisions

Choices made for the first build. Change any of them.

## From your answers

| You said | What I built |
| --- | --- |
| Mostly iPad, sometimes iPhone | One app for both. Sidebar, list and reading column on iPad. Collapses to one column on iPhone. Keyboard shortcuts: ⌘N new entry, ⌘E edit, ⌘↩ done, ⌘, settings. |
| Sync, but no paid developer account | A folder in iCloud Drive that you pick. A free account can't use the iCloud features built into apps (CloudKit). Folder access through the Files app needs no paid account. |
| Face ID plus phone passcode | `LocalAuthentication` with the "device owner" policy. Face ID first, passcode if it fails. Works on iPads with Touch ID too. |
| Multiple journals | Yes. Each has a name and a color hint. |
| Location picker, Home vs. enter a place | Home (set once in Settings, synced) or a searched or typed place. Uses Apple Maps search. No GPS. |
| Amber lenses | Dark "lamp" theme by default. See below. |
| Paper notebook, textures matter | Paper grain on every page and card, photos shown like prints, serif type. |
| No AI, reminders or suggested prompts | None. Templates are only your own pages. |
| Streaks | Current, longest, last seven days, calendar dots. |
| Skip for now: Day One import, mood, tags, weather | Left out. |

## Looking good through amber lenses

Amber lenses cut blue light. Blues go dark and warm colors blur together, but brightness differences stay.

- Meaning is carried by brightness, not hue. Text, buttons and states differ in lightness.
- No blue or purple anywhere.
- Journal colors are a hint only. Through the lens they look alike (see `docs/palette-preview.png`). The journal's name always appears beside the dot.
- Body text has a 10:1 contrast or better through the simulated lenses. Captions stay above 4.5:1.
- The light "Paper" theme is there too, but it goes very bright through amber lenses. Lamp is the default.

`python3 tools/check_palette.py` reruns the checks.

## Things I decided

- **Entries are Markdown files**, one folder each. Easy to back up, open elsewhere, and recover. Photos are saved as JPEG, 2400 px on the long edge. Location data inside photos is not kept.
- **Autosave.** There is no Save button. Text is saved about a second after you stop typing, when you leave the screen, and when the app goes to the background. An entry with nothing in it is never saved.
- **Nothing is deleted outright.** Deleting moves an entry to Recently Deleted for 30 days. Removed photos go to a `Removed` folder inside the entry. Switching folders copies and never overwrites.
- **Conflicts keep both.** If the iPad and iPhone edit one entry at the same time, the newest stays and the other becomes a second entry.
- **"New day starts at"** (midnight, 2 AM or 4 AM). You write late. An entry at 12:40 AM would otherwise break the streak. Default is midnight.
- **Lock timing.** Locks right away when you leave the app. You can allow 1, 5 or 15 minutes in Settings. The app contents are hidden in the app switcher whenever the app isn't in front.
- **Streak message** after the first entry of a day, such as "Saved. 12 days in a row." Quiet, no confetti.
- **Search** is included. It was cheap and a journal needs it.
- **A template is a page of Markdown.** It is written in the same editor as an entry, and a new entry starts as a copy. Nothing links the entry back to the template, so editing a template never changes old entries. Templates from the first version (a list of questions) open as `##` headings.
- **Live Markdown, with the symbols hidden.** The file keeps plain Markdown. On screen, symbols like `##` and `**` are hidden except on the line the cursor is on, so you can always edit by hand. Lists and checklists are shown as `•`, `☐` and `☑` and turned back into `-`, `1.` and `- [ ]` when saved.
- **Most-used templates first.** Counts are kept on each device, not in the journal folder, so two devices never write the same file.
- **Working name: Lamplight.** Easy to change: `project.yml` (`CFBundleDisplayName`) and the text in `App/Views`.
- **Minimum iOS 17.**

## Not built

- Day One import (you chose to wait).
- Mood, tags, weather.
- Rich text beyond Markdown. No colors, fonts or alignment.
- Photos placed inline in the text (planned, next). Photos sit above the text for now.
- Audio, drawings and video (planned, after that).
- Export. The files are the export. Sharing a single entry is planned.
- iPad Stage Manager multiple windows. One window only, so two windows can't edit one entry.
- Sign-in with Apple or accounts. There aren't any.

## Known limits

- **Not compiled.** See README.
- **Free account:** the app must be reinstalled from Xcode every 7 days. Data is safe in iCloud Drive.
- **First open on a second device** can take a while if there are many photos, because iCloud downloads each file. The app shows progress and retries.
- **Photo zoom** works with pinch and double-tap. The photo can't be dragged until it is zoomed.
- **Saving problems** (for example the folder is offline) show a message and keep your text in the app. Saving is tried again on your next change. There is no queue that survives quitting the app.
