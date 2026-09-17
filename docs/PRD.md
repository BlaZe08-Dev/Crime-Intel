# CrimeIntel — Product Requirements Document (PRD)

> AI-Powered Criminal Network Analysis System (Hackathon PS12)
> Platform: **Linux desktop app (Flutter)** · Deadline: **20 September 2026** · Team: one builder identity + AI assist

---

## 1. Problem Statement

Criminal activity is organized, interconnected, and buried across fragmented sources — FIRs, call detail records (CDRs), financial transactions, surveillance notes, criminal history, intelligence reports. Investigators lose critical links because the data is unstructured, siloed, and manually reviewed.

CrimeIntel is a desktop tool for a private investigator that pulls this data together, lets the investigator **query it in natural language** (like ChatGPT over a criminal database), automatically **maps relationships and networks**, surfaces **key individuals and suspicious patterns**, and keeps a **tamper-proof audit trail** of everything anyone does inside it.

## 2. Target Users

- **Private investigators / analysts** working criminal cases who need to explore a criminal database quickly and defensibly.
- Secondary: anyone needing an auditable, single-analyst intelligence workspace.

## 3. Core Features

### Custom-requested features
1. **Secure login with email OTP.** Investigator registers through a one-time passcode delivered by Resend. Face recognition is documented future work and is not part of the hackathon build.
2. **Chat-over-database (RAG).** The investigator uses the platform like ChatGPT, asking questions answered strictly from the criminal database and the audit logs.
3. **News search + attach (future work).** The documented repository/audit seam is retained, but no news search or attachment UI ships for this deadline.
4. **Assistant actions (bounded).** The assistant can create case notes. It **cannot** add/remove images or alter criminal records — a hard boundary.
5. **Immutable, all-covering logs.** Viewing a record, uploads, updates, and deletions are all logged. Nothing can be deleted from the log. Deleted data is retained in the log.
6. **Image enhancement (future work).** The documented disclaimer seam is retained, but Real-ESRGAN/GFPGAN is not shipping for this deadline.
7. **Synthetic criminal database.** 5–6 fully synthetic criminals with photos, crime-scene images, and related records (see Criminals.md).

### PS12-required features (folded in)
8. **Multi-source ingestion** — structured (CDR/financial/history) + unstructured (FIR/intel text).
9. **Entity extraction** — people, locations, vehicles, phone numbers, organizations.
10. **Relationship / network mapping** — a visual graph of how entities connect.
11. **Key-individual identification** — centrality analysis to surface likely leaders/hubs.
12. **Suspicious-pattern & anomaly detection** — unusual links, transaction bursts, clustering.
13. **Investigator insights** — visual + analytical dashboard, plus the LLM narrative.

## 4. Success Criteria

- Investigator registers via email OTP reliably with a configured Resend key.
- Asks a natural-language question and gets an answer grounded in the synthetic DB, with the source records shown.
- Sees an auto-generated relationship graph for a criminal and the flagged key individuals.
- Every action they take appears in an append-only, tamper-evident log they cannot alter.
- Creates a case note via the assistant; confirms the assistant cannot change a criminal record.

### Definition of Done (MVP)
Email-OTP login → chat-over-DB with real retrieval → relationship graph + key-individual highlight → immutable logging of actions → investigator media upload → assistant case-note creation, all working on a Linux build with the synthetic dataset.

## 5. Constraints & Principles

- **Linux desktop, Flutter.**
- **Local-first LLM** (Ollama 3B) — no hosted-API rate limits, no per-token cost. Internet used only for the news-search feature and the email-OTP send.
- **Synthetic data only.** No real person is depicted; no real case data.
- **Assistant is read-mostly** — grounded answers + case notes only; never mutates records.
- **Auditability is a first-class feature**, not an afterthought.

## 6. Out of Scope (this deadline)

- Real/live police data integration.
- Multi-user roles/permissions beyond the single investigator + assistant boundary.
- Mobile/web builds.
- True forensic identification claims from enhanced images.
- Face recognition / webcam capture / face-embedding authentication — descoped for the hackathon deadline; the OTP seam remains the supported auth path.
- News search and attachment UI — descoped for the hackathon deadline; the documented `ATTACH_NEWS` repository/audit seam remains for future work.
- Image enhancement (Real-ESRGAN/GFPGAN) — descoped for the hackathon deadline; the enhancement disclaimer seam remains for future work.
- Registration is intentionally open for this hackathon build: any address that receives an OTP can enroll. A production version would restrict enrollment to a vetted allowlist.
- **Demo-mode OTP fallback:** when `DEMO_MODE=true`, or Resend delivery fails, the generated OTP is displayed in the registration UI and the audit entry is marked `demo fallback, not emailed`. This keeps a deadline demo usable but is not appropriate for production authentication.

## 7. Team & Timeline

- One human builder ("Team") + AI assist (Claude Code and other AI tools).
- Deadline 12 September; the second team submits the same day on a different PS.
- **Human-only gates:** Linux build/package validation on the real target machine, face-recognition on real hardware/webcam, Ollama-on-AMD GPU enablement, on-machine performance under the 8GB limit. See ImplementationPlan.md.
