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
- **Model: `granite4.1:3b`** — IBM Granite 4.1 3B, Apache-2.0, ~2.1 GB. Chosen over Llama 3.2 3B / Qwen 2.5 3B because it is built for RAG grounding *and* native tool-calling, which the assistant action boundary depends on. Tool-calling verified working against this model.
- **Embeddings: `nomic-embed-text`** — 274 MB, 768 dimensions.
- **Swappable interface (`LlmClient`)** — base URL is config (`OLLAMA_BASE_URL`). Escape hatch: point at a stronger machine on the LAN. No code change, no hosted-API rate limits. `OllamaClient` is the only implementation that speaks HTTP; nothing outside `llm/` may call a model directly.
- **Endpoints:** `/api/chat` (with `tools`), `/api/embed` (batched) falling back to `/api/embeddings` on older servers, `/api/tags` for health.
- **GPU:** the current dev machine has an RTX 3050, so CUDA works without the AMD/ROCm workarounds this plan originally assumed. Measured on it: ~59 s cold (model load), ~4.3 s warm for a short tool-calling prompt.

### 2.3 RAG — `rag/`
- **This is retrieval, not training.** No model is fine-tuned anywhere in the app. Granite stays frozen; records are embedded once and pasted into a prompt at query time.
- On ingest, records + log entries are chunked and embedded into the **`vector_chunks` table** using `nomic-embed-text`.
- **Vector search runs in Dart** (`VectorMath.cosineSimilarity`), not sqlite-vec. sqlite-vec would mean loading a platform-specific native extension into `sqflite_common_ffi` and shipping that DLL with the Windows build — a packaging risk for a demo that must run from a zip. The corpus is ~100 chunks, where a linear scan of 768-dim vectors costs well under a millisecond, so an index buys nothing. Swap `VectorMath.rank` for an ANN index behind the same call if the corpus ever reaches thousands of chunks.
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
- **The graph is derived, never seeded.** `entities` and `edges` are rebuilt from the records on startup. Hand-authored graph constants were removed from `seed_data.dart` — a fixture presented as analysis is worse than no analysis.
- **Entity extraction:** gazetteer-plus-pattern NER (the "spaCy-style" option) over FIR/intel text → people (names + aliases, matched on word boundaries), phones, vehicle registrations, organisations, locations. Chosen over LLM structured extraction because it is deterministic and still works when Ollama is down; the model is used for the *narrative*, not the topology.
- **Graph build:** entities = nodes; edges derived from CDR (via phone-ownership resolution), financial transactions (counterparty resolved by name), and co-mentions in text. Every edge carries `evidenceIds` — the record ids that justify it.
- **Key individuals:** PageRank (primary ranking) + Brandes betweenness, over people only.
- **Communities & anomalies:** label propagation for communities (chosen over Louvain: a few dozen lines, no modularity bookkeeping, adequate at this scale). Anomaly rules are statistical and id-agnostic — a transaction is an outlier at ≥3× its own payer→payee 25th-percentile baseline, and several outliers inside 14 days are a burst. The 25th percentile rather than the median because when half a pair's transactions *are* the anomaly, the median hides it.
- **Visualization:** Fruchterman–Reingold force-directed widget, seeded deterministically so the layout is stable across runs.

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

### 3.1 How the boundary is enforced in code

Four independent things must all fail for the assistant to mutate a record:

1. **The advertised tool set has one member.** `ActionGuard.exposedTools` is what is sent to the model as its `tools` array. There is no `updateRecord` for it to name.
2. **Dispatch is allow-listed.** `ActionGuard.dispatch` compares against `caseNoteToolName` and refuses everything else, so a hallucinated tool name fails closed. Refusals are written to the audit chain.
3. **The guard cannot reach a mutation API.** Its dependency is typed `CaseNoteSink` — an interface with exactly one method. `CrimeRepository.updateCriminal` / `softDeleteCriminal` / `addMedia` / `attachNews` are not on that interface.
4. **It has no investigator privilege to borrow.** Those mutations require an `InvestigatorContext`; the guard holds only `AssistantContext`, so such a call would not compile.

### 3.2 Actor attribution

`AuditLogger.log` takes an `ActorContext`, not a `LogActor` enum, and reads the actor off the context's runtime type. A caller cannot name itself. `InvestigatorContext` is minted only by `AuthSessionIssuer.issue`, which is the single place investigator privilege is created.

## 4. Tech Stack

| Layer | Choice | Notes |
|---|---|---|
| UI / app | Flutter (Windows desktop) | one codebase, native window |
| LLM runtime | Ollama · `granite4.1:3b` | local, free, no rate limits, tool-calling |
| RAG store | SQLite `vector_chunks` + in-Dart cosine | offline, no native extension |
| Embeddings | `nomic-embed-text` (768-dim) | offline |
| Face auth | webcam + ONNX face embedder (ArcFace/FaceNet-style) | **not built yet** |
| OTP email | Plunk transactional email | **not built yet**; key in local `.env` |
| Image enhance | Real-ESRGAN + GFPGAN/CodeFormer | **not built yet** |
| Graph/NLP | gazetteer NER + PageRank/betweenness/label-propagation, pure Dart | no Python side-process |
| News | web search API / light fetch | **not built yet** |
| Typography | Inter + Outfit bundled in `assets/fonts` | OFL-1.1; **not** the `google_fonts` package, which downloads at runtime |

### 4.1 Runtime dependencies (Rules §18)

| Package | Licence | Purpose |
|---|---|---|
| `sqflite_common_ffi` | BSD-2 | SQLite on Windows desktop via FFI |
| `sqflite_common` | BSD-2 | SQLite API surface |
| `path` / `path_provider` | BSD-3 | Database file location |
| `crypto` | BSD-3 | SHA-256 for the audit chain |
| `uuid` | BSD-3 | Record identifiers |
| `intl` | BSD-3 | Date and number formatting |
| `http` | BSD-3 | Ollama transport (localhost by default) |

Removed: `google_fonts` (fetched fonts over HTTP at launch, breaking Rules §16) and `flutter_dotenv` (`.env` is now read from disk beside the executable, which is the right shape for a packaged desktop app and keeps secrets out of the asset bundle). `flutter_animate` was declared but never imported.

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
