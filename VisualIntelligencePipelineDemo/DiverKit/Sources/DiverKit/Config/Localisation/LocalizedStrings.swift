//
//  LocalizedStrings.swift
//  Diver
//
//  Centralized localization configuration for all app strings
//

import Foundation

/// Supported languages in the app
enum AppLanguage: String, CaseIterable {
    case english = "en"
    case spanish = "es"
    case french = "fr"
    case german = "de"
    case japanese = "ja"
    
    var displayName: String {
        switch self {
        case .english: return "English"
        case .spanish: return "Español"
        case .french: return "Français"
        case .german: return "Deutsch"
        case .japanese: return "日本語"
        }
    }
}

/// Main localization manager|
@MainActor
public class LocalizationManager: ObservableObject {
    @MainActor public static let shared = LocalizationManager()
    
    @Published @MainActor var currentLanguage: AppLanguage = .english
    
    @MainActor
    private init() {
        // Load saved language preference or use system default
        if let savedLang = UserDefaults.standard.string(forKey: "app_language"),
           let language = AppLanguage(rawValue: savedLang) {
            Task { @MainActor in
                currentLanguage = language
            }
        }
    }
    
    @MainActor
    func setLanguage(_ language: AppLanguage) {
        currentLanguage = language
        UserDefaults.standard.set(language.rawValue, forKey: "app_language")
    }
    
    nonisolated func string(for key: LocalizedStringKey) -> String {
        // Get current language synchronously from UserDefaults
        let savedLang = UserDefaults.standard.string(forKey: "app_language")
        let language = savedLang.flatMap { AppLanguage(rawValue: $0) } ?? .english
        return key.localized(for: language)
    }
}

/// All localized string keys in the app
enum LocalizedStringKey {
    // MARK: - General
    case appName
    case cancel
    case save
    case delete
    case edit
    case done
    case close
    case back
    case next
    case search
    case loading
    case error
    case success
    case retry
    
    // MARK: - Authentication
    case login
    case logout
    case signUp
    case email
    case password
    case forgotPassword
    case createAccount
    case welcomeBack
    case getStarted
    
    // MARK: - Sidebar
    case allInputs
    case pendingInputs
    case account
    case settings
    
    // MARK: - Inputs
    case newInput
    case createInput
    case inputUrl
    case inputType
    case inputTitle
    case inputDescription
    case noInputsTitle
    case noInputsMessage
    case selectCategory
    case selectCategoryMessage
    case noInputSelected
    case noInputSelectedMessage
    
    // MARK: - Chat
    case chat
    case sendMessage
    case typeMessage
    case hideChat
    case showChat
    case openInBrowser
    
    // MARK: - Spotify
    case playingTrack
    case pausedPlayback
    case failedToPlay
    case noDevicesAvailable
    case spotifyNotConnected
    case connectSpotify
    
    // MARK: - Toast Messages
    case trackSaved
    case uploadComplete
    case storageAlmostFull
    case connectionError
    case invalidUrl
    
    // MARK: - Empty States
    case noResults
    case noResultsMessage
    case noLinks
    case noLinksMessage
    
    // MARK: - Errors
    case genericError
    case networkError
    case authenticationError
    case validationError
    
    // MARK: - Actions
    case addLink
    case addLinkFromClipboard
    case addLinkManually
    case shareLink
    case copyLink
    case deleteLink
    
    // MARK: - Time
    case justNow
    case minutesAgo(Int)
    case hoursAgo(Int)
    case daysAgo(Int)
    
    // Get localized string for current language
    func localized(for language: AppLanguage = .english) -> String {
        switch language {
        case .english:
            return englishString
        case .spanish:
            return spanishString
        case .french:
            return frenchString
        case .german:
            return germanString
        case .japanese:
            return japaneseString
        }
    }
    
