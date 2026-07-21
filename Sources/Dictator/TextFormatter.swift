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
        // Spoken "quote … unquote/end quote" becomes real quotation marks,
        // with the trailing punctuation tucked inside. Only fires when both
        // halves appear on one line, so a lone "quote" stays a word.
        result = result.replacingOccurrences(
            of: "\\bquote[,:.]?\\s+([^\\n]+?)[,.]?\\s+(?:unquote|end ?quote)\\b([.!?]?)",
            with: "\u{0022}$1$2\u{0022}",
            options: [.regularExpression, .caseInsensitive]
        )
        let boundary = "(?:^|(?<=[,.!?;:\u{2013}\u{2014}\"'\u{201D}\u{2019}-]))"
        // Narration lead-ins ("and then new paragraph") are absorbed into the
        // command. The command must end at trailing punctuation, the end of
        // text, or a capitalized next word (the ASR starts a fresh sentence
        // after the command's pause even when it drops the period) — so noun
        // uses like "new line items" never convert.
        let leadIn = "(?:(?:and|then|now|okay|so)[\\s,]+){0,3}"
        let commandEnd = "(?:\\s*[.,!?]+\\s*|\\s+(?=[A-Z])|\\s*$)"
        let commands: [(pattern: String, insert: String)] = [
            (boundary + "\\s*" + leadIn + "(?:new[\\s,]+)+paragraph\\b" + commandEnd, "\n\n"),
            (boundary + "\\s*" + leadIn + "(?:new[\\s,]+)+line\\b" + commandEnd, "\n"),
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
