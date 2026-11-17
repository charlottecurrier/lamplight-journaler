# Video links to iCloud Photos: what I found

Written from Apple's documentation and developer forum threads. Nothing here was run on a device, so every "should" needs a test on your iPad and Mac.

## The idea

When you pick a video with the photo picker, the entry stores a link to it in your Photos library, a still frame, and a few facts about the video. No second copy. A "Keep a Copy" button saves the original into the journal if you want it.

## What I found

**The picker can hand back an identifier.**
- `PhotosPickerItem.itemIdentifier` is the local identifier of the picked item. It is nil if the picker is made without a photo library. [Apple: itemIdentifier](https://developer.apple.com/documentation/photosui/photospickeritem/itemidentifier)
- To get it, use the `PhotosPicker` initializers that take `photoLibrary:` (iOS 16 and later). [Apple: PhotosPicker](https://developer.apple.com/documentation/photosui/photospicker)
- The picker itself runs out of process and needs no permission. [WWDC21 notes](https://mackuba.eu/notes/wwdc21/improve-access-to-photos/)

**A local identifier is not safe to keep.**
- An Apple engineer: local identifiers "can change in the photo library under certain conditions", and `PHCloudIdentifier` "is the only type that is guaranteed to be consistent through all scenarios". Keep both, and fall back to the cloud identifier when the local one stops working. [Apple forums, thread 833047](https://developer.apple.com/forums/thread/833047)
- A cloud identifier works on any device synced through iCloud Photos. Store it with `stringValue` or `archivalStringValue`. Available from iOS 15. [Apple: PHCloudIdentifier](https://developer.apple.com/documentation/photos/phcloudidentifier)
- Looking one up is expensive, so do it when saving and loading, not while drawing. [Apple: cloudIdentifierMappings](https://developer.apple.com/documentation/photos/phphotolibrary/cloudidentifiermappings(forlocalidentifiers:))
- Errors: `identifierNotFound` (the photo was deleted, or can't be found), and `multipleIdentifiersFound` (the match is unclear, so ask the person to choose). An Apple engineer said deleted photos are likely the only case that fails when converting a local identifier to a cloud one. [Apple: PHCloudIdentifier](https://developer.apple.com/documentation/photos/phcloudidentifier), [thread 833047](https://developer.apple.com/forums/thread/833047)

**Linking needs permission to read the whole library.**
- Mapping to a cloud identifier needs photo library access, and the call causes the permission prompt. An Apple engineer: "You have to request photo library access to use the cloud identifier." [thread 697352](https://developer.apple.com/forums/thread/697352)
- Fetching the photo from an identifier without access fails. [thread 652819](https://developer.apple.com/forums/thread/652819)
- In Limited access mode, the picker does not widen what the app can read. A picked photo then fails to fetch and fails to map (`identifierNotFound`). Apple's answer: the data is only reachable through the picker's item provider, which means a copy. [thread 759040](https://developer.apple.com/forums/thread/759040), [thread 650902](https://developer.apple.com/forums/thread/650902)
- So a link only works if the person chooses "Allow Access to All Photos". If they choose Limited or refuse, we have to copy.

**Playing a video that lives in iCloud.**
- `PHVideoRequestOptions` has `isNetworkAccessAllowed`, `deliveryMode` and a `progressHandler`. [Apple: PHVideoRequestOptions](https://developer.apple.com/documentation/photos/phvideorequestoptions)
- The documented delivery modes are vague: `automatic` picks a quality by conditions, `highQualityFormat` gives only the best, `mediumQualityFormat` gives moderate quality unless a better one is cached. [Apple: delivery mode](https://developer.apple.com/documentation/photos/phvideorequestoptionsdeliverymode)
- Reports from developers, not Apple: the progress handler may not fire with `requestPlayerItem` ([thread 86023](https://developer.apple.com/forums/thread/86023)); medium quality can give a 720p file from iCloud that then fails to export ([thread 676918](https://developer.apple.com/forums/thread/676918)); a download with original and high quality set came out a different size than the original ([thread 763764](https://developer.apple.com/forums/thread/763764), no answer).
- Nobody I found explains how "Optimize Storage" changes this. It has to be tested.

**Keep a Copy.**
- `PHAssetResourceManager.writeData(for:toFile:options:)` writes an asset's underlying data to a file. It takes the same network and progress options. [Apple: PHAssetResourceManager](https://developer.apple.com/documentation/photos/phassetresourcemanager)
- Without permission, `loadFileRepresentation` or a `Transferable` movie on the picked item gives a copy. [thread 660696](https://developer.apple.com/forums/thread/660696)

**The Mac.**
- The cloud identifier calls exist on macOS 12 and later. Whether they work for an iPad app running on a Mac is not documented. PhotoKit only reaches the Mac's system photo library. [thread 662654](https://developer.apple.com/forums/thread/662654)

## What it means for the plan

- A link is possible but needs Full Access to Photos. Plan on **link when allowed, copy when not**, with the person told which happened.
- Store, per video: the cloud identifier, the local identifier (a cache), a still frame, duration, size, and creation date. If the cloud lookup fails, the date, duration and size are enough to offer likely matches.
- Show "waiting for iCloud" states. Never assume the file is on the device.
- Imported Day One videos are copied, because they only exist in the export.

## What needs a test on your devices

1. Picker with `photoLibrary: .shared()`: is `itemIdentifier` set, with no permission yet?
2. After "Allow Access to All Photos": do the local to cloud mapping and the fetch work?
3. After "Select Photos" (Limited): do they fail as the forums say, and does the app notice?
4. Link made on the iPad, opened on the Mac: does cloud to local mapping find the video?
5. A video that is only in iCloud (Optimize Storage on): how long until it plays, and does the progress handler fire?
6. Keep a Copy: is the written file the same size as the original, and how long does it take?
7. Delete the video from Photos: what error comes back, and does the still frame stay?
8. An edited video: does `version: .current` give the edited one?
