import SwiftUI
import PhotosUI
import Photos
import AVKit

/// What is remembered about a linked video. This is what an entry would keep.
struct LabLink: Codable, Equatable {
    var cloudID: String?
    var localID: String
    var created: Date?
    var duration: Double
    var width: Int
    var height: Int
}

/// Tries each risky step of linking a video to the Photos library and writes down what happened.
/// Nothing here touches the journal. It is for finding out what works on this device.
@MainActor
final class VideoLabModel: ObservableObject {
    @Published var log: [String] = []
    @Published var status: PHAuthorizationStatus = PHPhotoLibrary.authorizationStatus(for: .readWrite)
    @Published var link: LabLink?
    @Published var poster: UIImage?
    @Published var player: AVPlayer?

    private static let storeKey = "lab.videoLink"
    private var statusObservation: NSKeyValueObservation?
    private var lastLoggedPercent = -1

    init() {
        if let data = UserDefaults.standard.data(forKey: Self.storeKey),
           let saved = try? JSONDecoder().decode(LabLink.self, from: data) {
            link = saved
        }
        let device = UIDevice.current
        add("Device: \(device.model), iOS \(device.systemVersion), iPad app on a Mac: \(ProcessInfo.processInfo.isiOSAppOnMac)")
        add("Photos access: \(Self.statusText(status))")
    }

    // MARK: Words

    static func statusText(_ status: PHAuthorizationStatus) -> String {
        switch status {
        case .notDetermined: return "not asked yet"
        case .restricted: return "restricted"
        case .denied: return "denied"
        case .authorized: return "full access"
        case .limited: return "limited access"
        @unknown default: return "unknown"
        }
    }

    static func errorText(_ error: Error) -> String {
        if let photos = error as? PHPhotosError {
            return "PHPhotosError \(photos.code.rawValue), \(photos.localizedDescription)"
        }
        return error.localizedDescription
    }

    static func typeText(_ type: PHAssetResourceType) -> String {
        switch type {
        case .photo: return "photo"
        case .video: return "video"
        case .fullSizePhoto: return "fullSizePhoto"
        case .fullSizeVideo: return "fullSizeVideo"
        case .pairedVideo: return "pairedVideo"
        case .adjustmentData: return "adjustmentData"
        default: return "type \(type.rawValue)"
        }
    }

    static func short(_ text: String?) -> String {
        guard let text, !text.isEmpty else { return "none" }
        return text.count > 18 ? String(text.prefix(18)) + "…" : text
    }

    static func seconds(_ value: TimeInterval) -> String {
        String(format: "%.1f s", value)
    }

    private func add(_ line: String) {
        log.append(line)
    }

    private func persist() {
        if let link, let data = try? JSONEncoder().encode(link) {
            UserDefaults.standard.set(data, forKey: Self.storeKey)
        }
    }

    // MARK: Permission

    func askForAccess() {
        add("Asking for Photos access…")
        PHPhotoLibrary.requestAuthorization(for: .readWrite) { [weak self] newStatus in
            Task { @MainActor in
                self?.status = newStatus
                self?.add("Photos access is now: \(Self.statusText(newStatus))")
            }
        }
    }

    func refreshStatus() {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        add("Photos access: \(Self.statusText(status))")
    }

