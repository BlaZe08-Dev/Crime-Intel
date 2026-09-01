# CrimeIntel — Tracker

**Owner:** Team (single builder identity) · **Deadline:** 12 Sep
**Status:** ☐ todo · ◐ in progress · ☑ done · ⚠ at-risk
**Who:** 🤖 AI-assisted · 🧑 human-only

> **Status discipline:** a task is ☑ only when the code exists, runs, and is
> covered by a test or a measurement someone actually took. "Scaffolded",
> "modelled", or "the table exists" is ◐.

---

## Phase 0 — Foundation
| # | Task | Who | Status |
|---|---|---|---|
| 0.1 | Scaffold Flutter Windows project + modules | 🤖 | ☑ |
| 0.2 | SQLite + data models + synthetic ingestion | 🤖 | ☑ |
| 0.3 | Hash-chained AuditLogger | 🤖 | ☑ |
| 0.4 | ⚠ `flutter build windows` runs on real machine | 🧑 | ☐ |

- 0.1 — `windows/` runner generated; `flutter analyze` and `flutter test` run
  clean. Modules now match TechSpec §2: `llm/`, `rag/`, `graph/`, `assistant/`,
  `data/repositories/` all contain working code, not just models.
- 0.4 — **Blocked on Visual Studio.** Windows Flutter builds need the MSVC
  toolchain ("Desktop development with C++"), which is not installed. Nothing
  else can proceed to a launched app until it is.

## Phase 1 — LLM + RAG core ⭐
| # | Task | Who | Status |
|---|---|---|---|
| 1.1 | Install Ollama, pull model, confirm it answers | 🧑 | ☑ |
| 1.2 | LlmClient interface + Ollama HTTP client (configurable URL) | 🤖 | ☑ |
| 1.3 | RAG: embed → vector store → retrieve → grounded prompt | 🤖 | ☑ |
| 1.4 | Chat UI + source-ID display + "not in DB" behaviour | 🤖 | ☑ |
| 1.5 | ⚠ Measure end-to-end latency on the real machine | 🧑 | ◐ |
| 1.x | (Experimental) GPU acceleration | 🧑 | ☐ |

- 1.1 — Ollama 0.33.2 installed via winget. `granite4.1:3b` (2.1 GB) and
  `nomic-embed-text` (274 MB, 768-dim) pulled and verified responding.
- 1.5 — Measured directly against the Ollama API on this machine: **59 s cold**
  (first call, model load included), **4.3 s warm** for a short tool-calling
  prompt. Full retrieve→answer latency inside the app still needs measuring
  once the app launches (blocked by 0.4).
- 1.x — Machine has an RTX 3050, so CUDA works without the AMD/ROCm
  workarounds the plan assumed. Not yet confirmed in-app.

## Phase 2 — Auth
| # | Task | Who | Status |
|---|---|---|---|
| 2.1 | Email OTP via Plunk (send/verify), key in .env | 🤖 | ☐ |
| 2.2 | Face capture + embedder + enroll/match | 🤖 | ☐ |
| 2.3 | ⚠ Test face match on real webcam; tune threshold | 🧑 | ☐ |
| 2.4 | Gate app behind auth; log all attempts | 🤖 | ☐ |

- Not started. The app currently runs as the seeded investigator and
  **deliberately does not write a `LOGIN_OK` entry**, because nobody logged in.
  Startup records a `SYSTEM` entry saying the session was unauthenticated, so
  the gap is visible in the audit trail rather than hidden by it.
- The seam is in place: `AuthSessionIssuer.issue` is the single mint point for
  investigator privilege. Wiring auth means calling it after a successful match
  instead of at boot.

## Phase 3 — Pages, actions, logging
| # | Task | Who | Status |
|---|---|---|---|
| 3.1 | Criminal page UI (profile/media/records/notes/news) | 🤖 | ◐ |
| 3.2 | Log-on-view + upload/update (soft-delete, history kept) | 🤖 | ◐ |
| 3.3 | Assistant createCaseNote tool + ActionGuard | 🤖 | ☑ |
| 3.4 | Logs view + chain-integrity indicator | 🤖 | ☑ |

- 3.1 — Profile, media, FIR/intel, CDR, financial, history and case notes are
  all rendered. The **news** section is absent because the news feature does
  not exist yet (Phase 5).
- 3.2 — `VIEW_RECORD`, `UPDATE` and `DELETE` (soft, prior state hashed into the
  chain) are wired and tested. Media **upload has a repository method and audit
  entry but no UI**, so an investigator cannot yet upload from the app.

