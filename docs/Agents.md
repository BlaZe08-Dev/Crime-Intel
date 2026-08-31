# CrimeIntel — Agents Guide

For AI coding agents (Claude Code now; general for others later). Read this, PRD.md, TechSpec.md, and Rules.md before changing anything.

---

## 1. What this is
A Flutter **Windows desktop** app: an investigator logs in (face + email-OTP fallback), chats over a **synthetic criminal database** via a **local LLM (Ollama 3B) with RAG**, sees **relationship graphs / key individuals / anomalies**, enhances blurry images locally, and works under a **hash-chained immutable audit log**. The assistant can create case notes but can never alter records.

## 2. Read-first order
1. `PRD.md` — what & why
2. `TechSpec.md` — how, stack, the action-boundary and log design
3. `Rules.md` — hard constraints
4. `Schema.md` — data + the hash-chain log
5. `ImplementationPlan.md` + `Tracker.md` — status & next task
6. `Criminals.md` — the synthetic dataset spec

## 3. Hard rules for agents (do not violate)
- **Never give the assistant/LLM a tool that edits records or images.** Its only action is `createCaseNote`. If a task implies otherwise, stop and flag it.
- **Never add a log-deletion path.** Logs are append-only, hash-chained. Soft-delete + log instead.
- **Keep answers grounded.** RAG retrieves; the model answers only from retrieved context and says "not in the database" otherwise. Don't let it answer from priors.
- **Local LLM only by default.** No hosted-API calls in the default path (rate-limit/cost reasons). Access via the `LlmClient` interface with a configurable base URL.
- **Don't assume the RX6500 GPU works.** CPU is the baseline; GPU accel is an isolated, optional, experimental task.
- **Respect the 8GB budget.** Don't hold the LLM and image enhancement in memory simultaneously.
- **Synthetic data only; enhanced images labeled as non-forensic.**

## 4. Division of labor (one human + AI)
**You (agent) can:** scaffold, write Dart/Flutter code, build the RAG pipeline, the hash-chain logger, the ActionGuard, graph/NLP logic, UI, the Plunk OTP flow, docs, demo script.

**You cannot (hand to human, 🧑):** run the Windows build on the real machine, install/run Ollama on the 8GB/RX6500 box, test the webcam face match, do the GPU-accel wrangling, measure real latency/memory, judge whether enhancement quality is acceptable by eye. Never fabricate these results — mark the task 🧑 and hand over a precise checklist.

## 5. Working a task
1. Find it in `Tracker.md`; check dependencies in `ImplementationPlan.md`.
2. Smallest change that completes it; keep `main` buildable.
3. Route all data mutations through logging services; never bypass AuditLogger or ActionGuard.
4. If a decision shifted, update the matching doc in the same change.
5. Update the task status.
6. If it needs hardware, convert to a 🧑 checklist and stop.

## 6. When unsure — ask, don't guess
The human's style: **clarifying questions before building; decisions locked before execution.** Offer concrete options (MCQ for quick calls). Don't assume model choices, storage details, or flows.

## 7. Credential / setup steps
When the human must do setup (Plunk key, Ollama install, model pull, `.env`), write **plain-language, numbered, ordered steps**.

## 8. Definition of done (agent task)
- Compiles; `main` builds.
- Matches Schema + module boundaries.
- Every mutation logged; assistant boundary intact.
- Hardware validation handed off as a 🧑 checklist, not faked.
