import Foundation

enum TemplateComposer {
    /// Turns answers into the entry text. Unanswered questions are left out.
    /// `answers` lines up with `template.cleanQuestions`.
    static func body(for template: EntryTemplate, answers: [String]) -> String {
        var sections: [String] = []
        for (index, question) in template.cleanQuestions.enumerated() {
            let answer = index < answers.count
                ? answers[index].trimmingCharacters(in: .whitespacesAndNewlines)
                : ""
            guard !answer.isEmpty else { continue }
            sections.append("## \(question)\n\n\(answer)")
        }
        return sections.isEmpty ? "" : sections.joined(separator: "\n\n") + "\n"
    }
}
