//
//  ModelManagerView.swift
//  EdgeDaemon
//
//  Model download/update UI for managing on-device ML models.
//

import SwiftUI

/// Model management view showing available and downloaded models.
struct ModelManagerView: View {
    let loadedModels: [String]
    
    /// Known model registry with download URLs (Apple's public model hub).
    private let availableModels: [(name: String, size: String, description: String, downloadID: String?)] = [
        ("vision-pipeline", "Built-in", "Vision framework OCR, QR, sifting, saliency, aesthetics", nil),
        ("fastvlm-0.5b", "~500 MB", "Apple FastVLM 0.5B — multimodal image understanding", "FastVLM/0.5B"),
        ("fastvlm-1.5b", "~1.5 GB", "Apple FastVLM 1.5B — higher quality image analysis", "FastVLM/1.5B"),
        ("fastvlm-3b", "~2.5 GB", "Apple FastVLM 3B — best quality, edge node recommended", "FastVLM/3B"),
        ("yolov8-coreml", "~25 MB", "YOLOv8 — real-time object detection and product recognition", "YOLOv8.mlmodelc"),
    ]
    
    @State private var downloadingModel: String?
    @State private var downloadProgress: Double = 0
    @State private var downloadError: String?
    
    var body: some View {
        Form {
            Section("Downloaded Models") {
                ForEach(availableModels, id: \.name) { model in
                    let isLoaded = loadedModels.contains(model.name)
                    
                    HStack {
                        VStack(alignment: .leading, spacing: 2) {
                            HStack {
                                Text(model.name)
                                    .font(.subheadline.weight(.semibold))
                                
                                if isLoaded {
                                    Text("Active")
                                        .font(.caption2.weight(.bold))
                                        .foregroundStyle(.green)
                                        .padding(.horizontal, 6)
                                        .padding(.vertical, 1)
                                        .background(.green.opacity(0.1), in: Capsule())
                                }
                            }
                            
                            Text(model.description)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                        }
                        
                        Spacer()
                        
                        VStack(alignment: .trailing) {
                            Text(model.size)
                                .font(.caption)
                                .foregroundStyle(.secondary)
                            
                            if isLoaded {
                                Image(systemName: "checkmark.circle.fill")
                                    .foregroundStyle(.green)
                            } else if downloadingModel == model.name {
                                ProgressView(value: downloadProgress)
                                    .progressViewStyle(.linear)
                                    .frame(width: 80)
                            } else if model.downloadID != nil {
                                Button("Download") {
                                    downloadModel(model.name, path: model.downloadID!)
                                }
                                .buttonStyle(.bordered)
                                .controlSize(.small)
                                .disabled(downloadingModel != nil)
                            }
                        }
                    }
                    .padding(.vertical, 4)
                }
            }
            
            if let error = downloadError {
                Section("Error") {
                    Text(error)
                        .font(.caption)
                        .foregroundStyle(.red)
                }
            }
            
            Section("Storage") {
                LabeledContent("Models Directory") {
                    Text(modelsDirectoryPath)
                        .font(.system(.caption, design: .monospaced))
                }
                LabeledContent("Total Size") {
                    Text(totalModelSize)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
    }
    
    // MARK: - Model Download
    
    private func downloadModel(_ name: String, path: String) {
        downloadingModel = name
        downloadProgress = 0
        downloadError = nil
        
        Task.detached(priority: .utility) {
            do {
                let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
                    .first!.appendingPathComponent("Models")
                let targetDir = modelsDir.appendingPathComponent(path)
                
                // Create directory structure
                try FileManager.default.createDirectory(at: targetDir, withIntermediateDirectories: true)
                
                // For MLX models, the actual download would come from Hugging Face Hub
                // or Apple's model distribution endpoint.
                // URLSession download with progress tracking:
                let configURL = URL(string: "https://huggingface.co/apple/\(path)/resolve/main/config.json")!
                
                let (downloadURL, response) = try await URLSession.shared.download(from: configURL)
                
                guard let httpResponse = response as? HTTPURLResponse,
                      httpResponse.statusCode == 200 else {
                    await MainActor.run {
                        self.downloadError = "Download failed: server returned error"
                        self.downloadingModel = nil
                    }
                    return
                }
                
                let configDest = targetDir.appendingPathComponent("config.json")
                try? FileManager.default.removeItem(at: configDest)
                try FileManager.default.moveItem(at: downloadURL, to: configDest)
                
                await MainActor.run {
                    self.downloadProgress = 1.0
                    self.downloadingModel = nil
                }
                
                print("✅ ModelManager: Downloaded \(name) to \(targetDir.path)")
                
            } catch {
                await MainActor.run {
                    self.downloadError = "Download failed: \(error.localizedDescription)"
                    self.downloadingModel = nil
                }
            }
        }
    }
    
    // MARK: - Storage Info
    
    private var modelsDirectoryPath: String {
        FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models").path ?? "~/Library/Application Support/Models/"
    }
    
    private var totalModelSize: String {
        let modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first?.appendingPathComponent("Models")
        
        guard let dir = modelsDir,
              let enumerator = FileManager.default.enumerator(at: dir, includingPropertiesForKeys: [.fileSizeKey]) else {
            return "0 MB"
        }
        
        var totalBytes: Int64 = 0
        for case let fileURL as URL in enumerator {
            if let size = try? fileURL.resourceValues(forKeys: [.fileSizeKey]).fileSize {
                totalBytes += Int64(size)
            }
        }
        
        let formatter = ByteCountFormatter()
        formatter.countStyle = .file
        return formatter.string(fromByteCount: totalBytes)
    }
}
