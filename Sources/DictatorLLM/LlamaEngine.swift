import Foundation
import llama

/// Embedded llama.cpp inference — no server, no install: drop any GGUF chat
/// model into ~/Library/Application Support/Dictator/llm/ and it is used for
/// AI polish, taking priority over Ollama. Model stays resident after the
/// first use; greedy sampling (temperature 0 equivalent) for determinism.
public enum LlamaEngineError: Error {
    case modelLoadFailed
    case contextFailed
    case templateFailed
    case tokenizeFailed
    case decodeFailed
    case promptTooLong
}

public final class LlamaEngine {
    public static let modelsDirectory = FileManager.default
        .urls(for: .applicationSupportDirectory, in: .userDomainMask)[0]
        .appendingPathComponent("Dictator/llm", isDirectory: true)

    /// Resolves which model to load. A custom path may be a GGUF file (any
    /// extension — Ollama blobs qualify) or a directory to scan. A custom
    /// path that resolves to nothing is an error state, never a silent
    /// fallback to a different model. Empty/nil custom path = scan the
    /// default sideload directory.
    public static func resolveModelURL(customPath: String?) -> URL? {
        if let path = customPath?.trimmingCharacters(in: .whitespaces), !path.isEmpty {
            let expanded = (path as NSString).expandingTildeInPath
            var isDirectory: ObjCBool = false
            guard FileManager.default.fileExists(atPath: expanded, isDirectory: &isDirectory) else {
                return nil
            }
            let url = URL(fileURLWithPath: expanded)
            return isDirectory.boolValue ? firstGGUF(in: url) : url
        }
        return firstGGUF(in: modelsDirectory)
    }

    public static func availableModels(in directory: URL = modelsDirectory) -> [URL] {
        let contents = (try? FileManager.default.contentsOfDirectory(
            at: directory, includingPropertiesForKeys: nil
        )) ?? []
        return contents
            .filter { $0.pathExtension.lowercased() == "gguf" }
            .sorted { $0.lastPathComponent < $1.lastPathComponent }
    }

    private static func firstGGUF(in directory: URL) -> URL? {
        availableModels(in: directory).first
    }

    private static let backendInitialized: Void = llama_backend_init()

    public let modelName: String
    private let model: OpaquePointer
    private let vocab: OpaquePointer
    private let context: OpaquePointer
    private let template: String

    public init(modelURL: URL) throws {
        _ = Self.backendInitialized
        var modelParams = llama_model_default_params()
        modelParams.n_gpu_layers = 99
        guard let model = llama_model_load_from_file(modelURL.path, modelParams) else {
            throw LlamaEngineError.modelLoadFailed
        }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = 4096
        contextParams.n_batch = 4096
        guard let context = llama_init_from_model(model, contextParams) else {
            llama_model_free(model)
            throw LlamaEngineError.contextFailed
        }
        self.model = model
        self.context = context
        self.vocab = llama_model_get_vocab(model)
        if let cTemplate = llama_model_chat_template(model, nil) {
            self.template = String(cString: cTemplate)
        } else {
            self.template = "chatml"
        }
        self.modelName = modelURL.lastPathComponent
    }

    deinit {
        llama_free(context)
        llama_model_free(model)
    }

    public func chat(system: String, user: String, maxTokens: Int = 400) throws -> String {
        let prompt = try applyTemplate(system: system, user: user)
        var tokens = try tokenize(prompt)
        guard tokens.count < 3500 else { throw LlamaEngineError.promptTooLong }

        llama_memory_clear(llama_get_memory(context), true)
        // The batch stores the token pointer and llama_decode reads it later,
        // so the storage must stay pinned across BOTH calls — a bare &tokens
        // is only valid for the batch_get_one call itself and crashes in
        // release builds (stale stack slot → garbage token ids → ggml abort).
        let promptStatus = tokens.withUnsafeMutableBufferPointer { buffer in
            llama_decode(context, llama_batch_get_one(buffer.baseAddress, Int32(buffer.count)))
        }
        guard promptStatus == 0 else { throw LlamaEngineError.decodeFailed }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw LlamaEngineError.decodeFailed
        }
        defer { llama_sampler_free(sampler) }
        llama_sampler_chain_add(sampler, llama_sampler_init_greedy())

