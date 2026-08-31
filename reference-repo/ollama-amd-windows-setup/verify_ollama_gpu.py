#!/usr/bin/env python3
"""
verify_ollama_gpu.py -- Verify Ollama AMD GPU setup on Windows

Checks: Ollama install, AMD GPU detection, VRAM, quick inference test.

Usage:
  pip install requests
  python verify_ollama_gpu.py
  python verify_ollama_gpu.py --model llama3.2:3b
  python verify_ollama_gpu.py --skip-inference
  python verify_ollama_gpu.py --json
"""

import argparse
import json
import os
import platform
import shutil
import subprocess
import sys
import time
from dataclasses import dataclass, field
from typing import Optional

try:
    import requests
except ImportError:
    print("ERROR: pip install requests")
    sys.exit(1)

OLLAMA_HOST = os.environ.get("OLLAMA_HOST", "http://localhost:11434")
DEFAULT_TEST_MODEL = "llama3.2:3b"
INFERENCE_TIMEOUT = 120
INFERENCE_PROMPT = "Count from 1 to 10."

VRAM_RECS = [
    (4,  ["phi3:mini (3.8B)", "gemma2:2b"]),
    (6,  ["llama3.2:3b", "phi3:mini"]),
    (8,  ["llama3.1:8b", "mistral:7b"]),
    (12, ["llama3.1:8b", "codellama:13b"]),
    (16, ["deepseek-r1:14b", "mistral-nemo:12b"]),
    (20, ["deepseek-r1:32b", "codellama:13b"]),
    (24, ["deepseek-r1:32b", "mixtral:8x7b", "llama3.3:70b (Q2)"]),
]


@dataclass
class CheckResult:
    name: str
    passed: bool
    message: str
    detail: str = ""


@dataclass
class Report:
    checks: list = field(default_factory=list)
    gpu_info: dict = field(default_factory=dict)
    tps: Optional[float] = None
    warnings: list = field(default_factory=list)

    def add(self, name, passed, message, detail=""):
        self.checks.append(CheckResult(name, passed, message, detail))
        return passed

    def n_passed(self): return sum(1 for c in self.checks if c.passed)
    def n_failed(self): return sum(1 for c in self.checks if not c.passed)


def run_cmd(args, timeout=10):
    try:
        r = subprocess.run(args, capture_output=True, text=True, timeout=timeout)
        return r.returncode, r.stdout.strip(), r.stderr.strip()
    except Exception as e:
        return -1, "", str(e)


def check_ollama_installed():
    if shutil.which("ollama"):
        rc, out, _ = run_cmd(["ollama", "--version"])
        return True, (out if rc == 0 else "installed (version unknown)")
    return False, "ollama not found in PATH"


def get_ollama_version():
    try:
        resp = requests.get(f"{OLLAMA_HOST}/api/version", timeout=5)
        if resp.status_code == 200:
            return resp.json().get("version")
    except Exception:
        pass
    return None


def check_ollama_running():
    try:
        resp = requests.get(f"{OLLAMA_HOST}/", timeout=5)
        if resp.status_code == 200:
            v = get_ollama_version() or "unknown"
            return True, f"running at {OLLAMA_HOST} (v{v})"
        return False, f"HTTP {resp.status_code}"
    except requests.ConnectionError:
        return False, f"cannot connect to {OLLAMA_HOST} -- is 'ollama serve' running?"
    except Exception as e:
        return False, str(e)


def get_windows_gpu_info():
    gpus = []
    if platform.system() != "Windows":
        return gpus
    ps_cmd = (
        "Get-WmiObject Win32_VideoController | "
        "Where-Object {$_.Name -like '*AMD*' -or $_.Name -like '*Radeon*'} | "
        "Select-Object Name, AdapterRAM, DriverVersion | ConvertTo-Json"
    )
    rc, out, _ = run_cmd(["powershell", "-NoProfile", "-Command", ps_cmd], timeout=15)
    if rc == 0 and out:
        try:
            data = json.loads(out)
            if isinstance(data, dict):
                data = [data]
            for gpu in data:
                vram = (gpu.get("AdapterRAM") or 0) / (1024 ** 3)
                gpus.append({
                    "name": gpu.get("Name", "Unknown"),
                    "vram_gb": round(vram, 1),
                    "driver": gpu.get("DriverVersion", "unknown"),
                })
        except Exception:
            pass
    return gpus


