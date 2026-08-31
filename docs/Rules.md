# CrimeIntel — Rules & Conventions

Rules for any contributor (human or AI agent). Tool-agnostic.

---

## 1. Non-Negotiable Product Constraints
1. **Assistant never mutates records.** The LLM has exactly one action tool: `createCaseNote`. No tool to add/edit/delete criminal records or images may ever be exposed to it.
2. **Logs are append-only and immutable.** No code path deletes a `LogEntry`. "Deleting" data is a soft-delete + a logged event; prior state is retained.
3. **Everything is logged.** Logins, views, uploads, updates, deletes, case notes, enhancements, news attachments, LLM queries — all through the hash-chained AuditLogger.
4. **Answers are grounded.** The assistant answers only from retrieved DB/log context and says so when nothing is found. No invented facts, no answers from model priors dressed as data.
5. **Synthetic data only.** No real person depicted; media flagged `isSynthetic`.
6. **Enhanced images are labeled** as reconstructed visualizations, never as forensic evidence.

## 2. LLM / Cost / Hosting Rules
7. **Local-first LLM (Ollama), no hosted API** in the default path — protects against rate limits and per-token cost.
8. LLM access goes through the `LlmClient` interface with a **configurable base URL**, so switching to a LAN machine is config, not code.
9. Never assume the RX6500 GPU works — **CPU is the baseline**; GPU accel is optional and isolated.

## 3. Architecture Rules
10. Respect module boundaries (`auth/`, `llm/`, `rag/`, `enhance/`, `graph/`, `audit/`, `ingest/`, `news/`, `ui/`); cross-module calls via interfaces.
11. The **ActionGuard** is the single chokepoint for assistant actions — no assistant action bypasses it.
12. All data mutation flows through services that log; never write to SQLite records/media without an audit entry.
13. Image enhancement and the LLM must not both hold large memory at once (8GB budget) — run one heavy job at a time.

## 4. Security / Privacy Rules
14. Secrets (Plunk API key, any keys) live in a local `.env`, git-ignored, never committed.
15. Face embeddings stored locally only; never exported, never logged in raw form.
16. News search is the only default outbound network call besides OTP email; nothing else phones home.

## 5. Coding Standards
17. Follow Flutter/Dart conventions; keep heavy work (LLM, embedding, enhancement, graph) off the UI isolate.
18. Every dependency: record name + license + purpose in TechSpec.
19. No hardcoded secrets or machine-specific paths.

## 6. Testing / Hardware Rules
20. **Not "done" until it runs on the real 8GB machine.** LLM latency, face match, enhancement, and Windows build are hardware-gated (🧑).
21. Record real measured numbers; never claim performance not measured on-device.
22. Keep the M2 chat-over-DB demo runnable at all times after Day 5.

## 7. Git / Workflow Rules
23. Small, focused commits; `main` stays buildable.
24. Update Tracker.md status when a task changes state.
25. If a decision changes, update the matching doc in the same change.

## 8. Scope-Discipline Rules
26. Drop scope in fixed order: image enhancement → news → GPU accel → trim graph analytics. **Never** drop login, RAG chat, immutable logging, or the assistant boundary.

## 9. Submission Rules
27. If blind review applies, the write-up/video must not reveal team/institute identity — verify the exact rule first.
28. Demo must be reproducible from repo + documented setup (Ollama install, model pull, `.env`, synthetic data load).
