# CrimeIntel — Tracker

**Owner:** Team (single builder identity) · **Deadline:** 20 Sep 2026
**Status:** ☐ todo · ◐ in progress · ☑ done · ⚠ at-risk
**Who:** 🤖 AI-assisted · 🧑 human-only

> **Status discipline:** a task is ☑ only when the code exists, runs, and is
> covered by a test or a measurement someone actually took. "Scaffolded",
> "modelled", or "the table exists" is ◐.

---

## Phase 0 — Foundation
| # | Task | Who | Status |
|---|---|---|---|
| 0.1 | Scaffold Flutter Linux project + modules | 🤖 | ☑ |
| 0.2 | SQLite + data models + synthetic ingestion | 🤖 | ☑ |
| 0.3 | Hash-chained AuditLogger | 🤖 | ☑ |
| 0.4 | Linux desktop debug build and launch verification | 🤖 | ☑ |

- 0.1 — Linux runner generated; `flutter analyze` and `flutter test` run
  clean. Modules now match TechSpec §2: `llm/`, `rag/`, `graph/`, `assistant/`,
  `data/repositories/` all contain working code, not just models.
- 0.4 — **Verified 2026-09-16 on Linux:** GTK development headers, Clang,
  CMake, Ninja and pkg-config are installed; `flutter analyze` reported no
  issues; `flutter test` passed **57** tests (one `live` Ollama test skipped);
  and `flutter run -d linux` built `build/linux/x64/debug/bundle/crime_intel`,
  launched it, and exposed a local Dart VM service. This is a debug launch,
  not a signed/package-release validation.

## Phase 1 — LLM + RAG core ⭐
| # | Task | Who | Status |
|---|---|---|---|
| 1.1 | Install Ollama, pull model, confirm it answers | 🧑 | ☑ |
| 1.2 | LlmClient interface + Ollama HTTP client (configurable URL) | 🤖 | ☑ |
| 1.3 | RAG: embed → vector store → retrieve → grounded prompt | 🤖 | ☑ |
| 1.4 | Chat UI + source-ID display + "not in DB" behaviour | 🤖 | ☑ |
| 1.5 | ⚠ Measure end-to-end latency on the real machine | 🧑 | ◐ |
| 1.x | (Experimental) GPU acceleration | 🧑 | ☐ |

- 1.1 — Ollama 0.33.2 installed. `granite4.1:3b` (2.1 GB) and
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
| 2.1 | Email OTP via Resend (send/verify), key in .env | 🤖 | ☑ |
| 2.2 | Face capture + embedder + enroll/match (descoped) | 🤖 | ☐ |
| 2.3 | ⚠ Test face match on real webcam; tune threshold (descoped) | 🧑 | ☐ |
| 2.4 | Gate app behind auth; log all attempts | 🤖 | ☑ |

- A registration/login gate is implemented in source: email → Resend 6-digit,
  one-minute OTP → mandatory strong-password creation; later sessions require
  the stored salted, iterated password hash. `AuthSessionIssuer.issue` remains
  the single mint point and logs `LOGIN_OK` only after successful sign-in.
- `OTP_SENT`, `OTP_OK`, and `LOGIN_FAIL` are audit logged. The developer-owned
  `RESEND_API_KEY` is a local `.env` setting only. Resend's test sender can
  deliver to the Resend account owner's address without a verified domain.
- **Verified end-to-end on the real Linux target machine:** registration,
  Resend OTP delivery and verification, password setup, and a subsequent
  login all completed successfully. On any delivery failure, or with
  `DEMO_MODE=true`, the UI shows the code and logs `demo fallback, not emailed`.
  The auth flow is also covered by the automated test suite.
- Face recognition is descoped for the hackathon deadline. OTP-only login is
  the intended auth path; the face seam remains documented future work.

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
  entry plus a new file-picker UI and integration-style test in source. It is
  still ◐: **code complete, pending verification on the target Linux machine.**

## Phase 4 — Network / graph (PS12 core)
| # | Task | Who | Status |
|---|---|---|---|
| 4.1 | Entity extraction over FIR/intel | 🤖 | ☑ |
| 4.2 | Graph build + force-directed viz | 🤖 | ☑ |
| 4.3 | Centrality (key individuals) | 🤖 | ☑ |
| 4.4 | Community detection + anomaly flags | 🤖 | ☑ |
| 4.5 | "Explain this network" narrative | 🤖 | ◐ |