## Phase 4 — Network / graph (PS12 core)
| # | Task | Who | Status |
|---|---|---|---|
| 4.1 | Entity extraction over FIR/intel | 🤖 | ☑ |
| 4.2 | Graph build + force-directed viz | 🤖 | ☑ |
| 4.3 | Centrality (key individuals) | 🤖 | ☑ |
| 4.4 | Community detection + anomaly flags | 🤖 | ☑ |
| 4.5 | "Explain this network" narrative | 🤖 | ☐ |

- The graph is **derived**, not seeded. The hand-authored `entities` and
  `edges` constants were deleted from `seed_data.dart`; `GraphService` now
  extracts entities from the FIR/intel text and derives edges from CDR,
  financial and co-mention records, with `evidenceIds` on every edge.
- 4.3 — PageRank + Brandes betweenness. The hub badge is computed; a test
  proves it moves to a different subject when the data changes.
- 4.4 — Label propagation for communities; the C-004→C-001 burst is found by a
  percentile-baseline outlier rule that has no knowledge of those ids.
- 4.5 — Not built. The chat can answer graph questions from indexed records,
  but there is no dedicated "explain this network" action.

## Phase 5 — News + enhancement
| # | Task | Who | Status |
|---|---|---|---|
| 5.1 | News search + attach-to-page (logged) | 🤖 | ☐ |
| 5.2 | Real-ESRGAN + GFPGAN local enhancement + label | 🤖 | ☐ |
| 5.3 | ⚠ Verify 8GB budget; offload to LAN if needed | 🧑 | ☐ |

- Neither built. `ATTACH_NEWS` has a repository method and audit entry ready;
  `ENHANCE_IMAGE` has neither, only the disclaimer constant.
- 5.3 — The target machine is now 16 GB, not 8 GB, so the contention risk the
  plan was written around is much reduced.

## Phase 6 — Hardening + submission
| # | Task | Who | Status |
|---|---|---|---|
| 6.1 | ⚠ Full end-to-end run on real machine | 🧑 | ☐ |
| 6.2 | "Verify logs" chain-integrity button | 🤖 | ☑ |
| 6.3 | Polish + demo script + write-up (blind-safe) | 🤖 | ☐ |
| 6.4 | `flutter build windows` → package + setup steps | 🤖 | ☐ |
| 6.5 | Final demo dry-run | 🧑 | ☐ |

---

## Logging coverage (Rules §3)

| Action | Wired | Where |
|---|---|---|
| `UPLOAD` | ☑ | seeding, index rebuild, `addMedia` |
| `DELETE` | ☑ | `CrimeRepository.softDeleteCriminal` |
| `CREATE_CASENOTE` | ☑ | `CrimeRepository.writeCaseNote` |
| `VIEW_RECORD` | ☑ | `CrimeRepository.openCriminalRecord` |
| `UPDATE` | ☑ | `CrimeRepository.updateCriminal` |
| `LLM_QUERY` | ☑ | `AssistantService`, plus ActionGuard refusals |
| `ATTACH_NEWS` | ◐ | repository method ready; no news feature to call it |
| `LOGIN_OK` / `LOGIN_FAIL` / `OTP_SENT` / `OTP_OK` | ☐ | needs Phase 2 auth |
| `ENHANCE_IMAGE` | ☐ | needs Phase 5 enhancement |

The four unwired actions have no feature behind them yet. Emitting them now
would mean logging events that never happened, which is worse than the gap.

## Milestones
- **M1 (Day 2):** ☑ synthetic data loads; chain verifies.
- **M2 (Day 5):** ⭐ ◐ grounded chat is built and unit-tested against a fake
  model; **not yet seen running against Granite in the app** (blocked by 0.4).
- **M3 (Day 6):** ☐ face + OTP login.
- **M4 (Day 8):** ◐ assistant boundary complete and tested; logging covers
  everything that has a feature.
- **M5 (Day 10):** ☑ relationship graph + computed key individuals.
- **M6 (Day 12–13):** ☐ packaged build + rehearsed demo.

## Blockers log
| Date | Blocker | Resolution |
|---|---|---|
| 2026-09-01 | Visual Studio with "Desktop development with C++" not installed; `flutter run/build -d windows` cannot compile | 🧑 Owner installing VS 2022 Community with that workload |
| 2026-09-01 | `google_fonts` fetched fonts over HTTP at launch, breaking Rules §16 | Resolved: Inter + Outfit bundled in `assets/fonts`, package removed |
| 2026-09-01 | Graph, hub badge and entity counts were hand-authored constants presented as analysis | Resolved: derived by `GraphService`; seed constants deleted |

## Notes
- Criminals.md holds the synthetic dataset spec; teammates replace the
  placeholder images in `assets/synthetic/` with generated ones.
- `reference-repo/` is no longer tracked by git (still on disk).
