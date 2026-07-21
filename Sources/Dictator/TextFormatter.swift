import Foundation

/// Stage-1 deterministic formatting: always on, sub-millisecond.
/// The optional LLM pass (M4) runs after this, never instead of it.
struct DeterministicFormatter {
    static let fillers: Set<String> = ["um", "uh", "uhm", "erm"]

    func format(_ raw: String) -> String {
        let settings = SettingsStore.shared
        var text = raw

        if settings.removeFillers {
            text = stripFillers(text)
        }

        for replacement in settings.replacements {
            let from = replacement.from.trimmingCharacters(in: .whitespaces)
            guard !from.isEmpty else { continue }
            let pattern = "\\b\(NSRegularExpression.escapedPattern(for: from))\\b"
            text = text.replacingOccurrences(
                of: pattern,
                with: NSRegularExpression.escapedTemplate(for: replacement.to),
                options: [.regularExpression, .caseInsensitive]
            )
        }

        if settings.spokenCommands {
            text = applySpokenCommands(text)
        }

        text = text.replacingOccurrences(of: " {2,}", with: " ", options: .regularExpression)
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private func stripFillers(_ text: String) -> String {
        let words = text.split(separator: " ").filter { word in
            !Self.fillers.contains(
                word.lowercased().trimmingCharacters(in: .punctuationCharacters)
            )
        }
        return words.joined(separator: " ")
    }

    /// "new line" / "new paragraph" become actual breaks. A phrase only
    /// counts as a command when it stands alone — immediately after
    /// punctuation (how the ASR renders the pause around a spoken command)
    /// or at the start of the dictation. Mid-sentence mentions ("this should
    /// be a new paragraph") keep their words, and stuttered repeats
    /// ("new new paragraph") collapse into one command.
    private func applySpokenCommands(_ text: String) -> String {
        var result = text
        let boundary = "(?:^|(?<=[,.!?;:\u{2013}\u{2014}\"'\u{201D}\u{2019}-]))"
        let commands: [(pattern: String, insert: String)] = [
            (boundary + "\\s*(?:new[\\s,]+)+paragraph\\b[,.!?]?\\s*", "\n\n"),
            (boundary + "\\s*(?:new[\\s,]+)+line\\b[,.!?]?\\s*", "\n"),
        ]
        for command in commands {
            result = result.replacingOccurrences(
                of: command.pattern,
                with: command.insert,
                options: [.regularExpression, .caseInsensitive]
            )
        }
        return capitalizeAfterBreaks(result)
    }

    private func capitalizeAfterBreaks(_ text: String) -> String {
        let lines = text.components(separatedBy: "\n").map { line -> String in
            guard let first = line.first, first.isLowercase else { return line }
            return first.uppercased() + line.dropFirst()
        }
        return lines.joined(separator: "\n")
    }
}
