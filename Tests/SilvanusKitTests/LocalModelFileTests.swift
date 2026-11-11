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
    private let shared = "Library/Application Support/Biscotti/llms"

    @Test("With nothing chosen and nothing downloaded, there's no model")
    func noModel() {
        #expect(LocalModelFile.find(chosen: nil, home: Home().url) == nil)
    }

    @Test("A model another app downloaded is used, and says whose it is")
    func sharedModelIsFound() {
        let home = Home()
        let file = home.file("\(shared)/gemma-small.gguf")
        let found = LocalModelFile.find(chosen: nil, home: home.url)
        #expect(found?.url.lastPathComponent == file.lastPathComponent)
        #expect(found?.source == .shared("Biscotti"))
        #expect(found?.name == "gemma-small")
    }

    @Test("The chosen file wins over a shared one")
    func chosenWins() {
        let home = Home()
        home.file("\(shared)/gemma-small.gguf")
        let mine = home.file("Models/other.gguf")
        let found = LocalModelFile.find(chosen: mine.path, home: home.url)
        #expect(found?.url.path == mine.path)
        #expect(found?.source == .chosen)
    }

    @Test("A chosen file that's gone falls back to the shared one")
    func missingChoiceFallsBack() {
        let home = Home()
        home.file("\(shared)/gemma-small.gguf")
        let found = LocalModelFile.find(chosen: home.url.appendingPathComponent("gone.gguf").path, home: home.url)
        #expect(found?.source == .shared("Biscotti"))
    }

    @Test("Of several shared models the largest is used; other files are ignored")
    func largestSharedModel() {
        let home = Home()
        home.file("\(shared)/small.gguf", bytes: 10)
        home.file("\(shared)/large.gguf", bytes: 1000)
        home.file("\(shared)/larger.gguf.download", bytes: 5000)
        home.file("\(shared)/.hidden.gguf", bytes: 5000)
        #expect(LocalModelFile.find(chosen: nil, home: home.url)?.name == "large")
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
        #expect(LocalModelText.gemma4Prompt(system: "", user: " Hi \n")
            == "<|turn>user\nHi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        #expect(LocalModelText.gemma4Prompt(system: "Be brief.\n", user: "Hi")
            == "<|turn>system\nBe brief.<turn|>\n<|turn>user\nHi<turn|>\n<|turn>model\n<|channel>thought\n<channel|>")
        #expect(!LocalModelText.gemma4Prompt(system: "Be brief.", user: "Hi").contains("<bos>"))
    }

    @Test("The format follows the model file's own template")
    func formatFromTemplate() {
        #expect(LocalModelText.format(template: "{{ bos_token }}<|turn>system ...<turn|>") == .gemma4)
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
