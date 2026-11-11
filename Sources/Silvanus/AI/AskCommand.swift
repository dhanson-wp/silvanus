import Foundation
import SilvanusKit

/// Headless check of the local model, before any window opens.
///
///   APP_ASK=<question> Silvanus
/// loads the model file (Settings' choice, one another app downloaded, or APP_MODEL_FILE),
/// prints its answer and how long it took, and quits. APP_ASK_FILE=<text file> adds that
/// file's text after the question. Touches no meetings.
enum AskCommand {
    static func runIfRequested() -> Int32? {
        let env = ProcessInfo.processInfo.environment
        guard let question = env["APP_ASK"], !question.isEmpty else { return nil }
        setvbuf(stdout, nil, _IOLBF, 0)
        var user = question
        if let path = env["APP_ASK_FILE"], !path.isEmpty {
            guard let text = try? String(contentsOfFile: (path as NSString).expandingTildeInPath, encoding: .utf8) else {
                print("ASK FAIL no text file at that path")
                return 1
            }
            user += "\n\n" + text
        }
        guard let file = LocalModel.file() else {
            print("ASK FAIL \(LocalModelError.noModel.localizedDescription)")
            return 1
        }
        var code: Int32?
        Task {
            do {
                let clock = ContinuousClock()
                let load = try await clock.measure { try await LocalModel.shared.load(file.url) }
                print("ASK model \(file.name) loaded in \(seconds(load)) s")
                var answer = ""
                let run = try await clock.measure { answer = try await LocalModel.shared.answer(user: user) }
                print("ASK answered in \(seconds(run)) s")
                print(answer)
                await LocalModel.shared.unload()
                code = answer.isEmpty ? 1 : 0
            } catch {
                print("ASK FAIL \(error.localizedDescription)")
                code = 1
            }
        }
        while code == nil { RunLoop.main.run(mode: .default, before: Date().addingTimeInterval(0.05)) }
        return code ?? 1
    }

    private static func seconds(_ d: Duration) -> String {
        String(format: "%.1f", Double(d.components.seconds) + Double(d.components.attoseconds) / 1e18)
    }
}
