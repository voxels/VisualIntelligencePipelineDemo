//
//  IconService.swift
//  Diver
//
//  Icon utility service using SF Symbols
//  https://developer.apple.com/sf-symbols/
//

import SwiftUI

public enum IconWeight: String {
    case ultraLight
    case thin
    case light
    case regular
    case medium
    case semibold
    case bold
    case heavy
    case black
}

public enum IconService {
    /// Returns an SF Symbol icon with specified style
    /// - Parameters:
    ///   - name: The SF Symbol name (e.g., "arrow.down.doc", "eyeglasses")
    ///   - size: The size of the icon (default: 24)
    ///   - weight: The weight/style of the icon (default: .regular)
    /// - Returns: A SwiftUI Image view with the SF Symbol
    public static func icon(
        _ name: String,
        size: CGFloat = 24,
        weight: IconWeight = .regular
    ) -> some View {
        Image(systemName: sfSymbolName(for: name))
            .font(.system(size: size, weight: fontWeight(for: weight)))
            .frame(width: size, height: size)
    }
    
    /// Maps custom icon names to SF Symbol names
    private static func sfSymbolName(for name: String) -> String {
        switch name {
        case "file-arrow-down":
            return "arrow.down.doc"
        case "eyeglasses":
            return "eyeglasses"
        case "backspace":
            return "delete.backward"
        default:
            return "questionmark.circle"
        }
    }
    
    /// Converts IconWeight to Font.Weight
    private static func fontWeight(for weight: IconWeight) -> Font.Weight {
        switch weight {
        case .ultraLight: return .ultraLight
        case .thin: return .thin
        case .light: return .light
        case .regular: return .regular
        case .medium: return .medium
        case .semibold: return .semibold
        case .bold: return .bold
        case .heavy: return .heavy
        case .black: return .black
        }
    }
    
    /// Returns an SF Symbol icon as a button
    /// - Parameters:
    ///   - name: The SF Symbol name
    ///   - size: The size of the icon (default: 24)
    ///   - weight: The weight/style of the icon (default: .regular)
    ///   - action: The action to perform when button is tapped
    /// - Returns: A SwiftUI Button with the SF Symbol icon
    @MainActor
    public static func iconButton(
        _ name: String,
        size: CGFloat = 24,
        weight: IconWeight = .regular,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            icon(name, size: size, weight: weight)
        }
        .buttonStyle(.plain)
    }
}