    // MARK: - English Strings
    private var englishString: String {
        switch self {
        // General
        case .appName: return "Visual Intelligence"
        case .cancel: return "Cancel"
        case .save: return "Save"
        case .delete: return "Delete"
        case .edit: return "Edit"
        case .done: return "Done"
        case .close: return "Close"
        case .back: return "Back"
        case .next: return "Next"
        case .search: return "Search"
        case .loading: return "Loading..."
        case .error: return "Error"
        case .success: return "Success"
        case .retry: return "Retry"
            
        // Authentication
        case .login: return "Login"
        case .logout: return "Logout"
        case .signUp: return "Sign Up"
        case .email: return "Email"
        case .password: return "Password"
        case .forgotPassword: return "Forgot Password?"
        case .createAccount: return "Create Account"
        case .welcomeBack: return "Welcome Back"
        case .getStarted: return "Get Started"
            
        // Sidebar
        case .allInputs: return "All Inputs"
        case .pendingInputs: return "Pending Inputs"
        case .account: return "Account"
        case .settings: return "Settings"
            
        // Inputs
        case .newInput: return "New Input"
        case .createInput: return "Create Input"
        case .inputUrl: return "URL"
        case .inputType: return "Type"
        case .inputTitle: return "Title"
        case .inputDescription: return "Description"
        case .noInputsTitle: return "No Inputs"
        case .noInputsMessage: return "Share links from Safari or other apps to get started"
        case .selectCategory: return "Select a Category"
        case .selectCategoryMessage: return "Choose a category from the sidebar to view your links"
        case .noInputSelected: return "No Link Selected"
        case .noInputSelectedMessage: return "Select a link to view its details"
            
        // Chat
        case .chat: return "Chat"
        case .sendMessage: return "Send"
        case .typeMessage: return "Type a message..."
        case .hideChat: return "Hide Chat"
        case .showChat: return "Show Chat"
        case .openInBrowser: return "Open in Browser"
            
        // Spotify
        case .playingTrack: return "Playing track"
        case .pausedPlayback: return "Playback paused"
        case .failedToPlay: return "Failed to start playback"
        case .noDevicesAvailable: return "No devices available. Try opening the Spotify app on one of your devices."
        case .spotifyNotConnected: return "Spotify not connected"
        case .connectSpotify: return "Connect Spotify"
            
        // Toast Messages
        case .trackSaved: return "Track saved!"
        case .uploadComplete: return "Upload complete"
        case .storageAlmostFull: return "Storage almost full"
        case .connectionError: return "Connection error"
        case .invalidUrl: return "Invalid URL"
            
        // Empty States
        case .noResults: return "No Results"
        case .noResultsMessage: return "Try adjusting your search"
        case .noLinks: return "No Links"
        case .noLinksMessage: return "Add your first link to get started"
            
        // Errors
        case .genericError: return "Something went wrong"
        case .networkError: return "Network error. Please check your connection."
        case .authenticationError: return "Authentication failed"
        case .validationError: return "Please check your input"
            
        // Actions
        case .addLink: return "Add Link"
        case .addLinkFromClipboard: return "Add Link from Clipboard"
        case .addLinkManually: return "Add Link Manually"
        case .shareLink: return "Share Link"
        case .copyLink: return "Copy Link"
        case .deleteLink: return "Delete Link"
            
        // Time
        case .justNow: return "Just now"
        case .minutesAgo(let count): return "\(count) minute\(count == 1 ? "" : "s") ago"
        case .hoursAgo(let count): return "\(count) hour\(count == 1 ? "" : "s") ago"
        case .daysAgo(let count): return "\(count) day\(count == 1 ? "" : "s") ago"
        }
    }
    