    func chooseMoreForLimited() {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = scenes.first?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        guard let top else {
            add("Couldn't find a screen to show the limited picker on.")
            return
        }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: top)
    }

    // MARK: Linking

    func picked(_ item: PhotosPickerItem?) {
        guard let item else { return }
        add("— Picked a video —")
        guard let localID = item.itemIdentifier else {
            add("The picker gave no identifier (itemIdentifier is nil).")
            return
        }
        add("Picker identifier: \(Self.short(localID))")
        inspect(localID: localID)
    }

    private func inspect(localID: String) {
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        add("Photos access: \(Self.statusText(status))")

        let fetched = PHAsset.fetchAssets(withLocalIdentifiers: [localID], options: nil)
        add("Fetch by identifier found \(fetched.count) item(s)")

        var cloudID: String?
        let mappings = PHPhotoLibrary.shared().cloudIdentifierMappings(forLocalIdentifiers: [localID])
        switch mappings[localID] {
        case .success(let cloud)?:
            cloudID = cloud.stringValue
            add("Cloud identifier: \(Self.short(cloudID))")
        case .failure(let error)?:
            add("Cloud identifier failed: \(Self.errorText(error))")
        case nil:
            add("No cloud mapping came back")
        }

        guard let asset = fetched.firstObject else {
            add("Can't read the video's details without the asset.")
            return
        }
        add("Media type: \(asset.mediaType == .video ? "video" : "not a video"), \(Int(asset.duration)) s, \(asset.pixelWidth) x \(asset.pixelHeight)")
        add("Created: \(asset.creationDate.map { $0.formatted() } ?? "unknown")")
        let resources = PHAssetResource.assetResources(for: asset)
        add("Parts: " + resources.map { Self.typeText($0.type) }.joined(separator: ", "))

        requestStill(for: asset)

        link = LabLink(
            cloudID: cloudID, localID: localID, created: asset.creationDate,
            duration: asset.duration, width: asset.pixelWidth, height: asset.pixelHeight
        )
        persist()
        add("Saved this link on this device. Copy Link moves it to another device.")
    }

    private func requestStill(for asset: PHAsset) {
        let options = PHImageRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .highQualityFormat
        options.resizeMode = .fast
        let started = Date()
        PHImageManager.default().requestImage(
            for: asset, targetSize: CGSize(width: 1200, height: 1200), contentMode: .aspectFit, options: options
        ) { [weak self] image, _ in
            Task { @MainActor in
                guard let self else { return }
                let took = Self.seconds(Date().timeIntervalSince(started))
                if let image {
                    self.poster = image
                    self.add("Still frame: \(Int(image.size.width)) x \(Int(image.size.height)) in \(took)")
                } else {
                    self.add("No still frame came back after \(took)")
                }
            }
        }
    }

    func copyLink() {
        guard let link, let data = try? JSONEncoder().encode(link), let text = String(data: data, encoding: .utf8) else {
            add("No link to copy yet.")
            return
        }
        UIPasteboard.general.string = text
        add("Link copied. Paste it on the other device.")
    }

    func pasteLink() {
        guard let text = UIPasteboard.general.string,
              let saved = try? JSONDecoder().decode(LabLink.self, from: Data(text.utf8)) else {
            add("Nothing that looks like a link is on the clipboard.")
            return
        }
        link = saved
        persist()
        poster = nil
        add("Pasted a link. Cloud identifier: \(Self.short(saved.cloudID)), local identifier: \(Self.short(saved.localID))")
    }

    // MARK: Finding it again

    /// Looks for the linked video: by the local identifier, then by the cloud identifier, then by when it was made
    /// and how long it is. Says what each step found.
    private func findAsset() -> PHAsset? {
        guard let link else {
            add("No link yet. Pick a video or paste a link first.")
            return nil
        }
        add("— Looking for the video —")
        status = PHPhotoLibrary.authorizationStatus(for: .readWrite)
        add("Photos access: \(Self.statusText(status))")

        let byLocal = PHAsset.fetchAssets(withLocalIdentifiers: [link.localID], options: nil)
        add("By local identifier: \(byLocal.count) found")
        if let asset = byLocal.firstObject { return asset }

        if let cloudString = link.cloudID {
            let cloud = PHCloudIdentifier(stringValue: cloudString)
            let mappings = PHPhotoLibrary.shared().localIdentifierMappings(for: [cloud])
            switch mappings[cloud] {
            case .success(let local)?:
                add("By cloud identifier, this device's identifier is \(Self.short(local))")
                let byCloud = PHAsset.fetchAssets(withLocalIdentifiers: [local], options: nil)
                add("Fetch by that found \(byCloud.count)")
                if let asset = byCloud.firstObject { return asset }
            case .failure(let error)?:
                add("Cloud to local failed: \(Self.errorText(error))")
                if let photos = error as? PHPhotosError, photos.code == .multipleIdentifiersFound {
                    let several = photos.userInfo[PHLocalIdentifiersErrorKey] as? [String]
                    add("Several matches: \(several?.count ?? 0)")
                }
            case nil:
                add("No mapping came back")
            }
        } else {
            add("This link has no cloud identifier.")
        }

        if let created = link.created {
            let options = PHFetchOptions()
            options.predicate = NSPredicate(
                format: "mediaType == %d AND creationDate >= %@ AND creationDate <= %@",
                PHAssetMediaType.video.rawValue, created.addingTimeInterval(-3) as NSDate, created.addingTimeInterval(3) as NSDate
            )
            let nearby = PHAsset.fetchAssets(with: options)
            var matches: [PHAsset] = []
            nearby.enumerateObjects { asset, _, _ in
                if abs(asset.duration - link.duration) < 0.5 { matches.append(asset) }
            }
            add("By date and length: \(nearby.count) video(s) near that time, \(matches.count) the same length")
            if matches.count == 1 { return matches[0] }
        }
        add("Not found.")
        return nil
    }

    // MARK: Playing

    func findAndPlay() {
        player = nil
        statusObservation = nil
        guard let asset = findAsset() else { return }
        play(asset)
    }

    private func play(_ asset: PHAsset) {
        let options = PHVideoRequestOptions()
        options.isNetworkAccessAllowed = true
        options.deliveryMode = .automatic
        lastLoggedPercent = -1
        options.progressHandler = { [weak self] fraction, error, _, _ in
            Task { @MainActor in
                guard let self else { return }
                let percent = Int(fraction * 100) / 10 * 10
                if percent != self.lastLoggedPercent {
                    self.lastLoggedPercent = percent
                    self.add("Download progress: \(percent)%")
                }
                if let error { self.add("Progress reported an error: \(Self.errorText(error))") }
            }
        }
        let started = Date()
        add("Asking for the video…")
        PHImageManager.default().requestPlayerItem(forVideo: asset, options: options) { [weak self] item, info in
            Task { @MainActor in
                guard let self else { return }
                let took = Self.seconds(Date().timeIntervalSince(started))
                guard let item else {
                    let inCloud = (info?[PHImageResultIsInCloudKey] as? Bool).map { $0 ? "yes" : "no" } ?? "unknown"
                    self.add("No video came back after \(took). In iCloud: \(inCloud)")
                    return
                }
                self.add("The video arrived after \(took)")
                self.start(item, since: started)
            }
        }
    }

    private func start(_ item: AVPlayerItem, since started: Date) {
        let newPlayer = AVPlayer(playerItem: item)
        player = newPlayer
        statusObservation = item.observe(\.status, options: [.new]) { [weak self] observed, _ in
            Task { @MainActor in
                guard let self else { return }
                switch observed.status {
                case .readyToPlay:
                    self.add("Ready to play after \(Self.seconds(Date().timeIntervalSince(started)))")
                case .failed:
                    self.add("Playback failed: \(observed.error.map(Self.errorText) ?? "unknown")")
                default:
                    break
                }
            }
        }
        newPlayer.play()
    }

    func stop() {
        player?.pause()
        player = nil
        statusObservation = nil
        add("Stopped.")
    }

    // MARK: Keeping a copy

    func copyOriginal() {
        guard let asset = findAsset() else { return }
        let resources = PHAssetResource.assetResources(for: asset)
        guard let resource = resources.first(where: { $0.type == .fullSizeVideo })
            ?? resources.first(where: { $0.type == .video }) else {
            add("This video has no part to copy.")
            return
        }
        let url = FileManager.default.temporaryDirectory.appendingPathComponent("lab-\(UUID().uuidString).mov")
        let options = PHAssetResourceRequestOptions()
        options.isNetworkAccessAllowed = true
        options.progressHandler = { [weak self] fraction in
            Task { @MainActor in
                guard let self else { return }
                let percent = Int(fraction * 100) / 10 * 10
                if percent != self.lastLoggedPercent {
                    self.lastLoggedPercent = percent
                    self.add("Copy progress: \(percent)%")
                }
            }
        }
        lastLoggedPercent = -1
        let started = Date()
        add("Copying the \(Self.typeText(resource.type)) part to a temporary file…")
        PHAssetResourceManager.default().writeData(for: resource, toFile: url, options: options) { [weak self] error in
            Task { @MainActor in
                guard let self else { return }
                let took = Self.seconds(Date().timeIntervalSince(started))
                if let error {
                    self.add("Copy failed after \(took): \(Self.errorText(error))")
                    return
                }
                let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                let bytes = (attributes?[.size] as? NSNumber)?.int64Value ?? 0
                let size = ByteCountFormatter.string(fromByteCount: bytes, countStyle: .file)
                self.add("Copied \(size) in \(took). The temporary file is deleted now.")
                try? FileManager.default.removeItem(at: url)
            }
        }
    }

    func clearLog() {
        log = []
    }

    var logText: String {
        log.joined(separator: "\n")
    }
}

