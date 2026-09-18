import CoreGraphics
import Foundation
import Testing
import UsageCore

struct UsageGaugePolicyTests {
    @Test("compact two-window density keeps the current spacious metrics")
    func compactTwoWindowDensity() {
        let density = UsageGaugePolicy.density(compact: true, windowCount: 2)
        #expect(density.contentPadding == 14)
        #expect(density.rowSpacing == 10)
        #expect(density.barSpacing == 3)
        #expect(density.barHeight == 8)
        #expect(density.labelSize == 12)
        #expect(density.resetSize == 10)
        #expect(density.headerSize == 9)
    }

    @Test("compact three-window density fits a 158pt small widget")
    func compactThreeWindowFitsSmallWidget() {
        let two = UsageGaugePolicy.density(compact: true, windowCount: 2)
        let three = UsageGaugePolicy.density(compact: true, windowCount: 3)

        #expect(three.contentPadding < two.contentPadding)
        #expect(three.rowSpacing < two.rowSpacing)
        #expect(three.barSpacing < two.barSpacing)
        #expect(three.labelSize < two.labelSize)
        #expect(three.resetSize < two.resetSize)
        #expect(three.estimatedHeight(windowCount: 3, showsHeader: true) <= 158)
    }

    @Test("medium widget density stays spacious even with three windows")
    func mediumThreeWindowDensity() {
        let two = UsageGaugePolicy.density(compact: false, windowCount: 2)
        let three = UsageGaugePolicy.density(compact: false, windowCount: 3)
        #expect(three == two)
        #expect(three.contentPadding == 16)
        #expect(three.rowSpacing == 16)
    }
}