    // MARK: - Spanish Strings
    private var spanishString: String {
        switch self {
        // General
        case .appName: return "Visual Intelligence"
        case .cancel: return "Cancelar"
        case .save: return "Guardar"
        case .delete: return "Eliminar"
        case .edit: return "Editar"
        case .done: return "Hecho"
        case .close: return "Cerrar"
        case .back: return "Atrás"
        case .next: return "Siguiente"
        case .search: return "Buscar"
        case .loading: return "Cargando..."
        case .error: return "Error"
        case .success: return "Éxito"
        case .retry: return "Reintentar"
            
        // Authentication
        case .login: return "Iniciar sesión"
        case .logout: return "Cerrar sesión"
        case .signUp: return "Registrarse"
        case .email: return "Correo electrónico"
        case .password: return "Contraseña"
        case .forgotPassword: return "¿Olvidaste tu contraseña?"
        case .createAccount: return "Crear cuenta"
        case .welcomeBack: return "Bienvenido de nuevo"
        case .getStarted: return "Comenzar"
            
        // Sidebar
        case .allInputs: return "Todas las entradas"
        case .pendingInputs: return "Entradas pendientes"
        case .account: return "Cuenta"
        case .settings: return "Configuración"
            
        // Inputs
        case .newInput: return "Nueva entrada"
        case .createInput: return "Crear entrada"
        case .inputUrl: return "URL"
        case .inputType: return "Tipo"
        case .inputTitle: return "Título"
        case .inputDescription: return "Descripción"
        case .noInputsTitle: return "Sin entradas"
        case .noInputsMessage: return "Comparte enlaces desde Safari u otras aplicaciones para comenzar"
        case .selectCategory: return "Selecciona una categoría"
        case .selectCategoryMessage: return "Elige una categoría de la barra lateral para ver tus enlaces"
        case .noInputSelected: return "Ningún enlace seleccionado"
        case .noInputSelectedMessage: return "Selecciona un enlace para ver sus detalles"
            
        // Chat
        case .chat: return "Chat"
        case .sendMessage: return "Enviar"
        case .typeMessage: return "Escribe un mensaje..."
        case .hideChat: return "Ocultar chat"
        case .showChat: return "Mostrar chat"
        case .openInBrowser: return "Abrir en navegador"
            
        // Spotify
        case .playingTrack: return "Reproduciendo pista"
        case .pausedPlayback: return "Reproducción pausada"
        case .failedToPlay: return "Error al iniciar reproducción"
        case .noDevicesAvailable: return "No hay dispositivos disponibles. Intenta abrir la aplicación de Spotify en uno de tus dispositivos."
        case .spotifyNotConnected: return "Spotify no conectado"
        case .connectSpotify: return "Conectar Spotify"
            
        // Toast Messages
        case .trackSaved: return "¡Pista guardada!"
        case .uploadComplete: return "Carga completa"
        case .storageAlmostFull: return "Almacenamiento casi lleno"
        case .connectionError: return "Error de conexión"
        case .invalidUrl: return "URL inválida"
            
        // Empty States
        case .noResults: return "Sin resultados"
        case .noResultsMessage: return "Intenta ajustar tu búsqueda"
        case .noLinks: return "Sin enlaces"
        case .noLinksMessage: return "Agrega tu primer enlace para comenzar"
            
        // Errors
        case .genericError: return "Algo salió mal"
        case .networkError: return "Error de red. Por favor verifica tu conexión."
        case .authenticationError: return "Autenticación fallida"
        case .validationError: return "Por favor verifica tu entrada"
            
        // Actions
        case .addLink: return "Agregar enlace"
        case .addLinkFromClipboard: return "Agregar enlace desde portapapeles"
        case .addLinkManually: return "Agregar enlace manualmente"
        case .shareLink: return "Compartir enlace"
        case .copyLink: return "Copiar enlace"
        case .deleteLink: return "Eliminar enlace"
            
        // Time
        case .justNow: return "Justo ahora"
        case .minutesAgo(let count): return "Hace \(count) minuto\(count == 1 ? "" : "s")"
        case .hoursAgo(let count): return "Hace \(count) hora\(count == 1 ? "" : "s")"
        case .daysAgo(let count): return "Hace \(count) día\(count == 1 ? "" : "s")"
        }
    }
    
