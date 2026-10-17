import SwiftUI

/// A photo that fills whatever space it is given. Loads a small version, and shows a quiet placeholder
/// while the file is still coming down from iCloud.
struct PhotoThumb: View {
    @Environment(AppModel.self) private var model
    let entryID: UUID
    let photo: PhotoRef
    var maxPixel: CGFloat = 480

    @State private var image: UIImage?

    var body: some View {
        Theme.raised
            .overlay {
                if let image {
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
            .task(id: "\(photo.id.uuidString)-\(model.refreshCounter)") {
                guard image == nil else { return }
                let loaded = await model.image(entryID: entryID, photo: photo, maxPixel: maxPixel)
                withAnimation(.easeOut(duration: 0.25)) { image = loaded }
            }
            .accessibilityHidden(true)
    }
}

/// An entry's photos, laid out like Day One: one large photo, or a grid of squares.
struct PhotoMosaic: View {
    let entry: Entry
    var onOpen: (Int) -> Void

    var body: some View {
        let photos = entry.photos
        if photos.count == 1, let photo = photos.first {
            Button {
                onOpen(0)
            } label: {
                PhotoThumb(entryID: entry.id, photo: photo, maxPixel: 1600)
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
                            .overlay { PhotoThumb(entryID: entry.id, photo: photo, maxPixel: 800) }
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

/// Full-screen photos. Swipe between them, pinch or double-tap to zoom.
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
                    ZoomablePhoto(entryID: item.entryID, photo: photo)
                        .tag(position)
                }
            }
            .tabViewStyle(.page(indexDisplayMode: item.photos.count > 1 ? .automatic : .never))
            .ignoresSafeArea()

            Button {
                dismiss()
            } label: {
                Image(systemName: "xmark.circle.fill")
                    .font(.system(size: 32))
                    .symbolRenderingMode(.palette)
                    .foregroundStyle(Theme.ink, Theme.surface)
                    .padding(16)
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
