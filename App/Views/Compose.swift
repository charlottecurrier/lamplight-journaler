import SwiftUI

/// The sheet behind "New Entry": a blank page, or one of your templates.
struct ComposeSheet: View {
    @Environment(AppModel.self) private var model
    @Environment(\.dismiss) private var dismiss

    var onCreate: (_ journalID: UUID, _ templateID: UUID?, _ body: String) -> Void

    @State private var journalID: UUID
    @State private var flowTemplate: EntryTemplate?
    /// Answers survive going back to the list, so a slip of the thumb doesn't lose them.
    @State private var answers: [UUID: [String]] = [:]

    init(
        initialJournalID: UUID,
        initialTemplate: EntryTemplate? = nil,
        onCreate: @escaping (_ journalID: UUID, _ templateID: UUID?, _ body: String) -> Void
    ) {
        self.onCreate = onCreate
        _journalID = State(initialValue: initialJournalID)
        _flowTemplate = State(initialValue: initialTemplate)
    }

    private var hasUnsavedAnswers: Bool {
        answers.values.contains { list in list.contains { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty } }
    }

    private func journalForTemplate(_ template: EntryTemplate) -> UUID {
        if let preferred = template.defaultJournalID, model.journal(preferred) != nil { return preferred }
        return journalID
    }

    var body: some View {
        NavigationStack {
            List {
                Section {
                    Button {
                        onCreate(journalID, nil, "")
                    } label: {
                        choiceRow(title: "Blank page", subtitle: "Just start writing", systemImage: "square.and.pencil")
                    }
                }
                .listRowBackground(Theme.surface)

                if !model.templates.isEmpty {
                    Section {
                        ForEach(model.templates) { template in
                            Button {
                                flowTemplate = template
                            } label: {
                                let count = template.cleanQuestions.count
                                choiceRow(
                                    title: template.name,
                                    subtitle: count == 1 ? "1 question" : "\(count) questions",
                                    systemImage: "list.bullet.rectangle"
                                )
                            }
                        }
                    } header: {
                        Text("Templates")
                            .font(Theme.serif(.footnote))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }

                if model.journals.count > 1 {
                    Section {
                        Picker("Journal", selection: $journalID) {
                            ForEach(model.journals) { journal in
                                Text(journal.name).tag(journal.id)
                            }
                        }
                    } header: {
                        Text("Write in")
                            .font(Theme.serif(.footnote))
                            .foregroundStyle(Theme.inkSecondary)
                    }
                    .listRowBackground(Theme.surface)
                }
            }
            .scrollContentBackground(.hidden)
            .background(PaperBackground())
            .navigationTitle("New Entry")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Cancel") { dismiss() }
                }
            }
            .navigationDestination(item: $flowTemplate) { template in
                TemplateFlowView(
                    template: template,
                    answers: Binding(
                        get: {
                            answers[template.id] ?? Array(repeating: "", count: template.cleanQuestions.count)
                        },
                        set: { answers[template.id] = $0 }
                    )
                ) { text in
                    onCreate(journalForTemplate(template), template.id, text)
                }
            }
        }
        .presentationDetents([.medium, .large])
        .interactiveDismissDisabled(hasUnsavedAnswers)
    }

    private func choiceRow(title: String, subtitle: String, systemImage: String) -> some View {
        HStack(spacing: 14) {
            Image(systemName: systemImage)
                .font(.title3)
                .foregroundStyle(Theme.accent)
                .frame(width: 30)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(Theme.serif(.headline, weight: .semibold))
                    .foregroundStyle(Theme.ink)
                Text(subtitle)
                    .font(Theme.serif(.footnote))
                    .foregroundStyle(Theme.inkSecondary)
            }
            Spacer()
            Image(systemName: "chevron.right")
                .font(.footnote)
                .foregroundStyle(Theme.inkTertiary)
        }
        .padding(.vertical, 4)
        .contentShape(Rectangle())
    }
}

/// Answers a template's questions one at a time. When you finish, the answers become the start of an entry.
struct TemplateFlowView: View {
    let template: EntryTemplate
    @Binding var answers: [String]
    var onFinish: (String) -> Void

    @State private var index = 0
    @FocusState private var focused: Bool

    private var questions: [String] { template.cleanQuestions }
    private var isLast: Bool { index >= questions.count - 1 }

    private var currentAnswerIsBlank: Bool {
        guard index < answers.count else { return true }
        return answers[index].trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    var body: some View {
        Group {
            if questions.isEmpty {
                EmptyStateView(
                    systemImage: "list.bullet.rectangle",
                    title: "No questions yet",
                    message: "Add questions to this template from the Templates screen."
                )
            } else {
                page
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(PaperBackground())
        .navigationTitle(template.name)
        .navigationBarTitleDisplayMode(.inline)
    }

    private var page: some View {
        VStack(alignment: .leading, spacing: 20) {
            ProgressDots(count: questions.count, current: index)

            Text(questions[index])
                .font(Theme.serif(.title, weight: .bold))
                .foregroundStyle(Theme.ink)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityAddTraits(.isHeader)

            if index < answers.count {
                TextEditor(text: $answers[index])
                    .font(Theme.serif(.title3))
                    .lineSpacing(7)
                    .foregroundStyle(Theme.ink)
                    .scrollContentBackground(.hidden)
                    .padding(12)
                    .paperCard()
                    .focused($focused)
                    .frame(minHeight: 170, maxHeight: 360)
                    .accessibilityLabel("Your answer")
            }

            HStack {
                if index > 0 {
                    Button("Back") { go(-1) }
                        .buttonStyle(.quietPaper)
                }
                Spacer()
                Button(isLast ? "Finish" : (currentAnswerIsBlank ? "Skip" : "Next")) {
                    if isLast { finish() } else { go(1) }
                }
                .buttonStyle(.primaryPaper)
                .keyboardShortcut(.return, modifiers: .command)
            }

            Spacer(minLength: 0)
        }
        .padding(24)
        .frame(maxWidth: 640)
        .id(index)
        .transition(.opacity)
        .task(id: index) {
            try? await Task.sleep(nanoseconds: 250_000_000)
            focused = true
        }
    }

    private func go(_ step: Int) {
        withAnimation(.easeInOut(duration: 0.3)) {
            index = min(max(index + step, 0), questions.count - 1)
        }
    }

    private func finish() {
        onFinish(TemplateComposer.body(for: template, answers: answers))
    }
}

/// Dots showing where you are in a set of questions.
struct ProgressDots: View {
    let count: Int
    let current: Int

    var body: some View {
        HStack(spacing: 6) {
            ForEach(0..<count, id: \.self) { position in
                Capsule()
                    .fill(position <= current ? Theme.accent : Theme.line)
                    .frame(width: position == current ? 22 : 8, height: 8)
            }
        }
        .animation(.easeInOut(duration: 0.3), value: current)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Question \(current + 1) of \(count)")
    }
}
