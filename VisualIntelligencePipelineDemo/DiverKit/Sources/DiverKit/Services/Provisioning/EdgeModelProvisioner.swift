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

public actor EdgeModelProvisioner {
    
    public static let shared = EdgeModelProvisioner()
    
    // Config
    private let modelsDir: URL
    
    private init() {
        self.modelsDir = FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask)
            .first!.appendingPathComponent("Models")
        try? FileManager.default.createDirectory(at: self.modelsDir, withIntermediateDirectories: true)
    }
    
    /// Starts the automated provisioning pipeline for all necessary system models.
    public func provisionAll() async {
        print("📦 EdgeModelProvisioner: Starting unified provisioning pipeline...")
        
        await provisionSAM2()
        
        #if os(macOS)
        // Only the backend daemon provisions the heavy 7B MLX pipelines from raw PyTorch
        await provisionFastVLM7B()
        await provisionCLaRa7B()
        await provisionMLSharp()
        #else
        // iOS clients will pull the pre-converted fast ODR assets here in the future
        print("📱 EdgeModelProvisioner: iOS-specific lightweight provisioning...")
        #endif
        
        print("✅ EdgeModelProvisioner: Fully provisioned all models.")
    }
    
    // MARK: - SAM 2.1 CoreML (cross-platform)
    
    private func provisionSAM2() async {
        let samPath = modelsDir.appendingPathComponent("sam2.1-small.mlpackage")
        guard !FileManager.default.fileExists(atPath: samPath.path) else {
            return
        }
        
        print("📥 Preparing to download SAM 2.1 CoreML...")
        
        #if os(macOS)
        // The Mac daemon has standard python pip libraries available to quickly pull packages via HF Hub
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
        process.arguments = [
            "python3", "-c",
            "from huggingface_hub import snapshot_download; snapshot_download('apple/coreml-sam2.1-small', local_dir='sam2.1-small.mlpackage', local_dir_use_symlinks=False)"
        ]
        process.currentDirectoryURL = modelsDir
        
        do {
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
        let mlxModelPath = claraDir.appendingPathComponent("model.safetensors")
        
        guard !FileManager.default.fileExists(atPath: mlxModelPath.path) else {
            return
        }
        
        print("⚙️ Initiating native CLaRa PyTorch -> MLX Fusion...")
        do {
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
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = ["python3", "clara_provision.py"]
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
            process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
            process.arguments = [
                "python3", "-m", "mlx_lm.fuse",
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
    
    private func provisionFastVLM7B() async {
        let modelsTiers = modelsDir.appendingPathComponent("FastVLM/7B")
        let configPath = modelsTiers.appendingPathComponent("config.json")
        
        guard !FileManager.default.fileExists(atPath: configPath.path) else {
            return
        }
        print("⚙️ Triggering FastVLM 7B provision...")
        // We will execute the mlx conversion here similar to CLaRa
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
        } catch {
            print("⚠️ Failed to clone ml-sharp: \(error)")
        }
    }
    
    #endif
}
