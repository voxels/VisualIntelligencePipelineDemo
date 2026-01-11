//
//  ToastManager.swift
//  Diver
//
//  Created by Cascade
//

import SwiftUI
import Combine

enum ToastType {
    case success
    case error
    case info
    case warning
    
    var icon: String {
        switch self {
        case .success: return "checkmark.circle.fill"
        case .error: return "xmark.circle.fill"
        case .info: return "info.circle.fill"
        case .warning: return "exclamationmark.triangle.fill"
        }
    }
    
    var color: Color {
        switch self {
        case .success: return .green
        case .error: return .red
        case .info: return .blue
        case .warning: return .orange
        }
    }
}

struct ToastNotification: Identifiable, Equatable {
    let id = UUID()
    let type: ToastType
    let title: String
    let message: String?
    let duration: TimeInterval
    
    init(type: ToastType, title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        self.type = type
        self.title = title
        self.message = message
        self.duration = duration
    }
    
    static func == (lhs: ToastNotification, rhs: ToastNotification) -> Bool {
        lhs.id == rhs.id
    }
}

@MainActor
class ToastManager: ObservableObject {
    static let shared = ToastManager()
    
    @Published var currentToast: ToastNotification?
    private var workItem: DispatchWorkItem?
    
    private init() {}
    
    func show(_ toast: ToastNotification) {
        // Cancel any existing auto-dismiss
        workItem?.cancel()
        
        // Show the new toast
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentToast = toast
        }
        
        // Auto-dismiss after duration
        let task = DispatchWorkItem { [weak self] in
            Task { @MainActor in
                self?.dismiss()
            }
        }
        workItem = task
        DispatchQueue.main.asyncAfter(deadline: .now() + toast.duration, execute: task)
    }
    
    func show(type: ToastType, title: String, message: String? = nil, duration: TimeInterval = 3.0) {
        let toast = ToastNotification(type: type, title: title, message: message, duration: duration)
        show(toast)
    }
    
    func dismiss() {
        workItem?.cancel()
        withAnimation(.spring(response: 0.3, dampingFraction: 0.7)) {
            currentToast = nil
        }
    }
    
    // Convenience methods
    func success(_ title: String, message: String? = nil) {
        show(type: .success, title: title, message: message)
    }
    
    func error(_ title: String, message: String? = nil) {
        show(type: .error, title: title, message: message, duration: 4.0)
    }
    
    func info(_ title: String, message: String? = nil) {
        show(type: .info, title: title, message: message)
    }
    
    func warning(_ title: String, message: String? = nil) {
        show(type: .warning, title: title, message: message)
    }
}
