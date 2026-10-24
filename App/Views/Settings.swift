import SwiftUI
import UniformTypeIdentifiers

// MARK: - Settings

struct SettingsView: View {
    @Environment(AppModel.self) private var model
    @Environment(LockManager.self) private var lock
    @EnvironmentObject private var prefs: AppPrefs
    @Environment(\.dismiss) private var dismiss

    @State private var showFolderPicker = false
    @State private var lockProblem: String?

    private var lockBinding: Binding<Bool> {
        Binding(
            get: { prefs.lockEnabled },
            set: { wantsLock in
                if wantsLock && !LockManager.canAuthenticate {
                    lockProblem = "Set a passcode on this device first. Lamplight uses it, and Face ID, to lock your journal."
                } else {
                    prefs.lockEnabled = wantsLock
                    if !wantsLock { lock.forceUnlock() }
                }
            }
        )
    }

    private var version: String {
        let info = Bundle.main.infoDictionary
        let short = info?["CFBundleShortVersionString"] as? String ?? "0.1.0"
        let build = info?["CFBundleVersion"] as? String ?? "1"
        return "\(short) (\(build))"
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    Toggle("Lock with \(LockManager.methodName)", isOn: lockBinding)
                    if prefs.lockEnabled {
                        Picker("Lock", selection: $prefs.lockTimeout) {
                            ForEach(LockTimeout.allCases) { timeout in
                                Text(timeout.title).tag(timeout)
                            }
                        }
                    }
                } header: {
                    Text("Privacy")
                } footer: {
                    Text("If Face ID doesn't work, your device passcode opens it. When the app isn't in front, its contents are hidden.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Picker("Look", selection: $prefs.appearance) {
                        ForEach(AppearanceChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                } header: {
                    Text("Appearance")
                } footer: {
                    Text("Lamp is a dark, warm page that's gentle at night.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    Toggle("Open to a new entry", isOn: $prefs.openToNewEntry)
                    Picker("New day starts at", selection: $prefs.rolloverHour) {
                        Text("Midnight").tag(0)
                        Text("2 AM").tag(2)
                        Text("4 AM").tag(4)
                    }
                    NavigationLink {
                        HomeEditorView(current: model.settings.home)
                    } label: {
                        LabeledContent("Home", value: model.settings.home?.name ?? "Not set")
                    }
                } header: {
                    Text("Writing")
                } footer: {
                    Text("Opening the app starts a new entry if you haven't written yet today. Nothing is saved until you type. If you write after midnight, entries before this hour count toward the day before. That keeps your streak going.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    NavigationLink("Journals") { JournalsSettingsView() }
                    NavigationLink("Recently Deleted") { RecentlyDeletedView() }
                }
                .listRowBackground(Theme.surface)

                Section {
                    LabeledContent("Journal location", value: model.storageName)
                    Button("Choose a Different Folder…") { showFolderPicker = true }
                    Button("Refresh Now") {
                        Task { @MainActor in await model.refresh() }
                    }
                } header: {
                    Text("Storage")
                } footer: {
                    Text("Your entries are Markdown text files and photos in that folder. To use the journal on another device, choose the same iCloud Drive folder there. Switching folders copies your entries across and leaves the old folder as it was.")
                }
                .listRowBackground(Theme.surface)

                Section {
                    LabeledContent("Version", value: version)
                }
                .listRowBackground(Theme.surface)
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("Settings")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("Done") { dismiss() }
                        .font(Theme.serif(.body, weight: .semibold))
                }
            }
            .sheet(isPresented: $showFolderPicker) {
                FolderPicker { url in
                    showFolderPicker = false
                    model.useFolder(url)
                    dismiss()
                } onCancel: {
                    showFolderPicker = false
                }
            }
            .alert("Can't turn on the lock", isPresented: Binding(
                get: { lockProblem != nil },
                set: { if !$0 { lockProblem = nil } }
            )) {
                Button("OK", role: .cancel) {}
            } message: {
                Text(lockProblem ?? "")
            }
        }
    }
}

// MARK: - Journals

struct JournalsSettingsView: View {
    @Environment(AppModel.self) private var model

    @State private var editing: Journal?
    @State private var blockedDelete = false

