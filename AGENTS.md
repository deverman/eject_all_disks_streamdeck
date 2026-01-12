# Repository Guidelines

## Project Structure & Module Organization

- `swift-plugin/`: Swift Package that builds the Stream Deck plugin executable.
  - `swift-plugin/Sources/EjectAllDisksPlugin/`: plugin entry point + actions.
  - `swift-plugin/Tests/EjectAllDisksPluginTests/`: Swift Testing test suite.
- `swift/Packages/SwiftDiskArbitration/`: local library wrapping macOS DiskArbitration (plus tests).
- `org.deverman.ejectalldisks.sdPlugin/`: Stream Deck plugin bundle (`manifest.json`, `ui/`, `imgs/`, `libs/`).
- `.github/`: CI/workflows (if present).

## Build, Test, and Development Commands

- Build (release): `cd swift-plugin && ./build.sh`
- Install into Stream Deck: `cd swift-plugin && ./build.sh --install` (then restart Stream Deck or run `streamdeck restart org.deverman.ejectalldisks`)
- Run plugin tests: `cd swift-plugin && swift test`
- Run library tests: `cd swift/Packages/SwiftDiskArbitration && swift test`
- Package for distribution (requires Stream Deck CLI): `streamdeck pack org.deverman.ejectalldisks.sdPlugin`
- View logs: `log stream --predicate 'subsystem == "org.deverman.ejectalldisks"'`

## Coding Style & Naming Conventions

- Follow `.editorconfig` (tabs by default; spaces for `*.md`, `*.json`, `*.yaml`). For Swift, keep indentation consistent with existing files (Xcode-style spaces).
- Swift: follow Swift API Design Guidelines; prefer clear names over abbreviations.
- Logging/security: do not log volume names or user paths; prefer BSD identifiers and OSLog privacy where applicable.

## Testing Guidelines

- Tests use Swift Testing (`@Test`); keep tests deterministic and avoid relying on specific disk names.
- Integration-style tests may skip/record issues when no external volumes are available—keep that behavior intact.

## Commit & Pull Request Guidelines

- Commits: use a short imperative subject (e.g., `Fix …`, `Add …`, `Update …`); optional scopes like `UX:` or `Security:` match existing history.
- PRs: include a brief description, how you validated (commands run), and screenshots for UI/property-inspector changes (`org.deverman.ejectalldisks.sdPlugin/ui/`).

## Security & Configuration Notes

- Local development often requires **Full Disk Access** for Stream Deck; see `README.md`.
- If you change permission requirements or user-facing setup, update `org.deverman.ejectalldisks.sdPlugin/SETUP.md` and `README.md`.
