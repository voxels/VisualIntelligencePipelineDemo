# Visual Intelligence Edge Daemon

The Edge Daemon is a specialized macOS background service built to offload heavy machine learning workloads from the Visual Intelligence iOS app to Apple Silicon Macs.

It acts as an on-device edge node that accelerates the pipeline, entirely local and private.

## Core Capabilities

The Edge Daemon exposes several heavy ML models over a secure Bonjour-advertised local network connection (`_visualintel._tcp`):

1.  **Apple FastVLM Enrichment**: Provides multimodal image understanding (captioning, visual Q&A, object detection) using Apple's FastVLM models.
2.  **YOLOv8 Subject Detection**: High-speed, high-accuracy object detection.
3.  **Local Context Extraction**: Secure local execution of natural language processing tasks.

## How it Works

1.  **Discovery**: The iOS app automatically discovers the Edge Daemon on the local Wi-Fi network using zero-configuration Bonjour networking.
2.  **Handshake**: A secure, low-latency TLS handshake is established.
3.  **Inference**: The iOS app streams image tensors to the Mac. The daemon runs the inference entirely in GPU memory (using MLX or CoreML) and streams the structural metadata (like `FastVLMAnalysis`) back to the phone.
4.  **Persistence**: The iOS app tags the `ProcessedItem` with the exact `modelID` of the daemon that processed it (e.g., `apple/FastVLM/3B`). This allows the system to intelligently reprocess older items when a superior model becomes available.

## Running the Daemon

The EdgeDaemon is designed to be run from the terminal to bypass macOS Local Network Privacy restrictions that prevent ad-hoc signed apps from broadcasting Bonjour services.

```bash
# Start the daemon
./run_daemon.sh
```

Upon launching, you will be dropped into an interactive REPL shell.

### Commands

*   `help`: Show available commands.
*   `status`: Show daemon state (Listening/Idle) and total requests served.
*   `clients`: List connected iOS devices.
*   `models`: List the ML models currently loaded in memory.
*   `download <model_id>`: Download a pre-quantized MLX model directly from Hugging Face. (e.g., `download fastvlm-0.5b`).
*   `quit`: Shut down securely.

## Model Management (FastVLM)

The daemon automatically manages and provisions local ML weights directly from Hugging Face into `~/Library/Application Support/Models/FastVLM`.

### Supported Tiers

The `FastVLMEnrichmentService` dynamically upgrades to the highest tier model available in your local cache:

1.  **7B** (`fastvlm-7b`) - Highest accuracy, requires ~8GB unified memory.
2.  **1.5B** (`fastvlm-1.5b`) - Balanced, requires ~3GB unified memory.
3.  **0.5B** (`fastvlm-0.5b`) - Default community model, optimized for speed.

### Obtaining Apple's High-Tier Models (1.5B and 7B)

Apple limits access to the larger FastVLM checkpoints on HuggingFace, requiring you to accept a license agreement. They also only publish the original PyTorch weights, which must be compiled into MLX format to run efficiently on Apple Silicon GPUs.

To automate this, we provide a conversion script:

```bash
# Ensure you are logged into HuggingFace CLI first
huggingface-cli login

# Download, convert, and install the 1.5B tier
./convert_fastvlm.sh 1.5B

# Or install the massive 7B tier
./convert_fastvlm.sh 7B
```

The script will automatically grab the PyTorch model, run Apple's `mlx-vlm.convert` tool to convert the tensors, and place the resulting `safetensors` in the exact directory where the daemon expects to find them. The daemon will instantly recognize and switch to the new architecture!
