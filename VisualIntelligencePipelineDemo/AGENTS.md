# Repository Guidelines

## Project Structure & Module Organization

- `VisualIntelligencePipeline/`: Xcode app project.
  - `VisualIntelligencePipeline/VisualIntelligencePipeline/`: SwiftUI app source (`View/`, `Services/`, `AppIntents/`, `Model/`).
  - `VisualIntelligencePipeline/VisualIntelligencePipelineTests/`: XCTest unit tests.
  - `VisualIntelligencePipeline/VisualIntelligencePipelineUITests/`: UI tests.
  - `VisualIntelligencePipeline/ActionExtension/`: Share Sheet action extension.
  - `VisualIntelligencePipeline/VisualIntelligencePipelineWidget/`: Widget extension.
- `DiverKit/`: Core Swift Package (`Package.swift`).
  - `DiverKit/Sources/DiverKit/`: Reusable modules — `Services/`, `Models/`, `ViewModel/`, `Storage/`, `Core/`, `Authentication/`, `Schemas/`.
  - `DiverKit/Tests/DiverKitTests/`: Package tests.
- `DiverShared/`: Shared definitions & types (Pure Swift, no dependencies).
  - `DiverShared/Sources/DiverShared/`: Data models, App Group config, queue store, link wrapping.
  - `DiverShared/Tests/DiverSharedTests/`: Package tests.
- `Documentation/`: App summary and beta review notes.

Prefer putting cross-platform/shared logic in `DiverKit` and keeping `VisualIntelligencePipeline/` focused on UI + app wiring.

## Build, Test, and Development Commands

- Open the app in Xcode: `open VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj`
- Build the app (CLI): `xcodebuild -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj -scheme VisualIntelligencePipeline -destination 'platform=iOS Simulator,name=iPhone 17' build`
- Build/test DiverKit: `cd DiverKit && swift test`
- Build/test DiverShared: `cd DiverShared && swift test`
- **Finding Build Targets**:
  - If a build fails because the scheme is not found, verify available schemes using:
    `xcodebuild -list -project VisualIntelligencePipeline/VisualIntelligencePipeline.xcodeproj`
  - The primary scheme is `VisualIntelligencePipeline`.

## Coding Style & Naming Conventions

- Swift: follow Xcode defaults (4-space indentation) and Swift API Design Guidelines.
- Naming: `UpperCamelCase` types/files, `lowerCamelCase` for vars/functions.
- Organization: group by feature (folders) and keep types small; avoid "god" managers/services.

## Testing Guidelines

- Framework: XCTest for `VisualIntelligencePipelineTests`, `DiverKitTests`, and `DiverSharedTests`.
- Conventions: keep tests deterministic; name as `test_<behavior>_<condition>()` and co-locate helpers in the test target.
- Run package tests first (`swift test`) before simulator/UI test passes.

## Commit & Pull Request Guidelines

- Commits: short and imperative (e.g., "Update Package.swift", "Fix location persistence"); start with a verb.
- PRs: include a brief description, link the issue (if any), and add screenshots/screen recordings for UI changes.

## Security & Configuration Tips

- Don't commit tokens, API keys, or user data. Prefer local config and platform-secure storage (Keychain) when adding credentials.
