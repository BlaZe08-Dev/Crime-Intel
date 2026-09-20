# CrimeIntel — Installation & Quick Start Guide

CrimeIntel is an AI-powered criminal network analysis system for Linux desktop, featuring synthetic multi-source intelligence ingestion, retrieval-grounded LLM assistant (RAG), automatically derived relationship graph, and a tamper-evident cryptographic audit chain.

---

## Quick Start (Choose Your Distribution Format)

Pre-compiled packages require **no Flutter SDK**. Choose the format for your Linux distribution:

### Option 1: Debian / Ubuntu / Mint / Pop!_OS (`.deb`)

1. **Install the package:**
   ```bash
   sudo apt install ./crime-intel_1.0.0_amd64.deb
   ```
2. **Run the one-step setup script (once):**
   ```bash
   crime-intel-setup
   # or: bash /opt/crime-intel/setup.sh
   ```
   *Installs/checks Ollama and pulls required AI models (`granite4.1:3b` and `nomic-embed-text`).*
3. **Launch CrimeIntel:**
   Launch from your application menu or run `crime-intel`.
   *(Configuration is automatically created at `~/.config/crime-intel/.env`)*

---

### Option 2: Fedora / Arch / openSUSE / Any Linux (`.AppImage`)

1. **Download and make executable:**
   ```bash
   chmod +x CrimeIntel-1.0.0-x86_64.AppImage
   ```
2. **Run setup:**
   Download and run `setup.sh` once:
   ```bash
   chmod +x setup.sh && ./setup.sh
   ```
3. **Launch CrimeIntel:**
   ```bash
   ./CrimeIntel-1.0.0-x86_64.AppImage
   ```

---

### Option 3: Universal Portable Fallback (`.tar.gz`)

1. **Extract archive:**
   ```bash
   tar -xzf crime-intel-linux-x64-v1.0.0.tar.gz
   cd crime-intel-linux-x64-v1.0.0
   ```
2. **Run setup:**
   ```bash
   ./setup.sh
   ```
3. **Launch CrimeIntel:**
   ```bash
   ./crime_intel
   ```

---

## Configuring Authentication & Sync (`.env`)

CrimeIntel supports offline operation out-of-the-box. To customize settings, edit your `.env`:
- **For `.deb` and `AppImage`:** Located at `~/.config/crime-intel/.env`
- **For `.tar.gz`:** Located in the extracted folder alongside `crime_intel`

| Setting | Purpose |
|---|---|
| `SENDGRID_API_KEY` & `SENDGRID_FROM_EMAIL` | Real email OTP authentication (single verified sender). |
| `DEMO_MODE=true` | Displays generated 6-digit OTP codes directly on screen for testing without SendGrid. |
| `NEON_DATABASE_URL` | Neon PostgreSQL URI for multi-investigator central sync (leave blank for local SQLite). |
| `OLLAMA_BASE_URL` | Ollama service endpoint (default: `http://localhost:11434`). |

---

## Running from Source (Developer Workflow)

```bash
# 1. Install system build dependencies:
sudo apt install -y clang cmake ninja-build pkg-config libgtk-3-dev

# 2. Run one-step setup:
bash scripts/setup.sh

# 3. Launch from source:
flutter pub get
flutter run -d linux
```

---

## System Requirements

- **OS:** Linux x86_64 (Kernel 5.4+)
- **Memory:** 8 GB RAM minimum (16 GB recommended for local 3B LLM inference)
- **Storage:** ~3 GB free space for Ollama models (`granite4.1:3b` ~2.1 GB + `nomic-embed-text` ~274 MB)
