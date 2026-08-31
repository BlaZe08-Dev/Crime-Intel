# reference-repo/

Local copies of the code-relevant reference repositories, so Claude Code (or any agent) can read real implementation patterns offline instead of guessing API shapes from memory.

## What's cloned here (code you'll adapt from)

| Folder | Source | Why it's here |
|---|---|---|
| `Real-ESRGAN/` | github.com/xinntao/Real-ESRGAN | General image upscaling/deblurring — the base of the enhancement module |
| `GFPGAN/` | github.com/TencentARC/GFPGAN | Face restoration, paired with Real-ESRGAN for faces |
| `CodeFormer/` | github.com/sczhou/CodeFormer | Alternate/backup face-restoration model |
| `ollama-amd-windows-setup/` | github.com/ChharithOeun/ollama-amd-windows-setup | AMD-on-Windows Ollama setup notes — read before attempting the RX6500 GPU-accel task |

`.git` history was stripped from each — these are read-only reference snapshots, not repos to commit into or pull-update. If you need the latest version of any of these, re-clone fresh.

Model weights are **not** included (that's normal — these repos download weights separately via their own scripts/READMEs). Follow each project's own instructions to fetch weights during Phase 5 of `ImplementationPlan.md`.

## What's referenced but NOT cloned here (and why)

| Tool | Why not cloned |
|---|---|
| **Ollama** (ollama/ollama) | You install this as an application (the official Windows installer), not as vendored source. Get it from ollama.com. |
| **likelovewant/ollama-for-amd** | A full fork of Ollama meant to be *built or downloaded as a binary*, not read as reference code for this project. If you attempt the experimental RX6500 GPU path (Tracker.md Phase 1), download its release directly rather than building from a local clone. |
| `local_auth` (pub.dev package) | Only referenced in `docs/ReferenceRepo.md` as a **cautionary note** — it's the wrong tool for our custom face-matching approach (it does Windows Hello, not custom matching). Nothing to clone. |
| GraphAware criminal-network write-ups | An architecture reference (a blog series), not a code repo. |

## How to use this folder
Point Claude Code (or yourself) at the relevant subfolder when implementing that module — e.g. when building `enhance/`, read `Real-ESRGAN/inference_realesrgan.py` and `GFPGAN/inference_gfpgan.py` for the actual call patterns before writing the Flutter-side process invocation.
