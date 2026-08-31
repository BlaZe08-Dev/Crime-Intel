# CrimeIntel — Reference Repositories & Models

Grouped by role, with how each is used. Verify licenses at integration time (Rules §18).

---

## Local LLM (Ollama, 3B, swappable)

| Repo / Tool | Role | Notes |
|---|---|---|
| [ollama/ollama](https://github.com/ollama/ollama) | **LLM runtime** | Local server on `localhost:11434`; free, no rate limits. Pull `llama3.2:3b` (or `qwen2.5:3b`). |
| [likelovewant/ollama-for-amd](https://github.com/likelovewant/ollama-for-amd) | RX6500 GPU accel (experimental) | Community ROCm build supporting gfx1034. Optional/bonus only. |
| [ChharithOeun/ollama-amd-windows-setup](https://github.com/ChharithOeun/ollama-amd-windows-setup) | AMD-on-Windows setup guide | Confirms RX6500 = "3B at best," Vulkan/community-fork path. Read before attempting GPU. |
| Flutter ↔ Ollama patterns | Integration reference | `ollama_dart` package or plain `http` calls; stream responses. |

> **Design:** access the LLM through an `LlmClient` interface with a configurable base URL so you can point at a LAN machine (escape hatch) without code changes.

## RAG / Vector Search (local)

| Tool | Role | Notes |
|---|---|---|
| sqlite-vec (or a local FAISS-style index) | Vector store | Keeps retrieval fully local alongside SQLite records/logs. |
| A small local embedding model (via Ollama, e.g. `nomic-embed-text`) | Embeddings | Runs in the same Ollama instance; no extra service. |

## Face Recognition (custom auth)

| Repo / Model | Role | Notes |
|---|---|---|
| ArcFace / FaceNet-style ONNX embedder | Face embeddings | Enroll investigator → match by cosine similarity. |
| [pub.dev `local_auth`](https://pub.dev/packages/local_auth) | Reference only | Note: Windows path = Windows Hello (OS user), **not** custom matching — we intentionally build a custom matcher instead. Documented so no one re-adds it by mistake. |
| Webcam capture (Flutter `camera` / platform channel) | Capture | Feeds frames to the embedder. |

## Email OTP

| Tool | Role | Notes |
|---|---|---|
| [Plunk](https://www.useplunk.com/) (open-source email) | OTP delivery | Transactional email API; key in local `.env`. OTP = **email**, not SMS. |

## Image Enhancement (local, offline)

| Repo / Model | Role | Notes |
|---|---|---|
| [xinntao/Real-ESRGAN](https://github.com/xinntao/real-esrgan) | General upscaling / deblur | Has `--face_enhance` and tiling for low-VRAM. |
| [TencentARC/GFPGAN](https://github.com/tencentarc/gfpgan) | Face restoration | Pair with Real-ESRGAN for faces; clean (no-CUDA) version available. |
| CodeFormer (sczhou/CodeFormer) | Alt face restoration | Alternative to GFPGAN; good on heavy degradation. |
| [HF Space: avans06 upscale/restore](https://huggingface.co/spaces/avans06/Image_Face_Upscale_Restoration-GFPGAN-RestoreFormer-CodeFormer-GPEN) | Reference UI | Shows the model combo in action. |

> **Not using Gemini/paid APIs:** costs money, breaks the offline/self-contained story, and would send crime-scene images off-device. Local Real-ESRGAN+GFPGAN is the chosen path. Always label output as a reconstruction aid, not evidence.

## Graph / Network Analysis

| Tool | Role | Notes |
|---|---|---|
| NER (spaCy-style, or the local LLM in structured-extraction mode) | Entity extraction | People/locations/vehicles/phones/orgs from FIR/intel. |
| Centrality + community detection (Python `networkx` side-process, or a Dart graph lib) | Key individuals + clusters | Betweenness/PageRank + Louvain/Leiden. |
| Force-directed graph widget (Flutter) | Visualization | Renders the network in-app. |

## Reference architecture (whole-system inspiration)
- GraphAware's 2026 write-ups on building criminal-network intelligence from police records (knowledge graph → graph algorithms find leaders → LLM compiles the report) — the same "statistics detects, LLM narrates" pattern this project uses. Reference for approach, not code.

---

## Integration Checklist (per component)
1. Confirm license; record in TechSpec.
2. Wire behind its module interface (LlmClient, enhancer, embedder, etc.).
3. 🧑 Validate on the real 8GB/RX6500 machine (latency, memory, quality).
4. Log every action the component performs through AuditLogger.
