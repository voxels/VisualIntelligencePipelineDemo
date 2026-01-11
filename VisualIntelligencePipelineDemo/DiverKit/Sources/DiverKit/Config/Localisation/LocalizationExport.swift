//
//  LocalizationExport.swift
//  Diver
//
//  Utility for exporting/importing translations to/from JSON
//

import Foundation

/// Helper for exporting localization strings to JSON format for translators
struct LocalizationExporter {
    
    /// Export all strings for a specific language to JSON
    static func exportToJSON(language: AppLanguage) -> String {
        var translations: [String: String] = [:]
        
        // Get all cases using reflection (simplified version)
        // In production, you'd iterate through all LocalizedStringKey cases
        let sampleKeys: [LocalizedStringKey] = [
            .appName, .cancel, .save, .delete, .edit, .done,
            .login, .logout, .signUp, .email, .password,
            .allInputs, .pendingInputs, .account,
            .newInput, .createInput, .inputUrl,
            .chat, .sendMessage, .typeMessage,
            .playingTrack, .pausedPlayback, .failedToPlay,
            .trackSaved, .uploadComplete, .connectionError,
            .noResults, .noLinks,
            .genericError, .networkError, .authenticationError,
            .addLink, .shareLink, .copyLink
        ]
        
        for key in sampleKeys {
            let keyName = String(describing: key)
            translations[keyName] = key.localized(for: language)
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(translations),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
    
    /// Export all languages to separate JSON files
    static func exportAllLanguages() -> [AppLanguage: String] {
        var exports: [AppLanguage: String] = [:]
        
        for language in AppLanguage.allCases {
            exports[language] = exportToJSON(language: language)
        }
        
        return exports
    }
    
    /// Generate a translation template for new strings
    static func generateTranslationTemplate(keys: [String]) -> String {
        var template: [String: String] = [:]
        
        for key in keys {
            template[key] = "TODO: Translate '\(key)'"
        }
        
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        
        if let jsonData = try? encoder.encode(template),
           let jsonString = String(data: jsonData, encoding: .utf8) {
            return jsonString
        }
        
        return "{}"
    }
}

// MARK: - Example Usage

/*
 
 # EXPORTING TRANSLATIONS FOR TRANSLATORS
 
 ## Export all languages to JSON
 ```swift
 let exports = LocalizationExporter.exportAllLanguages()
 
 for (language, json) in exports {
     print("=== \(language.displayName) ===")
     print(json)
     print("\n")
 }
 ```
 
 ## Export single language
 ```swift
 let spanishJSON = LocalizationExporter.exportToJSON(language: .spanish)
 print(spanishJSON)
 ```
 
 ## Generate template for new keys
 ```swift
 let newKeys = ["settingsTitle", "notificationsEnabled", "darkMode"]
 let template = LocalizationExporter.generateTranslationTemplate(keys: newKeys)
 print(template)
 ```
 
 ## Sample JSON Output
 ```json
 {
   "account": "Account",
   "addLink": "Add Link",
   "allInputs": "All Inputs",
   "appName": "Visual Intelligence",
   "cancel": "Cancel",
   "chat": "Chat",
   "connectionError": "Connection error",
   "copyLink": "Copy Link",
   "createInput": "Create Input",
   "delete": "Delete",
   "done": "Done",
   "edit": "Edit",
   "email": "Email",
   "failedToPlay": "Failed to start playback",
   "genericError": "Something went wrong",
   "inputUrl": "URL",
   "login": "Login",
   "logout": "Logout",
   "networkError": "Network error. Please check your connection.",
   "newInput": "New Input",
   "noLinks": "No Links",
   "noResults": "No Results",
   "password": "Password",
   "pausedPlayback": "Playback paused",
   "pendingInputs": "Pending Inputs",
   "playingTrack": "Playing track",
   "save": "Save",
   "sendMessage": "Send",
   "shareLink": "Share Link",
   "signUp": "Sign Up",
   "trackSaved": "Track saved!",
   "typeMessage": "Type a message...",
   "uploadComplete": "Upload complete"
 }
 ```
 
 ## Workflow for Adding Translations
 
 1. **Developer adds new LocalizedStringKey cases**
 2. **Export English version to JSON**
    ```swift
    let englishJSON = LocalizationExporter.exportToJSON(language: .english)
    ```
 3. **Send JSON to translators** for each target language
 4. **Translators return translated JSON files**
 5. **Developer updates LocalizedStringKey** with translations from JSON
 
 ## Benefits
 
 - Translators work with familiar JSON format
 - Easy to track missing translations
 - Can use translation management tools
 - Version control friendly
 - Can automate with CI/CD
 
 */
