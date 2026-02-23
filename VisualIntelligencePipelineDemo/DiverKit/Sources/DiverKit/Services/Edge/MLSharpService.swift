import Foundation
import CoreGraphics
import DiverShared

#if os(macOS)
import AppKit

/// Wraps the Python-based execution of Apple's `ml-sharp` repository for 3D semantic edge cutting.
/// This service is strictly intended for the macOS EdgeDaemon.
public final class MLSharpService: Sendable {
    
    public init() {}
    
    /// Processes an input image payload through `ml-sharp` and returns the output USDZ mesh data.
    public func processImage(imageData: Data) async throws -> Data {
        let tempInputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + ".png")
        let tempOutputURL = FileManager.default.temporaryDirectory.appendingPathComponent(UUID().uuidString + "_mesh.usdz")
        
        do {
            try imageData.write(to: tempInputURL)
            
            // Try to find the local ml-sharp repository
            guard let mlSharpPath = findMLSharpRepo() else {
                throw EdgeInferenceError.serviceUnavailable("Local ml-sharp repository not found. Please ensure it is cloned.")
            }
            
            // Ensure we use the isolated virtual environment we set up in EdgeModelProvisioner
            let venvPythonURL = URL(fileURLWithPath: mlSharpPath).appendingPathComponent("venv/bin/python")
            guard FileManager.default.fileExists(atPath: venvPythonURL.path) else {
                throw EdgeInferenceError.serviceUnavailable("ml-sharp virtual environment not found. Please wait for provisioning to finish.")
            }
            
            let process = Process()
            process.executableURL = venvPythonURL
            process.arguments = [
                "enhance.py",
                "--input", tempInputURL.path,
                "--output", tempOutputURL.path,
                "--export-usdz" // Pass flag to Python to trigger surface reconstruction
            ]
            process.currentDirectoryURL = URL(fileURLWithPath: mlSharpPath)
            
            let pipe = Pipe()
            process.standardOutput = pipe
            process.standardError = pipe
            
            try process.run()
            process.waitUntilExit()
            
            if process.terminationStatus != 0 {
                let errorData = pipe.fileHandleForReading.readDataToEndOfFile()
                let errorMessage = String(data: errorData, encoding: .utf8) ?? "Unknown error"
                print("ML-Sharp Python process failed: \(errorMessage)")
                throw EdgeInferenceError.serviceUnavailable("ml-sharp script failed: \(errorMessage)")
            }
            
            // Read the binary USDZ representation
            let usdzData = try Data(contentsOf: tempOutputURL)
            
            // Clean up
            try? FileManager.default.removeItem(at: tempInputURL)
            try? FileManager.default.removeItem(at: tempOutputURL)
            
            return usdzData
            
        } catch {
            // Clean up on failure
            try? FileManager.default.removeItem(at: tempInputURL)
            try? FileManager.default.removeItem(at: tempOutputURL)
            throw error
        }
    }
    
    /// Locates the `apple/ml-sharp` repository via common paths or environments.
    private func findMLSharpRepo() -> String? {
        let fileManager = FileManager.default
        let homeDir = fileManager.homeDirectoryForCurrentUser.path
        
        // Typical cloning paths + EdgeModelProvisioner's Models directory
        let potentialPaths = [
            "\(homeDir)/Library/Application Support/Models/ml-sharp",
            "\(homeDir)/Documents/dev/ml-sharp",
            "\(homeDir)/ml-sharp",
            "\(homeDir)/Desktop/ml-sharp",
            "/opt/homebrew/opt/ml-sharp"
        ]
        
        for path in potentialPaths {
            if fileManager.fileExists(atPath: path + "/enhance.py") {
                return path
            }
        }
        
        return nil
    }
}
#endif
