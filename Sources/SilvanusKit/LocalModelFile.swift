import Foundation

/// Which model file writes to-dos and summaries. The model is a GGUF file on this Mac:
/// the one chosen in Settings, or else one another app already downloaded, so it isn't
/// downloaded twice. Nothing here opens the file.
public enum LocalModelFile {
    /// Where a model came from.
    public enum Source: Equatable, Sendable {
        /// Chosen in Settings.
        case chosen
        /// Found in another app's folder; the name is that app's.
        case shared(String)
    }

    public struct Found: Equatable, Sendable {
        public var url: URL
        public var source: Source

        public init(url: URL, source: Source) { self.url = url; self.source = source }

        /// The file's name without ".gguf", as Settings shows it.
        public var name: String { url.deletingPathExtension().lastPathComponent }
    }

    /// Folders where other apps keep GGUF models, under the home folder.
    public static let sharedFolders: [(app: String, path: String)] = [
        ("Biscotti", "Library/Application Support/Biscotti/llms"),
    ]

    /// The model to use: `chosen` when that file exists, else the largest GGUF file in
    /// the first shared folder that has one. Nil when there's none.
    public static func find(chosen: String?, home: URL, files: FileManager = .default) -> Found? {
        if let chosen, !chosen.isEmpty, files.fileExists(atPath: chosen) {
            return Found(url: URL(fileURLWithPath: chosen), source: .chosen)
        }
        for folder in sharedFolders {
            let url = home.appendingPathComponent(folder.path)
            let found = (try? files.contentsOfDirectory(at: url, includingPropertiesForKeys: [.fileSizeKey])) ?? []
            let models = found.filter { isModel($0) }
                .map { (url: $0, size: (try? $0.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0) }
                .sorted { ($0.size, $1.url.lastPathComponent) > ($1.size, $0.url.lastPathComponent) }
            if let best = models.first { return Found(url: best.url, source: .shared(folder.app)) }
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
        /// Gemma 4: `<|turn>` and `<turn|>`, with a system turn.
        case gemma4
        /// Gemma 3 and earlier: `<start_of_turn>` and `<end_of_turn>`.
        case gemma3
        /// Anything else: llama.cpp formats it from the file's own template.
        case other
    }

    /// The format a model file's own chat template asks for. llama.cpp doesn't know
    /// Gemma 4's template, so it's recognized here by its turn marker.
    public static func format(template: String?) -> Format {
        guard let template else { return .other }
        if template.contains("<|turn>") { return .gemma4 }
        if template.contains("<start_of_turn>") { return .gemma3 }
        return .other
    }

    /// Gemma 4's turn format with thinking off: the empty thought channel at the end
    /// tells the model to answer right away. No start-of-text marker: the tokenizer adds it.
    public static func gemma4Prompt(system: String, user: String) -> String {
        let system = system.trimmingCharacters(in: .whitespacesAndNewlines)
        let user = user.trimmingCharacters(in: .whitespacesAndNewlines)
        let lead = system.isEmpty ? "" : "<|turn>system\n\(system)<turn|>\n"
        return "\(lead)<|turn>user\n\(user)<turn|>\n<|turn>model\n<|channel>thought\n<channel|>"
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
