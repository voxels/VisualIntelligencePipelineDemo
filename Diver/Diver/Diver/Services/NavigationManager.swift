//
//  NavigationManager.swift
//  Diver
//
//  Created by Claude on 12/24/25.
//

import SwiftUI
import DiverShared
import DiverKit

class NavigationManager: ObservableObject {
    @Published var selection: ProcessedItem?
    @Published var isScanActive: Bool = false
    @Published var searchQuery: String = ""
    @Published var isSearching: Bool = false
}