    var body: some View {
        List {
            Section {
                ForEach(model.journals) { journal in
                    Button {
                        editing = journal
                    } label: {
                        HStack(spacing: 12) {
                            JournalDot(colorKey: journal.colorKey, size: 12)
                            Text(journal.name)
                                .font(Theme.serif(.body))
                                .foregroundStyle(Theme.ink)
                            Spacer()
                            let count = model.entryCount(in: journal.id)
                            Text(count == 1 ? "1 entry" : "\(count) entries")
                                .font(Theme.serif(.footnote))
                                .foregroundStyle(Theme.inkTertiary)
                        }
                    }
                }
                .onDelete { offsets in
                    // Collect ids first: deleting shifts the indexes.
                    let ids = offsets.map { model.journals[$0].id }
                    for id in ids where !model.deleteJournal(id) {
                        blockedDelete = true
                    }
                }
                .onMove { source, destination in
                    model.moveJournals(from: source, to: destination)
                }
            } footer: {
                Text("A journal can be deleted once it has no entries.")
            }
            .listRowBackground(Theme.surface)

            Section {
                Button {
                    editing = model.newJournal(named: "")
                } label: {
                    Label("Add Journal", systemImage: "plus")
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Journals")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .sheet(item: $editing) { journal in
            JournalEditor(journal: journal)
        }
        .alert("This journal still has entries", isPresented: $blockedDelete) {
            Button("OK", role: .cancel) {}
        } message: {
            Text("Move or delete its entries first. Your last journal can't be deleted.")
        }
    }
}

struct JournalEditor: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    @State private var journal: Journal

    init(journal: Journal) {
        _journal = State(initialValue: journal)
    }

    var body: some View {
        NavigationStack {
            Form {
                Section {
                    TextField("Name", text: $journal.name)
                        .font(Theme.serif(.body))
                } header: {
                    Text("Name")
                }
                .listRowBackground(Theme.surface)

                Section {
                    HStack(spacing: 14) {
                        ForEach(JournalColors.keys, id: \.self) { key in
                            Button {
                                journal.colorKey = key
                            } label: {
                                ZStack {
                                    Circle().fill(Theme.journalColor(key))
                                    if journal.colorKey == key {
                                        Image(systemName: "checkmark")
                                            .font(.footnote.weight(.bold))
                                            .foregroundStyle(Theme.page)
                                    }
                                }
                                .frame(width: 34, height: 34)
                            }
                            .buttonStyle(.plain)
                            .accessibilityLabel(key.capitalized)
                            .accessibilityAddTraits(journal.colorKey == key ? .isSelected : [])
                        }
                    }
                    .padding(.vertical, 4)
                } header: {
                    Text("Color")
                } footer: {
                    Text("A small hint beside the journal's name. The name is always shown too.")
                }
                .listRowBackground(Theme.surface)

                if !model.templates.isEmpty {
                    Section {
                        Picker("New entries start with", selection: $journal.defaultTemplateID) {
                            Text("Ask me").tag(UUID?.none)
                            ForEach(model.templates) { template in
                                Text(template.name).tag(Optional(template.id))
                            }
                        }
                        .font(Theme.serif(.body))
                    } footer: {
                        Text("Pick a template to start every new entry in this journal with it. With Ask me, a new entry offers your templates on the empty page.")
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle(journal.name.isEmpty ? "New Journal" : journal.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("Save") {
                        var saved = journal
                        let trimmed = saved.name.trimmingCharacters(in: .whitespacesAndNewlines)
                        saved.name = trimmed.isEmpty ? "Journal" : trimmed
                        model.save(journal: saved)
                        dismiss()
                    }
                    .font(Theme.serif(.body, weight: .semibold))
                }
            }
        }
        .presentationDetents([.medium, .large])
    }
}

// MARK: - Recently deleted

struct RecentlyDeletedView: View {
    @Environment(AppModel.self) private var model

    @State private var items: [TrashedEntry] = []
    @State private var loaded = false

    private func reload() async {
        items = await model.loadTrash()
        loaded = true
    }

    var body: some View {
        List {
            ForEach(items) { item in
                let summary = item.entry.summary()
                let daysLeft = Fmt.daysLeft(deletedAt: item.deletedAt)
                VStack(alignment: .leading, spacing: 4) {
                    Text(Fmt.fullDate(item.entry))
                        .font(Theme.serif(.headline, weight: .semibold))
                        .foregroundStyle(Theme.ink)
                    if !summary.title.isEmpty {
                        Text(summary.title)
                            .font(Theme.serif(.subheadline))
                            .foregroundStyle(Theme.inkSecondary)
                            .lineLimit(2)
                    }
                    Text(daysLeft == 1 ? "1 day left" : "\(daysLeft) days left")
                        .font(Theme.serif(.caption))
                        .foregroundStyle(Theme.inkTertiary)
                }
                .padding(.vertical, 4)
                .listRowBackground(Theme.surface)
                .swipeActions(edge: .leading) {
                    Button {
                        Task { @MainActor in await model.restore(item.id); await reload() }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    .tint(Theme.sage)
                }
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        Task { @MainActor in await model.deleteForever(item.id); await reload() }
                    } label: {
                        Label("Delete Now", systemImage: "trash")
                    }
                }
                .contextMenu {
                    Button {
                        Task { @MainActor in await model.restore(item.id); await reload() }
                    } label: {
                        Label("Restore", systemImage: "arrow.uturn.backward")
                    }
                    Button(role: .destructive) {
                        Task { @MainActor in await model.deleteForever(item.id); await reload() }
                    } label: {
                        Label("Delete Now", systemImage: "trash")
                    }
                }
            }
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Recently Deleted")
        .navigationBarTitleDisplayMode(.inline)
        .overlay {
            if loaded && items.isEmpty {
                EmptyStateView(
                    systemImage: "trash",
                    title: "Nothing deleted",
                    message: "Entries you delete stay here for 30 days, then they're removed for good."
                )
            }
        }
        .task { await reload() }
    }
}

// MARK: - Folder picker

/// The Files app's folder picker.
struct FolderPicker: UIViewControllerRepresentable {
    var onPick: (URL) -> Void
    var onCancel: () -> Void = {}

    func makeCoordinator() -> Coordinator {
        Coordinator(self)
    }

    func makeUIViewController(context: Context) -> UIDocumentPickerViewController {
        let picker = UIDocumentPickerViewController(forOpeningContentTypes: [.folder], asCopy: false)
        picker.allowsMultipleSelection = false
        picker.delegate = context.coordinator
        return picker
    }

    func updateUIViewController(_ controller: UIDocumentPickerViewController, context: Context) {}

    final class Coordinator: NSObject, UIDocumentPickerDelegate {
        private let parent: FolderPicker

        init(_ parent: FolderPicker) {
            self.parent = parent
        }

        func documentPicker(_ controller: UIDocumentPickerViewController, didPickDocumentsAt urls: [URL]) {
            if let url = urls.first { parent.onPick(url) }
        }

        func documentPickerWasCancelled(_ controller: UIDocumentPickerViewController) {
            parent.onCancel()
        }
    }
}
