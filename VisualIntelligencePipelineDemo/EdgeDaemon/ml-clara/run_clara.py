#!/usr/bin/env python3
import os
import sys
import argparse
import json
from pathlib import Path
import torch

def setup_clara_env():
    """Dynamically adds the ml-clara directory to sys.path so its modules can be imported."""
    clara_dir = Path(__file__).parent
    sys.path.append(str(clara_dir))

def load_latents(db_path):
    if not db_path.exists():
        return {}
    with open(db_path, "r") as f:
        return json.load(f)

def save_latents(db_path, latents):
    with open(db_path, "w") as f:
        json.dump(latents, f, indent=2)

def main():
    parser = argparse.ArgumentParser(description="Apple CLaRa Agentic Search Engine")
    parser.add_argument("--mode", choices=["ingest", "query"], required=True, help="Mode of operation")
    parser.add_argument("--payload", help="Path to JSON payload containing document to ingest or query to run")
    parser.add_argument("--db", default="clara_latents.json", help="Path to simple JSON DB holding latent representations")
    
    args = parser.parse_args()
    
    db_path = Path(args.db)
    payload_path = Path(args.payload) if args.payload else None
    
    if payload_path and not payload_path.exists():
        print(json.dumps({"error": f"Payload file not found: {payload_path}"}))
        sys.exit(1)
        
    setup_clara_env()
    
    # Check device availability
    device = torch.device('mps' if torch.backends.mps.is_available() else 'cpu')
    
    # Note: Full initialization of CLaRa-7B-E2E requires ~14GB RAM.
    # We dynamically load it here or connect to a running daemon process if heavily optimized.
    # For the pipeline implementation, we print JSON output that the Swift caller parses.
    
    if args.mode == "ingest":
        with open(payload_path, "r") as f:
            data = json.load(f)
            
        doc_id = data.get("documentID", "unknown")
        text = data.get("textContent", "")
        
        # Simulated compressor (Replace with actual apple/CLaRa-7B-Base / encode logic)
        # latents = model.encode(text)
        
        db = load_latents(db_path)
        db[doc_id] = {"text_preview": text[:100], "latent_vector_simulated": True}
        save_latents(db_path, db)
        
        print(json.dumps({"status": "success", "documentID": doc_id, "mode": "ingest"}))
        
    elif args.mode == "query":
        with open(payload_path, "r") as f:
            data = json.load(f)
            
        query_text = data.get("queryText", "")
        top_k = data.get("topK", 5)
        
        db = load_latents(db_path)
        
        # Simulated Search & Generate (Replace with apple/CLaRa-7B-E2E retrieval and generation)
        # response = model.generate(query_text, context_latents=db.values())
        
        cited_docs = list(db.keys())[:top_k]
        fake_response = f"This is an Agentic Search response evaluating '{query_text}' against {len(cited_docs)} compressed latents."
        
        print(json.dumps({
            "generatedAnswer": fake_response,
            "citedDocumentIDs": cited_docs,
            "status": "success",
            "mode": "query"
        }))

if __name__ == "__main__":
    main()