    // MARK: - French Strings
    private var frenchString: String {
        switch self {
        // General
        case .appName: return "Visual Intelligence"
        case .cancel: return "Annuler"
        case .save: return "Enregistrer"
        case .delete: return "Supprimer"
        case .edit: return "Modifier"
        case .done: return "Terminé"
        case .close: return "Fermer"
        case .back: return "Retour"
        case .next: return "Suivant"
        case .search: return "Rechercher"
        case .loading: return "Chargement..."
        case .error: return "Erreur"
        case .success: return "Succès"
        case .retry: return "Réessayer"
            
        // Authentication
        case .login: return "Connexion"
        case .logout: return "Déconnexion"
        case .signUp: return "S'inscrire"
        case .email: return "Email"
        case .password: return "Mot de passe"
        case .forgotPassword: return "Mot de passe oublié?"
        case .createAccount: return "Créer un compte"
        case .welcomeBack: return "Bon retour"
        case .getStarted: return "Commencer"
            
        // Sidebar
        case .allInputs: return "Toutes les entrées"
        case .pendingInputs: return "Entrées en attente"
        case .account: return "Compte"
        case .settings: return "Paramètres"
            
        // Inputs
        case .newInput: return "Nouvelle entrée"
        case .createInput: return "Créer une entrée"
        case .inputUrl: return "URL"
        case .inputType: return "Type"
        case .inputTitle: return "Titre"
        case .inputDescription: return "Description"
        case .noInputsTitle: return "Aucune entrée"
        case .noInputsMessage: return "Partagez des liens depuis Safari ou d'autres applications pour commencer"
        case .selectCategory: return "Sélectionner une catégorie"
        case .selectCategoryMessage: return "Choisissez une catégorie dans la barre latérale pour voir vos liens"
        case .noInputSelected: return "Aucun lien sélectionné"
        case .noInputSelectedMessage: return "Sélectionnez un lien pour voir ses détails"
            
        // Chat
        case .chat: return "Chat"
        case .sendMessage: return "Envoyer"
        case .typeMessage: return "Tapez un message..."
        case .hideChat: return "Masquer le chat"
        case .showChat: return "Afficher le chat"
        case .openInBrowser: return "Ouvrir dans le navigateur"
            
        // Spotify
        case .playingTrack: return "Lecture de la piste"
        case .pausedPlayback: return "Lecture en pause"
        case .failedToPlay: return "Échec du démarrage de la lecture"
        case .noDevicesAvailable: return "Aucun appareil disponible. Essayez d'ouvrir l'application Spotify sur l'un de vos appareils."
        case .spotifyNotConnected: return "Spotify non connecté"
        case .connectSpotify: return "Connecter Spotify"
            
        // Toast Messages
        case .trackSaved: return "Piste enregistrée!"
        case .uploadComplete: return "Téléchargement terminé"
        case .storageAlmostFull: return "Stockage presque plein"
        case .connectionError: return "Erreur de connexion"
        case .invalidUrl: return "URL invalide"
            
        // Empty States
        case .noResults: return "Aucun résultat"
        case .noResultsMessage: return "Essayez d'ajuster votre recherche"
        case .noLinks: return "Aucun lien"
        case .noLinksMessage: return "Ajoutez votre premier lien pour commencer"
            
        // Errors
        case .genericError: return "Quelque chose s'est mal passé"
        case .networkError: return "Erreur réseau. Veuillez vérifier votre connexion."
        case .authenticationError: return "Échec de l'authentification"
        case .validationError: return "Veuillez vérifier votre saisie"
            
        // Actions
        case .addLink: return "Ajouter un lien"
        case .addLinkFromClipboard: return "Ajouter un lien depuis le presse-papiers"
        case .addLinkManually: return "Ajouter un lien manuellement"
        case .shareLink: return "Partager le lien"
        case .copyLink: return "Copier le lien"
        case .deleteLink: return "Supprimer le lien"
            
        // Time
        case .justNow: return "À l'instant"
        case .minutesAgo(let count): return "Il y a \(count) minute\(count == 1 ? "" : "s")"
        case .hoursAgo(let count): return "Il y a \(count) heure\(count == 1 ? "" : "s")"
        case .daysAgo(let count): return "Il y a \(count) jour\(count == 1 ? "" : "s")"
        }
    }
    
