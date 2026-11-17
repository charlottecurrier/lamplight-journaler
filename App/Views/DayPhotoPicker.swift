import Photos
import SwiftUI

/// "Add Photos": the photos from the day of the entry first, then every other day, newest first.
///
/// It needs to read the Photos library to do that. If the person would rather not allow it, or can only share some
/// photos, the sheet says so and offers the system's Photos picker, which works without access.
struct DayPhotoPicker: View {
    @StateObject private var model: DayPhotoPickerModel
    @Environment(\.dismiss) private var dismiss
    @Environment(\.scenePhase) private var scenePhase

    /// Called with the photos chosen, as library identifiers, in the order they were tapped.
    var onAdd: ([String]) -> Void
    /// The person would rather use the system's Photos picker. The sheet closes itself after this.
    var onUseSystemPicker: () -> Void

    init(
        entryDate: Date, timeZone: TimeZone, calendar: DayCalendar,
        onAdd: @escaping ([String]) -> Void, onUseSystemPicker: @escaping () -> Void
    ) {
        _model = StateObject(wrappedValue: DayPhotoPickerModel(entryDate: entryDate, timeZone: timeZone, calendar: calendar))
        self.onAdd = onAdd
        self.onUseSystemPicker = onUseSystemPicker
    }

    private let columns = [GridItem(.adaptive(minimum: 104, maximum: 160), spacing: 3)]

    var body: some View {
        NavigationStack {
            content
                .background(PaperBackground())
                .navigationTitle("Add Photos")
                .navigationBarTitleDisplayMode(.inline)
                .toolbar {
                    ToolbarItem(placement: .cancellationAction) {
                        Button("Cancel") { dismiss() }
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button(model.selected.isEmpty ? "Add" : "Add \(model.selected.count)") {
                            onAdd(model.selected)
                            dismiss()
                        }
                        .font(Theme.serif(.body, weight: .semibold))
                        .disabled(model.selected.isEmpty)
                    }
                }
        }
        .task { await model.load() }
        // Back from Settings, or from sharing more photos: read again if the access changed.
        .onChange(of: scenePhase) {
            if scenePhase == .active { Task { await model.refreshIfAccessChanged() } }
        }
    }

    // MARK: Content

    @ViewBuilder
    private var content: some View {
        switch model.access {
        case .undecided:
            Explanation(
                title: "Photos from the day",
                message: "Lamplight can show the photos you took on the day of an entry first. To do that it needs to read your Photos library. Photos you add are copied into your journal folder. A video is not copied: the entry keeps a still frame and a link to the video in Photos.",
                primaryTitle: "Allow Access",
                primary: { Task { await model.requestAccess() } },
                secondaryTitle: "Use the Photos Picker",
                secondary: useSystemPicker
            )
        case .denied:
            Explanation(
                title: "Photos access is off",
                message: "Turn it on in Settings to see your photos by day. Or use the Photos picker, which works without it.",
                primaryTitle: "Open Settings",
                primary: openSettings,
                secondaryTitle: "Use the Photos Picker",
                secondary: useSystemPicker
            )
        case .full, .limited:
            grid
        }
    }

    private var grid: some View {
        ScrollView {
            if model.access == .limited { limitedNote }
            LazyVStack(alignment: .leading, spacing: 20) {
                ForEach(model.days) { day in
                    VStack(alignment: .leading, spacing: 8) {
                        header(for: day)
                        if day.count > 0 {
                            LazyVGrid(columns: columns, spacing: 3) {
                                ForEach(0..<day.count, id: \.self) { position in
                                    if let asset = model.asset(in: day, at: position) {
                                        PickerCell(model: model, asset: asset)
                                    }
                                }
                            }
                        } else if day.isEntryDay {
                            Text(model.isLoading ? "Looking…" : "Nothing from this day.")
                                .font(Theme.serif(.footnote))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                if model.isLoading && !model.days.isEmpty {
                    ProgressView().frame(maxWidth: .infinity).padding(.vertical, 12)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
        }
        .safeAreaInset(edge: .bottom) {
            if model.isFull {
                Text("\(DayPhotoPickerModel.limit) photos at a time.")
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
                    .padding(.vertical, 8)
                    .frame(maxWidth: .infinity)
                    .background(Theme.surface)
            }
        }
    }

    private var limitedNote: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text("Lamplight can see only some of your photos.")
                .font(Theme.serif(.subheadline))
                .foregroundStyle(Theme.inkSecondary)
            HStack {
                Button("Choose More") { chooseMoreToShare() }
                Button("Use the Photos Picker", action: useSystemPicker)
            }
            .buttonStyle(.quietPaper)
        }
        .padding(.horizontal, 16)
        .padding(.top, 12)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func header(for day: PickerDay) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title(for: day))
                .font(Theme.serif(day.isEntryDay ? .headline : .subheadline, weight: .semibold))
                .foregroundStyle(day.isEntryDay ? Theme.ink : Theme.inkSecondary)
            if day.isEntryDay {
                Text("The day of this entry")
                    .font(Theme.serif(.caption))
                    .foregroundStyle(Theme.inkTertiary)
            }
        }
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isHeader)
    }

