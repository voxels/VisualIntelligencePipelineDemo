# Config Directory

Configuration files for the Diver app, including API settings and localization.

## Files

### API Configuration

- **APIConfig.swift** - API endpoints, base URLs, and network configuration

### Localisation

- **Localisation/** - Folder containing all localization files
  - **LocalizedStrings.swift** - Main localization implementation with all app strings in 5 languages
  - **LocalizationExport.swift** - Utility for exporting translations to JSON format

## Localization Quick Start

### Using Localized Strings

```swift
// In SwiftUI views
Text(.allInputs)
Button(LocalizedStringKey.save.localized) { }

// In Swift code
let message = LocalizedStringKey.noInputsMessage.localized
ToastManager.shared.success(LocalizedStringKey.trackSaved.localized)
```

### Supported Languages

- 🇬🇧 English (en) - Default
- 🇪🇸 Spanish (es)
- 🇫🇷 French (fr)
- 🇩🇪 German (de)
- 🇯🇵 Japanese (ja)

### Changing Language

```swift
LocalizationManager.shared.setLanguage(.spanish)
```

### Adding New Strings

1. Add case to `LocalizedStringKey` enum
2. Add translation in each language section:
   - `englishString`
   - `spanishString`
   - `frenchString`
   - `germanString`
   - `japaneseString`

## String Categories

All strings are organized into logical categories:

- **General** - Common UI (save, cancel, delete, etc.)
- **Authentication** - Login, signup, passwords
- **Sidebar** - Navigation items
- **Inputs** - Input management
- **Chat** - Chat interface
- **Spotify** - Music playback
- **Toast Messages** - Notifications
- **Empty States** - No content messages
- **Errors** - Error messages
- **Actions** - User actions
- **Time** - Relative time strings

## Common String Replacements

| Hardcoded | Localized |
|-----------|-----------|
| `"All Inputs"` | `.allInputs` |
| `"Save"` | `.save` |
| `"Cancel"` | `.cancel` |
| `"Search"` | `.search` |
| `"Chat"` | `.chat` |

## For Translators

Use `LocalizationExporter` to export strings to JSON format:

```swift
let spanishJSON = LocalizationExporter.exportToJSON(language: .spanish)
```

This generates translator-friendly JSON files that can be imported back into the app.

## Best Practices

1. ✅ Always use `LocalizedStringKey` for user-facing strings
2. ✅ Provide translations for all 5 supported languages
3. ✅ Use descriptive key names
4. ✅ Group related strings with MARK comments
5. ✅ Test all language variants
6. ❌ Never hardcode user-facing strings

## Architecture

```text
LocalizationManager (Singleton)
    ├── currentLanguage: AppLanguage
    ├── setLanguage(_:)
    └── string(for:) -> String

LocalizedStringKey (Enum)
    ├── All string keys as cases
    ├── localized(for:) -> String
    └── Language-specific computed properties
        ├── englishString
        ├── spanishString
        ├── frenchString
        ├── germanString
        └── japaneseString
```

## Storage

Language preference is automatically saved to `UserDefaults` with key `"app_language"` and persists across app launches.
