import SwiftUI

/// The list of templates, in the middle column.
struct TemplatesScreen: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    var onStart: (EntryTemplate) -> Void

    private func createTemplate() {
        let template = model.newTemplate()
        model.save(template: template)
        selection = template.id
    }

    var body: some View {
        List(selection: $selection) {
            ForEach(model.templatesByUse()) { template in
                let preview = EntryText.summarize(body: template.body, answersFirst: false, maxPreview: 90)
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(Theme.serif(.headline, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        if !preview.title.isEmpty {
                            Text(preview.title)
                                .font(Theme.serif(.footnote))
                                .foregroundStyle(Theme.inkSecondary)
                                .lineLimit(1)
                        }
                        if !preview.preview.isEmpty {
                            Text(preview.preview)
                                .font(Theme.serif(.caption))
                                .foregroundStyle(Theme.inkTertiary)
                                .lineLimit(1)
                        }
                    }
                    Spacer()
                    Button {
                        onStart(template)
                    } label: {
                        Label("Write", systemImage: "square.and.pencil")
                            .labelStyle(.iconOnly)
                            .font(.title3)
                    }
                    .buttonStyle(.borderless)
                    .tint(Theme.accent)
                    .accessibilityLabel("Write with \(template.name)")
                }
                .padding(.vertical, 6)
                .tag(template.id)
                .entryRowStyle(selected: selection == template.id)
                .swipeActions(edge: .trailing) {
                    Button(role: .destructive) {
                        if selection == template.id { selection = nil }
                        model.deleteTemplate(template.id)
                    } label: {
                        Label("Delete", systemImage: "trash")
                    }
                }
            }
        }
        .listStyle(.plain)
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Templates")
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                Button(action: createTemplate) {
                    Label("New Template", systemImage: "plus")
                }
            }
        }
        .overlay {
            if model.templates.isEmpty {
                EmptyStateView(
                    systemImage: "doc.text",
                    title: "No templates yet",
                    message: "A template is a page you write once, with headings, prompts or checklists. New entries start with a copy of it.",
                    actionTitle: "Create a Template",
                    action: createTemplate
                )
            }
        }
    }
}

/// Shown in the detail column on the Templates screen when none is chosen. It lists your templates itself,
/// so the screen is never just a message, even when the list in the column beside it is out of sight.
struct TemplatePlaceholder: View {
    @Environment(AppModel.self) private var model
    @Binding var selection: UUID?
    var onNew: () -> Void

    var body: some View {
        if model.templates.isEmpty {
            EmptyStateView(
                systemImage: "doc.text",
                title: "No templates yet",
                message: "A template is a page you write once, with headings, prompts or checklists. New entries can start with a copy of it.",
                actionTitle: "New Template",
                action: onNew
            )
            .background(PaperBackground())
        } else {
            ScrollView {
                VStack(alignment: .leading, spacing: 4) {
                    Text("Your templates")
                        .font(Theme.serif(.title2, weight: .bold))
                        .foregroundStyle(Theme.ink)
                        .accessibilityAddTraits(.isHeader)
                    Text("Choose one to edit it. The pencil beside a template in the list starts an entry with it.")
                        .font(Theme.serif(.callout))
                        .foregroundStyle(Theme.inkSecondary)
                        .padding(.bottom, 12)

                    ForEach(model.templatesByUse()) { template in
                        Button {
                            selection = template.id
                        } label: {
                            HStack(spacing: 12) {
                                Label(template.name, systemImage: "doc.text")
                                    .font(Theme.serif(.body))
                                    .foregroundStyle(Theme.ink)
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.footnote)
                                    .foregroundStyle(Theme.inkTertiary)
                            }
                            .padding(.vertical, 13)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        Rectangle().fill(Theme.line).frame(height: 0.5)
                    }

                    Button("New Template", action: onNew)
                        .buttonStyle(.quietPaper)
                        .padding(.top, 16)
                }
                .frame(maxWidth: 520, alignment: .leading)
                .padding(24)
                .frame(maxWidth: .infinity)
            }
            .background(PaperBackground())
        }
    }
}

/// A template, edited as a page. Changes are saved as you make them.
struct TemplateEditorView: View {
    @Environment(AppModel.self) private var model
    let templateID: UUID
    var onStart: (EntryTemplate) -> Void
    var onDeleted: () -> Void

