#!/usr/bin/env python3
"""
Verify Ollama and AMD GPU setup on Windows.

Usage:
    python verify_gpu.py

Checks:
    - Ollama installation and version
    - Vulkan support via vulkaninfo
    - Ollama GPU detection (ollama ps or env var)
    - Ollama API availability (if server is running)

Prints diagnostics with fix suggestions.
"""

import subprocess
import sys
import json
from pathlib import Path


def run_command(cmd, shell=True):
    """Run a command and return stdout, stderr, returncode."""
    try:
        result = subprocess.run(
            cmd, shell=shell, capture_output=True, text=True, timeout=10
        )
        return result.stdout.strip(), result.stderr.strip(), result.returncode
    except subprocess.TimeoutExpired:
        return "", "Command timed out", -1
    except FileNotFoundError:
        return "", f"Command not found: {cmd}", -1
    except Exception as e:
        return "", str(e), -1


def check_ollama_installed():
    """Check if Ollama is installed and return version."""
    print("\n[1] Checking Ollama Installation...")
    stdout, stderr, code = run_command("ollama --version")
    if code == 0 and stdout:
        print(f"  ✓ Ollama installed: {stdout}")
        return True
    else:
        print("  ✗ Ollama not found or not in PATH")
        print("  → Fix: Install via 'winget install Ollama.Ollama'")
        print(f"  → Error: {stderr or 'Command failed'}")
        return False


def check_vulkan():
    """Check Vulkan 1.3 support via vulkaninfo."""
    print("\n[2] Checking Vulkan Support...")
    stdout, stderr, code = run_command("vulkaninfo --summary")
    if code == 0:
        if "1.3" in stdout or "apiVersion" in stdout:
            print("  ✓ Vulkan support detected")
            # Extract GPU info if available
            for line in stdout.split("\n"):
                if "Device" in line or "GPU" in line or "Radeon" in line:
                    print(f"    {line.strip()}")
            return True
        else:
            print("  ⚠ Vulkan detected but version unclear")
            print(f"  Output: {stdout[:200]}")
            return True
    else:
        print("  ✗ Vulkan not detected or vulkaninfo not available")
        print("  → Fix: Install/update AMD GPU driver with Vulkan support")
        print("  → AMD drivers: https://www.amd.com/en/support")
        if stderr:
            print(f"  → Error: {stderr}")
        return False


def check_ollama_gpu():
    """Check if Ollama detects GPU via 'ollama ps' or env var."""
    print("\n[3] Checking Ollama GPU Detection...")

    # Try 'ollama ps' (requires Ollama server running)
    stdout, stderr, code = run_command("ollama ps")
    if code == 0:
        print("  ✓ Ollama server is running")
        if "gpu_memory_allocated" in stdout or stdout.count("\t") > 2:
            print("  ✓ GPU appears to be allocated")
            for line in stdout.split("\n")[:3]:
                if line.strip():
                    print(f"    {line}")
            return True
        else:
            print("  ⚠ No models running yet (check after pulling a model)")
            return True
    else:
        print("  ⚠ Ollama server not running or 'ollama ps' failed")
        print("  → Start server: 'ollama serve' in another terminal")

        # Check env var as fallback
        import os
        if os.environ.get("OLLAMA_GPU_LAYERS"):
            print(f"  ℹ OLLAMA_GPU_LAYERS env var set: {os.environ.get('OLLAMA_GPU_LAYERS')}")

        return None


def check_ollama_api():
    """Check if Ollama API is responding."""
    print("\n[4] Checking Ollama API...")
    try:
        import requests
        try:
            response = requests.get("http://localhost:11434/api/tags", timeout=3)
            if response.status_code == 200:
                data = response.json()
                models = data.get("models", [])
                print(f"  ✓ Ollama API responding")
                if models:
                    print(f"  ✓ {len(models)} model(s) available:")
                    for model in models[:3]:
                        size_gb = model.get("size", 0) / (1024**3)
                        print(f"    - {model.get('name', 'unknown')} ({size_gb:.1f} GB)")
                    if len(models) > 3:
                        print(f"    ... and {len(models) - 3} more")
                else:
                    print("  ℹ No models pulled yet")
                    print("  → Pull a model: 'python scripts/pull_models.py --model llama3.1:8b'")
                return True
            else:
                print(f"  ✗ API returned status {response.status_code}")
                return False
        except requests.exceptions.ConnectionError:
            print("  ✗ Cannot connect to Ollama API at http://localhost:11434")
            print("  → Start server: 'ollama serve' in another terminal")
            return False
    except ImportError:
        print("  ⚠ 'requests' not installed, skipping API check")
        print("  → Install: 'pip install requests'")
        return None


def main():
    """Run all checks and print summary."""
    print("=" * 60)
    print("Ollama AMD GPU Setup Verification")
    print("=" * 60)

    checks = [
        ("Ollama Installed", check_ollama_installed),
        ("Vulkan Support", check_vulkan),
        ("GPU Detection", check_ollama_gpu),
        ("API Available", check_ollama_api),
    ]

    results = {}
    for name, check_func in checks:
        try:
            results[name] = check_func()
        except Exception as e:
            print(f"  ✗ Error: {e}")
            results[name] = False

    # Summary
    print("\n" + "=" * 60)
    print("Summary")
    print("=" * 60)
    passed = sum(1 for v in results.values() if v is True)
    failed = sum(1 for v in results.values() if v is False)
    uncertain = sum(1 for v in results.values() if v is None)

    for name, result in results.items():
        symbol = "✓" if result is True else "✗" if result is False else "?"
        status = "PASS" if result is True else "FAIL" if result is False else "WARN"
        print(f"  {symbol} {name}: {status}")

    print("\nNext Steps:")
    if failed == 0 and uncertain == 0:
        print("  → All checks passed! Try:")
        print("     python scripts/pull_models.py --model tinyllama")
        print("     python scripts/chat.py")
        sys.exit(0)
    elif failed > 0:
        print("  → Fix issues above before proceeding")
        sys.exit(1)
    else:
        print("  → Some checks incomplete. Ensure Ollama server is running:")
        print("     ollama serve")
        sys.exit(2)


if __name__ == "__main__":
    main()
