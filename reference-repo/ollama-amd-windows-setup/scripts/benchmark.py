#!/usr/bin/env python3
"""
Benchmark Ollama model performance on AMD GPU.

Usage:
    python benchmark.py
    python benchmark.py --model phi3:mini
    python benchmark.py --model llama3.1:8b --runs 5 --prompt "Your custom prompt"

Measures tokens/second for a given model using the REST API.
Requires Ollama server running on localhost:11434.
"""

import argparse
import json
import time
import sys
from typing import List, Dict, Any


def benchmark_model(
    model: str, prompt: str, runs: int = 3, api_url: str = "http://localhost:11434"
) -> Dict[str, Any]:
    """
    Benchmark a model by generating responses and measuring tokens/sec.

    Args:
        model: Model name (e.g., "tinyllama", "phi3:mini")
        prompt: Prompt to use for testing
        runs: Number of benchmark runs
        api_url: Base URL for Ollama API

    Returns:
        Dictionary with benchmark results (avg, min, max tokens/sec)
    """
    try:
        import requests
    except ImportError:
        print("Error: 'requests' not installed")
        print("Install: pip install requests")
        sys.exit(1)

    api_endpoint = f"{api_url}/api/generate"
    payload = {
        "model": model,
        "prompt": prompt,
        "stream": True,
    }

    times = []
    token_counts = []

    print(f"\nBenchmarking '{model}' with {runs} run(s)...")
    print(f"Prompt: {prompt[:60]}{'...' if len(prompt) > 60 else ''}")
    print("-" * 60)

    for run_num in range(1, runs + 1):
        try:
            start_time = time.time()
            token_count = 0

            response = requests.post(api_endpoint, json=payload, stream=True, timeout=300)
            response.raise_for_status()

            for line in response.iter_lines():
                if line:
                    try:
                        chunk = json.loads(line)
                        # Count tokens: either explicit count or assume 1 per response
                        token_count += 1
                    except json.JSONDecodeError:
                        continue

            end_time = time.time()
            elapsed = end_time - start_time

            if elapsed > 0:
                tokens_per_sec = token_count / elapsed
                times.append(elapsed)
                token_counts.append(token_count)
                print(f"  Run {run_num}: {token_count} tokens in {elapsed:.2f}s = {tokens_per_sec:.2f} t/s")
            else:
                print(f"  Run {run_num}: Error - elapsed time is 0")

        except requests.exceptions.ConnectionError:
            print(f"  Run {run_num}: Error - Cannot connect to Ollama API")
            print(f"            Make sure Ollama is running: ollama serve")
            sys.exit(1)
        except requests.exceptions.Timeout:
            print(f"  Run {run_num}: Error - Request timeout")
            sys.exit(1)
        except requests.exceptions.RequestException as e:
            print(f"  Run {run_num}: Error - {e}")
            sys.exit(1)

    if not times or not token_counts:
        print("Error: No successful runs")
        sys.exit(1)

    # Calculate statistics
    tokens_per_sec_list = [
        token_counts[i] / times[i] for i in range(len(times)) if times[i] > 0
    ]

    if not tokens_per_sec_list:
        print("Error: Could not calculate tokens/sec")
        sys.exit(1)

    avg_tps = sum(tokens_per_sec_list) / len(tokens_per_sec_list)
    min_tps = min(tokens_per_sec_list)
    max_tps = max(tokens_per_sec_list)

    print("-" * 60)
    print(f"Results:")
    print(f"  Average: {avg_tps:.2f} tokens/sec")
    print(f"  Min:     {min_tps:.2f} tokens/sec")
    print(f"  Max:     {max_tps:.2f} tokens/sec")

    return {
        "model": model,
        "avg_tokens_per_sec": avg_tps,
        "min_tokens_per_sec": min_tps,
        "max_tokens_per_sec": max_tps,
        "runs": runs,
    }


def main():
    """Parse args and run benchmark."""
    parser = argparse.ArgumentParser(
        description="Benchmark Ollama model performance"
    )
    parser.add_argument(
        "--model",
        default="tinyllama",
        help="Model to benchmark (default: tinyllama)",
    )
    parser.add_argument(
        "--prompt",
        default="Explain quantum computing in one sentence.",
        help="Prompt to use (default: quantum computing question)",
    )
    parser.add_argument(
        "--runs",
        type=int,
        default=3,
        help="Number of benchmark runs (default: 3)",
    )
    parser.add_argument(
        "--url",
        default="http://localhost:11434",
        help="Ollama API base URL (default: http://localhost:11434)",
    )

    args = parser.parse_args()

    print("=" * 60)
    print("Ollama Model Benchmark")
    print("=" * 60)

    result = benchmark_model(
        model=args.model,
        prompt=args.prompt,
        runs=args.runs,
        api_url=args.url,
    )

    print("\n" + "=" * 60)
    print("Benchmark complete!")
    print("=" * 60)


if __name__ == "__main__":
    main()
