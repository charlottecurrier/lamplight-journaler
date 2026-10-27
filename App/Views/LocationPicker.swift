import SwiftUI
import MapKit

/// Pick where an entry was written: nowhere, Home, or any place you search for or type.
struct LocationPickerView: View {
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searcher = PlaceSearcher()

    let current: EntryLocation?
    let home: EntryLocation?
    var onSelect: (EntryLocation?) -> Void

    @State private var query = ""
    @State private var isResolving = false

    private var typedName: String {
        query.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func choose(_ place: EntryLocation?) {
        onSelect(place)
        dismiss()
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        choose(nil)
                    } label: {
                        row(title: "No place", systemImage: "mappin.slash", selected: current == nil)
                    }
                    if let home {
                        Button {
                            choose(home)
                        } label: {
                            row(title: home.name, subtitle: "Home", systemImage: "house", selected: current?.isHome == true)
                        }
                    } else {
                        Text("Set your Home in Settings to add it here with one tap.")
                            .font(Theme.serif(.footnote))
                            .foregroundStyle(Theme.inkTertiary)
                    }
                }
                .listRowBackground(Theme.surface)

                Section {
                    TextField("Search or type a place", text: $query)
                        .font(Theme.serif(.body))
                        .autocorrectionDisabled()
                        .submitLabel(.done)
                    if !typedName.isEmpty {
                        Button {
                            choose(EntryLocation(name: typedName))
                        } label: {
                            row(title: "Use “\(typedName)”", systemImage: "pencil", selected: false)
                        }
                    }
                    ForEach(searcher.suggestions, id: \.self) { suggestion in
                        Button {
                            Task { @MainActor in
                                isResolving = true
                                let place = await searcher.resolve(suggestion)
                                isResolving = false
                                choose(place)
                            }
                        } label: {
                            row(title: suggestion.title, subtitle: suggestion.subtitle, systemImage: "mappin", selected: false)
                        }
                    }
                } header: {
                    Text("Find a place")
                        .font(Theme.serif(.footnote))
                        .foregroundStyle(Theme.inkSecondary)
                } footer: {
                    Text("Suggestions come from Apple Maps. Only the text you type here is sent.")
                        .font(Theme.serif(.caption))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("Place")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .overlay {
                if isResolving { ProgressView() }
            }
            .onChange(of: query) { searcher.update(query: query) }
        }
        .presentationDetents([.medium, .large])
    }

    private func row(title: String, subtitle: String? = nil, systemImage: String, selected: Bool) -> some View {
        HStack(spacing: 12) {
            PaperIcon(systemImage)
                .foregroundStyle(Theme.accent)
                .frame(width: 24)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.serif(.body))
                    .foregroundStyle(Theme.ink)
                if let subtitle, !subtitle.isEmpty {
                    Text(subtitle)
                        .font(Theme.serif(.caption))
                        .foregroundStyle(Theme.inkTertiary)
                }
            }
            Spacer()
            if selected {
                PaperIcon("checkmark")
                    .foregroundStyle(Theme.accent)
            }
        }
        .contentShape(Rectangle())
    }
}

/// Set up Home once: a name, and optionally where it is. It follows you to your other devices.
struct HomeEditorView: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss
    @StateObject private var searcher = PlaceSearcher()

    @State private var name: String
    @State private var place: EntryLocation?
    @State private var query = ""

    init(current: EntryLocation?) {
        _name = State(initialValue: current?.name ?? "Home")
        _place = State(initialValue: current)
    }

    var body: some View {
        Form {
            Section {
                TextField("Home", text: $name)
                    .font(Theme.serif(.body))
            } header: {
                Text("Name")
            } footer: {
                Text("This is what shows on entries, like “Home” or “Home, Portland”.")
            }
            .listRowBackground(Theme.surface)

            Section {
                if place?.latitude != nil {
                    Label("Location saved", systemImage: "checkmark")
                        .foregroundStyle(Theme.sage)
                }
                TextField("Search for an address", text: $query)
                    .font(Theme.serif(.body))
                    .autocorrectionDisabled()
                ForEach(searcher.suggestions, id: \.self) { suggestion in
                    Button {
                        Task { @MainActor in
                            let found = await searcher.resolve(suggestion)
                            place = found
                            query = ""
                            searcher.update(query: "")
                        }
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text(suggestion.title).foregroundStyle(Theme.ink)
                            if !suggestion.subtitle.isEmpty {
                                Text(suggestion.subtitle)
                                    .font(Theme.serif(.caption))
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                        }
                    }
                }
            } header: {
                Text("Where is it? (optional)")
            } footer: {
                Text("Suggestions come from Apple Maps. Only the text you type here is sent.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button("Save Home") {
                    let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
                    model.setHome(EntryLocation(
                        name: trimmed.isEmpty ? "Home" : trimmed,
                        latitude: place?.latitude,
                        longitude: place?.longitude,
                        isHome: true
                    ))
                    dismiss()
                }
                .font(Theme.serif(.body, weight: .semibold))
                if model.settings.home != nil {
                    Button("Remove Home", role: .destructive) {
                        model.setHome(nil)
                        dismiss()
                    }
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Home")
        .navigationBarTitleDisplayMode(.inline)
        .onChange(of: query) { searcher.update(query: query) }
    }
}