/// A page in Settings for trying out video links on this device.
struct VideoLinkLab: View {
    @StateObject private var lab = VideoLabModel()
    @State private var picked: PhotosPickerItem?

    var body: some View {
        List {
            Section {
                Text("Photos access: \(VideoLabModel.statusText(lab.status))")
                Button("Ask for Photos Access") { lab.askForAccess() }
                Button("Check Access Again") { lab.refreshStatus() }
                if lab.status == .limited {
                    Button("Choose More Videos to Share") { lab.chooseMoreForLimited() }
                }
            } header: {
                Text("1. Permission")
            } footer: {
                Text("Linking needs access to all your photos. Choose Allow Access to All Photos when asked.")
            }
            .listRowBackground(Theme.surface)

            Section {
                PhotosPicker(selection: $picked, matching: .videos, photoLibrary: .shared()) {
                    Label("Pick a Video", systemImage: "film")
                }
                if let poster = lab.poster {
                    Image(uiImage: poster)
                        .resizable()
                        .scaledToFit()
                        .frame(maxHeight: 160)
                        .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                }
                if let link = lab.link {
                    Text("Saved link: \(Int(link.duration)) s, cloud identifier \(VideoLabModel.short(link.cloudID))")
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.inkSecondary)
                }
                Button("Copy Link") { lab.copyLink() }
                Button("Paste Link") { lab.pasteLink() }
            } header: {
                Text("2. Link a video")
            } footer: {
                Text("To try a second device, copy the link here and paste it there. The clipboard is shared between your iPad and Mac.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Find It and Play") { lab.findAndPlay() }
                if let player = lab.player {
                    VideoPlayer(player: player)
                        .frame(height: 240)
                        .listRowInsets(EdgeInsets())
                }
                Button("Stop") { lab.stop() }
                Button("Copy the Original to a Temporary File") { lab.copyOriginal() }
            } header: {
                Text("3. Open it")
            } footer: {
                Text("To test a deleted video, delete it in Photos and press Find It and Play again.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Text(lab.logText)
                    .font(.system(.footnote, design: .monospaced))
                    .textSelection(.enabled)
                Button("Copy Results") { UIPasteboard.general.string = lab.logText }
                Button("Clear Results", role: .destructive) { lab.clearLog() }
            } header: {
                Text("Results")
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Video link test")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: picked) {
            guard let item = picked else { return }
            lab.picked(item)
            picked = nil
        }
    }
}
