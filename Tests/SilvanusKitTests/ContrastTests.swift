import Testing
@testable import SilvanusKit

// The contrast ratios design/KIT.md states for the Silvanus palette.
private let midnight = RGB(hex: 0x17142C)
private let raisedMidnight = RGB(hex: 0x252039)
private let ivory = RGB(hex: 0xF5EDDF)
private let paper = RGB(hex: 0xFFFBF5)
private let mutedInk = RGB(hex: 0x6D6674)
private let gold = RGB(hex: 0xC8AA73)
private let recordRed = RGB(hex: 0xB42318)
private let recordRedLight = RGB(hex: 0xFF8A80)

private func near(_ value: Double, _ expected: Double) -> Bool {
    abs(value - expected) <= 0.02
}

@Test("Gold on paper is 2.15:1, too low for text")
func goldOnPaper() {
    #expect(near(Contrast.ratio(gold, paper), 2.15))
}

@Test("Midnight on paper is 17.37:1")
func midnightOnPaper() {
    #expect(near(Contrast.ratio(midnight, paper), 17.37))
}

@Test("Muted ink on ivory is 4.75:1")
func mutedInkOnIvory() {
    #expect(near(Contrast.ratio(mutedInk, ivory), 4.75))
}

@Test("Record red with an ivory label is 5.65:1")
func recordRedWithIvory() {
    #expect(near(Contrast.ratio(recordRed, ivory), 5.65))
}

@Test("Light record red on raised midnight is 6.84:1")
func recordRedLightOnRaisedMidnight() {
    #expect(near(Contrast.ratio(recordRedLight, raisedMidnight), 6.84))
}

@Test("The ratio doesn't depend on the order of the two colors")
func ratioIsSymmetric() {
    #expect(Contrast.ratio(paper, midnight) == Contrast.ratio(midnight, paper))
}

@Test("Black on white is 21:1 and a color on itself is 1:1")
func ratioBounds() {
    #expect(near(Contrast.ratio(RGB(hex: 0x000000), RGB(hex: 0xFFFFFF)), 21))
    #expect(Contrast.ratio(gold, gold) == 1)
}

@Test("RGB keeps its hex value")
func rgbRoundTrip() {
    #expect(RGB(hex: 0xC8AA73).hex == 0xC8AA73)
}
