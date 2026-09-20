# CrimeIntel — Installation & Quick Start Guide

CrimeIntel is an AI-powered criminal network analysis system for Linux desktop, featuring a synthetic criminal dataset, retrieval-grounded chat assistant (RAG), automatically derived relationship graph, and a tamper-evident cryptographic audit chain.

---

## Quick Start (Pre-compiled Release Bundle)

If you downloaded the pre-compiled release archive (`crime-intel-linux-x64-v1.0.0.tar.gz`), **you do not need Flutter installed**.

### 1. Extract the release archive

```bash
tar -xzf crime-intel-linux-x64-v1.0.0.tar.gz
cd crime-intel-linux-x64-v1.0.0
```

### 2. Run the one-step setup script

The setup script verifies or installs Ollama and automatically pulls the required local AI models (`granite4.1:3b` and `nomic-embed-text`):

```bash
./setup.sh
```

> **Why model weights are fetched via script:**
> The `granite4.1:3b` model is ~2.1 GB, exceeding GitHub Release single-asset size limits. Running `./setup.sh` automates the local download on first run without requiring manual Ollama commands.

### 3. Configure `.env`

The setup script copies `.env.example` to `.env` if not already present. Open `.env` and configure your credentials:

```bash
nano .env   # or your preferred text editor
```

- **Authentication (Email OTP):**
  - Supply `SENDGRID_API_KEY` and a verified `SENDGRID_FROM_EMAIL`.
  - **OR** set `DEMO_MODE=true` to display the generated 6-digit OTP directly on screen (useful for offline or quick evaluations).
- **Multi-Investigator Central Sync (Optional):**
  - Leave `NEON_DATABASE_URL` blank to operate 100% offline with local SQLite.
  - Or paste a Neon PostgreSQL connection string to enable opportunistic sync across terminals.

### 4. Launch the application

```bash
./crime_intel
```

---

## Running from Source (Developer Workflow)

If you cloned the source repository:

### 1. Install prerequisites

Install the Flutter SDK (>= 3.19.0) and Linux desktop development headers:

```bash
# Ubuntu / Debian:
sudo apt update && sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev
```

Confirm Flutter is working:
```bash
flutter doctor
```

### 2. Run environment setup

```bash
bash scripts/setup.sh
```

### 3. Fetch dependencies and launch

```bash
flutter pub get
flutter run -d linux
```

---

## Useful Configuration Reference (.env)

| Key | Default | Purpose |
|---|---|---|
| `OLLAMA_BASE_URL` | `http://localhost:11434` | Point to a remote host/LAN if offloading AI inference |
| `OLLAMA_MODEL` | `granite4.1:3b` | Chat and question-answering LLM (~2.1 GB, Apache-2.0) |
| `OLLAMA_EMBED_MODEL` | `nomic-embed-text` | Embedding model for semantic vector search (~274 MB) |
| `SENDGRID_API_KEY` | *(blank)* | SendGrid API key for single-sender OTP emails |
| `SENDGRID_FROM_EMAIL` | *(blank)* | Single-sender verified sender email address |
| `DEMO_MODE` | `false` | When `true`, displays OTP code directly in UI for testing |
| `NEON_DATABASE_URL` | *(blank)* | Neon PostgreSQL connection URI for multi-station sync |

---

## System Requirements

- **Operating System:** Linux x86_64 (Ubuntu 20.04+, Debian 11+, Fedora 36+, Arch Linux)
- **RAM:** 8 GB minimum (16 GB recommended for Ollama model inference)
- **Disk:** ~3 GB free space for Ollama models
- **Graphics:** NVIDIA GPU with CUDA supported for hardware acceleration (CPU fallback is automatic)