    // MARK: - German Strings
    private var germanString: String {
        switch self {
        // General
        case .appName: return "Visaul Intelligence"
        case .cancel: return "Abbrechen"
        case .save: return "Speichern"
        case .delete: return "Löschen"
        case .edit: return "Bearbeiten"
        case .done: return "Fertig"
        case .close: return "Schließen"
        case .back: return "Zurück"
        case .next: return "Weiter"
        case .search: return "Suchen"
        case .loading: return "Lädt..."
        case .error: return "Fehler"
        case .success: return "Erfolg"
        case .retry: return "Wiederholen"
            
        // Authentication
        case .login: return "Anmelden"
        case .logout: return "Abmelden"
        case .signUp: return "Registrieren"
        case .email: return "E-Mail"
        case .password: return "Passwort"
        case .forgotPassword: return "Passwort vergessen?"
        case .createAccount: return "Konto erstellen"
        case .welcomeBack: return "Willkommen zurück"
        case .getStarted: return "Loslegen"
            
        // Sidebar
        case .allInputs: return "Alle Eingaben"
        case .pendingInputs: return "Ausstehende Eingaben"
        case .account: return "Konto"
        case .settings: return "Einstellungen"
            
        // Inputs
        case .newInput: return "Neue Eingabe"
        case .createInput: return "Eingabe erstellen"
        case .inputUrl: return "URL"
        case .inputType: return "Typ"
        case .inputTitle: return "Titel"
        case .inputDescription: return "Beschreibung"
        case .noInputsTitle: return "Keine Eingaben"
        case .noInputsMessage: return "Teilen Sie Links aus Safari oder anderen Apps, um zu beginnen"
        case .selectCategory: return "Kategorie auswählen"
        case .selectCategoryMessage: return "Wählen Sie eine Kategorie aus der Seitenleiste, um Ihre Links anzuzeigen"
        case .noInputSelected: return "Kein Link ausgewählt"
        case .noInputSelectedMessage: return "Wählen Sie einen Link aus, um Details anzuzeigen"
            
        // Chat
        case .chat: return "Chat"
        case .sendMessage: return "Senden"
        case .typeMessage: return "Nachricht eingeben..."
        case .hideChat: return "Chat ausblenden"
        case .showChat: return "Chat anzeigen"
        case .openInBrowser: return "Im Browser öffnen"
            
        // Spotify
        case .playingTrack: return "Titel wird abgespielt"
        case .pausedPlayback: return "Wiedergabe pausiert"
        case .failedToPlay: return "Wiedergabe konnte nicht gestartet werden"
        case .noDevicesAvailable: return "Keine Geräte verfügbar. Versuchen Sie, die Spotify-App auf einem Ihrer Geräte zu öffnen."
        case .spotifyNotConnected: return "Spotify nicht verbunden"
        case .connectSpotify: return "Spotify verbinden"
            
        // Toast Messages
        case .trackSaved: return "Titel gespeichert!"
        case .uploadComplete: return "Upload abgeschlossen"
        case .storageAlmostFull: return "Speicher fast voll"
        case .connectionError: return "Verbindungsfehler"
        case .invalidUrl: return "Ungültige URL"
            
        // Empty States
        case .noResults: return "Keine Ergebnisse"
        case .noResultsMessage: return "Versuchen Sie, Ihre Suche anzupassen"
        case .noLinks: return "Keine Links"
        case .noLinksMessage: return "Fügen Sie Ihren ersten Link hinzu, um zu beginnen"
            
        // Errors
        case .genericError: return "Etwas ist schief gelaufen"
        case .networkError: return "Netzwerkfehler. Bitte überprüfen Sie Ihre Verbindung."
        case .authenticationError: return "Authentifizierung fehlgeschlagen"
        case .validationError: return "Bitte überprüfen Sie Ihre Eingabe"
            
        // Actions
        case .addLink: return "Link hinzufügen"
        case .addLinkFromClipboard: return "Link aus Zwischenablage hinzufügen"
        case .addLinkManually: return "Link manuell hinzufügen"
        case .shareLink: return "Link teilen"
        case .copyLink: return "Link kopieren"
        case .deleteLink: return "Link löschen"
            
        // Time
        case .justNow: return "Gerade eben"
        case .minutesAgo(let count): return "Vor \(count) Minute\(count == 1 ? "" : "n")"
        case .hoursAgo(let count): return "Vor \(count) Stunde\(count == 1 ? "" : "n")"
        case .daysAgo(let count): return "Vor \(count) Tag\(count == 1 ? "" : "en")"
        }
    }
    
