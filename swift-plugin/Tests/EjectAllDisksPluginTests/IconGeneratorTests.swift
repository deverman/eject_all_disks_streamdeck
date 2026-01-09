//
//  IconGeneratorTests.swift
//  EjectAllDisksPluginTests
//
//  Unit tests for SVG icon generation
//

import Testing
@testable import EjectAllDisksPlugin

@Suite("IconGenerator Tests")
struct IconGeneratorTests {

    // MARK: - Normal Icon Tests

    @Test("Normal icon contains SVG structure")
    func normalIconStructure() {
        let svg = IconGenerator.createNormalSvgRaw(count: 0)

        #expect(svg.contains("<svg"))
        #expect(svg.contains("viewBox=\"0 0 144 144\""))
        #expect(svg.contains("xmlns=\"http://www.w3.org/2000/svg\""))
        #expect(svg.contains("</svg>"))
    }

    @Test("Normal icon contains eject triangle")
    func normalIconHasTriangle() {
        let svg = IconGenerator.createNormalSvgRaw(count: 0)

        // Triangle path
        #expect(svg.contains("M72 36L112 90H32L72 36Z"))
    }

    @Test("Normal icon contains horizontal bar")
    func normalIconHasBar() {
        let svg = IconGenerator.createNormalSvgRaw(count: 0)

        // Horizontal bar beneath triangle
        #expect(svg.contains("<rect x=\"32\" y=\"100\" width=\"80\" height=\"10\""))
    }

    @Test("Normal icon uses correct color")
    func normalIconColor() {
        let svg = IconGenerator.createNormalSvgRaw(count: 0)

        // Orange color for normal state
        #expect(svg.contains("#FF9F0A"))
    }

    @Test("Normal icon without count has no badge", arguments: [0, -1])
    func normalIconNoBadge(count: Int) {
        let svg = IconGenerator.createNormalSvgRaw(count: count)

        // Should not contain badge circle
        #expect(!svg.contains("cx=\"110\" cy=\"34\" r=\"20\""))
    }

    @Test("Normal icon with count shows badge", arguments: [1, 2, 5, 10, 99])
    func normalIconWithBadge(count: Int) {
        let svg = IconGenerator.createNormalSvgRaw(count: count)

        // Badge circle should be present
        #expect(svg.contains("cx=\"110\" cy=\"34\" r=\"20\""))
        // Badge should show the count
        #expect(svg.contains(">\(count)</text>"))
    }

    @Test("Normal icon badge uses red color")
    func normalIconBadgeColor() {
        let svg = IconGenerator.createNormalSvgRaw(count: 5)

        // Red badge background
        #expect(svg.contains("#FF3B30"))
    }

    // MARK: - Ejecting Icon Tests

    @Test("Ejecting icon contains animation")
    func ejectingIconAnimation() {
        let svg = IconGenerator.createEjectingSvg()

        #expect(svg.contains("animate"))
        #expect(svg.contains("attributeName"))
        #expect(svg.contains("opacity"))
        #expect(svg.contains("repeatCount=\"indefinite\""))
    }

    @Test("Ejecting icon uses yellow color")
    func ejectingIconColor() {
        let svg = IconGenerator.createEjectingSvg()

        // Yellow color for ejecting state
        #expect(svg.contains("#FFCC00") || svg.contains("%23FFCC00"))
    }

    @Test("Ejecting icon has no badge")
    func ejectingIconNoBadge() {
        let svg = IconGenerator.createEjectingSvg()

        // Should not contain badge with count
        #expect(!svg.contains("cx=\"110\" cy=\"34\" r=\"20\"") || !svg.contains("cx%3D%22110%22"))
    }

    // MARK: - Success Icon Tests

    @Test("Success icon contains checkmark")
    func successIconCheckmark() {
        let svg = IconGenerator.createSuccessSvg()

        // Checkmark path (M52 72L67 87L92 57)
        #expect(svg.contains("M52 72L67 87L92 57") || svg.contains("M52%2072L67%2087L92%2057"))
    }

    @Test("Success icon uses green color")
    func successIconColor() {
        let svg = IconGenerator.createSuccessSvg()

        // Green color for success state
        #expect(svg.contains("#34C759") || svg.contains("%2334C759"))
    }

    @Test("Success icon checkmark is white")
    func successIconCheckmarkColor() {
        let svg = IconGenerator.createSuccessSvg()

        // White stroke for checkmark
        #expect(svg.contains("#FFFFFF") || svg.contains("%23FFFFFF"))
    }

    // MARK: - Error Icon Tests

    @Test("Error icon contains X mark")
    func errorIconXMark() {
        let svg = IconGenerator.createErrorSvg()

        // X mark paths
        #expect(svg.contains("M60 60L84 84") || svg.contains("M60%2060L84%2084"))
        #expect(svg.contains("M84 60L60 84") || svg.contains("M84%2060L60%2084"))
    }

    @Test("Error icon uses red color")
    func errorIconColor() {
        let svg = IconGenerator.createErrorSvg()

        // Red color for error state
        #expect(svg.contains("#FF3B30") || svg.contains("%23FF3B30"))
    }

    @Test("Error icon X mark is white")
    func errorIconXColor() {
        let svg = IconGenerator.createErrorSvg()

        // White stroke for X mark
        #expect(svg.contains("#FFFFFF") || svg.contains("%23FFFFFF"))
    }

    // MARK: - Data URI Encoding Tests

    @Test("Normal icon is encoded as data URI")
    func normalIconDataUri() {
        let svg = IconGenerator.createNormalSvg(count: 0)

        #expect(svg.hasPrefix("data:image/svg+xml,"))
    }

    @Test("Ejecting icon is encoded as data URI")
    func ejectingIconDataUri() {
        let svg = IconGenerator.createEjectingSvg()

        #expect(svg.hasPrefix("data:image/svg+xml,"))
    }

    @Test("Success icon is encoded as data URI")
    func successIconDataUri() {
        let svg = IconGenerator.createSuccessSvg()

        #expect(svg.hasPrefix("data:image/svg+xml,"))
    }

    @Test("Error icon is encoded as data URI")
    func errorIconDataUri() {
        let svg = IconGenerator.createErrorSvg()

        #expect(svg.hasPrefix("data:image/svg+xml,"))
    }

    // MARK: - Edge Cases

    @Test("Large disk count displays correctly", arguments: [100, 999])
    func largeCountDisplay(count: Int) {
        let svg = IconGenerator.createNormalSvgRaw(count: count)

        #expect(svg.contains(">\(count)</text>"))
    }

    @Test("All icons have background circle")
    func allIconsHaveBackground() {
        let icons = [
            IconGenerator.createNormalSvgRaw(count: 0),
            IconGenerator.createEjectingSvg(),
            IconGenerator.createSuccessSvg(),
            IconGenerator.createErrorSvg()
        ]

        for svg in icons {
            // Background circle
            #expect(svg.contains("cx=\"72\" cy=\"72\" r=\"65\"") ||
                   svg.contains("cx%3D%2272%22%20cy%3D%2272%22%20r%3D%2265%22"))
        }
    }

    @Test("All icons have consistent dimensions")
    func allIconsConsistentDimensions() {
        let icons = [
            IconGenerator.createNormalSvgRaw(count: 0),
            IconGenerator.createEjectingSvg(),
            IconGenerator.createSuccessSvg(),
            IconGenerator.createErrorSvg()
        ]

        for svg in icons {
            #expect(svg.contains("width=\"144\"") || svg.contains("width%3D%22144%22"))
            #expect(svg.contains("height=\"144\"") || svg.contains("height%3D%22144%22"))
        }
    }
}
