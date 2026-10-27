import Foundation

/// What a slash command needs to know about "now".
struct SlashContext {
    var now: Date
    var timeZone: TimeZone
    var locale: Locale

    static var current: SlashContext {
        SlashContext(now: Date(), timeZone: .current, locale: .current)
    }
}

/// Typing "/" and a word, then a space, runs a command: "/h2" makes a heading, "/todo" a checklist item,
/// "/today" inserts the date.
enum SlashCommand: String, CaseIterable {
    case h1, h2, h3, h4, h5, h6
    case todo, list, num, quote, line, section, code
    case time, date, today, tomorrow, yesterday, now
    case todayFull = "today-full"
    case tomorrowFull = "tomorrow-full"
    case yesterdayFull = "yesterday-full"
    case nowFull = "now-full"

    var title: String {
        switch self {
        case .h1: return "Heading 1"
        case .h2: return "Heading 2"
        case .h3: return "Heading 3"
        case .h4: return "Heading 4"
        case .h5: return "Heading 5"
        case .h6: return "Heading 6"
        case .todo: return "Checklist"
        case .list: return "Bullet list"
        case .num: return "Numbered list"
        case .quote: return "Quote"
        case .line: return "Divider"
        case .section: return "Section"
        case .code: return "Code block"
        case .time: return "Time"
        case .date, .today: return "Today's date"
        case .tomorrow: return "Tomorrow's date"
        case .yesterday: return "Yesterday's date"
        case .now: return "Date and time"
        case .todayFull: return "Today, in full"
        case .tomorrowFull: return "Tomorrow, in full"
        case .yesterdayFull: return "Yesterday, in full"
        case .nowFull: return "Date and time, in full"
        }
    }

    /// Commands that change the whole line only work at the start of a line.
    var isBlockCommand: Bool {
        switch self {
        case .h1, .h2, .h3, .h4, .h5, .h6, .todo, .list, .num, .quote, .line, .section, .code: return true
        default: return false
        }
    }

    /// Commands whose name starts with what has been typed, shortest first.
    static func matching(_ typed: String) -> [SlashCommand] {
        let prefix = typed.lowercased()
        return allCases
            .filter { $0.rawValue.hasPrefix(prefix) }
            .sorted { ($0.rawValue.count, $0.rawValue) < ($1.rawValue.count, $1.rawValue) }
    }

    // MARK: Finding the command being typed

    /// The "/word" that ends at the caret, if there is one. It has to start the line or follow a space.
    static func typedToken(in doc: MarkdownDocument, caret: Int) -> (range: Range<Int>, name: String)? {
        let line = doc.lines[doc.lineIndex(containing: caret)]
        switch line.kind {
        case .divider, .section, .media, .fence, .code: return nil
        default: break
        }
        var start = caret
        while start > line.range.lowerBound, doc.units[start - 1] != 0x20 { start -= 1 }
        guard start < caret, doc.units[start] == 0x2F else { return nil }
        let name = doc.string((start + 1)..<caret)
        let allowed = name.unicodeScalars.allSatisfy { scalar in
            (scalar.value >= 0x61 && scalar.value <= 0x7A) || (scalar.value >= 0x41 && scalar.value <= 0x5A)
                || (scalar.value >= 0x30 && scalar.value <= 0x39) || scalar.value == 0x2D
        }
        guard allowed else { return nil }
        return (start..<caret, name)
    }

    /// Commands to offer while the person is typing a "/" word. Block commands are left out unless the word starts the line.
    static func suggestions(in text: String, caret: Int) -> [SlashCommand] {
        let doc = MarkdownDocument(text)
        guard let token = typedToken(in: doc, caret: caret) else { return [] }
        let line = doc.lines[doc.lineIndex(containing: caret)]
        let atLineStart = token.range.lowerBound == line.range.lowerBound + line.indent
        return matching(token.name).filter { atLineStart || !$0.isBlockCommand }
    }

    // MARK: Running a command

    /// The edit that runs this command on the "/word" at `token`. Nil if it can't run there.
    func edit(in doc: MarkdownDocument, token: Range<Int>, context: SlashContext = .current) -> TextEdit? {
        let line = doc.lines[doc.lineIndex(containing: token.lowerBound)]
        let atLineStart = token.lowerBound == line.range.lowerBound + line.indent

        func block(_ text: String, caretOffset: Int? = nil) -> TextEdit? {
            guard atLineStart else { return nil }
            let range = line.range.lowerBound..<token.upperBound
            let caret = range.lowerBound + (caretOffset ?? text.utf16.count)
            return TextEdit(range: range, replacement: text, selection: caret..<caret)
        }
        func insert(_ text: String) -> TextEdit {
            let caret = token.lowerBound + text.utf16.count
            return TextEdit(range: token, replacement: text, selection: caret..<caret)
        }

        switch self {
        case .h1: return block("# ")
        case .h2: return block("## ")
        case .h3: return block("### ")
        case .h4: return block("#### ")
        case .h5: return block("##### ")
        case .h6: return block("###### ")
        case .todo: return block(EditorGlyph.uncheckedString + " ")
        case .list: return block(EditorGlyph.bulletString + " ")
        case .num: return block("1. ")
        case .quote: return block("> ")
        case .line: return block("---\n")
        case .section: return block("---  ---", caretOffset: 4)
        case .code: return block("```\n\n```", caretOffset: 4)
        case .time: return insert(format(context, offsetDays: 0, date: .omitted, time: .shortened))
        case .date, .today: return insert(format(context, offsetDays: 0, date: .numeric, time: .omitted))
        case .tomorrow: return insert(format(context, offsetDays: 1, date: .numeric, time: .omitted))
        case .yesterday: return insert(format(context, offsetDays: -1, date: .numeric, time: .omitted))
        case .now: return insert(format(context, offsetDays: 0, date: .numeric, time: .shortened))
        case .todayFull: return insert(format(context, offsetDays: 0, date: .complete, time: .omitted))
        case .tomorrowFull: return insert(format(context, offsetDays: 1, date: .complete, time: .omitted))
        case .yesterdayFull: return insert(format(context, offsetDays: -1, date: .complete, time: .omitted))
        case .nowFull: return insert(format(context, offsetDays: 0, date: .complete, time: .shortened))
        }
    }

    private func format(
        _ context: SlashContext, offsetDays: Int,
        date: Date.FormatStyle.DateStyle, time: Date.FormatStyle.TimeStyle
    ) -> String {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = context.timeZone
        let moment = calendar.date(byAdding: .day, value: offsetDays, to: context.now) ?? context.now
        let style = Date.FormatStyle(
            date: date, time: time, locale: context.locale, calendar: calendar, timeZone: context.timeZone
        )
        return moment.formatted(style)
    }
}
