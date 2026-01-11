//
//  MetadataViewModel.swift
//  ActionExtension
//
//  Created by Claude on 12/24/25.
//

import Foundation
import Combine

class MetadataViewModel: ObservableObject {
    @Published var metadata: LinkMetadata
    
    init(metadata: LinkMetadata) {
        self.metadata = metadata
    }
}