- The graph is **derived**, not seeded. The hand-authored `entities` and
  `edges` constants were deleted from `seed_data.dart`; `GraphService` now
  extracts entities from the FIR/intel text and derives edges from CDR,
  financial and co-mention records, with `evidenceIds` on every edge.
- 4.3 — PageRank + Brandes betweenness. The hub badge is computed; a test
  proves it moves to a different subject when the data changes.
- 4.4 — Label propagation for communities; the C-004→C-001 burst is found by a
  percentile-baseline outlier rule that has no knowledge of those ids.
- 4.5 — A dedicated graph-screen action now routes its canned request through
  `AssistantService`/RAG and renders source IDs. It has test coverage in
  source has executable Linux desktop coverage through the verified app launch;
  its live Ollama response remains unverified because no Ollama server was
  configured for this run.

## Phase 5 — News + enhancement
| # | Task | Who | Status |
|---|---|---|---|
| 5.1 | News search + attach-to-page (logged, descoped) | 🤖 | ☐ |
| 5.2 | Real-ESRGAN + GFPGAN local enhancement + label (descoped) | 🤖 | ☐ |
| 5.3 | ⚠ Verify 8GB budget; offload to LAN if needed | 🧑 | ☐ |

- Neither built. `ATTACH_NEWS` has a repository method and audit entry ready;
  `ENHANCE_IMAGE` has neither, only the disclaimer constant.
- News search and image enhancement are descoped for the hackathon deadline;
  their existing documented seams are deliberately retained as future work.
- 5.3 — The target machine is now 16 GB, not 8 GB, so the contention risk the
  plan was written around is much reduced.

## Phase 6 — Hardening + submission
| # | Task | Who | Status |
|---|---|---|---|
| 6.1 | ⚠ Full end-to-end run on real machine | 🧑 | ☐ |
| 6.2 | "Verify logs" chain-integrity button | 🤖 | ☑ |
| 6.3 | Polish + demo script + write-up (blind-safe) | 🤖 | ☐ |
| 6.4 | `flutter build linux` → package + setup steps | 🤖 | ◐ |
| 6.5 | Final demo dry-run | 🧑 | ☐ |

- 6.4 — **Release build verified 2026-09-19:** `flutter build linux --release`
  exited 0 and produced
  `build/linux/x64/release/bundle/crime_intel` (with `lib/libapp.so`). This is
  a freshly built release bundle, not the debug artifact. The sandbox cannot
  access the host X display (`Gtk-WARNING: cannot open display: :0.0`), so an
  interactive launch of this release bundle still needs confirmation on the
  target desktop before this item can be marked ☑.

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
| `LOGIN_OK` / `LOGIN_FAIL` / `OTP_SENT` / `OTP_OK` | ◐ | auth flow in source; awaiting executable tests |
| `ENHANCE_IMAGE` | ☐ | needs Phase 5 enhancement |

The four unwired actions have no feature behind them yet. Emitting them now
would mean logging events that never happened, which is worse than the gap.

## Milestones
- **M1 (Day 2):** ☑ synthetic data loads; chain verifies.
- **M2 (Day 5):** ⭐ ◐ grounded chat is built and unit-tested against a fake
  model; **not yet seen running against Granite in the app** because no live
  Ollama server was configured for the verified Linux launch.
- **M3 (Day 6):** ☐ face + OTP login.
- **M4 (Day 8):** ◐ assistant boundary complete and tested; logging covers
  everything that has a feature.
- **M5 (Day 10):** ☑ relationship graph + computed key individuals.
- **M6 (Day 12–13):** ☐ packaged build + rehearsed demo.

## Blockers log
| Date | Blocker | Resolution |
|---|---|---|
| 2026-09-16 | Snap launcher could not run in the sandbox | Resolved for verification by invoking the installed Flutter SDK directly; Linux runner verification recorded in Phase 0 |
| 2026-09-01 | `google_fonts` fetched fonts over HTTP at launch, breaking Rules §16 | Resolved: Inter + Outfit bundled in `assets/fonts`, package removed |
| 2026-09-01 | Graph, hub badge and entity counts were hand-authored constants presented as analysis | Resolved: derived by `GraphService`; seed constants deleted |

## Notes
- Criminals.md holds the synthetic dataset spec; teammates replace the
  placeholder images in `assets/synthetic/` with generated ones.
- `reference-repo/` is no longer tracked by git (still on disk).
