# CrimeIntel — Product Requirements Document (PRD)

> AI-Powered Criminal Network Analysis System (Hackathon PS12)
> Platform: **Windows desktop app (Flutter)** · Deadline: **12 September** · Team: one builder identity + AI assist

---

## 1. Problem Statement

Criminal activity is organized, interconnected, and buried across fragmented sources — FIRs, call detail records (CDRs), financial transactions, surveillance notes, criminal history, intelligence reports. Investigators lose critical links because the data is unstructured, siloed, and manually reviewed.

CrimeIntel is a desktop tool for a private investigator that pulls this data together, lets the investigator **query it in natural language** (like ChatGPT over a criminal database), automatically **maps relationships and networks**, surfaces **key individuals and suspicious patterns**, and keeps a **tamper-proof audit trail** of everything anyone does inside it.

## 2. Target Users

- **Private investigators / analysts** working criminal cases who need to explore a criminal database quickly and defensibly.
- Secondary: anyone needing an auditable, single-analyst intelligence workspace.

## 3. Core Features

### Custom-requested features
1. **Secure login with face biometrics.** Investigator signs in via in-app face recognition (enrolled investigator photos, face-embedding match). Fallback: email one-time-passcode via Plunk.
2. **Chat-over-database (RAG).** After login, the investigator uses the platform like ChatGPT, asking questions answered strictly from the criminal database and the audit logs.
3. **News search + attach.** The assistant can search the web for related events; the investigator can attach a found article (link + image) into a criminal's page.
4. **Assistant actions (bounded).** The assistant can create case notes. It **cannot** add/remove images or alter criminal records — a hard boundary.
5. **Immutable, all-covering logs.** Viewing a record, uploads, updates, and deletions are all logged. Nothing can be deleted from the log. Deleted data is retained in the log.
6. **Image enhancement.** Blurry photo/crime-scene enhancement via local Real-ESRGAN + GFPGAN, labeled as an aid, not forensic proof.
7. **Synthetic criminal database.** 5–6 fully synthetic criminals with photos, crime-scene images, and related records (see Criminals.md).

### PS12-required features (folded in)
8. **Multi-source ingestion** — structured (CDR/financial/history) + unstructured (FIR/intel text).
9. **Entity extraction** — people, locations, vehicles, phone numbers, organizations.
10. **Relationship / network mapping** — a visual graph of how entities connect.
11. **Key-individual identification** — centrality analysis to surface likely leaders/hubs.
12. **Suspicious-pattern & anomaly detection** — unusual links, transaction bursts, clustering.
13. **Investigator insights** — visual + analytical dashboard, plus the LLM narrative.

## 4. Success Criteria

- Investigator logs in via face (or email-OTP fallback) reliably.
- Asks a natural-language question and gets an answer grounded in the synthetic DB, with the source records shown.
- Sees an auto-generated relationship graph for a criminal and the flagged key individuals.
- Every action they take appears in an append-only, tamper-evident log they cannot alter.
- Enhances a blurry image on demand.
- Creates a case note via the assistant; confirms the assistant cannot change a criminal record.

### Definition of Done (MVP)
Login → chat-over-DB with real retrieval → relationship graph + key-individual highlight → immutable logging of actions → image enhancement → assistant case-note creation, all working on a Windows build with the synthetic dataset.

## 5. Constraints & Principles

- **Windows desktop, Flutter.**
- **Local-first LLM** (Ollama 3B) — no hosted-API rate limits, no per-token cost. Internet used only for the news-search feature and the email-OTP send.
- **Synthetic data only.** No real person is depicted; no real case data.
- **Assistant is read-mostly** — grounded answers + case notes only; never mutates records.
- **Auditability is a first-class feature**, not an afterthought.

## 6. Out of Scope (this deadline)

- Real/live police data integration.
- Multi-user roles/permissions beyond the single investigator + assistant boundary.
- Mobile/web builds.
- True forensic identification claims from enhanced images.

## 7. Team & Timeline

- One human builder ("Team") + AI assist (Claude Code and other AI tools).
- Deadline 12 September; the second team submits the same day on a different PS.
- **Human-only gates:** Windows build/signing, face-recognition on real hardware/webcam, Ollama-on-AMD GPU enablement, on-machine performance under the 8GB limit. See ImplementationPlan.md.
