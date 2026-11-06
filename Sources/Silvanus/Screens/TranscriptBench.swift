import AppKit
import SilvanusKit
import SwiftUI

/// A headless timing of the Transcript view with a synthetic two-hour transcript (20,000
/// words, fictional), in an off-screen window at the canvas's default size:
///   APP_TRANSCRIPT_BENCH=1 APP_STORE=/tmp/<dir> Silvanus
/// prints the open time (read transcript.json, lay out the blocks, first layout and draw)
/// and the time per scroll step, then quits with 0 when opening took under 300 ms.
enum TranscriptBench {
    static func runHeadlessIfRequested() -> Int32? {
        guard ProcessInfo.processInfo.environment["APP_TRANSCRIPT_BENCH"] == "1" else { return nil }
        setvbuf(stdout, nil, _IOLBF, 0)
        guard Store.isScratch else {
            print("BENCH refused: set APP_STORE to a folder under /tmp")
            return 1
        }
        let library = MeetingLibrary(root: Store.root, trash: { try FileManager.default.removeItem(at: $0) })
        let meeting = Meeting(info: MeetingInfo(id: "bench-two-hours", title: "Acme planning day", start: Date()))
        guard (try? library.save(meeting)) != nil, (try? library.saveTranscript(synthetic(), for: meeting.id)) != nil else {
            print("BENCH couldn't write the transcript")
            return 1
        }
        let size = CGSize(width: Metric.windowDefault.width - Metric.canvasX, height: Metric.windowDefault.height - Metric.headerHeight)
        let window = NSWindow(contentRect: NSRect(origin: CGPoint(x: -6000, y: -6000), size: size),
                              styleMask: [.borderless], backing: .buffered, defer: false)
        window.isReleasedWhenClosed = false
        window.orderFrontRegardless()

        // Open: everything from the file on disk to the first drawn frame.
        let clock = ContinuousClock()
        var words = 0
        let open = clock.measure {
            let reader = MeetingLibrary(root: Store.root)
            let t = reader.readTranscript(id: meeting.id)
            let names = SpeakerNames.resolve(info: meeting.info, defaultMe: AppDefaults.meName)
            let layout = t.map { TranscriptView.Layout($0, me: names.me, them: names.them) }
            words = layout?.words.count ?? 0
            let host = NSHostingView(rootView: TranscriptView(layout: layout).background(Ink.canvas))
            host.frame = NSRect(origin: .zero, size: size)
            window.contentView = host
            host.layoutSubtreeIfNeeded()
            host.display()
        }
        let ms = Double(open.components.attoseconds) / 1e15 + Double(open.components.seconds) * 1000
        print(String(format: "BENCH open %d words: %.1f ms", words, ms))

        // Scroll: 200 steps of 120 pt, then jumps to the middle and the end.
        guard let scroll = window.contentView.flatMap(findScroll) else {
            print("BENCH no scroll view")
            return 1
        }
        var steps: [Double] = []
        func step(to y: CGFloat) {
            let t = clock.measure {
                scroll.contentView.scroll(to: NSPoint(x: 0, y: y))
                scroll.reflectScrolledClipView(scroll.contentView)
                window.contentView?.layoutSubtreeIfNeeded()
                window.contentView?.display()
            }
            steps.append(Double(t.components.attoseconds) / 1e15 + Double(t.components.seconds) * 1000)
        }
        for i in 1...200 { step(to: CGFloat(i) * 120) }
        let height = scroll.documentView?.frame.height ?? 0
        let jumps = [height / 2, height - size.height]
        for y in jumps { step(to: y) }
        let sorted = steps.dropLast(jumps.count).sorted()
        print(String(format: "BENCH scroll 200 steps of 120 pt: median %.2f ms, slowest %.2f ms; jump to middle %.1f ms, to end %.1f ms",
                     sorted[sorted.count / 2], sorted.last ?? 0, steps[steps.count - 2], steps[steps.count - 1]))
        let pass = ms < 300 && words == 20_000
        print("BENCH \(pass ? "PASS" : "FAIL") open under 300 ms")
        return pass ? 0 : 1
    }

    private static func findScroll(_ view: NSView) -> NSScrollView? {
        if let scroll = view as? NSScrollView { return scroll }
        for sub in view.subviews { if let found = findScroll(sub) { return found } }
        return nil
    }

    /// 20,000 words over two hours: turns of 20 to 140 words, alternating sides, with every
    /// 17th word unsure.
    static func synthetic() -> Transcript {
        let vocabulary = ["the", "plan", "export", "ledger", "milestone", "we", "should", "review", "Friday",
                          "launch", "scope", "checklist", "owner", "dates", "and", "then", "agreed", "next"]
        var lines: [TranscriptLine] = []
        var n = 0, time: TimeInterval = 0, turn = 0
        while n < 20_000 {
            let count = min(20_000 - n, 20 + (turn * 37) % 121)
            var words: [Word] = []
            for i in 0..<count {
                let w = vocabulary[(n + i) % vocabulary.count]
                words.append(Word(text: (i + 1) % 12 == 0 ? w + "." : w, start: time, end: time + 0.3,
                                  confidence: (n + i) % 17 == 0 ? 0.45 : 0.95))
                time += 0.36
            }
            lines.append(TranscriptLine(side: turn % 2 == 0 ? .me : .them, words: words))
            n += count
            time += 1.5
            turn += 1
        }
        return Transcript(lines: lines, engine: "bench", processedAt: Date(timeIntervalSince1970: 0))
    }
}
