import Testing
@testable import SilvanusKit

@Test("The kit builds and links")
func kitLinks() {
    #expect(SilvanusKit.name == "Silvanus")
}
