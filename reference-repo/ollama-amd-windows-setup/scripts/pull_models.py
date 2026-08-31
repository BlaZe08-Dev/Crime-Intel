#!/usr/bin/env python3
"""
Pull recommended models from Ollama registry via REST API.

Usage:
    python pull_models.py
    python pull_models.py --list
    python pull_models.py --model llama3.1:8b
    python pull_models.py --all

Predefined models:
    tinyllama (270M params, ~1 GB)
    phi3:mini (3.8B params, ~2 GB)
    llama3.1:8b (8.0B params, ~5 GB)
    mistral:7b (7.2B params, ~4 GB)
    qwen2.5:7b (7.6B params, ~4 GB)

Requires Ollama server running on localhost:11434.
"""

import argparse
import json
import sys
from typing import List


MODELS = {
    "tinyllama": {
        "name": "tinyllama",
        "size": "272 MB",
        "params": "1.1B",
        "vram": "~1 GB",
        "desc": "Ultra-fast, good for testing"
    },
    "phi3:mini": {
        "name": "phi3:mini",
        "size": "1.3 GB",
        "params": "3.8B",
        "vram": "~2 GB",
        "desc": "Fast, good quality"
    },
    "llama3.1:8b": {
        "name": "llama3.1:8b",
        "size": "4.7 GB",
        "params": "8.0B",
        "vram": "~6 GB",
        "desc": "Balanced, recommended default"
    },
    "mistral:7b": {
        "name": "mistral:7b",
        "size": "4.0 GB",
        "params": "7.2B",
        "vram": "~5 GB",
        "desc": "Fast, good reasoning"
    },
    "qwen2.5:7b": {
        "name": "qwen2.5:7b",
        "size": "3.8 GB",
        "params": "7.6B",
        "vram": "~5 GB",
        "desc": "Multilingual, fast"
    },
    "gemma2:9b": {
        "name": "gemma2:9b",
        "size": "5.5 GB",
        "params": "9.2B",
        "vram": "~7 GB",
        "desc": "High quality, larger context"
    },
}


def pull_model(model_name: str, api_url: str = "http://localhost:11434") -> bool:
    """
    Pull a model from Ollama registry.

    Args:
        model_name: Model name (e.g., "llama3.1:8b")
        api_url: Base URL for Ollama API

    Returns:
        True if successful, False otherwise
    """
    try:
        import requests
    except ImportError:
        print("Error: 'requests' not installed")
        print("Install: pip install requests")
        return False

    endpoint = f"{api_url}/api/pull"
    payload = {"name": model_name}

    print(f"\nPulling '{model_name}'...")
    print("-" * 60)

    try:
        response = requests.post(
            endpoint,
            json=payload,
            stream=True,
            timeout=3600  # 1 hour timeout for large models
        )
        response.raise_for_status()

        total_size = 0
        for line in response.iter_lines():
            if line:
                try:
                    chunk = json.loads(line)
                    status = chunk.get("status", "")

                    # Print progress
                    if "downloading" in status.lower():
                        completed = chunk.get("completed", 0)
                        total = chunk.get("total", 0)
                        if total > 0:
                            percent = (completed / total) * 100
                            mb_completed = completed / (1024 * 1024)
                            mb_total = total / (1024 * 1024)
                            print(f"  {percent:.1f}% ({mb_completed:.1f} / {mb_total:.1f} MB)")
                    elif "success" in status.lower() or "pulling" in status.lower():
                        print(f"  {status}")

                except json.JSONDecodeError:
                    continue

        print("-" * 60)
        print(f"✓ Successfully pulled '{model_name}'")
        return True

    except requests.exceptions.ConnectionError:
        print(f"✗ Error: Cannot connect to Ollama API at {api_url}")
        print("  Make sure Ollama is running: ollama serve")
        return False
    except requests.exceptions.Timeout:
        print(f"✗ Error: Request timeout (model might be large)")
        return False
    except requests.exceptions.RequestException as e:
        print(f"✗ Error: {e}")
        return False


def list_models():
    """List available models."""
    print("\n" + "=" * 60)
    print("Available Models")
    print("=" * 60)
    for name, info in MODELS.items():
        print(f"\n  {info['name']}")
        print(f"    Size:   {info['size']}")
        print(f"    Params: {info['params']}")
        print(f"    VRAM:   {info['vram']}")
        print(f"    {info['desc']}")


def main():
    """Parse args and pull models."""
    parser = argparse.ArgumentParser(
        description="Pull models from Ollama registry"
    )
    parser.add_argument(
        "--list",
        action="store_true",
        help="List available models",
    )
    parser.add_argument(
        "--model",
        help="Specific model to pull (e.g., 'llama3.1:8b')",
    )
    parser.add_argument(
        "--all",
        action="store_true",
        help="Pull all recommended models",
    )
    parser.add_argument(
        "--url",
        default="http://localhost:11434",
        help="Ollama API base URL (default: http://localhost:11434)",
    )

    args = parser.parse_args()

    print("=" * 60)
    print("Ollama Model Puller")
    print("=" * 60)

    if args.list:
        list_models()
        return

    # Determine which models to pull
    models_to_pull: List[str] = []

    if args.model:
        models_to_pull = [args.model]
    elif args.all:
        models_to_pull = list(MODELS.keys())
    else:
        # Default: pull tinyllama
        models_to_pull = ["tinyllama"]

    # Pull models
    success_count = 0
    for model_name in models_to_pull:
        if pull_model(model_name, args.url):
            success_count += 1

    # Summary
    print("\n" + "=" * 60)
    print(f"Pulled {success_count}/{len(models_to_pull)} model(s)")
    print("=" * 60)

    if success_count == len(models_to_pull):
        print("\n✓ All models pulled successfully!")
        print("\nNext: Try chatting with a model")
        print("  python scripts/chat.py --model tinyllama")
        sys.exit(0)
    else:
        print("\n✗ Some models failed to pull")
        sys.exit(1)


if __name__ == "__main__":
    main()
