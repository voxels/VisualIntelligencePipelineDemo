//
//  ImageProfileView.swift
//  DiverUI — cross-platform
//
//  Already had #if os(iOS) || os(visionOS) guard on MLSharpSplatView — kept as-is.
//

import SwiftUI
import SwiftData
import DiverShared
import DiverKit

/// Specialized profile for image captures: aesthetics, EXIF metadata, and ML-Sharp 3D splat.
public struct ImageProfileView: View {
    public let item: ProcessedItem
    @State private var isGeneratingSplat: Bool = false
    @State private var edgeError: String? = nil

    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        VStack(spacing: 16) {
            if let aesthetics = item.aestheticsScore {
                AestheticsCardView(score: aesthetics).padding(.horizontal).padding(.top, 8)
            }
            EXIFMetadataSection(item: item).padding(.horizontal)

            if let usdzData = item.mlSharpData {
                #if os(iOS) || os(visionOS)
                MLSharpSplatView(splatData: usdzData)
                #else
                Label("3D Splat ready — view on iPhone or Vision Pro", systemImage: "cube.transparent")
                    .font(.caption).foregroundStyle(.secondary).padding(.horizontal)
                #endif
            } else {
                Button(action: { generateSplat() }) {
                    if isGeneratingSplat {
                        ProgressView().progressViewStyle(.circular)
                    } else {
                        Label("Generate 3D Splat (ML-Sharp)", systemImage: "cube.transparent")
                            .font(.headline).foregroundStyle(.white)
                            .padding(.vertical, 12).frame(maxWidth: .infinity)
                            .background(Color.blue.gradient).clipShape(RoundedRectangle(cornerRadius: 12))
                    }
                }
                .frame(maxWidth: .infinity).padding(.horizontal)
                if let err = edgeError {
                    Text(err).font(.caption).foregroundStyle(.red).padding(.horizontal)
                }
            }
        }
    }

    private func generateSplat() {
        guard let imageData = item.rawPayload else { edgeError = "Missing raw image payload"; return }
        isGeneratingSplat = true; edgeError = nil
        Task {
            do {
                let router = await MainActor.run { Services.shared.edgeRouter }
                let system = await MainActor.run { Services.shared.actorSystem }
                if let router, let system {
                    let decision = await router.shouldOffload(task: .mlSharp)
                    if case .edge(let node, _) = decision {
                        let identity = EdgeActorID(id: "EdgeInference", nodeName: node.deviceName)
                        let edgeActor = try EdgeInferenceActor.resolve(id: identity, using: system)
                        let usdzData = try await edgeActor.runMLSharp(imageData: imageData)
                        await MainActor.run {
                            withAnimation {
                                self.item.mlSharpData = usdzData
                                try? self.item.modelContext?.save()
                                self.isGeneratingSplat = false
                            }
                        }
                    } else {
                        throw NSError(domain: "ImageProfileView", code: 1,
                            userInfo: [NSLocalizedDescriptionKey: "No edge node with ml-sharp capability."])
                    }
                }
            } catch {
                await MainActor.run { edgeError = error.localizedDescription; isGeneratingSplat = false }
            }
        }
    }
}

// MARK: - Aesthetics Card

public struct AestheticsCardView: View {
    public let score: Double
    public init(score: Double) { self.score = score }

    public var body: some View {
        HStack(spacing: 12) {
            ZStack {
                Circle().stroke(Color.white.opacity(0.2), lineWidth: 3)
                Circle()
                    .trim(from: 0.0, to: CGFloat(min(max(score, 0.0), 1.0)))
                    .stroke(AngularGradient(
                        colors: [.red, .orange, .green, .blue], center: .center,
                        startAngle: .degrees(0), endAngle: .degrees(360)
                    ), style: StrokeStyle(lineWidth: 3, lineCap: .round))
                    .rotationEffect(.degrees(-90))
                Text(String(format: "%.1f", score * 10)).font(.caption2.bold())
            }
            .frame(width: 36, height: 36)

            VStack(alignment: .leading, spacing: 2) {
                Text("Aesthetics Score").font(.subheadline).fontWeight(.medium)
                Text(qualityText).font(.caption).foregroundStyle(.secondary)
            }
            Spacer()
            Image(systemName: "sparkles").foregroundStyle(.yellow)
        }
        .padding(.vertical, 12).padding(.horizontal, 16)
        .glassEffect().clipShape(RoundedRectangle(cornerRadius: 12))
    }

