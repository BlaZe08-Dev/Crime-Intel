# CrimeIntel — Tracker

**Owner:** Team (single builder identity) · **Deadline:** 12 Sep
**Status:** ☐ todo · ◐ in progress · ☑ done · ⚠ at-risk
**Who:** 🤖 AI-assisted · 🧑 human-only

---

## Phase 0 — Foundation
| # | Task | Who | Status |
|---|---|---|---|
| 0.1 | Scaffold Flutter Windows project + modules | 🤖 | ☑ |
| 0.2 | SQLite + data models + synthetic ingestion | 🤖 | ☑ |
| 0.3 | Hash-chained AuditLogger | 🤖 | ☑ |
| 0.4 | `flutter build windows` runs on real machine | 🧑 | ☐ |

## Phase 1 — LLM + RAG core ⭐
| # | Task | Who | Status |
|---|---|---|---|
| 1.1 | ⚠ Install Ollama, pull 3B Q4, confirm CPU answers | 🧑 | ☐ |
| 1.2 | LlmClient interface + Ollama HTTP client (configurable URL) | 🤖 | ☐ |
| 1.3 | RAG: embed → vector store → retrieve → grounded prompt | 🤖 | ☐ |
| 1.4 | Chat UI + source-ID display + "not in DB" behavior | 🤖 | ☐ |
| 1.5 | ⚠ Measure latency; LAN-fallback if unusable | 🧑 | ☐ |
| 1.x | (Experimental) RX6500 GPU accel — allowed to fail | 🧑 | ☐ |

## Phase 2 — Auth
| # | Task | Who | Status |
|---|---|---|---|
| 2.1 | Email OTP via Plunk (send/verify), key in .env | 🤖 | ☐ |
| 2.2 | Face capture + embedder + enroll/match | 🤖 | ☐ |
| 2.3 | ⚠ Test face match on real webcam; tune threshold | 🧑 | ☐ |
| 2.4 | Gate app behind auth; log all attempts | 🤖 | ☐ |

## Phase 3 — Pages, actions, logging
| # | Task | Who | Status |
|---|---|---|---|
| 3.1 | Criminal page UI (profile/media/records/notes/news) | 🤖 | ☐ |
| 3.2 | Log-on-view + upload/update (soft-delete, history kept) | 🤖 | ☐ |
| 3.3 | Assistant createCaseNote tool + ActionGuard | 🤖 | ☐ |
| 3.4 | Logs view + chain-integrity indicator | 🤖 | ☐ |

## Phase 4 — Network / graph (PS12 core)
| # | Task | Who | Status |
|---|---|---|---|
| 4.1 | Entity extraction over FIR/intel | 🤖 | ☐ |
| 4.2 | Graph build + force-directed viz | 🤖 | ☐ |
| 4.3 | Centrality (key individuals) | 🤖 | ☐ |
| 4.4 | Community detection + anomaly flags | 🤖 | ☐ |
| 4.5 | "Explain this network" narrative | 🤖 | ☐ |

## Phase 5 — News + enhancement
| # | Task | Who | Status |
|---|---|---|---|
| 5.1 | News search + attach-to-page (logged) | 🤖 | ☐ |
| 5.2 | Real-ESRGAN + GFPGAN local enhancement + label | 🤖 | ☐ |
| 5.3 | ⚠ Verify 8GB budget; offload to LAN if needed | 🧑 | ☐ |

## Phase 6 — Hardening + submission
| # | Task | Who | Status |
|---|---|---|---|
| 6.1 | ⚠ Full end-to-end run on real machine | 🧑 | ☐ |
| 6.2 | "Verify logs" chain-integrity button | 🤖 | ☐ |
| 6.3 | Polish + demo script + write-up (blind-safe) | 🤖 | ☐ |
| 6.4 | flutter build windows → package + setup steps | 🤖 | ☐ |
| 6.5 | Final demo dry-run | 🧑 | ☐ |

---

## Milestones
- **M1 (Day 2):** Windows app loads synthetic data; logs chain.
- **M2 (Day 5):** ⭐ grounded chat-over-database working — *protected.*
- **M3 (Day 6):** face + OTP login.
- **M4 (Day 8):** immutable logging + assistant boundary complete.
- **M5 (Day 10):** relationship graph + key individuals.
- **M6 (Day 12–13):** packaged build + rehearsed demo.

## Blockers log
| Date | Blocker | Resolution |
|---|---|---|
| | | |

## Notes
- Criminals.md holds the synthetic dataset spec; teammates generate the images from its prompts.
- Any 🧑 slip = re-scope, don't cram. Keep M2 demo-ready after Day 5.
