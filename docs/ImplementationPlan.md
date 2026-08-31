# CrimeIntel — Implementation Plan

**Window:** ~30 Aug → **12 Sep** (≈13 days) · **Team:** one human builder + AI assist
**Strategy:** full scope with risk flagged.

---

## Legend
- 🤖 AI can do most of it · 🧑 human-only (Windows build, webcam, GPU, on-machine perf) · ⚠️ demo-critical risk

---

## Phase 0 — Foundation (Days 1–2)
- 🤖 Scaffold Flutter Windows desktop project; module structure per TechSpec.
- 🤖 SQLite setup; data models (Schema.md); ingestion of the synthetic dataset.
- 🤖 **Hash-chained AuditLogger** — build this early; everything else logs through it.
- 🧑 Confirm `flutter build windows` runs on the actual machine.

**Exit:** app opens on Windows, synthetic data loads, first log entries chain correctly.

## Phase 1 — Local LLM + RAG core (Days 3–5) ⚠️ core value
- 🧑 ⚠️ Install Ollama on the 8GB/RX6500 machine; pull a **3B Q4** model; confirm it answers on **CPU**. (GPU enablement = separate experimental task, below.)
- 🤖 `LlmClient` interface + Ollama HTTP client (base URL configurable → LAN fallback).
- 🤖 Build the RAG pipeline: embed records/logs → local vector store → retrieve → grounded prompt → answer with source IDs.
- 🤖 Chat UI; "not in the database" behavior when retrieval is empty.
- 🧑 Measure answer latency on the real machine; if unusable, switch base URL to a LAN machine.

**Exit:** ⭐ investigator asks a question, gets a grounded answer citing synthetic records. **Protect this milestone.**

### Parallel (anytime, experimental) 🧑 ⚠️
- GPU acceleration for Ollama on RX 6500 via `ollama-for-amd` + `HSA_OVERRIDE_GFX_VERSION` or Vulkan. **Allowed to fail** — CPU path is the baseline.

## Phase 2 — Auth (Days 5–6)
- 🤖 Email-OTP via Plunk (generate → send → verify); key in local `.env`.
- 🤖 Face-recognition scaffolding: webcam capture, embedder integration, enroll + match.
- 🧑 ⚠️ Test face match on the real webcam; tune threshold; confirm OTP fallback path.
- 🤖 Gate app behind auth; log all attempts.

**Exit:** face login works with OTP fallback; every attempt logged.

## Phase 3 — Criminal pages, actions, logging everywhere (Days 6–8)
- 🤖 Criminal page UI: profile, media, records, case notes, attached news.
- 🤖 Log-on-view; upload/update flows (soft-delete only, history retained).
- 🤖 Assistant `createCaseNote` tool + **ActionGuard** (no record/image mutation tool exists for the LLM).
- 🤖 Logs view with chain-integrity indicator.

**Exit:** opening/editing anything is logged immutably; assistant can note but not alter.

## Phase 4 — Network / graph analysis (Days 8–10) — PS12 core
- 🤖 Entity extraction (NER / structured-LLM) over FIR/intel text.
- 🤖 Graph build (nodes/edges) + force-directed visualization.
- 🤖 Centrality (key individuals), community detection, anomaly flags.
- 🤖 "Explain this network" grounded narrative.

**Exit:** relationship graph with highlighted key individuals + flagged patterns.

## Phase 5 — News search + Image enhancement (Days 10–11)
- 🤖 News search + investigator attach-to-page (logged).
- 🤖 Real-ESRGAN + GFPGAN local on-demand enhancement; side-by-side + honest label.
- 🧑 ⚠️ Verify enhancement + LLM don't blow the 8GB budget together; if they do, offload enhancement to a LAN machine (config).

**Exit:** news attach + labeled image enhancement working.

## Phase 6 — Hardening, demo, submission (Days 12–13)
- 🧑 ⚠️ Full run-through on the real machine end-to-end.
- 🤖 Chain-integrity "verify logs" button (visible proof of tamper-evidence — a judging highlight).
- 🤖 Polish, empty/error states, demo script, submission write-up (blind-review safe if required).
- 🤖 `flutter build windows` → package installer/zip with setup steps (Ollama + model pull + `.env`).

**Exit:** packaged Windows build + rehearsed demo + submission.

---

## Critical Path
1. AuditLogger first (everything depends on it).
2. LLM+RAG core next (the headline "ChatGPT over the database").
3. Auth, pages, actions.
4. Graph analysis (PS12 core).
5. News + enhancement (most droppable).

## Risk Register
| Risk | Impact | Mitigation |
|---|---|---|
| ⚠️ 3B model weak/slow on 8GB+RX6500 | High | CPU baseline; LAN-fallback to stronger machine via config; RAG reduces reasoning load |
| ⚠️ RX6500 GPU (unofficial ROCm) won't accelerate | Medium | Treated as bonus; CPU is the plan |
| ⚠️ Face recognition flaky on webcam | Medium | OTP-via-Plunk fallback always available |
| ⚠️ Enhancement + LLM contend for 8GB | Medium | Run one heavy job at a time; offload enhancement to LAN box |
| ⚠️ Solo human bandwidth over 13 days | High | AI does all code/docs; human time reserved for 🧑 tasks; drop order below |

## Scope-Drop Order (if time runs short)
1. Image enhancement (first to go / offload)
2. News search
3. GPU acceleration (already optional)
4. Trim graph analytics to centrality-only
**Never dropped:** login, chat-over-DB (RAG), immutable logging, the assistant action-boundary.
