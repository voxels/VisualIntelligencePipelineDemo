# Repository Guidelines

## Project Structure & Module Organization

- `Diver/`: Xcode app project.
  - `Diver/Diver/`: SwiftUI app source (`View/`, `ViewModel/`, `Model/`, `Controller/`).
  - `Diver/DiverTests/`, `Diver/DiverUITests/`: XCTest unit/UI tests.
- `DiverKit/`: Shared Swift Package (`Package.swift`).
  - `DiverKit/Sources/DiverKit/`: Reusable modules (e.g., `Auth/`, `Core/Networking/`, `Storage/`, `Services/`).
  - `DiverKit/Tests/DiverKitTests/`: Package tests.

Prefer putting cross-platform/shared logic in `DiverKit` and keeping `Diver/Diver/` focused on UI + app wiring.

## Build, Test, and Development Commands

- Open the app in Xcode: `open Diver/Diver.xcodeproj`
- Build/test the Swift package: `swift build --package-path DiverKit` / `swift test --package-path DiverKit`
- Build/test the app (CLI example): `xcodebuild -project Diver/Diver.xcodeproj -scheme Diver_iOS test -destination 'platform=iOS Simulator,name=iPhone 15'`
  - If you want artifacts in-repo (useful for CI), add: `-derivedDataPath ./DerivedData`
- **Finding Build Targets**:
  - If a build fails because the scheme is not found, verify available schemes using:
    `xcodebuild -list -project Diver/Diver.xcodeproj`
  - The primary schemes are typically `Diver_iOS` or `Diver_macOS` rather than just `Diver`.

## Coding Style & Naming Conventions

- Swift: follow Xcode defaults (4-space indentation) and Swift API Design Guidelines.
- Naming: `UpperCamelCase` types/files (e.g., `ChatViewModel.swift`), `lowerCamelCase` for vars/functions, `UPPER_SNAKE_CASE` for constants only when it improves clarity.
- Organization: group by feature (folders) and keep types small; avoid “god” managers/services.

## Testing Guidelines

- Framework: XCTest for `DiverTests`, `DiverUITests`, and `DiverKitTests`.
- Conventions: keep tests deterministic; name as `test_<behavior>_<condition>()` and co-locate helpers in the test target.
- Run package tests first (`swift test`) before simulator/UI test passes.

## Commit & Pull Request Guidelines

- Commits in this repo are short and imperative (e.g., “Update Package.swift”, “Clean project”); keep that style, start with a verb, and avoid noisy/unclear messages.
- PRs: include a brief description, link the issue (if any), and add screenshots/screen recordings for UI changes (iOS + macOS when relevant).

## Security & Configuration Tips

- Don’t commit tokens, API keys, or user data. Prefer local config and platform-secure storage (Keychain) when adding credentials.
