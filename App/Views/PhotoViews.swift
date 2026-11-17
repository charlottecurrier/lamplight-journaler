import AVKit
import Photos
import SwiftUI

/// A photo that fills whatever space it is given. Loads a small version, and shows a quiet placeholder
/// while the file is still coming down from iCloud.
struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    let photo: PhotoRef
    var maxPixel: CGFloat = 480

    @State private var image: UIImage?
    /// Which photo `image` belongs to. The view can be reused for a different photo, so the two must match.
    @State private var imageFor: UUID?

    var body: some View {
        Theme.raised
            .overlay {
                if let image, imageFor == photo.id {
                    Image(uiImage: image)
                        .resizable()
                        .scaledToFill()
                } else {
                    Image(systemName: "photo")
                        .font(.title3)
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            .clipped()
            .overlay(alignment: .bottomTrailing) {
                if let video = photo.video {
                    VideoLengthTab(text: video.durationText)
                        .padding(5)
                }
            }
            .task(id: "\(photo.id.uuidString)-\(model.refreshCounter)") {
                if image != nil, imageFor == photo.id { return }
                let loaded = await model.image(entryID: entryID, photo: photo, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.25)) {
                    image = loaded
                    imageFor = loaded == nil ? nil : photo.id
                }
            }
            .accessibilityHidden(true)
    }
}

/// Photos laid out like Day One: one large photo, or a grid of squares. Used for the photos that are not placed
/// in the text, which is all of them for entries from before photos could be placed.
struct PhotoMosaic: View {
    let entryID: UUID
    let photos: [PhotoRef]
    /// Called with the position of the tapped photo in `photos`.
    var onOpen: (Int) -> Void

    var body: some View {
        if photos.count == 1, let photo = photos.first {
            Button {
                onOpen(0)
            } label: {
                PhotoThumb(entryID: entryID, photo: photo, maxPixel: 1600)
                    .aspectRatio(min(max(photo.aspectRatio, 0.8), 1.8), contentMode: .fit)
                    .clipShape(RoundedRectangle(cornerRadius: 14, style: .continuous))
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Photo")
            .accessibilityHint("Opens the photo full screen")
        } else {
            let columnCount = (photos.count == 2 || photos.count == 4) ? 2 : 3
            LazyVGrid(
                columns: Array(repeating: GridItem(.flexible(), spacing: 6), count: columnCount),
                spacing: 6
            ) {
                ForEach(Array(photos.enumerated()), id: \.element.id) { index, photo in
                    Button {
                        onOpen(index)
                    } label: {
                        Color.clear
                            .aspectRatio(1, contentMode: .fit)
                            .overlay { PhotoThumb(entryID: entryID, photo: photo, maxPixel: 800) }
                            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Photo \(index + 1) of \(photos.count)")
                    .accessibilityHint("Opens the photo full screen")
                }
            }
        }
    }
}

struct PhotoViewerItem: Identifiable {
    let id = UUID()
    let entryID: UUID
    let photos: [PhotoRef]
    var index: Int
}

/// Full-screen photos. Swipe between them, pinch or double-tap to zoom. A video shows its still frame and plays
/// when asked.
struct PhotoViewer: View {
    @Environment(\.dismiss) private var dismiss
    let item: PhotoViewerItem
    @State private var index: Int

    init(item: PhotoViewerItem) {
        self.item = item
        _index = State(initialValue: item.index)
    }

    var body: some View {
        ZStack(alignment: .topTrailing) {
            Theme.page.ignoresSafeArea()
            TabView(selection: $index) {
                ForEach(Array(item.photos.enumerated()), id: \.element.id) { position, photo in
                    Group {
                        if let video = photo.video {
                            LinkedVideoPage(entryID: item.entryID, photo: photo, video: video, isShowing: index == position)
                        } else {
                            ZoomablePhoto(entryID: item.entryID, photo: photo)
                        }
                    }
                    .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: item.photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                PaperCloseChip(diameter: 36)
                    .padding(16)
                    .contentShape(Rectangle())
            }
            .accessibilityLabel("Close")
            .keyboardShortcut(.cancelAction)
        }
    }
}

struct ZoomablePhoto: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    let photo: PhotoRef

    @State private var image: UIImage?
    @State private var scale: CGFloat = 1
    @GestureState private var pinch: CGFloat = 1

    var body: some View {
        GeometryReader { proxy in
            let factor = max(scale * pinch, 1)
            ScrollView([.horizontal, .vertical], showsIndicators: false) {
                Group {
                    if let image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                    } else {
                        ProgressView().tint(Theme.inkSecondary)
                    }
                }
                .frame(width: proxy.size.width * factor, height: proxy.size.height * factor)
            }
            .gesture(
                MagnifyGesture()
                    .updating($pinch) { value, state, _ in state = value.magnification }
                    .onEnded { value in scale = min(max(scale * value.magnification, 1), 5) }
            )
            .onTapGesture(count: 2) {
                withAnimation(.easeInOut(duration: 0.25)) { scale = scale > 1.01 ? 1 : 2.5 }
            }
        }
        .task {
            image = await model.image(entryID: entryID, photo: photo, maxPixel: 2400)
        }
    }
}

/// How long a video is, on a dark tab so it shows on any picture. It marks a picture as a video's still frame.
struct VideoLengthTab: View {
    let text: String

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "play.fill")
                .font(.system(size: 8))
            Text(text)
                .font(.system(size: 12, weight: .medium).monospacedDigit())
        }
        .foregroundStyle(Theme.lampCore)
        .padding(.horizontal, 7)
        .padding(.vertical, 3)
        .background(Capsule().fill(Theme.lampFrame.opacity(0.62)))
        .accessibilityHidden(true)
    }
}

