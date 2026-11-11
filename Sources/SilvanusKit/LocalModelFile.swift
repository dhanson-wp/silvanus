import Foundation

/// Which model file writes to-dos and summaries. The model is a GGUF file on this Mac:
/// the one chosen in Settings, or else one Silvanus downloaded into its own models
/// folder. Nothing here opens the file.
public enum LocalModelFile {
    /// Where a model came from.
    public enum Source: Equatable, Sendable {
        /// A file of the user's own, chosen in Settings.
        case chosen
        /// Downloaded by Silvanus into its models folder.
        case downloaded
    }

    public struct Found: Equatable, Sendable {
        public var url: URL
        public var source: Source
        /// The catalog's name for a downloaded model ("Gemma 4, 12B").
        public var title: String?

        public init(url: URL, source: Source, title: String? = nil) {
            self.url = url
            self.source = source
            self.title = title
        }

        /// What Settings calls it: the catalog's name, or the file's name without ".gguf".
        public var name: String { title ?? url.deletingPathExtension().lastPathComponent }
    }

    /// Silvanus's models folder under `home`: `Library/Application Support/Silvanus/models`.
    public static func folder(home: URL) -> URL {
        home.appendingPathComponent("Library/Application Support/Silvanus/models", isDirectory: true)
    }

    /// The model to use: `chosen` when that file exists, else the first of `models`
    /// (the recommended one first) that's been downloaded into `folder`. Nil when there's
    /// none. A file still downloading has another name, so it's never picked.
    public static func find(chosen: String?, folder: URL, models: [CatalogModel], files: FileManager = .default) -> Found? {
        if let chosen, !chosen.isEmpty, files.fileExists(atPath: chosen) {
            return Found(url: URL(fileURLWithPath: chosen), source: .chosen)
        }
        return downloaded(in: folder, models: models, files: files)
    }

    /// The first of `models` whose file is in `folder`.
    public static func downloaded(in folder: URL, models: [CatalogModel], files: FileManager = .default) -> Found? {
        for model in models {
            let url = folder.appendingPathComponent(model.fileName)
            if files.fileExists(atPath: url.path) { return Found(url: url, source: .downloaded, title: model.name) }
        }
        return nil
    }

    /// A finished GGUF file: not hidden, and not a download still in progress.
    public static func isModel(_ url: URL) -> Bool {
        url.pathExtension.lowercased() == "gguf" && !url.lastPathComponent.hasPrefix(".")
    }
}

/// What the local model is asked, and what's kept of its answer.
public enum LocalModelText {
    /// How a model file wants a request written.
    public enum Format: Equatable, Sendable {
        /// Gemma 4: `<|turn>` and `<turn|>`, with a system turn. `closesThinking` is true
        /// for files whose template ends a request with an empty thought channel when
        /// thinking is off (the 12B does; the small E2B model doesn't).
        case gemma4(closesThinking: Bool)
        /// Gemma 3 and earlier: `<start_of_turn>` and `<end_of_turn>`.
        case gemma3
        /// Anything else: llama.cpp formats it from the file's own template.
        case other
    }

    /// The empty thought channel, as a Gemma 4 template spells it in its own source.
    static let emptyThoughtInTemplate = #"<|channel>thought\n<channel|>"#

    /// The format a model file's own chat template asks for. llama.cpp doesn't know
    /// Gemma 4's template, so it's recognized here by its turn marker.
    public static func format(template: String?) -> Format {
        guard let template else { return .other }
        if template.contains("<|turn>") { return .gemma4(closesThinking: template.contains(emptyThoughtInTemplate)) }
        if template.contains("<start_of_turn>") { return .gemma3 }
        return .other
    }

    /// Gemma 4's turn format with thinking off, as the file's own template writes it:
    /// with `closesThinking`, an empty thought channel at the end tells the model to
    /// answer right away. No start-of-text marker: the tokenizer adds it.
    public static func gemma4Prompt(system: String, user: String, closesThinking: Bool) -> String {
        let system = system.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = system.isEmpty ? "" : "<|turn>system\n\(system)<turn|>\n"
        return "\(lead)<|turn>user\n\(user)<turn|>\n<|turn>model\n" + (closesThinking ? "<|channel>thought\n<channel|>" : "")
    }

    /// Gemma 3's turn format; also the fallback for a file whose template llama.cpp can't use.
    public static func gemmaPrompt(system: String, user: String) -> String {
        let lead = system.isEmpty ? "" : system + "\n\n"
        return "<start_of_turn>user\n\(lead)\(user)<end_of_turn>\n<start_of_turn>model\n"
    }

    /// The answer without the model's thinking or stray turn markers, trimmed.
    public static func cleaned(_ answer: String) -> String {
        var text = answer
        for (open, close) in [("<think>", "</think>"), ("<|channel>thought", "<channel|>")] {
            while let start = text.range(of: open) {
                if let end = text.range(of: close, range: start.upperBound..<text.endIndex) {
                    text.removeSubrange(start.lowerBound..<end.upperBound)
                } else {
                    text.removeSubrange(start.lowerBound..<text.endIndex)
                }
            }
        }
        for marker in ["<end_of_turn>", "<start_of_turn>model", "<start_of_turn>", "<turn|>", "<|turn>model", "<|turn>", "<channel|>"] {
            text = text.replacingOccurrences(of: marker, with: "")
        }
        return text.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}