def check_dll():
    if platform.system() != "Windows":
        return True, "not applicable (not Windows)"
    dll = r"C:\Windows\System32\amdhip64_6.dll"
    if os.path.exists(dll):
        mb = os.path.getsize(dll) / (1024 * 1024)
        return True, f"amdhip64_6.dll found ({mb:.1f} MB)"
    ps_cmd = (
        "Get-ChildItem 'C:\Windows\System32\amdhip64*.dll' "
        "-ErrorAction SilentlyContinue | Select-Object -ExpandProperty Name"
    )
    rc, out, _ = run_cmd(["powershell", "-NoProfile", "-Command", ps_cmd], timeout=10)
    if rc == 0 and out:
        return True, f"found: {out}"
    return False, "amdhip64_6.dll missing -- update AMD Adrenalin drivers"


def check_vulkan_env():
    if os.environ.get("OLLAMA_VULKAN") == "1":
        return True, "OLLAMA_VULKAN=1 (Vulkan backend enabled)"
    return False, "OLLAMA_VULKAN not set (ROCm/HIP path only)"


def check_kfd():
    if platform.system() == "Windows":
        return True, "not applicable (Windows)"
    if os.path.exists("/dev/kfd"):
        return True, "/dev/kfd found -- ROCm passthrough available"
    if os.path.exists("/dev/dxg"):
        return False, "/dev/kfd not found (WSL2 DXCore only -- AMD ROCm may not work)"
    return False, "/dev/kfd not found"


def run_inference(model):
    try:
        resp = requests.get(f"{OLLAMA_HOST}/api/tags", timeout=5)
        if resp.status_code == 200:
            names = [m["name"] for m in resp.json().get("models", [])]
            if model not in names:
                return {"error": f"Model not pulled. Run: ollama pull {model}", "available": names[:8]}
    except Exception as e:
        return {"error": str(e)}

    print(f"  Prompt: {INFERENCE_PROMPT!r}")
    start = time.time()
    first_tok = None
    text = ""

    try:
        resp = requests.post(
            f"{OLLAMA_HOST}/api/generate",
            json={"model": model, "prompt": INFERENCE_PROMPT, "stream": True,
                  "options": {"num_predict": 50, "temperature": 0}},
            stream=True, timeout=INFERENCE_TIMEOUT,
        )
        for line in resp.iter_lines():
            if not line:
                continue
            try:
                chunk = json.loads(line)
                if chunk.get("response"):
                    if first_tok is None:
                        first_tok = time.time()
                    text += chunk["response"]
                if chunk.get("done"):
                    n = chunk.get("eval_count", 0)
                    d = chunk.get("eval_duration", 0) / 1e9
                    tps = n / d if d > 0 else 0
                    return {
                        "ok": True,
                        "text": text.strip(),
                        "tps": round(tps, 1),
                        "first_tok_s": round(first_tok - start, 2) if first_tok else None,
                        "load_s": round(chunk.get("load_duration", 0) / 1e9, 2),
                    }
            except json.JSONDecodeError:
                continue
    except requests.Timeout:
        return {"error": f"Timed out after {INFERENCE_TIMEOUT}s"}
    except Exception as e:
        return {"error": str(e)}
    return {"ok": True, "text": text.strip(), "tps": 0}


def interpret_tps(tps):
    if tps >= 30: return f"{tps} tok/s -- GPU confirmed (excellent)"
    if tps >= 15: return f"{tps} tok/s -- likely GPU accelerated (good)"
    if tps >= 5:  return f"{tps} tok/s -- possibly partial GPU offload (mediocre)"
    if tps >= 1:  return f"{tps} tok/s -- CPU-only or near-zero GPU offload (slow)"
    return f"{tps} tok/s -- something is wrong"


def vram_recs(vram):
    for t, models in VRAM_RECS:
        if vram <= t:
            return models
    return VRAM_RECS[-1][1]


