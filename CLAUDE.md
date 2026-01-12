# CLAUDE.md - Swift Stream Deck Plugin Development Guide

**Last Updated:** 2026-01-11

This document provides comprehensive guidelines for developing Swift-native Stream Deck plugins using the [StreamDeckPlugin](https://github.com/emorydunn/StreamDeckPlugin) library. It captures architecture patterns, best practices, and lessons learned from production plugin development.

---

## Table of Contents

1. [Quick Start](#quick-start)
2. [Architecture Overview](#architecture-overview)
3. [Creating a New Plugin](#creating-a-new-plugin)
4. [Adding Actions to a Plugin](#adding-actions-to-a-plugin)
5. [Swift 6 Concurrency Requirements](#swift-6-concurrency-requirements)
6. [Build & Distribution](#build--distribution)
7. [Testing Strategy](#testing-strategy)
8. [Common Patterns](#common-patterns)
9. [Troubleshooting](#troubleshooting)
10. [Validation Checklists](#validation-checklists)
11. [Marketplace Distribution](#marketplace-distribution)

---

## Quick Start

### Build and Run Existing Plugin
```bash
cd swift-plugin
./build.sh --install
streamdeck restart org.deverman.ejectalldisks
```

### View Logs
```bash
log stream --predicate 'subsystem == "org.deverman.ejectalldisks"' --level debug
```

### Package for Distribution
```bash
streamdeck pack org.deverman.ejectalldisks.sdPlugin
```

---

## Architecture Overview

### Project Structure
```
your-plugin-name/
├── swift-plugin/                        # Swift package
│   ├── Package.swift                    # Swift package manifest
│   ├── build.sh                         # Build and install script
│   ├── Sources/YourPluginName/
│   │   ├── YourPluginName.swift         # @main plugin entry point
│   │   └── Actions/
│   │       ├── ActionOne.swift          # First action
│   │       └── ActionTwo.swift          # Additional actions
│   └── Tests/YourPluginNameTests/       # Swift Testing tests
├── org.yourorg.pluginname.sdPlugin/     # Plugin bundle (source assets)
│   ├── manifest.json                    # Plugin manifest (CodePath = binary name)
│   ├── imgs/                            # Icons and images
│   │   ├── plugin/                      # Plugin-level icons
│   │   │   ├── marketplace.png          # Marketplace icon (144x144)
│   │   │   └── category-icon.png        # Category icon (28x28)
│   │   └── actions/
│   │       └── action-name/
│   │           ├── icon.png             # Action icon (20x20)
│   │           ├── state.svg            # Normal state image
│   │           └── other-states.svg     # Additional state images
│   └── ui/
│       └── action-name.html             # Property Inspector HTML
└── CLAUDE.md                            # This file
```

### Key Dependencies

| Dependency | Purpose | Source |
|------------|---------|--------|
| StreamDeckPlugin | Swift SDK for Stream Deck plugins | `https://github.com/emorydunn/StreamDeckPlugin.git` |
| Swift Testing | Modern test framework | Built into Swift 6.2.1+ |

### Plugin vs Action Architecture

- **Plugin** (`Plugin` protocol): Main entry point, defines metadata and registers actions
- **Action** (`KeyAction` protocol): Individual button behavior, handles user interaction
- **Settings** (`Codable` struct): Per-action settings stored by Stream Deck
- **GlobalSettings** (`GlobalSettings` extension): Shared state across all action instances

---

## Creating a New Plugin

### Step 1: Create Package.swift

```swift
// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "YourPluginName",
    platforms: [
        .macOS(.v13)  // Stream Deck 6.4+ requires macOS 13+
    ],
    products: [
        .executable(
            name: "org.yourorg.pluginname",  // MUST match plugin UUID
            targets: ["YourPluginName"]
        )
    ],
    dependencies: [
        .package(url: "https://github.com/emorydunn/StreamDeckPlugin.git", from: "0.6.0"),
        // Add your own dependencies here
    ],
    targets: [
        .executableTarget(
            name: "YourPluginName",
            dependencies: [
                .product(name: "StreamDeck", package: "StreamDeckPlugin"),
            ],
            path: "Sources/YourPluginName"
        ),
        .testTarget(
            name: "YourPluginNameTests",
            dependencies: ["YourPluginName"],
            path: "Tests/YourPluginNameTests"
        )
    ]
)
```

### Step 2: Create Plugin Entry Point

```swift
// Sources/YourPluginName/YourPluginName.swift

import Foundation
import StreamDeck
import OSLog

fileprivate let log = Logger(subsystem: "org.yourorg.pluginname", category: "plugin")

// Define global settings if needed
extension GlobalSettings {
    @Entry var someGlobalState: Bool = false
}

@main
class YourPluginName: Plugin {

    // MARK: - Plugin Metadata
    static var name: String = "Your Plugin Name"
    static var description: String = "What your plugin does"
    static var author: String = "Your Name"
    static var icon: String = "imgs/plugin/marketplace"
    static var version: String = "1.0.0"
    static var os: [PluginOS] = [.macOS("13")]

    // MARK: - Actions
    @ActionBuilder
    static var actions: [any Action.Type] {
        YourFirstAction.self
        // Add more actions here
    }

    // MARK: - Layouts (for Stream Deck+ dials)
    @LayoutBuilder
    static var layouts: [Layout] { }

    // MARK: - Initialization
    required init() {
        log.info("Plugin initialized")
    }
}
```

### Step 3: Create manifest.json

```json
{
    "Name": "Your Plugin Name",
    "Version": "1.0.0",
    "Author": "Your Name",
    "Actions": [
        {
            "Name": "Your Action",
            "UUID": "org.yourorg.pluginname.actionname",
            "Icon": "imgs/actions/actionname/icon",
            "Tooltip": "What this action does",
            "PropertyInspectorPath": "ui/actionname.html",
            "Controllers": ["Keypad"],
            "States": [
                {
                    "Image": "imgs/actions/actionname/state",
                    "TitleAlignment": "middle",
                    "FontSize": 16
                }
            ]
        }
    ],
    "Category": "Your Plugin Name",
    "CategoryIcon": "imgs/plugin/category-icon",
    "CodePath": "org.yourorg.pluginname",
    "Description": "What your plugin does",
    "Icon": "imgs/plugin/marketplace",
    "SDKVersion": 2,
    "Software": {
        "MinimumVersion": "6.4"
    },
    "OS": [
        {
            "Platform": "mac",
            "MinimumVersion": "13"
        }
    ],
    "UUID": "org.yourorg.pluginname"
}
```

### Step 4: Create build.sh

```bash
#!/bin/bash
set -e

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(dirname "$SCRIPT_DIR")"
PLUGIN_DIR="$PROJECT_ROOT/org.yourorg.pluginname.sdPlugin"

echo "Building YourPluginName..."
cd "$SCRIPT_DIR"
swift build -c release
echo "Build succeeded!"

if [ "$1" == "--install" ]; then
    echo "Installing to Stream Deck..."
    swift run org.yourorg.pluginname export org.yourorg.pluginname \
        --generate-manifest \
        --copy-executable

    INSTALL_DIR="$HOME/Library/Application Support/com.elgato.StreamDeck/Plugins/org.yourorg.pluginname.sdPlugin"
    cp -r "$PLUGIN_DIR/imgs" "$INSTALL_DIR/"
    cp -r "$PLUGIN_DIR/ui" "$INSTALL_DIR/"

    echo "Plugin installed!"
    echo "Restart with: streamdeck restart org.yourorg.pluginname"
fi
```

---

## Adding Actions to a Plugin

### Action Template (KeyAction)

```swift
// Sources/YourPluginName/Actions/YourAction.swift

import Foundation
import StreamDeck
import OSLog

fileprivate let log = Logger(subsystem: "org.yourorg.pluginname", category: "action")

/// Settings for this action (persisted per-button)
struct YourActionSettings: Codable, Hashable, Sendable {
    var showTitle: Bool = true
    var customOption: String = "default"
}

/// Your action implementation
class YourAction: KeyAction {

    // MARK: - Action Metadata
    typealias Settings = YourActionSettings

    static var name: String = "Your Action Name"
    static var uuid: String = "org.yourorg.pluginname.actionname"
    static var icon: String = "imgs/actions/actionname/icon"
    static var propertyInspectorPath: String? = "ui/actionname.html"

    static var states: [PluginActionState]? = [
        PluginActionState(
            image: "imgs/actions/actionname/state",
            titleAlignment: .middle
        )
    ]

    // MARK: - Instance Properties
    var context: String
    var coordinates: StreamDeck.Coordinates?

    /// Access to global settings
    @GlobalSetting(\.someGlobalState) var isProcessing: Bool

    /// Timer for polling (if needed)
    private var pollingTimer: DispatchSourceTimer?

    // MARK: - Initialization
    required init(context: String, coordinates: StreamDeck.Coordinates?) {
        self.context = context
        self.coordinates = coordinates
    }

    // MARK: - Lifecycle Events

    /// Called when action appears on Stream Deck
    func willAppear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action appeared on device \(device)")
        let settings = payload.settings
        // Initialize based on settings
        updateDisplay(settings: settings)
    }

    /// Called when action disappears from Stream Deck
    func willDisappear(device: String, payload: AppearEvent<Settings>) {
        log.info("Action disappeared from device \(device)")
        // Cleanup timers, observers, etc.
        stopPolling()
    }

    /// Called when settings change in Property Inspector
    func didReceiveSettings(device: String, payload: SettingsEvent<Settings>.Payload) {
        log.debug("Settings updated")
        updateDisplay(settings: payload.settings)
    }

    // MARK: - Key Events

    /// Called when key is released (primary action)
    func keyUp(device: String, payload: KeyEvent<Settings>, longPress: Bool) {
        if longPress { return }  // Optional: handle long press differently

        log.info("Key pressed")

        // Prevent concurrent operations
        guard !isProcessing else {
            log.warning("Already processing, ignoring")
            return
        }

        let settings = payload.settings

        Task { @MainActor in
            await performAction(settings: settings)
        }
    }

    // MARK: - Action Logic

    @MainActor
    private func performAction(settings: Settings) async {
        isProcessing = true

        // Show progress state
        setImage(toImage: "processing", withExtension: "svg", subdirectory: "imgs/actions/actionname")
        setTitle(to: settings.showTitle ? "Working..." : nil, target: nil, state: nil)

        do {
            // YOUR ACTION LOGIC HERE
            let result = try await doSomething()

            // Show success
            setImage(toImage: "success", withExtension: "svg", subdirectory: "imgs/actions/actionname")
            setTitle(to: settings.showTitle ? "Done!" : nil, target: nil, state: nil)
            showOk()

        } catch {
            log.error("Action failed: \(error.localizedDescription)")
            setImage(toImage: "error", withExtension: "svg", subdirectory: "imgs/actions/actionname")
            setTitle(to: settings.showTitle ? "Error" : nil, target: nil, state: nil)
            showAlert()
        }

        // Reset after delay
        try? await Task.sleep(for: .seconds(2))
        isProcessing = false
        updateDisplay(settings: settings)
    }

    // MARK: - Display Updates

    private func updateDisplay(settings: Settings) {
        setImage(toImage: "state", withExtension: "svg", subdirectory: "imgs/actions/actionname")
        setTitle(to: settings.showTitle ? "Ready" : nil, target: nil, state: nil)
    }

    // MARK: - Polling (Optional)

    private func startPolling(interval: TimeInterval = 3.0) {
        let timer = DispatchSource.makeTimerSource(queue: .main)
        timer.schedule(deadline: .now() + interval, repeating: interval)
        timer.setEventHandler { [weak self] in
            guard let self = self else { return }
            Task {
                await self.refreshData()
            }
        }
        timer.resume()
        pollingTimer = timer
    }

    private func stopPolling() {
        pollingTimer?.cancel()
        pollingTimer = nil
    }

    private func refreshData() async {
        // Poll for updates
    }
}
```

### After Adding an Action

1. Register it in the plugin's `@ActionBuilder`:
   ```swift
   @ActionBuilder
   static var actions: [any Action.Type] {
       ExistingAction.self
       YourNewAction.self  // Add here
   }
   ```

2. Add to `manifest.json` in the `Actions` array

3. Create image assets in `imgs/actions/actionname/`

4. Create Property Inspector HTML in `ui/actionname.html`

---

## Swift 6 Concurrency Requirements

### CRITICAL: Sendable Conformance

All types that cross async boundaries MUST be `Sendable`.

```swift
// ✅ GOOD: Sendable types in TaskGroup
await withTaskGroup(of: String.self) { group in ... }
await withTaskGroup(of: (String, Bool).self) { group in ... }
await withTaskGroup(of: MySendableStruct.self) { group in ... }

// ❌ BAD: Non-Sendable types
await withTaskGroup(of: [String: Any].self) { group in ... }  // Any is not Sendable!
await withTaskGroup(of: SomeClass.self) { group in ... }      // Classes need @unchecked Sendable
```

### Sendable Reference

| Type | Sendable? | Notes |
|------|-----------|-------|
| `String`, `Int`, `Bool` | ✅ Yes | Value types |
| `Array<T>`, `Dictionary<K,V>`, `Set<T>` | ✅ If T/K/V are Sendable | |
| Custom `struct` | ✅ If marked `Sendable` | All properties must be Sendable |
| `Any`, `AnyObject` | ❌ No | Never use in async contexts |
| `[String: Any]` | ❌ No | Any makes it non-Sendable |
| Classes | ❌ No | Unless marked `@unchecked Sendable` |
| Actors | ✅ Yes | Always Sendable |

### Pattern: Extract Sendable Data

```swift
// Instead of passing complex objects through TaskGroup:
struct DiskInfo: Sendable {
    let identifier: String
    let isExternal: Bool
}

let results = await withTaskGroup(of: DiskInfo.self) { group in
    for disk in disks {
        group.addTask {
            DiskInfo(identifier: disk.id, isExternal: disk.checkIfExternal())
        }
    }
    return await group.reduce(into: []) { $0.append($1) }
}
```

### Mental Compilation Checklist

Before committing Swift code:
```
☐ All TaskGroup types are Sendable
☐ No [String: Any] dictionaries crossing async boundaries
☐ No implicit captures of non-Sendable data
☐ Actor isolation boundaries are respected
☐ All async functions have proper await calls
```

---

## Build & Distribution

### Development Workflow

```bash
# 1. Make code changes
# 2. Build and install
cd swift-plugin && ./build.sh --install

# 3. Restart plugin (no need to restart Stream Deck app)
streamdeck restart org.yourorg.pluginname

# 4. View logs
log stream --predicate 'subsystem == "org.yourorg.pluginname"' --level debug
```

### Install Stream Deck CLI

```bash
npm install -g @elgato/cli
```

### Package for Distribution

```bash
# Using Stream Deck CLI (recommended)
streamdeck pack org.yourorg.pluginname.sdPlugin

# Output: org.yourorg.pluginname.streamDeckPlugin
```

### Releasing a New Version

Version is defined in **one place only**: `Sources/YourPluginName/YourPluginName.swift`

```swift
static var version: String = "3.0.0"  // ← Change this
```

The manifest.json is **auto-generated** by `swift run ... export`, so you don't need to edit it manually.

**Release Steps:**

1. **Bump version** in Swift file:
   ```swift
   // swift-plugin/Sources/YourPluginName/YourPluginName.swift
   static var version: String = "3.1.0"  // MAJOR.MINOR.PATCH
   ```

2. **Build and test**:
   ```bash
   cd swift-plugin
   swift test
   ./build.sh --install
   ```

3. **Commit and tag**:
   ```bash
   git add -A
   git commit -m "Bump version to 3.1.0"
   git tag -a v3.1.0 -m "Release v3.1.0"
   git push && git push origin v3.1.0
   ```

4. **Create GitHub release**:
   - Go to: https://github.com/yourorg/yourplugin/releases/new?tag=v3.1.0
   - GitHub Actions will automatically build and attach the `.streamDeckPlugin` file

**Version Format:** `MAJOR.MINOR.PATCH`
- **MAJOR**: Breaking changes
- **MINOR**: New features (backward compatible)
- **PATCH**: Bug fixes

### Distribution Checklist

```
☐ Version bumped in YourPluginName.swift
☐ Tests pass: swift test
☐ Build succeeds: ./build.sh --install
☐ Plugin works correctly in Stream Deck
☐ Git tagged with version
☐ GitHub release created
```

---

## Testing Strategy

### Unit Tests with Swift Testing

```swift
// Tests/YourPluginNameTests/DisplayLogicTests.swift

import Testing
@testable import YourPluginName

@Suite("Display Title Tests")
struct DisplayTitleTests {

    @Test("Shows correct title for count")
    func titleForCount() {
        #expect(formatTitle(count: 0) == "No Items")
        #expect(formatTitle(count: 1) == "1 Item")
        #expect(formatTitle(count: 5) == "5 Items")
    }

    @Test("Respects showTitle setting")
    func showTitleSetting() {
        #expect(formatTitle(count: 3, showTitle: false) == nil)
    }
}
```

### Run Tests

```bash
cd swift-plugin
swift test
```

### Integration Testing

Since Stream Deck plugins require the Stream Deck application:

1. **Manual testing**: Build, install, test in Stream Deck
2. **Mocking**: Create protocols for external dependencies
3. **Logging**: Use OSLog for debugging production issues

---

## Common Patterns

### Pattern 1: Polling for Updates

```swift
private var pollingTimer: DispatchSourceTimer?

func startPolling() {
    let timer = DispatchSource.makeTimerSource(queue: .main)
    timer.schedule(deadline: .now() + 3.0, repeating: 3.0)
    timer.setEventHandler { [weak self] in
        Task { await self?.refresh() }
    }
    timer.resume()
    pollingTimer = timer
}

func stopPolling() {
    pollingTimer?.cancel()
    pollingTimer = nil
}
```

### Pattern 2: Preventing Concurrent Operations

```swift
extension GlobalSettings {
    @Entry var isProcessing: Bool = false
}

class MyAction: KeyAction {
    @GlobalSetting(\.isProcessing) var isProcessing: Bool

    func keyUp(...) {
        guard !isProcessing else { return }
        Task { @MainActor in
            isProcessing = true
            defer { isProcessing = false }
            await doWork()
        }
    }
}
```

### Pattern 3: Timeout for Async Operations

```swift
func withTimeout<T: Sendable>(
    seconds: TimeInterval,
    operation: @escaping @Sendable () async throws -> T
) async throws -> T {
    try await withThrowingTaskGroup(of: T.self) { group in
        group.addTask { try await operation() }
        group.addTask {
            try await Task.sleep(for: .seconds(seconds))
            throw TimeoutError()
        }
        let result = try await group.next()!
        group.cancelAll()
        return result
    }
}
```

### Pattern 4: Error Title Formatting

```swift
func formatErrorTitle(_ error: Error) -> String {
    switch error {
    case let e as PermissionError:
        return "Grant\nAccess"
    case let e as BusyError:
        return "In Use"
    case let e as TimeoutError:
        return "Timeout"
    default:
        return "Error"
    }
}
```

---

## Troubleshooting

### Plugin Doesn't Load

1. Check binary exists: `ls org.yourorg.pluginname.sdPlugin/org.yourorg.pluginname`
2. Check manifest.json `CodePath` matches binary name (no `bin/` prefix)
3. Check Stream Deck logs: `tail -f ~/Library/Logs/com.elgato.StreamDeck/StreamDeck0.log`
4. Verify plugin installed: `ls ~/Library/Application\ Support/com.elgato.StreamDeck/Plugins/`

### Actions Don't Appear

1. Verify action UUID in Swift matches manifest.json
2. Check action is registered in `@ActionBuilder`
3. Restart Stream Deck application (not just plugin)

### Button Doesn't Update

1. Ensure code runs on main thread: `Task { @MainActor in ... }`
2. Check setImage/setTitle are called with correct paths
3. Verify image files exist in installed plugin

### Build Errors

| Error | Solution |
|-------|----------|
| "Type does not conform to Sendable" | Use Sendable types or create custom Sendable struct |
| "Cannot find type 'KeyAction'" | Import StreamDeck |
| "Actor-isolated property" | Use `@MainActor` or `nonisolated` appropriately |

---

## Validation Checklists

### Before Committing Swift Code

```
☐ All TaskGroup types are Sendable
☐ No [String: Any] crossing async boundaries
☐ Actor isolation is correct
☐ async/await calls are proper
☐ No implicit captures of mutable state
```

### Before Releasing Plugin

```
☐ Version number updated
☐ All tests pass: swift test
☐ Builds for release: swift build -c release
☐ Installs correctly: ./build.sh --install
☐ Plugin restarts: streamdeck restart org.yourorg.pluginname
☐ All actions work as expected
☐ Error states display correctly
☐ README is accurate
☐ Package creates: streamdeck pack org.yourorg.pluginname.sdPlugin
```

### Before Pushing

```
☐ All changes committed
☐ All commits pushed
☐ No build artifacts in commit (.build/, *.o)
```

---

## Marketplace Distribution

### Overview

To sell plugins on the [Elgato Marketplace](https://marketplace.elgato.com):
1. Create account at [Maker Console](https://maker.elgato.com)
2. Sign the Maker Agreement
3. Submit plugin with required assets
4. Wait 4-10 business days for review

**Revenue Split:** 70% to you, 30% to Elgato (via Stripe Connect)

### Required Assets

| Asset | Dimensions | Format | Notes |
|-------|------------|--------|-------|
| **Plugin Icon** | 288 × 288 px | PNG | Main marketplace icon |
| **Thumbnail** | 1920 × 960 px | PNG | Listing header image |
| **Gallery Images** | 1920 × 960 px | PNG | 3-10 images recommended |
| **Category Icon** | 28 × 28 px | SVG | White on transparent |
| **Action Icons** | 20 × 20 px | SVG | White on transparent |

### Required manifest.json Fields

```json
{
    "Name": "Plugin Name",
    "Version": "1.0.0",
    "Author": "Your Organization",
    "URL": "https://your-homepage.com",
    "Description": "What your plugin does",
    "Icon": "imgs/plugin/marketplace",
    "UUID": "org.yourorg.pluginname"
}
```

### Product Listing Requirements

| Field | Requirements |
|-------|-------------|
| **Name** | Unique, descriptive, no trademarks |
| **Description** | Complete functionality description |
| **Support URL** | GitHub issues or help page |
| **Release Notes** | What's new in this version |
| **Alt Text** | For all images (accessibility) |

### Submission Checklist

```
☐ Maker Console account created
☐ Maker Agreement signed
☐ Plugin packaged: streamdeck pack org.yourorg.pluginname.sdPlugin
☐ Plugin icon created (288 × 288 px PNG)
☐ Thumbnail created (1920 × 960 px PNG)
☐ 3+ gallery images created (1920 × 960 px PNG)
☐ Product description written
☐ Release notes written
☐ Support URL configured
☐ Price set (or free)
☐ No copyrighted material
☐ No external payment systems
☐ Tested on clean install
```

### Gallery Image Ideas

1. **Hero Shot** - Button on Stream Deck showing primary state
2. **All States** - Side-by-side of different button states
3. **Features** - Highlight key capabilities
4. **Speed/Performance** - If applicable, show benchmarks
5. **Error Handling** - Show intelligent error messages
6. **Setup Steps** - Simple installation process

### Pricing Notes

- One-time purchase only (no subscriptions)
- No free trials supported
- No external payment systems allowed
- Minimum price: $0.99 USD
- DRM automatically enabled with CLI 1.6+

### Post-Submission

- Review takes 4-10 business days
- Elgato may request changes
- UUID cannot be changed after publishing
- Updates follow same review process

### Marketing Assets Template

See `MARKETPLACE_ASSETS.md` for complete marketing copy and image specifications.

---

## Resources

- [StreamDeckPlugin Library](https://github.com/emorydunn/StreamDeckPlugin)
- [Stream Deck SDK Documentation](https://docs.elgato.com/sdk/)
- [Stream Deck CLI](https://www.npmjs.com/package/@elgato/cli)
- [Swift Concurrency Guide](https://docs.swift.org/swift-book/LanguageGuide/Concurrency.html)
- [Elgato Marketplace](https://marketplace.elgato.com)
- [Maker Console](https://maker.elgato.com)
- [Maker Documentation](https://docs.elgato.com/makers/)
- [Plugin Metadata Guidelines](https://docs.elgato.com/guidelines/streamdeck/plugins/metadata/)

---

*This document should be consulted before every plugin development session.*