        var bytes: [UInt8] = []
        var current: llama_token = 0
        for _ in 0..<maxTokens {
            current = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, current) { break }
            bytes.append(contentsOf: piece(for: current))
            let status = withUnsafeMutablePointer(to: &current) { pointer in
                llama_decode(context, llama_batch_get_one(pointer, 1))
            }
            guard status == 0 else { break }
        }
        return String(decoding: bytes, as: UTF8.self)
    }

    private func applyTemplate(system: String, user: String) throws -> String {
        var cStrings: [UnsafeMutablePointer<CChar>?] = [
            strdup("system"), strdup(system), strdup("user"), strdup(user),
        ]
        defer { cStrings.forEach { free($0) } }
        var messages = [
            llama_chat_message(role: cStrings[0], content: cStrings[1]),
            llama_chat_message(role: cStrings[2], content: cStrings[3]),
        ]
        var size = (system.utf8.count + user.utf8.count) * 2 + 1024
        var buffer = [CChar](repeating: 0, count: size)
        var written = llama_chat_apply_template(
            template, &messages, messages.count, true, &buffer, Int32(size)
        )
        if written > Int32(size) {
            size = Int(written) + 1
            buffer = [CChar](repeating: 0, count: size)
            written = llama_chat_apply_template(
                template, &messages, messages.count, true, &buffer, Int32(size)
            )
        }
        guard written > 0 else { throw LlamaEngineError.templateFailed }
        return String(
            decoding: buffer[0..<Int(written)].map(UInt8.init(bitPattern:)),
            as: UTF8.self
        )
    }

    private func tokenize(_ text: String) throws -> [llama_token] {
        var tokens = [llama_token](repeating: 0, count: text.utf8.count + 16)
        let count = llama_tokenize(
            vocab, text, Int32(text.utf8.count), &tokens, Int32(tokens.count), false, true
        )
        guard count >= 0 else { throw LlamaEngineError.tokenizeFailed }
        return Array(tokens[0..<Int(count)])
    }

    private func piece(for token: llama_token) -> [UInt8] {
        var buffer = [CChar](repeating: 0, count: 256)
        let count = llama_token_to_piece(vocab, token, &buffer, 256, 0, false)
        guard count > 0 else { return [] }
        return buffer[0..<Int(count)].map(UInt8.init(bitPattern:))
    }
}

/// Serializes access to the engine and keeps it loaded across dictations.
public actor LlamaPolisher {
    public static let shared = LlamaPolisher()

    private var engine: LlamaEngine?
    private var loadedFrom: URL?
    private let inferenceQueue = DispatchQueue(label: "dictator.llama", qos: .userInitiated)

    /// Loads the model so the first dictation doesn't pay the multi-second
    /// model load.
    public func warmUp(modelURL: URL) {
        _ = try? loadedEngine(modelURL: modelURL)
    }

    public func polish(
        _ text: String,
        context: DictationContext,
        tone: String,
        modelURL: URL
    ) async throws -> String {
        let engine = try loadedEngine(modelURL: modelURL)
        let system = PolishPrompt.system
        let user = PolishPrompt.user(text: text, context: context, tone: tone)
        return try await withCheckedThrowingContinuation { continuation in
            inferenceQueue.async {
                do {
                    continuation.resume(returning: try engine.chat(system: system, user: user))
                } catch {
                    continuation.resume(throwing: error)
                }
            }
        }
    }

    private func loadedEngine(modelURL: URL) throws -> LlamaEngine {
        if engine == nil || loadedFrom != modelURL {
            NSLog("Dictator: loading embedded LLM %@", modelURL.lastPathComponent)
            engine = try LlamaEngine(modelURL: modelURL)
            loadedFrom = modelURL
        }
        return engine!
    }
}
