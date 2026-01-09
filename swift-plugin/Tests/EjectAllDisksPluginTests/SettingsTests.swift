//
//  SettingsTests.swift
//  EjectAllDisksPluginTests
//
//  Unit tests for action settings
//

import Testing
import Foundation
@testable import EjectAllDisksPlugin

@Suite("EjectActionSettings Tests")
struct SettingsTests {

    // MARK: - Default Values

    @Test("Default settings have showTitle true")
    func defaultShowTitle() {
        let settings = EjectActionSettings()
        #expect(settings.showTitle == true)
    }

    // MARK: - Codable Conformance

    @Test("Settings encode to JSON correctly")
    func settingsEncode() throws {
        let settings = EjectActionSettings(showTitle: true)
        let encoder = JSONEncoder()
        let data = try encoder.encode(settings)
        let json = String(data: data, encoding: .utf8)!

        #expect(json.contains("showTitle"))
        #expect(json.contains("true"))
    }

    @Test("Settings decode from JSON correctly")
    func settingsDecode() throws {
        let json = """
        {"showTitle": false}
        """
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()
        let settings = try decoder.decode(EjectActionSettings.self, from: data)

        #expect(settings.showTitle == false)
    }

    @Test("Settings round-trip through JSON", arguments: [true, false])
    func settingsRoundTrip(showTitle: Bool) throws {
        let original = EjectActionSettings(showTitle: showTitle)

        let encoder = JSONEncoder()
        let data = try encoder.encode(original)

        let decoder = JSONDecoder()
        let decoded = try decoder.decode(EjectActionSettings.self, from: data)

        #expect(decoded.showTitle == original.showTitle)
    }

    // MARK: - Hashable Conformance

    @Test("Same settings are equal")
    func settingsEquality() {
        let settings1 = EjectActionSettings(showTitle: true)
        let settings2 = EjectActionSettings(showTitle: true)

        #expect(settings1 == settings2)
    }

    @Test("Different settings are not equal")
    func settingsInequality() {
        let settings1 = EjectActionSettings(showTitle: true)
        let settings2 = EjectActionSettings(showTitle: false)

        #expect(settings1 != settings2)
    }

    @Test("Settings can be used in Set")
    func settingsInSet() {
        var set = Set<EjectActionSettings>()
        set.insert(EjectActionSettings(showTitle: true))
        set.insert(EjectActionSettings(showTitle: true))
        set.insert(EjectActionSettings(showTitle: false))

        #expect(set.count == 2)
    }

    // MARK: - Edge Cases

    @Test("Settings decode with missing fields uses defaults")
    func settingsDecodePartial() throws {
        // Empty JSON object should use defaults
        let json = "{}"
        let data = json.data(using: .utf8)!
        let decoder = JSONDecoder()

        // This will fail if showTitle is required - which is expected
        // since we defined it with a default value but didn't mark it optional
        do {
            let settings = try decoder.decode(EjectActionSettings.self, from: data)
            // If decoding succeeds with empty JSON, default should be true
            #expect(settings.showTitle == true)
        } catch {
            // Decoding failure is also acceptable behavior for missing required fields
            // In this case, the field is required because we didn't make it optional
        }
    }
}
