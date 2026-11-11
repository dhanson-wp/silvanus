import Foundation
import Testing
@testable import SilvanusKit

/// A made-up home folder in the temp folder, removed when the test ends.
private final class Home {
    let url = FileManager.default.temporaryDirectory.appendingPathComponent("silvanus-home-\(UUID().uuidString)")
    init() { try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true) }
    deinit { try? FileManager.default.removeItem(at: url) }

    @discardableResult func file(_ path: String, bytes: Int = 1) -> URL {
        let file = url.appendingPathComponent(path)
        try? FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        FileManager.default.createFile(atPath: file.path, contents: Data(count: bytes))
        return file
    }
}

@Suite("Local model file") struct LocalModelFileTests {
    private let models = LocalModelCatalog.all
    private func folder(_ home: Home) -> URL { LocalModelFile.folder(home: home.url) }
    private func path(_ model: CatalogModel) -> String { "Library/Application Support/Silvanus/models/\(model.fileName)" }

    @Test("With nothing chosen and nothing downloaded, there's no model")
    func noModel() {
        let home = Home()
        #expect(LocalModelFile.find(chosen: nil, folder: folder(home), models: models) == nil)
    }

    @Test("A model Silvanus downloaded is used, under its catalog name")
    func downloadedModelIsFound() {
        let home = Home()
        let file = home.file(path(LocalModelCatalog.small))
        let found = LocalModelFile.find(chosen: nil, folder: folder(home), models: models)
        #expect(found?.url.lastPathComponent == file.lastPathComponent)
        #expect(found?.source == .downloaded)
        #expect(found?.name == "Gemma 4, small")
    }

    @Test("The chosen file wins over a downloaded one, and shows its file name")
    func chosenWins() {
        let home = Home()
        home.file(path(LocalModelCatalog.small))
        let mine = home.file("Models/other.gguf")
        let found = LocalModelFile.find(chosen: mine.path, folder: folder(home), models: models)
        #expect(found?.url.path == mine.path)
        #expect(found?.source == .chosen)
        #expect(found?.name == "other")
    }

    @Test("A chosen file that's gone falls back to the downloaded one")
    func missingChoiceFallsBack() {
        let home = Home()
        home.file(path(LocalModelCatalog.small))
        let found = LocalModelFile.find(chosen: home.url.appendingPathComponent("gone.gguf").path, folder: folder(home), models: models)
        #expect(found?.source == .downloaded)
    }

    @Test("With both downloaded, the recommended one is used")
    func recommendedFirst() {
        let home = Home()
        home.file(path(LocalModelCatalog.small))
        home.file(path(LocalModelCatalog.large))
        let little = LocalModelCatalog.ordered(physicalMemory: 16_000_000_000)
        let roomy = LocalModelCatalog.ordered(physicalMemory: 32_000_000_000)
        #expect(LocalModelFile.find(chosen: nil, folder: folder(home), models: little)?.name == "Gemma 4, small")
        #expect(LocalModelFile.find(chosen: nil, folder: folder(home), models: roomy)?.name == "Gemma 4, 12B")
    }

    @Test("A download still in progress, and another app's models, are never used")
    func onlyFinishedDownloads() {
        let home = Home()
        home.file("Library/Application Support/Silvanus/models/\(LocalModelCatalog.large.partialName)")
        home.file("Library/Application Support/Silvanus/models/stray.gguf")
        home.file("Library/Application Support/Another App/llms/\(LocalModelCatalog.large.fileName)")
        #expect(LocalModelFile.find(chosen: nil, folder: folder(home), models: models) == nil)
    }

    @Test("The fallback request is in Gemma's turn format")
    func gemmaPrompt() {
        #expect(LocalModelText.gemmaPrompt(system: "", user: "Hi")
            == "<start_of_turn>user\nHi<end_of_turn>\n<start_of_turn>model\n")
        #expect(LocalModelText.gemmaPrompt(system: "Be brief.", user: "Hi")
            == "<start_of_turn>user\nBe brief.\n\nHi<end_of_turn>\n<start_of_turn>model\n")
    }

    @Test("A Gemma 4 request uses its own turn markers, with thinking off")
    func gemma4Prompt() {
        #expect(LocalModelText.gemma4Prompt(system: "", user: " Hi \n", closesThinking: true)
            == "<|turn>user\nHi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        #expect(LocalModelText.gemma4Prompt(system: "Be brief.\n", user: "Hi", closesThinking: true)
            == "<|turn>system\nBe brief.<turn|>\n<|turn>user\nHi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        #expect(!LocalModelText.gemma4Prompt(system: "Be brief.", user: "Hi", closesThinking: true).contains("<bos>"))
    }

    @Test("A Gemma 4 file whose template has no empty thought channel gets none")
    func gemma4PromptWithoutThoughtChannel() {
        #expect(LocalModelText.gemma4Prompt(system: "Be brief.", user: "Hi", closesThinking: false)
            == "<|turn>system\nBe brief.<turn|>\n<|turn>user\nHi<turn|>\n<|turn>model\n")
    }

    @Test("The format follows the model file's own template")
    func formatFromTemplate() {
        // The 12B's template closes an empty thought channel when thinking is off; the small one's doesn't.
        let large = #"{{- '<|turn>model\n' -}}{%- if not enable_thinking -%}{{- '<|channel>thought\n<channel|>' -}}{%- endif -%}"#
        let small = #"{{- '<|channel>thought\n' + thinking_text + '\n<channel|>' -}} ... {{- '<|turn>model\n' -}}"#
        #expect(LocalModelText.format(template: large) == .gemma4(closesThinking: true))
        #expect(LocalModelText.format(template: small) == .gemma4(closesThinking: false))
        #expect(LocalModelText.format(template: "{{ '<start_of_turn>' + role }}") == .gemma3)
        #expect(LocalModelText.format(template: "<|im_start|>user") == .other)
        #expect(LocalModelText.format(template: nil) == .other)
    }

    @Test("The answer drops the model's thinking and turn markers")
    func cleanedAnswer() {
        #expect(LocalModelText.cleaned("<think>hmm</think>\n- [ ] Send the notes<end_of_turn>\n") == "- [ ] Send the notes")
        #expect(LocalModelText.cleaned("  Plain answer.  ") == "Plain answer.")
        #expect(LocalModelText.cleaned("Done.<think>never closed") == "Done.")
        #expect(LocalModelText.cleaned("- [ ] Send the notes<turn|>\n") == "- [ ] Send the notes")
        #expect(LocalModelText.cleaned("<|channel>thought\nlet me see<channel|>Done.<turn|>") == "Done.")
    }
}