    private var qualityText: String {
        score > 0.8 ? "Professional Quality" : score > 0.6 ? "High Quality"
            : score > 0.4 ? "Average Quality" : "Low Quality"
    }
}

// MARK: - EXIF Section

public struct EXIFMetadataSection: View {
    public let item: ProcessedItem
    public init(item: ProcessedItem) { self.item = item }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("File Information").font(.headline)
            VStack(spacing: 8) {
                if let date = item.originalDate {
                    MetaInfoRow(icon: "calendar", title: "Date Captured",
                               value: date.formatted(date: .abbreviated, time: .shortened))
                }
                if let loc = item.location {
                    MetaInfoRow(icon: "mappin.and.ellipse", title: "Location", value: loc)
                }
                if let name = item.filename {
                    MetaInfoRow(icon: "doc", title: "Filename", value: name)
                }
                if let size = item.fileSize {
                    MetaInfoRow(icon: "externaldrive", title: "File Size",
                               value: ByteCountFormatter.string(fromByteCount: Int64(size), countStyle: .file))
                }
            }
            .padding().glassEffect().clipShape(RoundedRectangle(cornerRadius: 12))
        }
    }
}

private struct MetaInfoRow: View {
    let icon: String; let title: String; let value: String
    var body: some View {
        HStack {
            Image(systemName: icon).frame(width: 24).foregroundStyle(.secondary)
            Text(title).font(.subheadline).foregroundStyle(.secondary)
            Spacer()
            Text(value).font(.subheadline).fontWeight(.medium)
        }
    }
}

// MARK: - ML-Sharp Splat View (iOS + visionOS only)

#if os(iOS) || os(visionOS)
import RealityKit

public struct MLSharpSplatView: View {
    public let splatData: Data
    @State private var rotation: simd_quatf = simd_quatf(angle: 0, axis: [0, 1, 0])
    @State private var scale: Float = 1.0
    @State private var rootEntity = Entity()

    public init(splatData: Data) { self.splatData = splatData }

    public var body: some View {
        RealityView { content in
            content.add(rootEntity)
            let tmpURL = FileManager.default.temporaryDirectory
                .appendingPathComponent(UUID().uuidString + ".usdz")
            do {
                try splatData.write(to: tmpURL)
                Task {
                    do {
                        let loaded = try await Entity.load(contentsOf: tmpURL)
                        await MainActor.run {
                            loaded.position = [0,0,0]
                            rootEntity.addChild(loaded)
                            try? FileManager.default.removeItem(at: tmpURL)
                        }
                    } catch { try? FileManager.default.removeItem(at: tmpURL) }
                }
            } catch {}
        } update: { _ in
            rootEntity.transform.rotation = rotation
            rootEntity.transform.scale = [scale, scale, scale]
        }
        .gesture(DragGesture().onChanged { v in
            let dx = Float(v.translation.width) * 0.01
            let dy = Float(v.translation.height) * 0.01
            rotation = rotation * simd_quatf(angle: dx, axis: [0,1,0]) * simd_quatf(angle: dy, axis: [1,0,0])
        })
        .gesture(MagnifyGesture().onChanged { v in scale = min(max(Float(v.magnification), 0.5), 3.0) })
        .frame(height: 300)
        .clipShape(RoundedRectangle(cornerRadius: 16))
        .overlay(RoundedRectangle(cornerRadius: 16).stroke(Color.white.opacity(0.1), lineWidth: 1))
        .overlay(alignment: .bottomTrailing) {
            Image(systemName: "arkit").font(.system(size: 20))
                .foregroundColor(.white.opacity(0.7)).padding(12)
                .background(Color.black.opacity(0.4)).clipShape(Circle()).padding(8)
        }
    }
}
#endif
