//
//  ToastManager+Examples.swift
//  Diver
//
//  Usage examples for ToastManager
//

import Foundation

/*
 
 USAGE EXAMPLES:
 
 1. Show a success toast:
    ToastManager.shared.success("Track saved!")
 
 2. Show an error toast with details:
    ToastManager.shared.error("Failed to load", message: "Please check your connection")
 
 3. Show an info toast:
    ToastManager.shared.info("New message received")
 
 4. Show a warning toast:
    ToastManager.shared.warning("Storage almost full")
 
 5. Custom toast with specific duration:
    ToastManager.shared.show(
        type: .success,
        title: "Upload complete",
        message: "Your file has been uploaded",
        duration: 5.0
    )
 
 6. Manually dismiss current toast:
    ToastManager.shared.dismiss()
 
 INTEGRATION:
 
 The toast system is already integrated at the app level via RouterView.
 You can call ToastManager.shared from anywhere in your app without any setup.
 
 The toast will automatically appear at the top of the screen and dismiss after
 the specified duration (default 3 seconds for most types, 4 seconds for errors).
 
 */
