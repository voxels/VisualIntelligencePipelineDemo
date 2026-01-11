# Localisation

Multi-language support for the Diver app.

## Files

- **LocalizedStrings.swift** - Main implementation with all app strings in 5 languages
- **LocalizationExport.swift** - Utility for exporting translations to JSON

## Supported Languages

- 🇬🇧 English (en) - Default
- 🇪🇸 Spanish (es)
- 🇫🇷 French (fr)
- 🇩🇪 German (de)
- 🇯🇵 Japanese (ja)

## Quick Usage

```swift
// SwiftUI
Text(.allInputs)
Button(LocalizedStringKey.save.localized) { }

// Swift code
let message = LocalizedStringKey.noInputsMessage.localized
ToastManager.shared.success(LocalizedStringKey.trackSaved.localized)

// Change language
LocalizationManager.shared.setLanguage(.spanish)
```

## Adding New Strings

1. Add case to `LocalizedStringKey` enum in `LocalizedStrings.swift`
2. Add translation in each language section:
   - `englishString`
   - `spanishString`
   - `frenchString`
   - `germanString`
   - `japaneseString`

## String Categories

- General (save, cancel, delete, etc.)
- Authentication (login, signup, passwords)
- Sidebar (navigation items)
- Inputs (input management)
- Chat (chat interface)
- Spotify (music playback)
- Toast Messages (notifications)
- Empty States (no content messages)
- Errors (error messages)
- Actions (user actions)
- Time (relative time strings)

## For Translators

Export strings to JSON:

```swift
let json = LocalizationExporter.exportToJSON(language: .spanish)
```

See `LocalizationExport.swift` for more details.
