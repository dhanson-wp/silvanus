import Foundation
import Testing
@testable import SilvanusKit

@Suite("Summaries") struct SummariesTests {
    @Test("The summary starts at the answer's first heading; fences and lead-ins are dropped")
    func parse() {
        let answer = "Here's the summary:\n```markdown\n## Overview\nAgreed on scope.\n\n## Decisions\n- Launch in March\n```\n"
        #expect(Summaries.parse(answer) == "## Overview\nAgreed on scope.\n\n## Decisions\n- Launch in March\n")
        #expect(Summaries.parse("I can't summarize this.") == "")
    }

    @Test("The request names the reader and carries the transcript")
    func request() {
        let text = Summaries.request(transcript: "[00:01] **Sam Rivera:** Hello.", me: "Sam Rivera")
        #expect(text.contains("The person reading this summary is Sam Rivera."))
        #expect(text.hasSuffix("**Sam Rivera:** Hello."))
    }

    @Test("An empty summary.md gets the new summary")
    func mergeIntoEmpty() {
        #expect(Summaries.merge(existing: "", written: "", generated: "## Overview\nNew.\n") == "## Overview\nNew.\n")
    }

    @Test("Writing again replaces what the model wrote last time")
    func mergeReplacesOwn() {
        let old = "## Overview\nOld.\n"
        #expect(Summaries.merge(existing: old, written: old, generated: "## Overview\nNew.\n") == "## Overview\nNew.\n")
    }

    @Test("An imported summary is kept under the new one, and stays there on the next write")
    func mergeKeepsImported() {
        let imported = "## Imported summary\n\nA recap as it came in.\n"
        let first = Summaries.merge(existing: imported, written: "", generated: "## Overview\nOne.\n")
        #expect(first == "## Overview\nOne.\n\n## Imported summary\n\nA recap as it came in.\n")
        let second = Summaries.merge(existing: first, written: "## Overview\nOne.\n", generated: "## Overview\nTwo.\n")
        #expect(second == "## Overview\nTwo.\n\n## Imported summary\n\nA recap as it came in.\n")
    }

    @Test("An answer with no summary changes nothing")
    func mergeNothing() {
        #expect(Summaries.merge(existing: "## Overview\nOld.\n", written: "", generated: "") == "## Overview\nOld.\n")
    }
}
