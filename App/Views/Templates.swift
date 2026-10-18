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
            ForEach(model.templates) { template in
                let count = template.cleanQuestions.count
                HStack(spacing: 12) {
                    VStack(alignment: .leading, spacing: 4) {
                        Text(template.name)
                            .font(Theme.serif(.headline, weight: .semibold))
                            .foregroundStyle(Theme.ink)
                        Text(count == 1 ? "1 question" : "\(count) questions")
                            .font(Theme.serif(.footnote))
                            .foregroundStyle(Theme.inkSecondary)
                        if let first = template.cleanQuestions.first {
                            Text(first)
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
                    systemImage: "list.bullet.rectangle",
                    title: "No templates yet",
                    message: "A template is a set of questions you answer one at a time. Make one for your evening check-in.",
                    actionTitle: "Create a Template",
                    action: createTemplate
                )
            }
        }
    }
}

/// Shown in the detail column on the Templates screen when none is chosen.
struct TemplatePlaceholder: View {
    var body: some View {
        EmptyStateView(
            systemImage: "list.bullet.rectangle",
            title: "Choose a template",
            message: "Edit its questions here, or tap the pencil beside it to write with it."
        )
        .background(PaperBackground())
    }
}

private struct QuestionItem: Identifiable, Equatable {
    let id = UUID()
    var text: String
}

/// Edit a template's name and questions. Changes are saved as you make them.
struct TemplateEditorView: View {
    @Environment(AppModel.self) private var model
    let templateID: UUID
    var onStart: (EntryTemplate) -> Void
    var onDeleted: () -> Void

    var body: some View {
        if let template = model.template(templateID) {
            TemplateForm(template: template, onStart: onStart, onDeleted: onDeleted)
                .id(templateID)
        } else {
            TemplatePlaceholder()
        }
    }
}

private struct TemplateForm: View {
    @Environment(AppModel.self) private var model
    let template: EntryTemplate
    var onStart: (EntryTemplate) -> Void
    var onDeleted: () -> Void

    @State private var name: String
    @State private var items: [QuestionItem]
    @State private var defaultJournalID: UUID?
    @State private var confirmDelete = false

    init(template: EntryTemplate, onStart: @escaping (EntryTemplate) -> Void, onDeleted: @escaping () -> Void) {
        self.template = template
        self.onStart = onStart
        self.onDeleted = onDeleted
        _name = State(initialValue: template.name)
        _items = State(initialValue: template.questions.map { QuestionItem(text: $0) })
        _defaultJournalID = State(initialValue: template.defaultJournalID)
    }

    private var current: EntryTemplate {
        var updated = template
        let trimmed = name.trimmingCharacters(in: .whitespacesAndNewlines)
        updated.name = trimmed.isEmpty ? "Untitled" : trimmed
        updated.questions = items.map(\.text)
        updated.defaultJournalID = defaultJournalID
        return updated
    }

    private func save() {
        model.save(template: current)
    }

    var body: some View {
        Form {
            Section {
                TextField("Template name", text: $name)
                    .font(Theme.serif(.title3, weight: .semibold))
            } header: {
                Text("Name")
            }
            .listRowBackground(Theme.surface)

            Section {
                ForEach($items) { $item in
                    TextField("Question", text: $item.text, axis: .vertical)
                        .font(Theme.serif(.body))
                        .lineLimit(1...4)
                }
                .onDelete { offsets in
                    items.remove(atOffsets: offsets)
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                }
                Button {
                    items.append(QuestionItem(text: ""))
                } label: {
                    Label("Add Question", systemImage: "plus")
                }
            } header: {
                Text("Questions")
            } footer: {
                Text("You'll answer these one at a time. Blank questions are skipped.")
            }
            .listRowBackground(Theme.surface)

            if model.journals.count > 1 {
                Section {
                    Picker("Write in", selection: $defaultJournalID) {
                        Text("Ask each time").tag(UUID?.none)
                        ForEach(model.journals) { journal in
                            Text(journal.name).tag(Optional(journal.id))
                        }
                    }
                } header: {
                    Text("Journal")
                }
                .listRowBackground(Theme.surface)
            }

            Section {
                Button {
                    onStart(current)
                } label: {
                    Label("Write with This Template", systemImage: "square.and.pencil")
                        .font(Theme.serif(.body, weight: .semibold))
                }
                Button(role: .destructive) {
                    confirmDelete = true
                } label: {
                    Label("Delete Template", systemImage: "trash")
                }
            }
            .listRowBackground(Theme.surface)
        }
        .scrollContentBackground(.hidden)
        .background(PaperBackground())
        .navigationTitle("Edit Template")
        .navigationBarTitleDisplayMode(.inline)
        .toolbar {
            ToolbarItem(placement: .primaryAction) { EditButton() }
        }
        .onChange(of: name) { save() }
        .onChange(of: items) { save() }
        .onChange(of: defaultJournalID) { save() }
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
