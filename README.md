# CrimeIntel

AI-powered criminal-network analysis for a single investigator. A Flutter
Linux desktop app with a synthetic criminal database, a retrieval-grounded chat
assistant, an automatically derived relationship graph, and a tamper-evident
audit log.

See `docs/` for the PRD, tech spec, schema, flows and rules.

---

## Screenshots

<table>
<tr>
<td width="50%"><img src="docs/screenshots/login.png" alt="Investigator sign-in"></td>
<td width="50%"><img src="docs/screenshots/dashboard.png" alt="Investigator Workspace dashboard"></td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/assistant.png" alt="Assistant"></td>
<td width="50%"><img src="docs/screenshots/network.png" alt="Network analysis"></td>
</tr>
<tr>
<td width="50%"><img src="docs/screenshots/audit-log.png" alt="Immutable audit trail"></td>
<td width="50%"><img src="docs/screenshots/criminal-detail.png" alt="Criminal detail record"></td>
</tr>
</table>

---

## How to run

1. Install the current stable [Flutter SDK for Linux desktop](https://docs.flutter.dev/get-started/install/linux/desktop)
   and its Linux desktop development dependencies. Confirm the Linux toolchain
   is available:

```
flutter --version
flutter doctor
```

   The project was last verified with Flutter **3.47.4** / Dart **3.13.3**.

2. Clone the repository and enter it:

```
git clone https://github.com/BlaZe08-Dev/Crime-Intel.git
cd Crime-Intel
```

3. Create your local configuration. `.env` is ignored by Git; never commit a
   SendGrid key. Add a SendGrid API key and verified single sender email to receive OTP emails, or temporarily set
   `DEMO_MODE=true` only for a labelled local demo fallback:

```
cp .env.example .env
```

4. Install [Ollama](https://ollama.com/) for Linux and start its local service.
   Do not run `ollama pull`: CrimeIntel verifies and downloads its required
   models (~2.5 GB) automatically on first launch, with live progress and a
   retry option. The app needs network access for that first launch.

```
curl -fsSL https://ollama.com/install.sh | sh
ollama serve                     # only when your system service is not running
```

   Ollama serves on `http://localhost:11434`. The app also contacts SendGrid when
   sending a real email OTP.

5. Fetch dependencies and launch the Linux desktop app:

```
flutter pub get
flutter run -d linux
```

   On first launch, the app seeds the synthetic dataset and derives the network
   graph. In **Assistant**, use **Build index** once to embed records for chat.

6. Optional local checks:

```
flutter test        # unit + integration tests; no model server needed
flutter analyze
```

### Packaged Linux releases

The Debian/Ubuntu `.deb` installs Ollama during package configuration, so it
requires network access at install time. It does not bundle or pull models.
On first launch, CrimeIntel downloads the required ~2.5 GB of models with a
visible progress screen. AppImage and tarball users run `scripts/setup.sh` to
install Ollama; that script also leaves model downloads to first launch.

### Configuration reference

The useful `.env` keys are:

| Key | Default | Why you would change it |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Point at another machine on the LAN to offload inference |
| `OLLAMA_MODEL` | `granite4.1:3b` | Swap the chat model |
| `RAG_TOP_K` | `6` | How many records ground each answer |
| `RAG_MIN_SCORE` | `0.35` | Relevance floor; below it the assistant refuses to answer |
| `SENDGRID_API_KEY` | *(blank)* | OTP email through SendGrid API |
| `SENDGRID_FROM_EMAIL` | *(blank)* | Verified single sender email address for SendGrid OTP emails |
| `NEON_DATABASE_URL` | *(blank)* | Neon (PostgreSQL) connection string for opportunistic multi-investigator sync |
| `DEMO_MODE` | `false` | When `true`, show the registration OTP in the app instead of emailing it |

`.env` is git-ignored and read from disk (next to the executable in a packaged
build), never bundled into the app.

### Central Neon Sync Setup (Multi-Investigator)

CrimeIntel operates 100% offline out-of-the-box using local SQLite. To enable cross-investigator synchronization:

1. Create a free PostgreSQL database on [Neon](https://neon.tech/).
2. Copy the connection string (with pooled or direct endpoint, e.g. `postgresql://user:pass@ep-xyz.neon.tech/neondb?sslmode=require`).
3. Set `NEON_DATABASE_URL` in your local `.env`.
4. Launch the app. The app automatically provisions the required tables (`shared_criminals`, `shared_case_notes`, `shared_media_items`, `shared_text_records`, and `central_audit_log`).
5. **Sync behavior:** Sync is automatic and opportunistic whenever network connectivity is detected. A manual affordance is also available by clicking the cloud sync badge in the bottom of the navigation rail.
6. **Two-Chain Audit Log:** Each workstation maintains its own local tamper-evident chain. Synced entries append into the central Neon chain in strict arrival order, recording both local and server timestamps.
7. **Anonymized Attribution:** Contributions from peer investigators can be queried via RAG and search, but personal investigator identities are never revealed across terminals.

---

## What is real, and what is not

The project is mid-build. This is the honest state:

**Built and verified**
- Hash-chained, append-only audit log with chain verification
- SQLite store + synthetic dataset from `docs/Criminals.md`
- Email-OTP registration and subsequent password login via SendGrid on the Linux target
- Local LLM interface via Ollama behind a swappable `LlmClient`
- RAG: embed → retrieve → grounded answer with cited record ids (automated coverage)
- Assistant action boundary (`createCaseNote` only), enforced structurally
- Derived entity graph: extraction, edge derivation, PageRank/betweenness,
  communities, statistical anomaly detection, force-directed visualisation

**Built, pending target-machine confirmation**
- Media upload UI and its audit path
- The graph-screen **Explain this network** narrative against a live Ollama server
- Interactive launch of the freshly built Linux release bundle

**Intentional future work (not silent gaps)**
- Face recognition / webcam authentication — email OTP is the supported
  hackathon auth path. If SendGrid delivery fails or `DEMO_MODE=true`, the app
  clearly displays the generated code and records the non-emailed fallback.
- News search and attachment UI — only the documented repository/audit seam is retained.
- Image enhancement (Real-ESRGAN / GFPGAN) — only the documented disclaimer seam is retained.

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
