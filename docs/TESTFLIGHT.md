# Sharing Lamplight with friends

TestFlight is Apple's way to hand a test version of an app to other people. You need the paid Apple Developer Program. Your friends don't. They install Apple's free TestFlight app and tap a link from you.

Apple's pages: [TestFlight](https://developer.apple.com/testflight/), [invite testers](https://developer.apple.com/help/app-store-connect/test-a-beta-version/invite-external-testers), [test information](https://developer.apple.com/help/app-store-connect/test-a-beta-version/provide-test-information).

## Once

1. Enroll in the Apple Developer Program as an individual. Copy your **Team ID** from developer.apple.com/account, under Membership details.
2. The Team ID is in `project.yml` as `DEVELOPMENT_TEAM`. Build to your iPad once with it, to check that signing works and to register the app ID.
3. In App Store Connect, go to Apps, then New App. Platform iOS, bundle ID `com.forageandjump.lamplight`. The App Store name has to be unique across the store, so "Lamplight" may be taken. If it is, pick another. The name under the icon on your home screen is separate (`CFBundleDisplayName`).

## Each upload

1. Raise the build number. Apple refuses an upload that isn't higher than the last one. The first upload can use the number that's there. After that, run `python3 tools/bump_build.py` and commit the change.
2. In Xcode, pick **Any iOS Device (arm64)** at the top, not a simulator.
3. Product, then Archive. When it finishes, the Organizer opens.
4. Distribute App, then App Store Connect, then Distribute. Keep the default choices.
5. Wait for the email from Apple saying the build finished processing. It can take several minutes.
6. The build is in App Store Connect under TestFlight. If a note says "Missing Compliance", answer that the app uses no encryption beyond what iOS provides. The app already says so (`ITSAppUsesNonExemptEncryption`), so this shouldn't appear.

A build can be installed for 90 days. Upload a new one before then.

## The first time you share

1. In App Store Connect, open the app, then TestFlight.
2. Under **Test Information**, fill in the fields below.
3. Create a group under **External Testing**. Add the build to it. Submit it for Beta App Review. The first build of a version gets a full review. Later builds of the same version may not.
4. When it's approved, turn on the **public link** for the group and send the link to friends. Or add them by email.

Fill in these:

**Beta App Description**

> Lamplight is a private journal for iPad and iPhone. You write entries in plain text. They are saved as files in a place you choose, such as a folder in iCloud Drive. There is no account and no analytics.

**What to Test** (for each build, edit as needed)

> Pick where your journal lives. Write a few entries. Add some photos. Close the app and open it again, and check that everything is still there. Tell me about anything that looks wrong, is slow to open, or loses text.

**Feedback Email**: the address you want friends to write to.

## Message for friends

> I made a journaling app called Lamplight and I'd like you to try it. It's a test version, so it may have bugs. Keep your own backup of anything you write that matters.
>
> 1. Install TestFlight from the App Store.
> 2. Open this link on your iPhone or iPad: (link)
> 3. Tap Install.
>
> It needs iOS 17 or later. The first time you open it, it asks where to keep your entries. If something looks wrong or you lose text, take a screenshot and send it to me. You can also do that from inside TestFlight.

## Things to know

- Testers can send you screenshots with notes from TestFlight. You also get crash reports.
- Lamplight doesn't send entries to you or to anyone. They stay in each person's own folder, and in iCloud Drive if that is the folder. The one thing that leaves the device is place search: what someone types in the place field goes to Apple Maps to find matches.
- Lamplight is version 0.1.0. Start with one or two friends.
- An App Store release is a separate step. It needs a privacy policy page, screenshots and review. This page doesn't cover it.
- `App/PrivacyInfo.xcprivacy` tells Apple which system features the app uses and why. `tools/check_privacy_manifest.py` fails when the code starts using one that isn't listed.