/// A video an entry links to, full screen. It shows the still frame the entry keeps, and plays the video from the
/// Photos library when asked. The video may have to come down from iCloud first, or may be gone, and the page says
/// which.
struct LinkedVideoPage: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    let photo: PhotoRef
    let video: VideoLink
    /// False once the person has swiped to another page, which stops the video.
    let isShowing: Bool

    private enum Stage: Equatable {
        case still
        case finding
        case downloading(Double)
        case playing
        case problem(String)
    }

    @State private var frame: UIImage?
    @State private var stage: Stage = .still
    @State private var player: AVPlayer?

    var body: some View {
        ZStack {
            if let player, stage == .playing {
                VideoPlayer(player: player)
            } else {
                still
            }
        }
        .task {
            frame = await model.image(entryID: entryID, photo: photo, maxPixel: 2400)
        }
        .onChange(of: isShowing) {
            if !isShowing { stop() }
        }
        .onDisappear { stop() }
    }

    private var still: some View {
        ZStack {
            if let frame {
                Image(uiImage: frame)
                    .resizable()
                    .scaledToFit()
            }
            VStack(spacing: 14) {
                switch stage {
                case .still:
                    Button(action: play) {
                        Image(systemName: "play.fill")
                            .font(.system(size: 26))
                            .foregroundStyle(Theme.lampCore)
                            .frame(width: 76, height: 76)
                            .background(Circle().fill(Theme.lampFrame.opacity(0.62)))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel("Play video, \(video.durationText)")
                case .finding:
                    ProgressView().tint(Theme.lampCore)
                    note("Finding the video in Photos")
                case .downloading(let fraction):
                    ProgressView(value: fraction)
                        .tint(Theme.lampCore)
                        .frame(width: 160)
                    note("Bringing it down from iCloud")
                case .playing:
                    EmptyView()
                case .problem(let message):
                    note(message)
                    Button("Try Again", action: play)
                        .buttonStyle(.quietPaper)
                }
            }
            .padding(24)
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(Theme.serif(.subheadline))
            .foregroundStyle(Theme.lampCore)
            .multilineTextAlignment(.center)
            .padding(.horizontal, 14)
            .padding(.vertical, 8)
            .background(RoundedRectangle(cornerRadius: 12, style: .continuous).fill(Theme.lampFrame.opacity(0.62)))
            .frame(maxWidth: 320)
    }

    private func play() {
        guard stage == .still || isProblem else { return }
        stage = .finding
        Task { @MainActor in
            // Playing asks for the library the first time, if it was never asked for on this device.
            if PhotoAccess.current == .undecided {
                _ = await PHPhotoLibrary.requestAuthorization(for: .readWrite)
            }
            let link = video
            let found = await Task.detached(priority: .userInitiated) { VideoLibrary.asset(for: link) }.value
            guard stage == .finding else { return }
            switch found {
            case .failure(let problem):
                stage = .problem(Self.message(for: problem))
            case .success(let asset):
                let result = await VideoLibrary.playerItem(for: asset) { fraction in
                    Task { @MainActor in
                        // Only while still waiting: a late report must not cover the video once it plays.
                        switch stage {
                        case .finding, .downloading:
                            if fraction < 1 { stage = .downloading(fraction) }
                        default:
                            break
                        }
                    }
                }
                guard stage == .finding || isDownloading else { return }
                switch result {
                case .failure(let problem):
                    stage = .problem(Self.message(for: problem))
                case .success(let item):
                    let player = AVPlayer(playerItem: item)
                    self.player = player
                    stage = .playing
                    player.play()
                }
            }
        }
    }

    private var isProblem: Bool {
        if case .problem = stage { return true }
        return false
    }

    private var isDownloading: Bool {
        if case .downloading = stage { return true }
        return false
    }

    private func stop() {
        player?.pause()
        player = nil
        stage = .still
    }

    private static func message(for problem: VideoLibrary.Problem) -> String {
        switch problem {
        case .noAccess:
            return "Lamplight can't read your Photos library, so it can't play this video. Photos access is in Settings."
        case .notFound:
            return "This video isn't in Photos on this device. It may have been deleted, or iCloud Photos may be off here."
        case .unavailable:
            return "Photos couldn't hand over the video. It may need a connection to come down from iCloud."
        }
    }
}
