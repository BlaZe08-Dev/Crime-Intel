#!/usr/bin/env bash
# ==============================================================================
# CrimeIntel — Automated One-Step Environment Setup
# ==============================================================================
# Sets up prerequisites for running CrimeIntel on Linux:
#   1. Detects or installs Ollama (via official install script)
#   2. Verifies Ollama service daemon is active
#   3. Leaves model downloads to the first app launch (with visible progress)
#   4. Checks for Flutter SDK (with non-blocking guidance for binary users)
#   5. Initializes local .env from .env.example
# ==============================================================================

set -uo pipefail

# ANSI color codes
if [ -t 1 ]; then
  BOLD='\033[1m'
  RED='\033[0;31m'
  GREEN='\033[0;32m'
  YELLOW='\033[0;33m'
  BLUE='\033[0;34m'
  CYAN='\033[0;36m'
  RESET='\033[0m'
else
  BOLD=''
  RED=''
  GREEN=''
  YELLOW=''
  BLUE=''
  CYAN=''
  RESET=''
fi

echo -e "${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}   CrimeIntel — One-Step Environment Setup           ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}"
echo ""

# Determine directory paths
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ "$(basename "$SCRIPT_DIR")" = "scripts" ]; then
  ROOT_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"
else
  ROOT_DIR="$SCRIPT_DIR"
fi

# Tracking statuses
STATUS_OLLAMA_CLI="UNKNOWN"
STATUS_OLLAMA_SRV="UNKNOWN"
STATUS_FLUTTER="UNKNOWN"
STATUS_ENV="UNKNOWN"
WARNINGS=0
ERRORS=0

# ------------------------------------------------------------------------------
# 1. Ollama Installation Check
# ------------------------------------------------------------------------------
echo -e "${BOLD}[1/5] Checking Ollama installation...${RESET}"

if command -v ollama >/dev/null 2>&1; then
  OLLAMA_VER="$(ollama --version 2>/dev/null || echo "installed")"
  echo -e "  ${GREEN}✓${RESET} Ollama found: ${OLLAMA_VER}"
  STATUS_OLLAMA_CLI="Installed (${OLLAMA_VER})"
else
  echo -e "  ${YELLOW}!${RESET} Ollama is not installed. Installing via official installer (https://ollama.com/install.sh)..."
  if command -v curl >/dev/null 2>&1; then
    if curl -fsSL https://ollama.com/install.sh | sh; then
      OLLAMA_VER="$(ollama --version 2>/dev/null || echo "installed")"
      echo -e "  ${GREEN}✓${RESET} Ollama installed successfully: ${OLLAMA_VER}"
      STATUS_OLLAMA_CLI="Installed (${OLLAMA_VER})"
    else
      echo -e "  ${RED}✗${RESET} Failed to install Ollama automatically."
      echo -e "    Please install manually: curl -fsSL https://ollama.com/install.sh | sh"
      STATUS_OLLAMA_CLI="FAILED (Installation error)"
      ((ERRORS++))
    fi
  else
    echo -e "  ${RED}✗${RESET} 'curl' command is required to download Ollama."
    STATUS_OLLAMA_CLI="FAILED (curl missing)"
    ((ERRORS++))
  fi
fi

# ------------------------------------------------------------------------------
# 2. Ollama Service / Daemon Check
# ------------------------------------------------------------------------------
echo -e "${BOLD}[2/5] Verifying Ollama service daemon...${RESET}"

is_ollama_responding() {
  curl -s -m 3 http://localhost:11434/api/version >/dev/null 2>&1
}

if is_ollama_responding; then
  echo -e "  ${GREEN}✓${RESET} Ollama service is active on http://localhost:11434"
  STATUS_OLLAMA_SRV="Active (port 11434)"
elif command -v ollama >/dev/null 2>&1; then
  echo -e "  ${YELLOW}!${RESET} Ollama service not responding. Attempting to start service..."
  
  # Try systemd service first if available
  if command -v systemctl >/dev/null 2>&1 && systemctl list-unit-files ollama.service >/dev/null 2>&1; then
    sudo systemctl start ollama 2>/dev/null || true
  fi

  # Poll for up to 6 seconds
  WAIT_COUNT=0
  while [ $WAIT_COUNT -lt 6 ]; do
    if is_ollama_responding; then
      break
    fi
    sleep 1
    ((WAIT_COUNT++))
  done

  # If still not responding, launch background process
  if ! is_ollama_responding; then
    echo -e "  ${YELLOW}→${RESET} Launching local 'ollama serve' in background..."
    nohup ollama serve >/tmp/ollama_serve.log 2>&1 &
    sleep 3
  fi

  if is_ollama_responding; then
    echo -e "  ${GREEN}✓${RESET} Ollama service is now active on http://localhost:11434"
    STATUS_OLLAMA_SRV="Active (started)"
  else
    echo -e "  ${RED}✗${RESET} Could not contact Ollama service on http://localhost:11434"
    echo -e "    Run 'ollama serve' in another terminal window, or check 'systemctl status ollama'."
    STATUS_OLLAMA_SRV="Offline (start with 'ollama serve')"
    ((ERRORS++))
  fi
else
  STATUS_OLLAMA_SRV="Skipped (Ollama not installed)"
fi

