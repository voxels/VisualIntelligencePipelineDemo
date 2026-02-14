//
//  NavigationManager.swift
//  Diver
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import DiverShared
import DiverKit
import PhotosUI

class NavigationManager: ObservableObject {
    @Published var selectedSession: DiverSession?
    @Published var selection: ProcessedItem?
    @Published var isScanActive: Bool = false
    @Published var scanSessionID: String?
    @Published var pendingImportItems: [PhotosPickerItem] = []
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
}
