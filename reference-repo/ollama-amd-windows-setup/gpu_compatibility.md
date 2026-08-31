# GPU Compatibility Table — Ollama on Windows

> Last updated: 2026-03-29 | Ollama v0.12.11+ | ROCm 6.1 (official) / ROCm 6.4 (community fork)

## Quick Legend

| Symbol | Meaning |
|--------|---------|
| ✅ | Works reliably |
| ⚠️ | Works with workaround |
| 🔶 | Community fork only |
| ❌ | Does not work / falls back to CPU |
| 🧪 | Experimental (Vulkan) |

---

## RX 9000 Series (RDNA 4)

| GPU | VRAM | GFX | Official ROCm | Community Fork | Vulkan | Recommended Method | Max Model (Q4_K_M) |
|-----|------|-----|--------------|----------------|--------|-------------------|--------------------|
| RX 9070 XT | 16 GB | gfx1200 | ❌ | 🔶 v0.18.2+ | 🧪 | Community fork | 13B clean, 32B tight |
| RX 9070 | 16 GB | gfx1200 | ❌ | 🔶 v0.18.2+ | 🧪 | Community fork | 13B clean, 32B tight |

---

## RX 7000 Series (RDNA 3)

| GPU | VRAM | GFX | Official ROCm | Community Fork | Vulkan | Recommended Method | Max Model (Q4_K_M) |
|-----|------|-----|--------------|----------------|--------|-------------------|--------------------|
| RX 7900 XTX | 24 GB | gfx1100 | ✅ | ✅ | 🧪 | Official Ollama | 32B clean, 70B partial |
| RX 7900 XT | 20 GB | gfx1100 | ✅ | ✅ | 🧪 | Official Ollama | 32B clean |
| RX 7900 GRE | 16 GB | gfx1100 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 7800 XT | 16 GB | gfx1101 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 7700 XT | 12 GB | gfx1101 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean |
| RX 7600 XT | 16 GB | gfx1102 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 7600 | 8 GB | gfx1102 | ✅ | ✅ | 🧪 | Official Ollama | 7B/8B clean |

---

## RX 6000 Series (RDNA 2)

| GPU | VRAM | GFX | Official ROCm | Community Fork | Vulkan | Recommended Method | Max Model (Q4_K_M) |
|-----|------|-----|--------------|----------------|--------|-------------------|--------------------|
| RX 6950 XT | 16 GB | gfx1030 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 6900 XT | 16 GB | gfx1030 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 6800 XT | 16 GB | gfx1030 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 6800 | 16 GB | gfx1030 | ✅ | ✅ | 🧪 | Official Ollama | 13B clean, 32B tight |
| RX 6700 XT | 12 GB | gfx1031 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 13B clean |
| RX 6700 | 10 GB | gfx1031 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 6650 XT | 8 GB | gfx1032 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 6600 XT | 8 GB | gfx1032 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 6600 | 8 GB | gfx1032 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 6500 XT | 4 GB | gfx1034 | ❌ | 🔶 | 🧪 | Vulkan only (very tight) | 3B at best |
| RX 6400 | 4 GB | gfx1034 | ❌ | 🔶 | 🧪 | Vulkan only | 3B at best |

> **Note on gfx1030 regression:** Ollama v0.12.1–v0.12.10 broke RX 6800/6900 on Windows. Fixed in v0.12.11+.

---

## RX 5000 Series (RDNA 1)

| GPU | VRAM | GFX | Official ROCm | Community Fork | Vulkan | Recommended Method | Max Model (Q4_K_M) |
|-----|------|-----|--------------|----------------|--------|-------------------|--------------------|
| RX 5700 XT | 8 GB | gfx1010 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 5700 | 8 GB | gfx1010 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |
| RX 5600 XT | 6 GB | gfx1010 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B tight |
| RX 5500 XT | 8 GB | gfx1012 | ❌ | 🔶 | 🧪 | Community fork or Vulkan | 7B/8B clean |

---

## Integrated GPUs (RDNA 3.5 / Phoenix / Hawk Point)

| GPU | VRAM (shared) | GFX | Official ROCm | Community Fork | Vulkan | Notes |
|-----|--------------|-----|--------------|----------------|--------|-------|
| Radeon 780M (Ryzen 7040) | up to 8 GB | gfx1103 | ❌ | 🔶 | 🧪 | Can conflict with dGPU |
| Radeon 760M (Ryzen 7040) | up to 8 GB | gfx1103 | ❌ | 🔶 | 🧪 | Same |
| Radeon 890M (Ryzen AI HX) | up to 16 GB | gfx1150/1151 | ❌ | 🔶 | 🧪 | Community fork v0.18.2+ |
| Radeon 880M (Ryzen AI) | up to 12 GB | gfx1150 | ❌ | 🔶 | 🧪 | Community fork v0.18.2+ |

> **iGPU Warning:** If you have both an iGPU and a discrete GPU, Ollama may pick the iGPU. Workaround: disable iGPU in BIOS, or use `ROCR_VISIBLE_DEVICES=1`.

---

## Model Size Quick Reference

| GPU VRAM | 7B/8B | 13B | 32B | 70B | Notes |
|----------|-------|-----|-----|-----|-------|
| 4 GB | ⚠️ (tight) | ❌ | ❌ | ❌ | Q4_K_M barely fits 7B |
| 6–8 GB | ✅ | ⚠️ | ❌ | ❌ | |
| 10–12 GB | ✅ | ✅ | ❌ | ❌ | |
| 16 GB | ✅ | ✅ | ⚠️ | ❌ | 32B tight at 32K ctx |
| 20 GB | ✅ | ✅ | ✅ | ❌ | |
| 24 GB | ✅ | ✅ | ✅ | ⚠️ | 70B needs Q2/Q3 quant |

> Estimates assume Q4_K_M quantization. KV cache at 32K ctx adds ~4.5 GB for 8B (FP16). Use `OLLAMA_FLASH_ATTENTION=1` on Linux/ROCm.

---

## GFX Version Quick Reference

| GFX Version | Architecture | Example GPUs |
|-------------|-------------|--------------|
| gfx906 | Vega 20 | Radeon VII, Instinct MI50/60 |
| gfx1010 | Navi 10 (RDNA 1) | RX 5700 XT, RX 5700 |
| gfx1012 | Navi 14 (RDNA 1) | RX 5500 XT |
| gfx1030 | Navi 21 (RDNA 2) | RX 6800, RX 6800 XT, RX 6900 XT, RX 6950 XT |
| gfx1031 | Navi 22 (RDNA 2) | RX 6700 XT, RX 6700 |
| gfx1032 | Navi 23 (RDNA 2) | RX 6600 XT, RX 6600, RX 6650 XT |
| gfx1034 | Navi 24 (RDNA 2) | RX 6500 XT, RX 6400 |
| gfx1035/1036 | Rembrandt/Phoenix iGPU | Radeon 680M, 760M |
| gfx1100 | Navi 31 (RDNA 3) | RX 7900 XTX, RX 7900 XT, RX 7900 GRE |
| gfx1101 | Navi 32 (RDNA 3) | RX 7800 XT, RX 7700 XT |
| gfx1102 | Navi 33 (RDNA 3) | RX 7600 XT, RX 7600 |
| gfx1103 | Phoenix (RDNA 3) | Radeon 780M, 760M (Ryzen 7040) |
| gfx1150/1151 | Hawk Point / Strix (RDNA 3.5) | Radeon 890M, 880M (Ryzen AI 300) |
| gfx1200/1201 | Navi 48/44 (RDNA 4) | RX 9070 XT, RX 9070 |
