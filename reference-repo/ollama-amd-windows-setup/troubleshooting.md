# Troubleshooting — Ollama AMD GPU on Windows

> The 10 most common failure modes, with root causes and fixes.

---

## 1. "Unable to load amdhip64_6.dll"

**Symptom:** Ollama log shows:
```
unable to load amdhip64_6.dll, please make sure to upgrade to the latest AMD driver
```
Ollama silently falls back to CPU.

**Root cause:** Ollama's ROCm/HIP backend requires `amdhip64_6.dll`, shipped with AMD Adrenalin drivers.

**Fix:**
1. Install latest [AMD Adrenalin drivers](https://www.amd.com/en/support/download/drivers.html)
2. Verify: `Get-ChildItem "C:\Windows\System32\amdhip64_6.dll"`
3. Restart Ollama

---

## 2. GPU Detected but 0% GPU Utilization

**Symptom:** `ollama ps` shows model loaded but GPU stays at 0% while CPU runs at 100%. Very slow inference (1–5 tok/s).

**Root causes:**
- Model too large for VRAM — silent CPU fallback
- iGPU selected instead of dGPU
- `HIP_VISIBLE_DEVICES` or `ROCR_VISIBLE_DEVICES` set incorrectly

**Fixes:**
```powershell
# Verbose logs to diagnose
$env:OLLAMA_DEBUG = "1"; ollama serve

# Target dGPU explicitly (if iGPU is selected)
$env:ROCR_VISIBLE_DEVICES = "1"
$env:HIP_VISIBLE_DEVICES = "1"
ollama serve
```

---

## 3. "Vulkan initialization failed" / OLLAMA_VULKAN=1 Does Nothing

**Root cause:** Vulkan backend requires Ollama v0.12.11 or later.

**Fix:**
```powershell
ollama --version   # Must be 0.12.11+
# Update from https://ollama.com/download/windows

$env:OLLAMA_DEBUG = "1"
$env:OLLAMA_VULKAN = "1"
ollama serve   # Look for "vulkan" in startup logs
```

---

## 4. Exception 0xc0000005 Crash After Update

**Root cause:** Conflicting `ggml-hip.dll` copies after Ollama update.

**Fix:**
```powershell
ollama stop
taskkill /F /IM ollama.exe
Remove-Item -Recurse -Force "$env:LOCALAPPDATA\Programs\Ollama\lib\ollama"
# Reinstall from https://ollama.com/download/windows
```

---

## 5. iGPU + dGPU Conflict ("ROCm error: invalid device function")

**Root cause:** ROCm enumerates all AMD devices. The iGPU (e.g., gfx1103) causes errors.

**Fixes (in order of reliability):**
1. Disable iGPU in BIOS
2. Set device index:
   ```powershell
   $env:ROCR_VISIBLE_DEVICES = "1"   # 0=iGPU, 1=dGPU (adjust as needed)
   $env:HIP_VISIBLE_DEVICES = "1"
   ollama serve
   ```
3. Community fork with per-device override:
   ```powershell
   $env:HSA_OVERRIDE_GFX_VERSION_0 = "10.3.0"
   ```

---

## 6. AMD GPU Not Detected in Docker on Windows

**Root cause:** Docker Desktop uses WSL2. WSL2 exposes `/dev/dxg` not `/dev/kfd`. ROCm requires `/dev/kfd`.

**Workaround:** Use Vulkan in the standard image:
```yaml
services:
  ollama:
    image: ollama/ollama:latest   # not :rocm
    environment:
      - OLLAMA_VULKAN=1
```

**Best solution:** Don't use Docker for AMD GPU inference on Windows. Run Ollama natively.

---

## 7. HSA_OVERRIDE_GFX_VERSION Has No Effect on Windows

**Root cause:** The official Ollama Windows binary ignores this variable (see [Issue #3107](https://github.com/ollama/ollama/issues/3107)).

**Fix:** Use the `ollama-for-amd` community fork:
- https://github.com/likelovewant/ollama-for-amd/releases
- Replace official Ollama with the community build, then set `HSA_OVERRIDE_GFX_VERSION`

---

## 8. "Out of Memory" / Model Fails to Load

**Fixes:**
```powershell
# Reserve VRAM headroom (1.25 GB for 12 GB cards)
$env:OLLAMA_GPU_OVERHEAD = "1342177280"
ollama serve

# Reduce context window (in Modelfile or API call)
# PARAMETER num_ctx 4096

# Use more aggressive quantization: Q3_K_M or Q2_K instead of Q4_K_M
```

For RX 7900 XTX users seeing only 12GB of 24GB VRAM:
```
# In Modelfile
PARAMETER num_gpu 99
```

---

## 9. GPU Stopped Working After Windows/Driver Update

**Fix:**
1. Check DLL: `Get-ChildItem "C:\Windows\System32\amdhip64*.dll"`
2. If missing: reinstall previous Adrenalin from [AMD driver archive](https://www.amd.com/en/support/previous-drivers.html)
3. Run `python verify_ollama_gpu.py` to diagnose

---

## 10. Vulkan Picks Integrated GPU Instead of Discrete GPU

**Root cause:** Vulkan enumerates all Vulkan-capable devices; iGPU may enumerate first.

**Workarounds:**
1. Disable iGPU in BIOS (most reliable)
2. Use ROCm path with `ROCR_VISIBLE_DEVICES=1` instead of Vulkan
3. Verify which GPU is active in Task Manager → Performance → GPU 0/1

---

## Diagnostic Checklist

```powershell
# Run before opening a GitHub issue:
ollama --version
$env:OLLAMA_DEBUG = "1"; ollama serve 2>&1 | Select-String "gpu|GPU|hip|vulkan|rocm|device"
Get-ChildItem "C:\Windows\System32\amdhip64*.dll" | Select Name, Length
ollama ps
python verify_ollama_gpu.py
```

Report issues at: https://github.com/ollama/ollama/issues
