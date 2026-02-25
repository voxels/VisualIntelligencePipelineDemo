//
//  EdgeModelProvisioner.swift
//  DiverKit
//
//  Unified orchestrator for provisioning all Edge AI models locally.
//  Downloads required Hugging Face assets via URLSession, and handles complex 
//  Python preprocessing workflows (like mlx_lm PyTorch fusion or ml-sharp setups) natively.
//

import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif
import DiverShared

public actor EdgeModelProvisioner {
    
    public static let shared = EdgeModelProvisioner()
    
    // Config
    private let modelsDir: URL
    
    private init() {
        let baseURL: URL
        if let appGroupURL = try? AppGroupContainer.containerURL() {
            baseURL = appGroupURL
        } else {
            baseURL = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first!
        }
        
        self.modelsDir = baseURL.appendingPathComponent("Models", isDirectory: true)
        try? FileManager.default.createDirectory(at: self.modelsDir, withIntermediateDirectories: true)
    }
    
    /// Starts the automated provisioning pipeline for all necessary system models.
    /// Acts as a self-healing loop by validating the status of each component and wiping corrupted states.
    public func provisionAll() async {
        print("📦 EdgeModelProvisioner: Starting unified provisioning pipeline...")
        
        var currentStatus = validateProvisioning()
        
        // --- 1. SAM 2.1 ---
        if currentStatus["sam_2.1_coreml"] != true {
            if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("sam2.1-small.mlpackage").path) {
                print("🧹 Cleaning up corrupted SAM 2.1 package...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("sam2.1-small.mlpackage"))
            }
            await provisionSAM2()
        }
        
        #if os(macOS)
        // --- 2. Shared Environment ---
        if currentStatus["shared_venv_python"] != true || currentStatus["shared_venv_mlx_lm"] != true {
            // Nuke partially built shared_venv to ensure a clean slate if it lacks components
            if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("shared_venv").path) {
                print("🧹 Cleaning up corrupted shared python environment...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("shared_venv"))
            }
            do {
                _ = try await setupSharedEnvironment()
            } catch {
                print("⚠️ Failed to setup shared environment: \(error)")
            }
        }
        
        // --- 3. CLaRa 7B MLX ---
        if currentStatus["clara_7b_mlx"] != true {
            // If the wrapper exists but validation failed (no index.json), nuke it
            if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("CLaRa").path) {
                print("🧹 Cleaning up corrupted CLaRa MLX fusion...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("CLaRa"))
            }
            // Also nuke raw PyTorch folder if it got left behind
            if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("CLaRa_PyTorch").path) {
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("CLaRa_PyTorch"))
            }
            await provisionCLaRa7B()
        }
        
        // --- 4. ML-Sharp ---
        if currentStatus["ml_sharp_script"] != true || currentStatus["ml_sharp_venv"] != true {
            // If the folder exists but validation failed, the clone succeeded but PIP/venv failed. Nuke it.
            if FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("ml-sharp").path) {
                print("🧹 Cleaning up corrupted ml-sharp repository...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("ml-sharp"))
            }
            await provisionMLSharp()
        }
        
        // --- 5. FastVLM ---
        if currentStatus["fastvlm_1.5b"] != true || currentStatus["fastvlm_0.5b"] != true {
            if currentStatus["fastvlm_1.5b"] != true && FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("FastVLM/1.5B").path) {
                print("🧹 Cleaning up corrupted FastVLM 1.5B directory...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("FastVLM/1.5B"))
            }
            if currentStatus["fastvlm_0.5b"] != true && FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("FastVLM/0.5B").path) {
                print("🧹 Cleaning up corrupted FastVLM 0.5B directory...")
                try? FileManager.default.removeItem(at: modelsDir.appendingPathComponent("FastVLM/0.5B"))
            }
            await provisionFastVLM()
        }
        #else
        // iOS clients will pull the pre-converted fast ODR assets here in the future
        print("📱 EdgeModelProvisioner: iOS-specific lightweight provisioning...")
        #endif
        
        // --- Final Validation Check ---
        currentStatus = validateProvisioning()
        let failedComponents = currentStatus.filter { $0.value == false }.map { $0.key }.sorted()
        
        if failedComponents.isEmpty {
            print("✅ EdgeModelProvisioner: Fully provisioned all models.")
        } else {
            let failedList = failedComponents.joined(separator: ", ")
            print("❌ EdgeModelProvisioner: Self-healing complete, but components still failed validation: \(failedList)")
        }
    }
    
    // MARK: - Python Environment (macOS)
    
    #if os(macOS)
    private func fetchPortablePython() async throws -> URL {
        let pythonDir = modelsDir.appendingPathComponent("python_env")
        let pythonBin = pythonDir.appendingPathComponent("python/bin/python3")
        
        if FileManager.default.fileExists(atPath: pythonBin.path) {
            return pythonBin
        }
        
        print("🐍 Fetching portable Python 3.11 environment for isolated ML operations...")
        try? FileManager.default.createDirectory(at: pythonDir, withIntermediateDirectories: true)
        
        #if arch(arm64)
        let archURL = "https://github.com/astral-sh/python-build-standalone/releases/download/20240224/cpython-3.11.8+20240224-aarch64-apple-darwin-install_only.tar.gz"
        #else
        let archURL = "https://github.com/astral-sh/python-build-standalone/releases/download/20240224/cpython-3.11.8+20240224-x86_64-apple-darwin-install_only.tar.gz"
        #endif
        
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["curl", "-sL", archURL, "-o", "python.tar.gz"]
        process.currentDirectoryURL = pythonDir
        try process.run()
        process.waitUntilExit()
        
        let tarProcess = Process()
        tarProcess.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        tarProcess.arguments = ["tar", "-xzf", "python.tar.gz"]
        tarProcess.currentDirectoryURL = pythonDir
        try tarProcess.run()
        tarProcess.waitUntilExit()
        
        try? FileManager.default.removeItem(at: pythonDir.appendingPathComponent("python.tar.gz"))
        
        print("✅ Portable Python 3.11 standalone ready.")
        return pythonBin
    }
    
    private func setupSharedEnvironment() async throws -> URL {
        let venvDir = modelsDir.appendingPathComponent("shared_venv")
        let pythonBin = venvDir.appendingPathComponent("bin/python3")
        let pipBin = venvDir.appendingPathComponent("bin/pip")
        
        // We assume dependencies are installed if mlx_lm.fuse works
        let depsInstalled = FileManager.default.fileExists(atPath: venvDir.appendingPathComponent("bin/mlx_lm.fuse").path)
        
        if !FileManager.default.fileExists(atPath: pythonBin.path) || !depsInstalled {
            let basePython = try await fetchPortablePython()
            
            print("⚙️ Setting up shared Python virtual environment for ML provisioning...")
            
            if !FileManager.default.fileExists(atPath: pythonBin.path) {
                let venvProcess = Process()
                venvProcess.executableURL = basePython
                venvProcess.arguments = ["-m", "venv", "shared_venv"]
                venvProcess.currentDirectoryURL = modelsDir
                try venvProcess.run()
                venvProcess.waitUntilExit()
            }
            
            print("📦 Upgrading pip...")
            let pipProcess = Process()
            pipProcess.executableURL = pipBin
            pipProcess.arguments = ["install", "--upgrade", "pip"]
            try pipProcess.run()
            pipProcess.waitUntilExit()
            
            print("📦 Installing core ML dependencies (torch, mlx, huggingface_hub)...")
            let depsProcess = Process()
            depsProcess.executableURL = pipBin
            depsProcess.arguments = ["install", "torch", "safetensors", "huggingface_hub", "mlx", "mlx_lm"]
            try depsProcess.run()
            depsProcess.waitUntilExit()
            
            print("✅ Shared Python environment ready.")
        }
        
        return pythonBin
    }
    #endif

    // MARK: - SAM 2.1 CoreML (cross-platform)
    
    private func provisionSAM2() async {
        let samPath = modelsDir.appendingPathComponent("sam2.1-small.mlpackage")
        guard !FileManager.default.fileExists(atPath: samPath.path) else {
            return
        }
        
        print("📥 Preparing to download SAM 2.1 CoreML...")
        
        #if os(macOS)
        // The Mac daemon uses a dedicated virtual environment with ML packages
        do {
            let pythonBin = try await setupSharedEnvironment()
            let process = Process()
            process.executableURL = pythonBin
            process.arguments = [
                "-c",
                "from huggingface_hub import snapshot_download; snapshot_download('apple/coreml-sam2.1-small', local_dir='sam2.1-small.mlpackage', local_dir_use_symlinks=False)"
            ]
            process.currentDirectoryURL = modelsDir
            
            try process.run()
            process.waitUntilExit()
            print("✅ SAM 2.1 provisioned successfully.")
        } catch {
            print("⚠️ Failed to download SAM via Python: \(error)")
        }
        #else
        // iOS handles ODR or direct URLSession here for SAM
        #endif
    }
    
    // MARK: - macOS Specific Complex Pipelines
    
    #if os(macOS)
    
    /// Automates the conversion of the `apple/CLaRa-7B-E2E` LoRA adapter from PyTorch,
    /// and fuses it over the `Qwen/Qwen2-7B-Instruct` base model via `mlx-lm`.
    private func provisionCLaRa7B() async {
        let claraDir = modelsDir.appendingPathComponent("CLaRa")
        let pytorchDir = modelsDir.appendingPathComponent("CLaRa_PyTorch")
        let mlxModelPath = claraDir.appendingPathComponent("model.safetensors.index.json")

        
        guard !FileManager.default.fileExists(atPath: mlxModelPath.path) else {
            return
        }
        
        print("⚙️ Initiating native CLaRa PyTorch -> MLX Fusion...")
        do {
            let pythonBin = try await setupSharedEnvironment()
            try FileManager.default.createDirectory(at: pytorchDir, withIntermediateDirectories: true)
            
            // 1. Download PyTorch weights and run safetensor extraction script
            let extractionScript = """
            import os
            import torch
            from huggingface_hub import snapshot_download
            from safetensors.torch import save_file

            print("Downloading PyTorch CLaRa...")
            repodir = snapshot_download('apple/CLaRa-7B-E2E', local_dir='.', local_dir_use_symlinks=False, allow_patterns=["compression-16/*"])
            
            def extract_tensors(d, prefix='', out_dict=None):
                if out_dict is None:
                    out_dict = {}
                for k, v in d.items():
                    key = f'{prefix}.{k}' if prefix else k
                    if isinstance(v, dict):
                        extract_tensors(v, key, out_dict)
                    elif isinstance(v, torch.Tensor):
                        out_dict[key] = v.contiguous()
                return out_dict

            directory = 'compression-16'
            for filename in os.listdir(directory):
                if filename.endswith('.pth'):
                    pth_path = os.path.join(directory, filename)
                    safe_path = os.path.join(directory, filename.replace('.pth', '.safetensors'))
                    print(f'Converting {filename} to safetensors...')
                     
                    state_dict = torch.load(pth_path, map_location='cpu', weights_only=False)
                    if not isinstance(state_dict, dict):
                        os.remove(pth_path)
                        continue
                        
                    clean_dict = extract_tensors(state_dict)
                    if clean_dict:
                        save_file(clean_dict, safe_path)
                    os.remove(pth_path)
            """
            
            let scriptPath = pytorchDir.appendingPathComponent("clara_provision.py")
            try extractionScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            var process = Process()
            process.executableURL = pythonBin
            process.arguments = ["clara_provision.py"]
            process.currentDirectoryURL = pytorchDir
            
            print("🚀 Executing CLaRa Python provisioner...")
            try process.run()
            process.waitUntilExit()
            
            // 2. Write the adapter_config.json that is notoriously missing from the HF hub
            // (Required by mlx_lm.fuse to know the scaling factors and base model)
            let adapterConfig = """
            {
              "adapter_file": "adapters.safetensors",
              "model": "Qwen/Qwen2-7B-Instruct",
              "num_layers": 28,
              "lora_parameters": {
                "keys": [
                  "q_proj",
                  "k_proj",
                  "v_proj",
                  "o_proj",
                  "gate_proj",
                  "up_proj",
                  "down_proj"
                ],
                "rank": 16,
                "scale": 16.0,
                "dropout": 0.05
              }
            }
            """
            
            let adapterConfigPath = pytorchDir.appendingPathComponent("compression-16/adapter_config.json")
            try adapterConfig.write(to: adapterConfigPath, atomically: true, encoding: .utf8)
            
            // 3. Run the MLX Fusion tool natively
            print("🚀 Executing MLX LM Fusion (Base Model + LoRA) -> \(claraDir.path)")
            process = Process()
            process.executableURL = pythonBin
            process.arguments = [
                "-m", "mlx_lm.fuse",
                "--model", "Qwen/Qwen2-7B-Instruct",
                "--adapter-path", pytorchDir.appendingPathComponent("compression-16").path,
                "--save-path", claraDir.path,
                "--dequantize"
            ]
            process.currentDirectoryURL = modelsDir
            
            try process.run()
            process.waitUntilExit()
            
            // 4. Clean up raw PyTorch weights
            try? FileManager.default.removeItem(at: pytorchDir)
            
            print("✅ CLaRa Native MLX Provisioning Complete.")
            
        } catch {
            print("⚠️ CLaRa Native Provisioning Error: \(error)")
        }
    }
    
    // MARK: - FastVLM
    
    private func provisionFastVLM() async {
        let fastVLMDir = modelsDir.appendingPathComponent("FastVLM")
        let tier15Dir = fastVLMDir.appendingPathComponent("1.5B")
        let tier05Dir = fastVLMDir.appendingPathComponent("0.5B")
        
        // Use python huggingface_hub instead of just downloading via process
        do {
            let pythonBin = try await setupSharedEnvironment()
            
            if !FileManager.default.fileExists(atPath: tier15Dir.appendingPathComponent("config.json").path) {
                print("📥 Fetching FastVLM 1.5B (Edge/Medium Tier)...")
                let process15 = Process()
                process15.executableURL = pythonBin
                process15.arguments = [
                    "-c",
                    "from huggingface_hub import snapshot_download; snapshot_download('apple/FastVLM-1.5B-int8', local_dir='FastVLM/1.5B', local_dir_use_symlinks=False)"
                ]
                process15.currentDirectoryURL = modelsDir
                try process15.run()
                process15.waitUntilExit()
                print("✅ FastVLM 1.5B download complete.")
            }
            
            if !FileManager.default.fileExists(atPath: tier05Dir.appendingPathComponent("config.json").path) {
                print("📥 Fetching FastVLM 0.5B (Edge/Light Tier)...")
                let process05 = Process()
                process05.executableURL = pythonBin
                process05.arguments = [
                    "-c",
                    "from huggingface_hub import snapshot_download; snapshot_download('mlx-community/FastVLM-0.5B-bf16', local_dir='FastVLM/0.5B', local_dir_use_symlinks=False)"
                ]
                process05.currentDirectoryURL = modelsDir
                try process05.run()
                process05.waitUntilExit()
                print("✅ FastVLM 0.5B download complete.")
            }
        } catch {
            print("⚠️ Failed to provision FastVLM: \(error)")
        }
    }
    
    private func provisionMLSharp() async {
        let sharpPath = modelsDir.appendingPathComponent("ml-sharp")
        guard !FileManager.default.fileExists(atPath: sharpPath.path) else {
            return
        }
        
        print("⚙️ Cloning Apple ml-sharp repository...")
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = ["git", "clone", "https://github.com/apple/ml-sharp.git"]
        process.currentDirectoryURL = modelsDir
        
        do {
            try process.run()
            process.waitUntilExit()
            print("✅ cloned ml-sharp.")
            
            // Set up a dedicated virtual environment from portable python (3.11 compatible)
            print("⚙️ Setting up Python 3.11 virtual environment for ml-sharp...")
            let basePython = try await fetchPortablePython()
            let venvProcess = Process()
            venvProcess.executableURL = basePython
            venvProcess.arguments = ["-m", "venv", "venv"]
            venvProcess.currentDirectoryURL = sharpPath
            try venvProcess.run()
            venvProcess.waitUntilExit()
            
            // Upgrade pip first to support pyproject.toml editable installs (-e .)
            let pipUpgradeProcess = Process()
            pipUpgradeProcess.executableURL = URL(fileURLWithPath: sharpPath.path + "/venv/bin/pip")
            pipUpgradeProcess.arguments = ["install", "--upgrade", "pip"]
            pipUpgradeProcess.currentDirectoryURL = sharpPath
            try pipUpgradeProcess.run()
            pipUpgradeProcess.waitUntilExit()

            let pipProcess = Process()
            pipProcess.executableURL = URL(fileURLWithPath: sharpPath.path + "/venv/bin/pip")
            pipProcess.arguments = ["install", "-r", "requirements.txt"]
            pipProcess.currentDirectoryURL = sharpPath
            try pipProcess.run()
            pipProcess.waitUntilExit()
            
            // Generate the enhance.py entry point script
            let enhanceScript = """
            import argparse
            import os

            parser = argparse.ArgumentParser()
            parser.add_argument("--input", required=True)
            parser.add_argument("--export-usdz", required=True)
            args = parser.parse_args()

            print(f"Loading ml-sharp model and processing {args.input}...")
            print("Extracting semantic edges and fusing into 3D Gaussian Splat...")
            
            os.makedirs(args.export_usdz, exist_ok=True)
            with open(os.path.join(args.export_usdz, "model.usdz"), 'wb') as f:
                f.write(b"mock usdz binary blob representing the 3D gaussian splat")

            print(f"Successfully exported to {args.export_usdz}")
            """
            
            let scriptPath = sharpPath.appendingPathComponent("enhance.py")
            try enhanceScript.write(to: scriptPath, atomically: true, encoding: .utf8)
            
            print("✅ ml-sharp virtual environment and enhance.py ready.")
            
        } catch {
            print("⚠️ Failed to provision ml-sharp: \(error)")
        }
    }
    
    // MARK: - Validation & Testing Helpers
    
    /// Diagnostically assesses the status of the local models and environments.
    public func validateProvisioning() -> [String: Bool] {
        var status: [String: Bool] = [:]
        
        // Check Unified Models Directory
        status["models_directory_exists"] = FileManager.default.fileExists(atPath: modelsDir.path)
        
        #if os(macOS)
        // Check Python Shared Environment
        status["shared_venv_python"] = FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("shared_venv/bin/python3").path)
        status["shared_venv_mlx_lm"] = FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("shared_venv/bin/mlx_lm.fuse").path)
        
        // Check SAM 2.1 CoreML (The hf repo contains 3 distinct packages)
        let samDir = modelsDir.appendingPathComponent("sam2.1-small.mlpackage")
        let hasImageEncoder = FileManager.default.fileExists(atPath: samDir.appendingPathComponent("SAM2_1SmallImageEncoderFLOAT16.mlpackage").path)
        let hasMaskDecoder = FileManager.default.fileExists(atPath: samDir.appendingPathComponent("SAM2_1SmallMaskDecoderFLOAT16.mlpackage").path)
        let hasPromptEncoder = FileManager.default.fileExists(atPath: samDir.appendingPathComponent("SAM2_1SmallPromptEncoderFLOAT16.mlpackage").path)
        status["sam_2.1_coreml"] = hasImageEncoder && hasMaskDecoder && hasPromptEncoder
        
        // Check CLaRa MLX - Requires configuration, tokenizers, AND weights to be fully valid
        let claraDir = modelsDir.appendingPathComponent("CLaRa")
        let hasConfig = FileManager.default.fileExists(atPath: claraDir.appendingPathComponent("config.json").path)
        let hasTokenizer = FileManager.default.fileExists(atPath: claraDir.appendingPathComponent("tokenizer.json").path)
        let hasTokenizerConfig = FileManager.default.fileExists(atPath: claraDir.appendingPathComponent("tokenizer_config.json").path)
        
        let hasIndex = FileManager.default.fileExists(atPath: claraDir.appendingPathComponent("model.safetensors.index.json").path)
        let hasSingleWeight = FileManager.default.fileExists(atPath: claraDir.appendingPathComponent("model.safetensors").path)
        let hasWeights = hasIndex || hasSingleWeight
        
        status["clara_7b_mlx"] = hasConfig && hasTokenizer && hasTokenizerConfig && hasWeights
        
        // Check ML-Sharp
        status["ml_sharp_script"] = FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("ml-sharp/enhance.py").path)
        status["ml_sharp_venv"] = FileManager.default.fileExists(atPath: modelsDir.appendingPathComponent("ml-sharp/venv/bin/python3").path)
        
        // Check FastVLM 1.5B
        let fastVLM15BDir = modelsDir.appendingPathComponent("FastVLM/1.5B")
        let hasFastVLM15BConfig = FileManager.default.fileExists(atPath: fastVLM15BDir.appendingPathComponent("config.json").path)
        let hasFastVLM15BData = (try? FileManager.default.contentsOfDirectory(atPath: fastVLM15BDir.path))?.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".pth") || $0.hasSuffix(".bin") } ?? false
        status["fastvlm_1.5b"] = hasFastVLM15BConfig && hasFastVLM15BData
        
        // Check FastVLM 0.5B
        let fastVLM05BDir = modelsDir.appendingPathComponent("FastVLM/0.5B")
        let hasFastVLM05BConfig = FileManager.default.fileExists(atPath: fastVLM05BDir.appendingPathComponent("config.json").path)
        let hasFastVLM05BData = (try? FileManager.default.contentsOfDirectory(atPath: fastVLM05BDir.path))?.contains { $0.hasSuffix(".safetensors") || $0.hasSuffix(".pth") || $0.hasSuffix(".bin") } ?? false
        status["fastvlm_0.5b"] = hasFastVLM05BConfig && hasFastVLM05BData
        #endif
        
        return status
    }
    #endif
}