    /// "Saturday, November 8", with the year when it isn't the entry's year.
    private func title(for day: PickerDay) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = model.timeZone
        guard let noon = calendar.date(from: DateComponents(year: day.day.year, month: day.day.month, day: day.day.day, hour: 12))
        else { return "" }
        var style = Date.FormatStyle(timeZone: model.timeZone).weekday(.wide).month(.wide).day()
        if day.day.year != model.entryDay.year { style = style.year() }
        return noon.formatted(style)
    }

    // MARK: Actions

    private func useSystemPicker() {
        onUseSystemPicker()
        dismiss()
    }

    private func openSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    private func chooseMoreToShare() {
        guard let presenter = Self.topViewController() else { return }
        PHPhotoLibrary.shared().presentLimitedLibraryPicker(from: presenter) { _ in
            Task { @MainActor in await model.load() }
        }
    }

    private static func topViewController() -> UIViewController? {
        let scenes = UIApplication.shared.connectedScenes.compactMap { $0 as? UIWindowScene }
        var top = (scenes.first { $0.activationState == .foregroundActive } ?? scenes.first)?.keyWindow?.rootViewController
        while let presented = top?.presentedViewController { top = presented }
        return top
    }
}

/// One photo in the grid: its picture, and a number once it is chosen.
private struct PickerCell: View {
    @ObservedObject var model: DayPhotoPickerModel
    let asset: PHAsset
    @Environment(\.displayScale) private var displayScale
    @State private var image: UIImage?

    var body: some View {
        let number = model.number(of: asset.localIdentifier)
        Theme.raised
            .aspectRatio(1, contentMode: .fit)
            .overlay {
                if let image {
                    Image(uiImage: image).resizable().scaledToFill()
                }
            }
            .clipped()
            .overlay {
                if number != nil {
                    Rectangle().strokeBorder(Theme.accent, lineWidth: 3)
                }
            }
            .overlay(alignment: .topTrailing) {
                if let number {
                    Text("\(number)")
                        .font(.system(size: 13, weight: .semibold, design: .serif))
                        .foregroundStyle(Theme.onAccent)
                        .frame(width: 24, height: 24)
                        .background(Circle().fill(Theme.accent))
                        .padding(5)
                }
            }
            .overlay(alignment: .bottomTrailing) {
                if asset.mediaType == .video {
                    VideoLengthTab(text: VideoLink.durationText(seconds: asset.duration))
                        .padding(5)
                }
            }
            .contentShape(Rectangle())
            .onTapGesture { model.toggle(asset.localIdentifier) }
            .task(id: asset.localIdentifier) {
                for await next in model.thumbnails(for: asset, side: 160 * displayScale) { image = next }
            }
            .accessibilityElement()
            .accessibilityLabel(label)
            .accessibilityValue(number.map { "Chosen, number \($0)" } ?? "")
            .accessibilityAddTraits(.isButton)
    }

    private var label: String {
        let kind = asset.mediaType == .video ? "Video" : "Photo"
        guard let date = asset.creationDate else { return kind }
        return "\(kind) from " + date.formatted(date: .omitted, time: .shortened)
    }
}

/// Why the grid isn't showing, and what to do about it.
private struct Explanation: View {
    let title: String
    let message: String
    let primaryTitle: String
    let primary: () -> Void
    let secondaryTitle: String
    let secondary: () -> Void

    var body: some View {
        VStack(spacing: 18) {
            Image(systemName: "photo.on.rectangle.angled")
                .font(.system(size: 44, weight: .light))
                .foregroundStyle(Theme.inkTertiary)
                .accessibilityHidden(true)
            Text(title)
                .font(Theme.serif(.title2, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text(message)
                .font(Theme.serif(.callout))
                .foregroundStyle(Theme.inkSecondary)
                .multilineTextAlignment(.center)
                .frame(maxWidth: 420)
            Button(primaryTitle, action: primary)
                .buttonStyle(.primaryPaper)
            Button(secondaryTitle, action: secondary)
                .buttonStyle(.quietPaper)
        }
        .padding(32)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
    }
}
