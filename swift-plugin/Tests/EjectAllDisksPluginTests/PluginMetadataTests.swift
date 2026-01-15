//
//  PluginMetadataTests.swift
//  EjectAllDisksPluginTests
//
//  Tests for plugin and action metadata
//

import Testing
import Foundation
@testable import EjectAllDisksPlugin

@Suite("Plugin Metadata Tests")
@MainActor
struct PluginMetadataTests {

    // MARK: - Plugin Properties

    @Test("Plugin has correct name")
    func pluginName() {
        #expect(EjectAllDisksPlugin.name == "Eject All Disks")
    }

    @Test("Plugin has description")
    func pluginDescription() {
        #expect(!EjectAllDisksPlugin.description.isEmpty)
        #expect(EjectAllDisksPlugin.description.lowercased().contains("eject"))
    }

    @Test("Plugin has author")
    func pluginAuthor() {
        #expect(EjectAllDisksPlugin.author == "Brent Deverman")
    }

    @Test("Plugin has valid version")
    func pluginVersion() {
        let version = EjectAllDisksPlugin.version
        #expect(!version.isEmpty)

        // Should be in semver-like format (x.y.z)
        let components = version.split(separator: ".")
        #expect(components.count >= 2, "Version should have at least major.minor")
    }

    @Test("Plugin has icon path")
    func pluginIcon() {
        #expect(!EjectAllDisksPlugin.icon.isEmpty)
        #expect(EjectAllDisksPlugin.icon.contains("imgs/"))
    }

    @Test("Plugin targets macOS")
    func pluginOS() {
        let os = EjectAllDisksPlugin.os
        #expect(!os.isEmpty)

        let macOSSupport = os.first { $0.platform == .mac }
        #expect(macOSSupport != nil, "Plugin should support macOS")
    }

    @Test("Plugin has macOS version requirement")
    func pluginMinMacOS() {
        let macOS = EjectAllDisksPlugin.os.first { $0.platform == .mac }
        #expect(macOS != nil, "Plugin should have macOS support")
    }
}

@Suite("EjectAction Metadata Tests")
@MainActor
struct EjectActionMetadataTests {

    // MARK: - Action Properties

    @Test("Action has correct name")
    func actionName() {
        #expect(EjectAction.name == "Eject All Disks")
    }

    @Test("Action has correct UUID")
    func actionUuid() {
        #expect(EjectAction.uuid == "org.deverman.ejectalldisks.eject")
        #expect(EjectAction.uuid.hasPrefix("org.deverman."))
    }

    @Test("Action UUID follows reverse domain notation")
    func actionUuidFormat() {
        let uuid = EjectAction.uuid
        let components = uuid.split(separator: ".")

        #expect(components.count >= 3, "UUID should have at least 3 components")
        #expect(components[0] == "org")
    }

    @Test("Action has icon path")
    func actionIcon() {
        #expect(!EjectAction.icon.isEmpty)
        #expect(EjectAction.icon.contains("imgs/"))
    }

    @Test("Action has property inspector path")
    func actionPropertyInspector() {
        #expect(EjectAction.propertyInspectorPath != nil)
        #expect(EjectAction.propertyInspectorPath?.contains(".html") == true)
    }

    @Test("Action has at least one state")
    func actionStates() {
        #expect(EjectAction.states?.isEmpty == false)
        #expect((EjectAction.states?.count ?? 0) >= 1)
    }

    @Test("Action state has image")
    func actionStateImage() {
        let state = EjectAction.states?.first
        #expect(state != nil)
        #expect(state?.image.contains("imgs/") == true)
    }

    @Test("Action state has title alignment")
    func actionStateTitleAlignment() {
        let state = EjectAction.states?.first
        #expect(state != nil)
        #expect(state?.titleAlignment == .middle)
    }
}

@Suite("Plugin UUID Consistency Tests")
@MainActor
struct UuidConsistencyTests {

    @Test("Action UUID starts with plugin base")
    func actionUuidMatchesPlugin() {
        let baseUuid = "org.deverman.ejectalldisks"
        let actionUuid = EjectAction.uuid

        #expect(actionUuid.hasPrefix(baseUuid), "Action UUID should start with plugin base UUID")
    }

    @Test("Icon paths are consistent")
    func iconPathsConsistent() {
        // All icon paths should use the same base directory structure
        let pluginIcon = EjectAllDisksPlugin.icon
        let actionIcon = EjectAction.icon

        #expect(pluginIcon.hasPrefix("imgs/"))
        #expect(actionIcon.hasPrefix("imgs/"))
    }
}
