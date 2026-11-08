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
- **Templates are offered on the empty page.** A new entry opens empty, with your templates listed under the cursor, like Notion and Day One. They go away once you type. A journal can have a default template, which fills in by itself instead of asking.
- **The phone has a bottom bar, the iPad a sidebar.** On a phone the app opens on the entry list, with Journal, On This Day, Calendar and Templates along the bottom and a New Entry button in the middle. Settings is the gear at the top left. Switching journals is the title at the top of the list.
- **On an iPad a new entry takes the whole screen.** The sidebar and list slip away while you write, and come back when you tap Done. Opening the app to a new entry is quiet: the keyboard waits until you tap the page. Tapping New Entry yourself brings the keyboard up at once.
- **A section is one line: `--- Title ---`.** It is a titled break, drawn as a small title with a thin line to the edge, and it is different from a header, which stays for the questions under it. The line is plain text, so in another Markdown app it shows as `--- Title ---`, which is readable and keeps the file portable. The dashes hide when your cursor is elsewhere. When you tap Done, a template's sections with nothing written under them are removed along with the empty questions. A section you added yourself is never removed.
- **Choosing a section always shows its list.** If a new entry has the whole iPad screen, or a phone is on an entry, picking a section from the sidebar or the bottom bar brings the list back. On the Templates screen the right-hand side lists your templates too, so it is never only a message.
- **Opening the app starts a new entry** if you haven't written yet today and it's a fresh launch (not each time you switch back to the app). It's a setting. A page that still holds only a template is dropped, not saved.
- **Tap the text to edit.** There's no read mode to leave first. A link or checklist box still does its own thing when tapped.
- **Empty template headings are removed on Done.** Only headings that came from the entry's template, with nothing written under them. Anything you wrote is kept.
- **Textures are a setting, not a fixed look.** There are nine, with a strength slider, because the right feel is personal. Each is a faint tile that changes brightness only, so it stays easy to read through amber lenses. Pick one in Settings → Appearance → Paper. The default is Cotton, an even soft grain. The first texture (Fibers) used random flecks and short fibers, which looked like dust on the screen, so it is now an option at the end, not the default. The darkened edges of the page were also made much lighter for the same reason.
- **A ribbon, not a star.** A favorite entry shows a small ribbon bookmark. It's stored as `favorite: true` in the entry's own file, so two devices never fight over a shared list.
- **All Entries is the home page.** The app opens there. Today was the home page at first, and you found it less useful the more you used it. Today is still in the sidebar and in the phone's tab bar, after All Entries. On This Day, Favorites and Templates are under More on the phone. The iPad sidebar lists them all.
- **Sharing makes copies.** A shared Markdown file or PDF is built in a temporary folder and handed to the share sheet. Nothing in the journal changes. The PDF is dark ink on white paper, US Letter in the US and A4 elsewhere.
- **The moon is approximate.** It uses the average length of the lunar cycle, so a phase can be off by about half a day at the turning points. It's drawn by brightness, not color.
- **Done closes the page.** A new entry goes back to the list when you tap Done, and the page fades out first. Editing an old entry returns to reading it.
- **A look back, not a prompt.** After the first entry of a day is saved, the message shows what you wrote on this date in the most recent earlier year. It stays about 10 seconds and can be tapped or closed. It never says what to write.
- **Turning pages.** Swiping right in the reader goes to the older entry, left to the newer. It starts away from the left edge so the phone's back gesture still works.
- **The lamp.** The page starts dim and eases up when the journal opens or unlocks. It's skipped when Reduce Motion is on.
- **No haptics on iPad.** The iPad has no haptic motor, so nothing here depends on one. The phone still gets a tap when you finish an entry or tick a box.
- **Swipe to delete has no confirmation.** It only moves the entry to Recently Deleted, where it stays 30 days.
- **Working name: Lamplight.** Easy to change: `project.yml` (`CFBundleDisplayName`) and the text in `App/Views`.
- **Minimum iOS 17.**
- **Photos in the text.** A photo you add goes into the text at the caret, on a line of its own, `![](photos/NAME.jpg)`, full width. That is plain Markdown, so other apps can read the file. The editor hides the line's text and draws the photo in its place. Tap a photo to open it large. Photos in older entries stay above the text, and a photo that isn't named in the text always shows above it, so none is hidden. Backspace on the line after a photo moves the caret up to it, and a second Backspace removes it. Typing, pasting or deleting next to a photo can never mix it with words. A photo taken out of the text is kept in the entry's `Removed` folder when the entry is finished, so deleting it can still be undone while writing. Sharing as text leaves the picture lines out. Markdown and PDF exports put the photos where they are in the text.
- **Icons.** Everything you tap uses one light weight, set in one place (`Theme.iconWeight`), in three sizes (`PaperIcon`). The big decorative icons on empty and lock screens stay lighter. Close and remove buttons are a thin cross on a paper chip. Templates has one icon, `doc.text`, everywhere. The format bar uses the same weight and has taps about 44 points wide.
- **Flat system bars.** The toolbar buttons stay flat, the way they were before iOS 26, so they sit on the paper without glass chips. This is `UIDesignRequiresCompatibility` in `project.yml`. Apple says the key will stop working in a later release. Delete the line to try the glass.
- **Checks on GitHub.** Every pull request runs the Core tests, the type-check of the model and storage code, and the palette check on Linux. Pull requests that change code also build the app and run the tests in the iPad simulator on a Mac runner. That second one is the only compile check of the screens outside Xcode. The repo is private, so Mac runner minutes count ten times, which is why it only runs on pull requests that change code and stops an older run when you push again. To turn it off, delete `.github/workflows/app.yml`.
- **Opening the journal doesn't wait for ever.** Reading a file or listing a folder in iCloud Drive gives up after 12 to 15 seconds (60 for a photo). The entry is left out and tried again every few seconds, as an entry that hasn't downloaded yet already was. After three gives-ups in a row nothing new is tried for 20 seconds, so a folder iCloud isn't answering for opens with what is already here in about half a minute, not never. Saving is never given up on. A folder that can't be listed is an error, not an empty folder, so the app never starts a second, empty journal beside the real one or writes a new first journal over one it couldn't read yet. The loading page names the step it is on, shows the count from the start, and says so after 12 seconds.

