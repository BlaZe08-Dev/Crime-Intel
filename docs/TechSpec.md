# CrimeIntel — Technical Specification (TechSpec)

Platform: **Flutter (Windows desktop)** · Target machine baseline: **8GB RAM, AMD RX 6500 (4GB, unofficial ROCm)** — plan assumes CPU inference works; GPU is a bonus.

---

## 1. High-Level Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Flutter Windows UI                         │
│  Login(Face/OTP) · Chat · Criminal Pages · Graph · Logs ·     │
│  Image Enhancer · Case Notes                                  │
├─────────────────────────────────────────────────────────────┤
│                     App / Domain Layer                        │
│  AuthService · AssistantOrchestrator · ActionGuard ·          │
│  AuditLogger(hash-chained) · IngestionService · GraphService  │
├───────────┬───────────┬────────────┬───────────┬─────────────┤
│  Auth      │  LLM       │  RAG       │  Enhance  │  Graph/NLP   │
│  Face embed│  Ollama    │  Vector DB │  Real-    │  entity ext  │
│  + Plunk   │  (3B Q4,   │  + record  │  ESRGAN   │  + centrality│
│  email OTP │  swappable)│  store     │  + GFPGAN │  + anomaly   │
├───────────┴───────────┴────────────┴───────────┴─────────────┤
│  Local Storage: SQLite (records+logs) · Vector index · Files  │
└─────────────────────────────────────────────────────────────┘
```

**Golden rule enforced in code:** the LLM reaches data only through a retrieval layer and can act only through a whitelisted `createCaseNote` tool. It has no path to mutate criminal records or images (see §7 ActionGuard).

## 2. Modules

### 2.1 Auth — `auth/`
- **Primary: custom face recognition.** Capture from webcam → face detector → face-embedding model (e.g. an ONNX ArcFace/FaceNet-style embedder) → cosine-match against enrolled investigator embeddings stored locally. Threshold-gated.
- **Fallback: email OTP via Plunk.** Generate a 6-digit code → send through Plunk's transactional email API → verify. Plunk API key lives in a local `.env` (never in repo).
- Note: this is a *custom* matcher (matches faces we enrolled), deliberately **not** Windows Hello (which only checks the OS user and can't be forced face-only on Windows).
- Session gated behind successful auth; every login attempt (success/fail/OTP) is logged.

### 2.2 LLM — `llm/`
- **Runtime: Ollama**, local HTTP server on `localhost:11434`. Flutter talks to it over HTTP.
- **Model: 3B Q4_K_M** — Llama 3.2 3B (default) or Qwen 2.5 3B. Chosen to fit the 8GB/4GB-VRAM machine; CPU-first.
- **Swappable interface (`LlmClient`)** — base URL is config. Escape hatch: point at a stronger teammate's machine on the LAN if the 3B underperforms. No code change, no hosted-API rate limits.
- **GPU:** RX 6500 acceleration via community `ollama-for-amd` + `HSA_OVERRIDE_GFX_VERSION` or Vulkan — **experimental, allowed to fail**, marked 🧑.

### 2.3 RAG — `rag/`
- On ingest, records + log entries are chunked and embedded into a **local vector store** (e.g. sqlite-vec / a local FAISS-style index) using a small local embedding model.
- Query flow: user question → retrieve top-k relevant records/logs → build a grounded prompt (retrieved context + cit­ation IDs) → LLM answers **only** from retrieved context → answer shown with the source record IDs.
- Refuses / says "not in the database" when retrieval returns nothing relevant (no hallucinated facts).

### 2.4 News Search — `news/`
- On-demand web search (a search API or scrape-light fetch) triggered when the investigator asks for related events.
- Results shown as candidates; the investigator explicitly chooses to **attach** an article (title, link, optional image) into a criminal's page.
- Attaching is an investigator action (logged); the assistant proposes, the human commits.

### 2.5 Image Enhancement — `enhance/`
- **Real-ESRGAN** (general upscaling/deblur) + **GFPGAN/CodeFormer** (face restoration) run as a local on-demand process (Python side-process invoked by the app, or bundled executable).
- One image at a time, not resident in memory (protects the 8GB budget).
- Output always labeled: *"AI-enhanced visualization — reconstructed detail, not forensic evidence."*
- Config flag to run enhancement on a separate machine if the demo box is tight.

### 2.6 Graph / Network Analysis — `graph/`
- **Entity extraction:** NER (spaCy-style, or the local LLM in a structured-extraction prompt) over FIR/intel text → people, locations, vehicles, phones, orgs.
- **Graph build:** entities = nodes, co-occurrence/CDR/financial links = edges, stored in SQLite and loaded into an in-memory graph (a Dart graph lib or a small Python analysis side-process).
- **Key individuals:** betweenness / PageRank centrality.
- **Communities & anomalies:** Louvain/Leiden clustering; simple anomaly rules (unusual edges, transaction bursts).
- **Visualization:** force-directed graph widget in Flutter; geographic view for location entities.

### 2.7 Audit Logger — `audit/`
- **Append-only, hash-chained.** Each entry stores: actor, action, target, timestamp, payload hash, and `prevHash`. `entryHash = H(entry fields + prevHash)`. Any tampering breaks the chain and is detectable.
- Covers: logins, record views, uploads, updates, deletions (the *deletion event and the deleted content reference* are retained), case-note creation, image enhancements, news attachments, LLM queries.
- No delete path exists in code for log rows. "Delete data" = mark record deleted + log it; the log entry and prior state remain.

### 2.8 Ingestion — `ingest/`
- Loads the synthetic dataset (Criminals.md-derived records + images) into SQLite on first run.
- Supports investigator **upload/update** of records and images (logged); no hard delete of history.

## 3. Assistant Action Boundary (critical)

- The assistant is given exactly one tool: `createCaseNote(criminalId, text)`.
- It has **no** tool to edit/add/delete records or images. Even if prompted to, it cannot — the capability does not exist in its tool set.
- All record/image mutation happens only through explicit investigator UI actions, each logged.

## 4. Tech Stack

| Layer | Choice | Notes |
|---|---|---|
| UI / app | Flutter (Windows desktop) | one codebase, native window |
| LLM runtime | Ollama (3B Q4, swappable) | local, free, no rate limits |
| RAG store | SQLite + local vector index (sqlite-vec/FAISS-style) | offline |
| Embeddings | small local embedding model | offline |
| Face auth | webcam + ONNX face embedder (ArcFace/FaceNet-style) | custom matcher |
| OTP email | Plunk transactional email | key in local .env |
| Image enhance | Real-ESRGAN + GFPGAN/CodeFormer | local, on-demand |
| Graph/NLP | NER + centrality/community (Dart lib or Python side-process) | — |
| News | web search API / light fetch | on-demand only |

## 5. Performance Budget (8GB machine)

- Only one heavy workload resident at a time: LLM chat **or** image enhancement, not both simultaneously.
- 3B Q4 model ~2–3GB working set; keep the app lean; enhancement spawned per-image then released.
- If contention appears in testing → offload enhancement (and/or the LLM) to a LAN machine via config. 🧑 to validate on hardware.

## 6. Build & Release

- Enable desktop: `flutter config --enable-windows-desktop`
- Run: `flutter run -d windows`
- Build: `flutter build windows` → `build/windows/x64/runner/Release/`
- Package the folder (and any bundled enhancement/Ollama-setup helper) into an installer/zip for teammates.

## 7. Security / Privacy

- Face embeddings + Plunk key + any secrets stored locally, never committed.
- Synthetic data only; nothing real leaves the machine except opt-in news queries.
- Hash-chained logs make the audit trail defensible — a headline feature for judging.