def main():
    ap = argparse.ArgumentParser(description="Verify Ollama AMD GPU setup")
    ap.add_argument("--model", default=DEFAULT_TEST_MODEL)
    ap.add_argument("--skip-inference", action="store_true")
    ap.add_argument("--json", dest="json_out", action="store_true")
    args = ap.parse_args()

    report = Report()
    W = "✓"; F = "✗"; S = "—"

    print()
    print("=" * 60)
    print("  Ollama AMD GPU Verification")
    print(f"  Platform: {platform.system()} {platform.release()}")
    print("=" * 60)
    print()

    print("[1/7] Ollama installation...")
    ok, msg = check_ollama_installed()
    report.add("ollama_installed", ok, msg)
    print(f"  {W if ok else F} {msg}")
    if not ok:
        print("  Install from: https://ollama.com/download/windows")
        sys.exit(1)

    print("\n[2/7] Ollama server...")
    ok, msg = check_ollama_running()
    report.add("ollama_running", ok, msg)
    print(f"  {W if ok else F} {msg}")
    if not ok:
        print("  Run: ollama serve")

    print("\n[3/7] AMD ROCm DLL (Windows)...")
    ok, msg = check_dll()
    report.add("amd_dll", ok, msg)
    print(f"  {W if ok else F} {msg}")

    print("\n[4/7] AMD GPU detection (WMI)...")
    gpus = get_windows_gpu_info()
    if gpus:
        report.gpu_info["gpus"] = gpus
        for g in gpus:
            report.add("gpu_detected", True, f"{g['name']} detected")
            print(f"  {W} {g['name']}")
            print(f"    VRAM (WMI): {g['vram_gb']} GB  |  Driver: {g['driver']}")
            if g["vram_gb"] <= 4.0:
                report.warnings.append(f"WMI may underreport VRAM for {g['name']}")
                print("    NOTE: WMI caps VRAM at 4 GB -- actual may be higher")
            else:
                print(f"    Suggested models: {', '.join(vram_recs(g['vram_gb'])[:3])}")
    else:
        if platform.system() == "Windows":
            report.add("gpu_detected", False, "No AMD GPU found via WMI")
            print(f"  {F} No AMD GPU detected")
        else:
            report.add("gpu_detected", True, "WMI not applicable (non-Windows)")
            print(f"  {S} WMI skipped (not Windows)")

    print("\n[5/7] ROCm device nodes...")
    ok, msg = check_kfd()
    if platform.system() != "Windows":
        report.add("kfd_device", ok, msg)
    print(f"  {(W if ok else F) if platform.system() != 'Windows' else S} {msg}")

    print("\n[6/7] Vulkan backend config...")
    ok, msg = check_vulkan_env()
    report.add("vulkan_env", ok, msg)
    print(f"  {W if ok else S} {msg}")
    if not ok:
        print("  Tip: $env:OLLAMA_VULKAN = '1' then restart ollama serve  (v0.12.11+)")

    if not args.skip_inference:
        print(f"\n[7/7] Inference test ({args.model})...")
        if report.checks[1].passed:
            result = run_inference(args.model)
            if result.get("error"):
                report.add("inference", False, result["error"])
                print(f"  {F} {result['error']}")
                if "available" in result:
                    print(f"  Available: {', '.join(result['available'])}")
            elif result.get("ok"):
                tps = result.get("tps", 0)
                interp = interpret_tps(tps)
                report.add("inference", True, interp)
                report.tps = tps
                print(f"  {W} {interp}")
                preview = result.get("text", "")[:60]
                print(f"    Output: \"{preview}...\"")
                if result.get("load_s"):
                    print(f"    Load time: {result['load_s']}s")
                if result.get("first_tok_s"):
                    print(f"    First token: {result['first_tok_s']}s")
        else:
            report.add("inference", False, "Skipped -- Ollama not running")
            print(f"  {S} Skipped")
    else:
        print("\n[7/7] Inference test skipped (--skip-inference)")

    print()
    print("=" * 60)
    print("  SUMMARY")
    print("=" * 60)
    for c in report.checks:
        print(f"  {W if c.passed else F} {c.name:30s} {c.message}")

    failed = report.n_failed()
    passed = report.n_passed()
    total = len(report.checks)
    print()
    if failed == 0:
        print(f"  ALL CHECKS PASSED ({passed}/{total})")
    else:
        print(f"  {passed}/{total} passed, {failed} failed")
        print()
        print("  Failures:")
        for c in report.checks:
            if not c.passed:
                print(f"    {F} {c.name}: {c.message}")
        print()
        print("  See troubleshooting.md or https://github.com/ollama/ollama/issues")

    for w in report.warnings:
        print(f"  WARNING: {w}")

    print()
    print("  Key environment variables:")
    print("    OLLAMA_VULKAN=1           Vulkan backend (v0.12.11+, all AMD with Adrenalin)")
    print("    OLLAMA_GPU_OVERHEAD=bytes Reserve VRAM headroom (e.g. 1073741824 = 1GB)")
    print("    OLLAMA_FLASH_ATTENTION=1  Reduce KV cache VRAM (ROCm Linux only)")
    print("    OLLAMA_DEBUG=1            Verbose GPU detection logs")
    print("    ROCR_VISIBLE_DEVICES=1    Select AMD GPU by index")
    print()

    if args.json_out:
        print(json.dumps({
            "checks": [{"name": c.name, "passed": c.passed, "message": c.message}
                       for c in report.checks],
            "gpu_info": report.gpu_info,
            "tps": report.tps,
            "warnings": report.warnings,
            "all_passed": failed == 0,
        }, indent=2))

    sys.exit(0 if failed == 0 else 1)


if __name__ == "__main__":
    main()