# ------------------------------------------------------------------------------
# 3. AI model download notice
# ------------------------------------------------------------------------------
echo -e "${BOLD}[3/5] AI model download${RESET}"
echo -e "  ${BLUE}ℹ${RESET} No models are downloaded by setup.sh."
echo -e "    CrimeIntel downloads its required ~2.5 GB of models automatically"
echo -e "    on first launch, with live progress and retry support."

# ------------------------------------------------------------------------------
# 4. Flutter SDK Check (Non-blocking)
# ------------------------------------------------------------------------------
echo -e "${BOLD}[4/5] Checking Flutter development environment...${RESET}"

if command -v flutter >/dev/null 2>&1; then
  FLUTTER_VERSION_INFO="$(flutter --version 2>/dev/null | head -n 1 || echo "Flutter detected")"
  echo -e "  ${GREEN}✓${RESET} Flutter SDK detected: ${FLUTTER_VERSION_INFO}"
  STATUS_FLUTTER="Detected (${FLUTTER_VERSION_INFO})"
else
  echo -e "  ${BLUE}ℹ${RESET} Flutter SDK was not found on PATH."
  echo -e "    • If you are running the ${BOLD}pre-compiled binary (./crime_intel)${RESET}, Flutter is ${GREEN}NOT required${RESET}."
  echo -e "    • If you plan to build or develop from source ('flutter run'), install Flutter:"
  echo -e "      Guide: https://docs.flutter.dev/get-started/install/linux/desktop"
  echo -e "      Linux build deps: sudo apt install clang cmake ninja-build pkg-config libgtk-3-dev"
  STATUS_FLUTTER="Not installed (Only needed for source builds)"
fi

# ------------------------------------------------------------------------------
# 5. Environment Configuration (.env)
# ------------------------------------------------------------------------------
echo -e "${BOLD}[5/5] Checking environment configuration (.env)...${RESET}"

ENV_FILE="$ROOT_DIR/.env"
ENV_EXAMPLE="$ROOT_DIR/.env.example"

if [ -f "$ENV_FILE" ]; then
  echo -e "  ${GREEN}✓${RESET} Local .env file exists at ${ENV_FILE}"
  STATUS_ENV="Found existing .env"
elif [ -f "$ENV_EXAMPLE" ]; then
  echo -e "  ${YELLOW}!${RESET} .env not found. Copying from .env.example..."
  cp "$ENV_EXAMPLE" "$ENV_FILE"
  echo -e "  ${GREEN}✓${RESET} Created ${ENV_FILE}"
  STATUS_ENV="Created from .env.example"
else
  echo -e "  ${RED}✗${RESET} Neither .env nor .env.example found in ${ROOT_DIR}."
  STATUS_ENV="Missing (.env not found)"
  ((WARNINGS++))
fi

# Check optional settings in .env
if [ -f "$ENV_FILE" ]; then
  SENDGRID_SET=false
  NEON_SET=false
  DEMO_SET=false

  if grep -E "^SENDGRID_API_KEY=[a-zA-Z0-9_-]+" "$ENV_FILE" >/dev/null 2>&1; then
    SENDGRID_SET=true
  fi
  if grep -E "^NEON_DATABASE_URL=postgresql://" "$ENV_FILE" >/dev/null 2>&1; then
    NEON_SET=true
  fi
  if grep -E "^DEMO_MODE=true" "$ENV_FILE" >/dev/null 2>&1; then
    DEMO_SET=true
  fi

  if [ "$SENDGRID_SET" = false ] && [ "$DEMO_SET" = false ]; then
    echo -e "  ${YELLOW}Notice:${RESET} SENDGRID_API_KEY is not set in .env."
    echo -e "         To log in, either add SendGrid credentials to .env or set DEMO_MODE=true for local OTP display."
  fi
  if [ "$NEON_SET" = true ]; then
    echo -e "  ${GREEN}✓${RESET} Central Neon PostgreSQL synchronization is configured."
  else
    echo -e "  ${BLUE}ℹ${RESET} Central Neon sync not configured (app operates in 100% offline SQLite mode)."
  fi
fi

# ------------------------------------------------------------------------------
# Final Status Summary
# ------------------------------------------------------------------------------
echo ""
echo -e "${BOLD}${CYAN}======================================================${RESET}"
echo -e "${BOLD}${CYAN}                  Setup Summary                       ${RESET}"
echo -e "${BOLD}${CYAN}======================================================${RESET}"
printf " %-26s : %s\n" "Ollama CLI" "$STATUS_OLLAMA_CLI"
printf " %-26s : %s\n" "Ollama Service" "$STATUS_OLLAMA_SRV"
printf " %-26s : %s\n" "Flutter Environment" "$STATUS_FLUTTER"
printf " %-26s : %s\n" "Configuration (.env)" "$STATUS_ENV"
echo -e "${CYAN}------------------------------------------------------${RESET}"

if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}${BOLD}✓ Environment is ready to run CrimeIntel!${RESET}\n"
  
  if [ -x "$ROOT_DIR/crime_intel" ]; then
    echo -e "To launch the pre-compiled application:"
    echo -e "  ${BOLD}cd \"$ROOT_DIR\" && ./crime_intel${RESET}"
  elif command -v flutter >/dev/null 2>&1; then
    echo -e "To run from source:"
    echo -e "  ${BOLD}cd \"$ROOT_DIR\" && flutter run -d linux${RESET}"
  fi
  echo ""
  exit 0
else
  echo -e "${RED}${BOLD}✗ Setup encountered $ERRORS error(s). Please review messages above.${RESET}\n"
  exit 1
fi