    var body: some View {
        if let template = model.template(templateID) {
            TemplatePage(template: template, onStart: onStart, onDeleted: onDeleted)
                .id(templateID)
        } else {
            // The template was just deleted. The screen goes back to the list in a moment.
            Color.clear.background(PaperBackground())
        }
    }
}

private struct TemplatePage: View {
    @Environment(AppModel.self) private var model
    @Environment(\.scenePhase) private var scenePhase
    let template: EntryTemplate
    var onStart: (EntryTemplate) -> Void
    var onDeleted: () -> Void

    private struct Snapshot: Equatable {
        var name: String
        var text: String
        var journal: UUID?
    }

    @State private var name: String
    @State private var text: String
    @State private var defaultJournalID: UUID?
    @State private var saved: Snapshot
    @State private var confirmDelete = false
    @State private var controller = MarkdownEditorController()

    init(template: EntryTemplate, onStart: @escaping (EntryTemplate) -> Void, onDeleted: @escaping () -> Void) {
        self.template = template
        self.onStart = onStart
        self.onDeleted = onDeleted
        _name = State(initialValue: template.name)
        _text = State(initialValue: template.body)
        _defaultJournalID = State(initialValue: template.defaultJournalID)
        _saved = State(initialValue: Snapshot(name: template.name, text: template.body, journal: template.defaultJournalID))
    }

    private var snapshot: Snapshot {
        Snapshot(name: name, text: text, journal: defaultJournalID)
    }

    private var current: EntryTemplate {
        var updated = template
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? "Untitled" : trimmed
        updated.body = text
        updated.defaultJournalID = defaultJournalID
        return updated
    }

    private func save() {
        // A template deleted a moment ago must not come back from a late save.
        guard model.template(template.id) != nil, snapshot != saved else { return }
        saved = snapshot
        model.save(template: current)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("Template name", text: $name)
                .font(Theme.serif(.title2, weight: .bold))
                .foregroundStyle(Theme.ink)
            Text("New entries start with a copy of this page. Headings, bullets, checklists and quotes all work.")
                .font(Theme.serif(.footnote))
                .foregroundStyle(Theme.inkSecondary)

            MarkdownEditor(text: $text, controller: controller)
                .overlay(alignment: .topLeading) {
                    if text.isEmpty {
                        Text("Write your template here…")
                            .font(Theme.serif(.title3))
                            .foregroundStyle(Theme.inkTertiary)
                            .padding(.top, 8)
                            .allowsHitTesting(false)
                            .accessibilityHidden(true)
                    }
                }
        }
        .frame(maxWidth: Theme.readingWidth)
        .padding(.horizontal, 24)
        .padding(.top, 14)
        .frame(maxWidth: .infinity)
        .background(PaperBackground())
        .navigationTitle("Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItemGroup(placement: .primaryAction) {
                if model.journals.count > 1 {
                    Menu {
                        Picker("Write in", selection: $defaultJournalID) {
                            Text("The current journal").tag(UUID?.none)
                            ForEach(model.journals) { journal in
                                Text(journal.name).tag(Optional(journal.id))
                            }
                        }
                    } label: {
                        Label("Journal", systemImage: "book.closed")
                    }
                }
                Button {
                    save()
                    onStart(current)
                } label: {
                    Label("Write with This Template", systemImage: "square.and.pencil")
                }
                Menu {
                    Button(role: .destructive) {
                        confirmDelete = true
                    } label: {
                        Label("Delete Template", systemImage: "trash")
                    }
                } label: {
                    Label("More", systemImage: "ellipsis.circle")
                }
            }
        }
        // Wait for a pause in typing before saving.
        .task(id: snapshot) {
            try? await Task.sleep(nanoseconds: 600_000_000)
            guard !Task.isCancelled else { return }
            save()
        }
        .onDisappear { save() }
        .onChange(of: scenePhase) {
            if scenePhase != .active { save() }
        }
        .confirmationDialog("Delete this template?", isPresented: $confirmDelete, titleVisibility: .visible) {
            Button("Delete Template", role: .destructive) {
                model.deleteTemplate(template.id)
                onDeleted()
            }
        } message: {
            Text("Entries you already wrote with it are not affected.")
        }
    }
}