    // MARK: - Japanese Strings
    private var japaneseString: String {
        switch self {
        // General
        case .appName: return "Visual Intelligence"
        case .cancel: return "キャンセル"
        case .save: return "保存"
        case .delete: return "削除"
        case .edit: return "編集"
        case .done: return "完了"
        case .close: return "閉じる"
        case .back: return "戻る"
        case .next: return "次へ"
        case .search: return "検索"
        case .loading: return "読み込み中..."
        case .error: return "エラー"
        case .success: return "成功"
        case .retry: return "再試行"
            
        // Authentication
        case .login: return "ログイン"
        case .logout: return "ログアウト"
        case .signUp: return "サインアップ"
        case .email: return "メール"
        case .password: return "パスワード"
        case .forgotPassword: return "パスワードをお忘れですか？"
        case .createAccount: return "アカウント作成"
        case .welcomeBack: return "おかえりなさい"
        case .getStarted: return "始める"
            
        // Sidebar
        case .allInputs: return "すべての入力"
        case .pendingInputs: return "保留中の入力"
        case .account: return "アカウント"
        case .settings: return "設定"
            
        // Inputs
        case .newInput: return "新しい入力"
        case .createInput: return "入力を作成"
        case .inputUrl: return "URL"
        case .inputType: return "タイプ"
        case .inputTitle: return "タイトル"
        case .inputDescription: return "説明"
        case .noInputsTitle: return "入力なし"
        case .noInputsMessage: return "SafariまたはOther appsからリンクを共有して開始"
        case .selectCategory: return "カテゴリを選択"
        case .selectCategoryMessage: return "サイドバーからカテゴリを選択してリンクを表示"
        case .noInputSelected: return "リンクが選択されていません"
        case .noInputSelectedMessage: return "リンクを選択して詳細を表示"
            
        // Chat
        case .chat: return "チャット"
        case .sendMessage: return "送信"
        case .typeMessage: return "メッセージを入力..."
        case .hideChat: return "チャットを非表示"
        case .showChat: return "チャットを表示"
        case .openInBrowser: return "ブラウザで開く"
            
        // Spotify
        case .playingTrack: return "トラック再生中"
        case .pausedPlayback: return "再生一時停止"
        case .failedToPlay: return "再生開始に失敗"
        case .noDevicesAvailable: return "利用可能なデバイスがありません。デバイスでSpotifyアプリを開いてみてください。"
        case .spotifyNotConnected: return "Spotify未接続"
        case .connectSpotify: return "Spotifyに接続"
            
        // Toast Messages
        case .trackSaved: return "トラックを保存しました！"
        case .uploadComplete: return "アップロード完了"
        case .storageAlmostFull: return "ストレージがほぼ満杯"
        case .connectionError: return "接続エラー"
        case .invalidUrl: return "無効なURL"
            
        // Empty States
        case .noResults: return "結果なし"
        case .noResultsMessage: return "検索を調整してみてください"
        case .noLinks: return "リンクなし"
        case .noLinksMessage: return "最初のリンクを追加して開始"
            
        // Errors
        case .genericError: return "問題が発生しました"
        case .networkError: return "ネットワークエラー。接続を確認してください。"
        case .authenticationError: return "認証に失敗しました"
        case .validationError: return "入力を確認してください"
            
        // Actions
        case .addLink: return "リンクを追加"
        case .addLinkFromClipboard: return "クリップボードからリンクを追加"
        case .addLinkManually: return "手動でリンクを追加"
        case .shareLink: return "リンクを共有"
        case .copyLink: return "リンクをコピー"
        case .deleteLink: return "リンクを削除"
            
        // Time
        case .justNow: return "たった今"
        case .minutesAgo(let count): return "\(count)分前"
        case .hoursAgo(let count): return "\(count)時間前"
        case .daysAgo(let count): return "\(count)日前"
        }
    }
}

// MARK: - Convenience Extensions

@MainActor
extension LocalizedStringKey {
    /// Get localized string using current app language
    var localized: String {
        LocalizationManager.shared.string(for: self)
    }
}

// MARK: - SwiftUI Helper
import SwiftUI

@MainActor
extension Text {
    init(_ key: LocalizedStringKey) {
        self.init(key.localized)
    }
}
