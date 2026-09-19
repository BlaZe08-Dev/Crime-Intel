# CrimeIntel — Product Requirements Document (PRD)

> AI-Powered Criminal Network Analysis System (Hackathon PS12)
> Platform: **Linux desktop app (Flutter)** · Deadline: **20 September 2026** · Team: one builder identity + AI assist

---

## 1. Problem Statement

Criminal activity is organized, interconnected, and buried across fragmented sources — FIRs, call detail records (CDRs), financial transactions, surveillance notes, criminal history, intelligence reports. Investigators lose critical links because the data is unstructured, siloed, and manually reviewed.

CrimeIntel is a Linux desktop tool for a private investigator that brings this
synthetic data together, supports **natural-language queries** over retrieved
records, derives **relationships and networks**, surfaces **key individuals and
suspicious patterns**, and records supported in-app actions in a
tamper-evident audit trail. Current verification boundaries are tracked in
`Tracker.md`.

## 2. Target Users

- **Private investigators / analysts** working criminal cases who need to explore a criminal database quickly and defensibly.
- Secondary: anyone needing an auditable, single-analyst intelligence workspace.

## 3. Core Features

### Custom-requested features
1. **Secure login with email OTP.** Investigator registers through a one-time passcode delivered by Resend. Face recognition is documented future work and is not part of the hackathon build.
2. **Chat-over-database (RAG).** The investigator uses the platform like ChatGPT, asking questions answered strictly from the criminal database and the audit logs.
3. **News search + attach (future work).** The documented repository/audit seam is retained, but no news search or attachment UI ships for this deadline.
4. **Assistant actions (bounded).** The assistant can create case notes. It **cannot** add/remove images or alter criminal records — a hard boundary.
5. **Immutable audit logs.** Supported record views, updates, deletions, case-note
   creation, auth events, and the implemented media-upload path are logged in
   a hash chain. Deleted data is retained in the audit history; unbuilt features
   do not emit fictional events.
6. **Image enhancement (future work).** The documented disclaimer seam is retained, but Real-ESRGAN/GFPGAN is not shipping for this deadline.
7. **Synthetic criminal database.** 5–6 fully synthetic criminals with photos, crime-scene images, and related records (see Criminals.md).

### PS12-required features (folded in)
8. **Multi-source ingestion** — structured (CDR/financial/history) + unstructured (FIR/intel text).
9. **Entity extraction** — people, locations, vehicles, phone numbers, organizations.
10. **Relationship / network mapping** — a visual graph of how entities connect.
11. **Key-individual identification** — centrality analysis to surface likely leaders/hubs.
12. **Suspicious-pattern & anomaly detection** — unusual links, transaction bursts, clustering.
13. **Investigator insights** — visual + analytical dashboard. The LLM network
    narrative is implemented but awaits live-Ollama verification on the target machine.

## 4. Success Criteria

These are acceptance targets; `Tracker.md` records which have been verified.

- Investigator registers via email OTP reliably with a configured Resend key.
- Asks a natural-language question and gets an answer grounded in the synthetic DB, with the source records shown.
- Sees an auto-generated relationship graph for a criminal and the flagged key individuals.
- Every supported action appears in an append-only, tamper-evident log they cannot alter.
- Creates a case note via the assistant; confirms the assistant cannot change a criminal record.

### Definition of Done (MVP)
Email-OTP login → chat-over-DB with real retrieval → relationship graph +
key-individual highlight → immutable logging of supported actions → investigator
media upload → assistant case-note creation, all verified on a Linux build with
the synthetic dataset. Media-upload and live-Ollama verification remain open at
the time of this document update.

## 5. Constraints & Principles

- **Linux desktop, Flutter.**
- **Local-first LLM** (Ollama 3B) — no hosted-API rate limits or per-token cost.
  Network access is needed for email-OTP delivery; news search is future work.
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
- **Admin/Oversight De-anonymization View (Explicit Assumption):** Contributing investigators are recorded in the central Neon audit log for accountability, but no de-anonymization screen is shipped in this pass. Cross-investigator views remain strictly anonymized.
- **Real-time Push Notifications & Merge Conflict Resolution UI:** Synchronization is periodic/opportunistic and conflicts follow last-synced-wins; interactive conflict merge screens and live push notifications are out of scope.

---

## 7. Scope Addition: Offline-First Sync to Central Neon Database (19 September 2026)

### 7.1 Objective & Context
Multiple field investigators work cases independently in disconnected or spotty network conditions. Investigators must be able to add criminal profiles, evidence notes, and media locally without network dependency. When network access is regained, pending additions push to a **central Neon (PostgreSQL) database**, and new contributions by peer investigators are pulled down into the local SQLite store.

### 7.2 The Two-Chain Audit Model
The existing audit log is an immutable SHA-256 linear hash chain (`SHA256(seq|actor|action|targetType|targetId|payloadHash|ts|prevHash)`). Multiple offline devices cannot independently append to a single shared linear chain without breaking cryptographic integrity upon interleaving.
- **Local Per-Device Chain:** Continues to be written on the local device, guaranteeing local tamper-evidence offline.
- **Canonical Central Chain (Neon):** Maintained centrally on Neon. Pending entries arriving from devices are appended in **arrival order** at the server (not local creation order). Neon assigns the canonical sequence and hash. Each entry records both the original local timestamp (`local_ts`) and the server arrival timestamp (`server_ts`).
- **Both chains are valid and distinct.**

### 7.3 Anonymized Attribution Guarantee
- When RAG or search queries surface information contributed by another investigator, the UI and AI assistant cite only the entity/record ID (e.g., `[C-001]`, `[NOTE-003]`), **never** the contributing investigator's identity.
- True attribution is preserved in that investigator's local chain and in the central Neon audit log for administrative accountability, but is never exposed across investigators in the application layer.
- **Assumption:** No admin/oversight de-anonymization UI is built for this pass.

### 7.4 Non-Degraded Offline Experience
Local SQLite, local RAG vector search, local graph analysis, and local audit verification continue to function with zero network access. Neon sync is opportunistic and non-blocking.

---

## 8. Team & Timeline

- One human builder ("Team") + AI assist (Claude Code and other AI tools).
- Deadline 24 September 2026.
- **Remaining human-only gates:** interactive launch of the fresh Linux release
  bundle, media upload on the target machine, live-Ollama responses (including
  the network narrative), and end-to-end latency measurement. Face recognition
  is deliberately descoped; GPU acceleration is experimental rather than a
  delivery gate. See `Tracker.md`.
