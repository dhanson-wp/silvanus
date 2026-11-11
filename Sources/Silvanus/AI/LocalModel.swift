import Foundation
import SilvanusKit
import llama

enum LocalModelError: LocalizedError {
    case noModel
    case cannotLoad(String)
    case tooLong
    case failed(String)

    var errorDescription: String? {
        switch self {
        case .noModel: "There's no model yet. Download one in Settings > Summaries."
        case let .cannotLoad(name): "Unable to load the model \(name)."
        case .tooLong: "This is too long for the model to read at once."
        case let .failed(step): "The model stopped while \(step)."
        }
    }
}

/// The local model that writes to-dos and summaries: a GGUF file run by llama.cpp on
/// this Mac's GPU. Nothing is sent anywhere. One request at a time; the model stays
/// loaded between requests until `unload()`, which gives its memory back.
actor LocalModel {
    static let shared = LocalModel()

    /// One request, start to finish: loads the model file, answers, and gives the memory
    /// back. What the app's features call; a connector to another model would replace it.
    @MainActor static func ask(system: String, user: String) async throws -> String {
        guard let file = file() else { throw LocalModelError.noModel }
        try await shared.load(file.url)
        do {
            let answer = try await shared.answer(system: system, user: user)
            await shared.unload()
            return answer
        } catch {
            await shared.unload()
            throw error
        }
    }

    private var model: OpaquePointer?
    private var loaded: URL?
    private static let started: Void = {
        // Quiet: llama.cpp logs every layer to stderr otherwise.
        llama_log_set({ _, _, _ in }, nil)
        llama_backend_init()
    }()

    /// The model file in use: Settings' choice, or one Silvanus downloaded (the one
    /// recommended for this Mac first). `APP_MODEL_FILE` picks a file for the headless commands.
    @MainActor static func file() -> LocalModelFile.Found? {
        let env = ProcessInfo.processInfo.environment["APP_MODEL_FILE"].flatMap { $0.isEmpty ? nil : ($0 as NSString).expandingTildeInPath }
        // Test, snapshot, and self-test runs never load a model on their own: it's gigabytes.
        if AppDefaults.isTest, env == nil, ProcessInfo.processInfo.environment["APP_ASK"] == nil { return nil }
        return LocalModelFile.find(chosen: env ?? AppDefaults.shared.string(forKey: AppDefaults.modelFileKey),
                                   folder: SummaryModels.defaultFolder,
                                   models: LocalModelCatalog.ordered(physicalMemory: ProcessInfo.processInfo.physicalMemory))
    }

    /// Loads `url` unless it's already loaded.
    func load(_ url: URL) throws {
        if loaded == url, model != nil { return }
        unload()
        _ = Self.started
        var params = llama_model_default_params()
        params.n_gpu_layers = -1
        guard let model = llama_model_load_from_file(url.path, params) else {
            throw LocalModelError.cannotLoad(url.deletingPathExtension().lastPathComponent)
        }
        self.model = model
        loaded = url
    }

    func unload() {
        if let model { llama_model_free(model) }
        model = nil
        loaded = nil
    }

    /// The model's answer to `user`, following `system`. Stops at the model's own end, or
    /// after `maxTokens`. `onText` gets the answer so far as it grows.
    func answer(system: String = "", user: String, maxTokens: Int = 1024,
                onText: (@Sendable (String) -> Void)? = nil) throws -> String {
        guard let model else { throw LocalModelError.noModel }
        let vocab = llama_model_get_vocab(model)
        let prompt = Self.prompt(model: model, system: system, user: user)
        var tokens = [llama_token](repeating: 0, count: prompt.utf8.count + 16)
        let count = llama_tokenize(vocab, prompt, Int32(prompt.utf8.count), &tokens, Int32(tokens.count), true, true)
        guard count > 0 else { throw LocalModelError.failed("reading the request") }
        tokens.removeSubrange(Int(count)...)

        // Room for the request and the answer, no more: the context's memory grows with it.
        let needed = tokens.count + maxTokens + 64
        guard needed <= Int(llama_model_n_ctx_train(model)) else { throw LocalModelError.tooLong }
        var contextParams = llama_context_default_params()
        contextParams.n_ctx = UInt32((needed + 1023) / 1024 * 1024)
        contextParams.n_batch = 2048
        contextParams.no_perf = true
        guard let context = llama_init_from_model(model, contextParams) else { throw LocalModelError.failed("starting") }
        defer { llama_free(context) }

        var index = 0
        while index < tokens.count {
            let end = min(index + Int(contextParams.n_batch), tokens.count)
            let status = tokens[index..<end].withUnsafeMutableBufferPointer {
                llama_decode(context, llama_batch_get_one($0.baseAddress, Int32($0.count)))
            }
            guard status == 0 else { throw LocalModelError.failed("reading the request") }
            index = end
        }

        guard let sampler = llama_sampler_chain_init(llama_sampler_chain_default_params()) else {
            throw LocalModelError.failed("starting")
        }
        defer { llama_sampler_free(sampler) }
        // Close to the likeliest words: these are notes, not stories.
        llama_sampler_chain_add(sampler, llama_sampler_init_top_k(40))
        llama_sampler_chain_add(sampler, llama_sampler_init_top_p(0.9, 1))
        llama_sampler_chain_add(sampler, llama_sampler_init_temp(0.2))
        llama_sampler_chain_add(sampler, llama_sampler_init_dist(1))

        var bytes: [UInt8] = []
        var piece = [CChar](repeating: 0, count: 256)
        for _ in 0..<maxTokens {
            try Task.checkCancellation()
            var token = llama_sampler_sample(sampler, context, -1)
            if llama_vocab_is_eog(vocab, token) { break }
            let length = llama_token_to_piece(vocab, token, &piece, Int32(piece.count), 0, true)
            if length > 0 { bytes.append(contentsOf: piece[..<Int(length)].map { UInt8(bitPattern: $0) }) }
            if let onText { onText(String(decoding: bytes, as: UTF8.self)) }
            guard llama_decode(context, llama_batch_get_one(&token, 1)) == 0 else {
                throw LocalModelError.failed("writing")
            }
        }
        return LocalModelText.cleaned(String(decoding: bytes, as: UTF8.self))
    }

    /// The request in the model's own chat format: Gemma 4's and Gemma 3's are written
    /// here (llama.cpp doesn't know Gemma 4's template), any other by llama.cpp from the
    /// file's template, and Gemma 3's when that fails.
    private static func prompt(model: OpaquePointer, system: String, user: String) -> String {
        let fallback = LocalModelText.gemmaPrompt(system: system, user: user)
        guard let template = llama_model_chat_template(model, nil) else { return fallback }
        switch LocalModelText.format(template: String(cString: template)) {
        case let .gemma4(closesThinking):
            return LocalModelText.gemma4Prompt(system: system, user: user, closesThinking: closesThinking)
        case .gemma3: return fallback
        case .other: break
        }
        let turns = (system.isEmpty ? [] : [("system", system)]) + [("user", user)]
        let strings = turns.map { (strdup($0.0), strdup($0.1)) }
        defer { strings.forEach { free($0.0); free($0.1) } }
        let messages = strings.map { llama_chat_message(role: $0.0, content: $0.1) }
        var buffer = [CChar](repeating: 0, count: 2 * (system.utf8.count + user.utf8.count) + 1024)
        let length = llama_chat_apply_template(template, messages, messages.count, true, &buffer, Int32(buffer.count))
        guard length > 0, Int(length) <= buffer.count else { return fallback }
        return String(decoding: buffer[..<Int(length)].map { UInt8(bitPattern: $0) }, as: UTF8.self)
    }
}
