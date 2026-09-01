# CrimeIntel

AI-powered criminal network analysis for a single investigator. Flutter Windows
desktop app, fully local: a synthetic criminal database, a chat assistant that
answers **only** from retrieved records, an automatically derived relationship
graph, and a tamper-evident audit log.

See `docs/` for the PRD, tech spec, schema, flows and rules.

---

## Setup

### 1. Flutter SDK

```
# Download the current stable Windows SDK and unzip it, e.g. to %USERPROFILE%\dev\flutter
# https://docs.flutter.dev/get-started/install/windows/desktop
setx PATH "%PATH%;%USERPROFILE%\dev\flutter\bin"
flutter --version
```

Built against Flutter **3.47.2** / Dart **3.13.2**.

### 2. Visual Studio (required for Windows builds)

`flutter run -d windows` needs the MSVC toolchain. Install **Visual Studio 2022
Community** with the **"Desktop development with C++"** workload. Confirm with:

```
flutter doctor
```

The line `[√] Visual Studio - develop Windows apps` must be green. Without it
the app cannot compile — this is the only hard prerequisite that is not a
download away.

### 3. Ollama and the models

```
winget install Ollama.Ollama
ollama pull granite4.1:3b       # chat / answers  (~2.1 GB, Apache-2.0)
ollama pull nomic-embed-text    # embeddings      (~274 MB, 768-dim)
ollama list                     # both should appear
```

Ollama serves on `http://localhost:11434`. Nothing else is contacted at
runtime.

### 4. Configuration

```
copy .env.example .env
```

Everything has a working default, so the app runs without editing it. The keys
that matter:

| Key | Default | Why you would change it |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Point at another machine on the LAN to offload inference |
| `OLLAMA_MODEL` | `granite4.1:3b` | Swap the chat model |
| `RAG_TOP_K` | `6` | How many records ground each answer |
| `RAG_MIN_SCORE` | `0.35` | Relevance floor; below it the assistant refuses to answer |
| `PLUNK_API_KEY` | *(blank)* | OTP email, once auth lands |

`.env` is git-ignored and read from disk (next to the executable in a packaged
build), never bundled into the app.

### 5. Run

```
flutter pub get
flutter run -d windows
```

First launch seeds the synthetic dataset and derives the network graph. Open
**Assistant → Build index** once to embed the records for chat; it takes a few
seconds and persists.

```
flutter test        # unit + integration tests, no model server needed
flutter analyze
```

---

## What is real, and what is not

The project is mid-build. This is the honest state:

**Working**
- Hash-chained, append-only audit log with chain verification
- SQLite store + synthetic dataset from `docs/Criminals.md`
- Local LLM via Ollama behind a swappable `LlmClient`
- RAG: embed → retrieve → grounded answer with cited record ids
- Assistant action boundary (`createCaseNote` only), enforced structurally
- Derived entity graph: extraction, edge derivation, PageRank/betweenness,
  communities, statistical anomaly detection, force-directed visualisation

**Not built yet**
- Face-recognition login and the Plunk email-OTP fallback — the app currently
  runs as the seeded investigator and records that the session was
  unauthenticated rather than faking a login
- News search and attach
- Image enhancement (Real-ESRGAN / GFPGAN)

`docs/Tracker.md` has the task-level detail, including which log actions are
wired and which are waiting on a feature.

---

## Notes

- **Synthetic data only.** Every person, record and image is invented. The
  images in `assets/synthetic/` are labelled placeholders until teammates
  generate real synthetic ones per `docs/Criminals.md`.
- **No training.** The model is never fine-tuned. Retrieval only.
- **`reference-repo/`** holds upstream Real-ESRGAN / GFPGAN / CodeFormer
  checkouts for reference. It is git-ignored; nothing in `lib/` imports it.
