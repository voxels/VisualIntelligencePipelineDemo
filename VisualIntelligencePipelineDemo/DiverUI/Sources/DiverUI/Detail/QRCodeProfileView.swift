//
//  QRCodeProfileView.swift
//  DiverUI — cross-platform
//
//  QR generation uses CoreImage (cross-platform).
//  UIImage replaced with PlatformImage. RichWebView guarded with #if os(iOS).
//

import SwiftUI
import SwiftData
import DiverShared
import DiverKit
import CoreImage.CIFilterBuiltins

public struct QRCodeProfileView: View {
    public let item: ProcessedItem
    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        if let context = item.qrContext {
            VStack {
                QRCodeGeneratorView(context: context)
            }
            .padding(.horizontal).padding(.top, 16)
        }
    }
}

public struct QRCodeGeneratorView: View {
    public let context: QRCodeContext
    private let ciContext = CIContext()
    private let filter = CIFilter.qrCodeGenerator()

    public init(context: QRCodeContext) { self.context = context }

    public var body: some View {
        VStack(spacing: 16) {
            // Re-generated QR image
            if let platformImg = generateQRCode(from: context.payload) {
                Image(platformImage: platformImg)
                    .resizable().interpolation(.none).scaledToFit()
                    .frame(width: 200, height: 200).padding()
                    .background(Color.white).clipShape(RoundedRectangle(cornerRadius: 12)).shadow(radius: 4)
            } else {
                Image(systemName: "qrcode.viewfinder").font(.largeTitle).foregroundStyle(.secondary)
            }

            // Payload text
            VStack(spacing: 4) {
                Text("Scanned Content").font(.caption).fontWeight(.bold).foregroundStyle(.secondary)
                Text(context.payload).font(.body).multilineTextAlignment(.center).textSelection(.enabled)
            }

            // Web view for URL payloads
            if let url = URL(string: context.payload), ["http","https"].contains(url.scheme?.lowercased()) {
                Divider()
                #if os(iOS)
                RichWebView(url: url).frame(height: 300).clipShape(RoundedRectangle(cornerRadius: 12))
                #else
                Link(destination: url) {
                    Label("Open in Browser", systemImage: "safari").font(.subheadline)
                }.buttonStyle(.bordered)
                #endif
            }
        }
        .frame(maxWidth: .infinity).padding()
        .background(Color.secondary.opacity(0.1)).clipShape(RoundedRectangle(cornerRadius: 16))
    }

    private func generateQRCode(from string: String) -> PlatformImage? {
        filter.message = Data(string.utf8)
        guard let outputImage = filter.outputImage else { return nil }
        let scaled = outputImage.transformed(by: CGAffineTransform(scaleX: 10, y: 10))
        guard let cgImage = ciContext.createCGImage(scaled, from: scaled.extent) else { return nil }
        #if os(macOS)
        return NSImage(cgImage: cgImage, size: NSSize(width: cgImage.width, height: cgImage.height))
        #else
        return UIImage(cgImage: cgImage)
        #endif
    }
}
