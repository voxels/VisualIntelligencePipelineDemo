//
//  PlatformImage.swift
//  DiverUI
//
//  Cross-platform image abstraction.
//  Use PlatformImage and Image(diverData:) throughout DiverUI —
//  never UIImage or NSImage directly.
//

import SwiftUI

#if os(macOS)
import AppKit
public typealias PlatformImage = NSImage
#else
import UIKit
public typealias PlatformImage = UIImage
#endif

// MARK: - Image init from Data

public extension Image {
    /// Creates a SwiftUI Image from raw Data (JPEG/PNG/HEIC).
    /// Returns nil-safe via the optional PlatformImage init.
    init?(diverData data: Data) {
        guard let platform = PlatformImage(data: data) else { return nil }
        self.init(platformImage: platform)
    }

    /// Creates a SwiftUI Image from a PlatformImage (NSImage on macOS, UIImage on iOS/visionOS).
    init(platformImage image: PlatformImage) {
#if os(macOS)
        self.init(nsImage: image)
#else
        self.init(uiImage: image)
#endif
    }
}

// MARK: - Thumbnail View

/// A fixed-size image view backed by raw Data. Graceful fallback to a system icon.
public struct DiverThumbnail: View {
    public let data: Data?
    public let fallbackIcon: String
    public let size: CGFloat
    public let cornerRadius: CGFloat

    public init(
        data: Data?,
        fallbackIcon: String = "photo",
        size: CGFloat = 44,
        cornerRadius: CGFloat = 7
    ) {
        self.data = data
        self.fallbackIcon = fallbackIcon
        self.size = size
        self.cornerRadius = cornerRadius
    }

    public var body: some View {
        Group {
            if let data, let img = Image(diverData: data) {
                img
                    .resizable()
                    .scaledToFill()
            } else {
                Image(systemName: fallbackIcon)
                    .font(.system(size: size * 0.35))
                    .foregroundStyle(.secondary)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                    .background(.secondary.opacity(0.1))
            }
        }
        .frame(width: size, height: size)
        .clipShape(RoundedRectangle(cornerRadius: cornerRadius))
    }
}
