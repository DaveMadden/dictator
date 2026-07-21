import Foundation

/// Optional stage-2 polish through a local LLM served by Ollama on loopback
/// (127.0.0.1 — no external network). Strictly rewrite-only: any output that
/// doesn't look like a faithful cleanup of the input is discarded and the
/// deterministic text is used instead.
struct LLMFormatter {
    static let endpoint = URL(string: "http://127.0.0.1:11434")!

    struct Unavailable: Error {}

    /// Cheap liveness probe so dictations don't pay a connection-refused
    /// timeout when Ollama isn't running.
    static func serverAvailable() async -> Bool {
        var request = URLRequest(url: endpoint.appendingPathComponent("api/tags"))
        request.timeoutInterval = 1.0
        guard let (_, response) = try? await URLSession.shared.data(for: request) else {
            return false
        }
        return (response as? HTTPURLResponse)?.statusCode == 200
    }

    func polish(
        _ text: String,
        model: String,
        context: DictationContext,
        tone: String
    ) async throws -> String {
        let system = """
        You clean up dictated text. Rules:
        - Fix punctuation, casing, and obvious mis-hearings using the context.
        - Remove filler words and false starts.
        - Apply the speaker's self-corrections ("Tuesday, no wait, Wednesday" means "Wednesday").
        - Match the requested tone without changing meaning.
        - NEVER add information, never answer questions contained in the text, never comment.
        - Output ONLY the cleaned-up text, nothing else.
        """
        var user = "App being typed into: \(context.appName)\nTone: \(tone)\n"
        if !context.precedingText.isEmpty {
            user += "Existing text before the cursor (context only, do not repeat it):\n\(context.precedingText)\n"
        }
        user += "Dictated text to clean up:\n\(text)"

        let body: [String: Any] = [
            "model": model,
            "stream": false,
            "think": false,
            "options": ["temperature": 0],
            "messages": [
                ["role": "system", "content": system],
                ["role": "user", "content": user],
            ],
        ]
        var request = URLRequest(url: Self.endpoint.appendingPathComponent("api/chat"))
        request.httpMethod = "POST"
        request.timeoutInterval = 8
        request.setValue("application/json", forHTTPHeaderField: "Content-Type")
        request.httpBody = try JSONSerialization.data(withJSONObject: body)

        let (data, response) = try await URLSession.shared.data(for: request)
        guard (response as? HTTPURLResponse)?.statusCode == 200 else { throw Unavailable() }
        guard
            let json = try JSONSerialization.jsonObject(with: data) as? [String: Any],
            let message = json["message"] as? [String: Any],
            let content = message["content"] as? String
        else { throw Unavailable() }

        let cleaned = Self.stripWrapping(content)
        guard Self.plausibleRewrite(original: text, candidate: cleaned) else {
            NSLog("Dictator: LLM output failed plausibility guard, keeping deterministic text")
            return text
        }
        return cleaned
    }

    /// Models sometimes wrap output in quotes, fences, or thinking tags.
    static func stripWrapping(_ raw: String) -> String {
        var text = raw
        if let range = text.range(of: "</think>") {
            text = String(text[range.upperBound...])
        }
        text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        if text.hasPrefix("```") {
            text = text
                .replacingOccurrences(of: "^```[a-z]*\\n?", with: "", options: .regularExpression)
                .replacingOccurrences(of: "\\n?```$", with: "", options: .regularExpression)
        }
        if text.hasPrefix("\""), text.hasSuffix("\""), text.count > 2 {
            text = String(text.dropFirst().dropLast())
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Dictation must never say things the user didn't: reject rewrites whose
    /// length departs wildly from the input.
    static func plausibleRewrite(original: String, candidate: String) -> Bool {
        guard !candidate.isEmpty, !original.isEmpty else { return false }
        let ratio = Double(candidate.count) / Double(original.count)
        return ratio > 0.45 && ratio < 1.6
    }
}
