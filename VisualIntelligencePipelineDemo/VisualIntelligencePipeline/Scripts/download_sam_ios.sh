#!/bin/bash
set -e

# This script runs during the Xcode Build Phase for the VisualIntelligencePipeline iOS target.
# It automatically downloads Apple's SAM 2.1 Small CoreML model from Hugging Face if it's not present.

MODEL_NAME="sam2.1-small.mlpackage"
TARGET_DIR="${SRCROOT}/DiverKit/Sources/DiverKit/Resources"
MODEL_PATH="${TARGET_DIR}/${MODEL_NAME}"

export PIP_BREAK_SYSTEM_PACKAGES=1

if [ ! -d "$MODEL_PATH" ]; then
    echo "📥 Downloading SAM 2.1 Small CoreML model (this may take a minute)..."
    
    # Ensure target directory exists
    mkdir -p "$TARGET_DIR"
    
    # Check if huggingface_hub is installed, if not, try to install it or use the anaconda python
    # We will use Python directly to avoid PATH issues with huggingface-cli
    
    if command -v python3 &> /dev/null; then
        echo "📦 Verifying huggingface_hub is installed..."
        python3 -m pip install -q huggingface_hub || true
        
        echo "⬇️ Fetching weights directly from Hugging Face..."
        cd "$TARGET_DIR"
        python3 -c "from huggingface_hub import snapshot_download; snapshot_download('apple/coreml-sam2.1-small', local_dir='${MODEL_NAME}', local_dir_use_symlinks=False)"
        
        echo "✅ SAM 2.1 downloaded successfully to $MODEL_PATH"
    else
        echo "❌ ERROR: python3 is not installed or not in PATH. Please install Python to automatically download the SAM 2.1 model, or download it manually."
        exit 1
    fi
else
    echo "✅ SAM 2.1 model already exists. Skipping download."
fi