## Not built

- Day One import (planned, after inline photos and video). See the next section.
- Mood, tags, weather.
- Rich text beyond Markdown. No colors, fonts or alignment.
- Video, placed in the text like photos (planned, next). Video isn't supported yet, and you said it has to be.
- Audio and drawings (planned, after that).
- Export. The files are the export. Sharing a single entry is planned.
- iPad Stage Manager multiple windows. One window only, so two windows can't edit one entry.
- Sign-in with Apple or accounts. There aren't any.

## Day One import (planned)

**Order.** Inline photos and video first, then the importer, so imported entries keep their media where it was in Day One.

**What you decided.**
- Tags become a `#tag` line at the end of the entry.
- Pinned entries become favorites, along with starred ones.
- Audio and PDFs are copied into the entry's folder so nothing is lost, even though the app can't show them yet.
- Video has to be supported, so video is imported as video, not just copied.
- Video you add yourself keeps the same photo picker. It is saved as a link to the video in your Photos library, so the journal doesn't hold a second copy. A still frame is saved in the entry so something always shows, and each video has a Keep a Copy button. The link points inside Photos, not at a web address, so it plays in Lamplight and other apps show the still frame. The app has to ask to read your Photos library, and finding the same video on your other device depends on iCloud Photos. If that proves unreliable, the fallback is copying the original. Imported Day One videos can't be linked, because they only exist in the export, so those are copied.
- **Video link test.** Settings has a "Video link test" page. It tries each risky step on the device (permission, linking, opening on the other device, playing from iCloud, keeping a copy) and prints a result to paste back, so the final design is chosen from real results. It changes nothing in the journal. Remove it when the video feature ships.

**How the fields map.** This comes from third-party descriptions of the export. Day One publishes no schema. Check it against a real export with `tools/dayone_inspect.py` before writing the importer.
- `uuid` becomes the entry id, the same id every time, so running the import twice doesn't duplicate entries.
- `creationDate` with `timeZone` becomes created time and time zone. `modifiedDate` becomes modified time.
- `text` becomes the body. Day One's backslash escapes are removed, and its media markers (`![](dayone-moment://…)`) become inline media.
- `starred` becomes favorite. `location` becomes location. `photos` are saved the way new photos are.
- Each journal file becomes a journal.
- Weather and camera details are dropped. Day One tables show as plain text.

**Things to keep in mind.**
- The entry file header only keeps fields the app knows. Anything else is dropped the next time the app saves that entry, so anything extra needs a model field.
- iOS has no built-in unzip. Unzip the export in the Files app, then pick the folder.

## Known limits

- **Not compiled.** See README.
- **Free account:** the app must be reinstalled from Xcode every 7 days. Data is safe in iCloud Drive.
- **First open on a second device** can take a while if there are many photos, because iCloud downloads each file. The app shows progress and retries.
- **Photo zoom** works with pinch and double-tap. The photo can't be dragged until it is zoomed.
- **Photos in the text** are drawn by the editor, which I could only type-check, not run. The line height, where the photo sits in it, and the caret around it are the parts to watch. VoiceOver may read out the hidden picture line. Not checked.
- **Saving problems** (for example the folder is offline) show a message and keep your text in the app. Saving is tried again on your next change. There is no queue that survives quitting the app.
