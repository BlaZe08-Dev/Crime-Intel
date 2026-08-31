#!/usr/bin/env bash
# wsl2_setup.sh -- Automated Ollama + ROCm setup inside WSL2 (Ubuntu 22.04)
#
# Run this INSIDE your WSL2 Ubuntu terminal, not in PowerShell/CMD.
#
# Usage:
#   chmod +x wsl2_setup.sh && ./wsl2_setup.sh
#
# What this does:
#   1. Installs AMD ROCm 6.2 inside Ubuntu 22.04
#   2. Installs Ollama (Linux binary)
#   3. Configures environment variables
#   4. Prints port-forwarding command for Windows access
#
# Known limitation: AMD GPU passthrough in WSL2 requires /dev/kfd.
# Many WSL2 setups expose /dev/dxg instead, which ROCm cannot use.
# This script checks for /dev/kfd and warns if not found.

set -euo pipefail

RED='\033[0;31m'; YELLOW='\033[1;33m'; GREEN='\033[0;32m'; BLUE='\033[0;34m'; NC='\033[0m'
log_info()  { echo -e "${BLUE}[INFO]${NC} $*"; }
log_ok()    { echo -e "${GREEN}[OK]${NC}   $*"; }
log_warn()  { echo -e "${YELLOW}[WARN]${NC} $*"; }
log_error() { echo -e "${RED}[ERROR]${NC} $*"; }

echo ""
echo "=================================================="
echo "  Ollama AMD GPU Setup for WSL2 (Ubuntu 22.04)   "
echo "=================================================="
echo ""

# 1. Verify WSL2
log_info "Checking WSL2 environment..."
if ! grep -qi microsoft /proc/version 2>/dev/null; then
    log_error "Must run inside WSL2, not native Linux."
    exit 1
fi

UBUNTU_VERSION=$(lsb_release -rs 2>/dev/null || echo "unknown")
if [[ "$UBUNTU_VERSION" != "22.04" ]]; then
    log_warn "Ubuntu $UBUNTU_VERSION detected. ROCm in WSL2 works best on 22.04."
    read -rp "Continue? (y/N) " CONT
    [[ "$CONT" =~ ^[Yy] ]] || exit 1
fi

# 2. Check GPU device nodes
log_info "Checking AMD GPU device nodes..."
if [[ -e /dev/kfd ]]; then
    log_ok "/dev/kfd found -- ROCm GPU passthrough should work"
elif [[ -e /dev/dxg ]]; then
    log_warn "/dev/kfd NOT found. /dev/dxg present (WSL2 DXCore)."
    log_warn "ROCm requires /dev/kfd. AMD GPU may not work inside WSL2."
    log_warn "Consider using native Windows + ollama-for-amd fork instead."
    read -rp "Continue anyway? (y/N) " CONT
    [[ "$CONT" =~ ^[Yy] ]] || exit 1
else
    log_error "No GPU device node found. GPU passthrough not available."
    log_error "Run 'wsl --update' in PowerShell and restart WSL2."
    exit 1
fi

# 3. System update
log_info "Updating system packages..."
sudo apt-get update -qq && sudo apt-get upgrade -y -qq

# 4. Prerequisites
log_info "Installing prerequisites..."
sudo apt-get install -y -qq wget curl gnupg2 lsb-release build-essential

# 5. AMD ROCm 6.2 repo
log_info "Adding AMD ROCm 6.2 repository..."
wget -q -O - https://repo.radeon.com/rocm/rocm.gpg.key | \
    sudo gpg --dearmor -o /usr/share/keyrings/rocm.gpg

echo "deb [arch=amd64 signed-by=/usr/share/keyrings/rocm.gpg] \
    https://repo.radeon.com/rocm/apt/6.2 $(lsb_release -cs) main" | \
    sudo tee /etc/apt/sources.list.d/rocm.list > /dev/null

echo "Package: *
Pin: release o=repo.radeon.com
Pin-Priority: 600" | sudo tee /etc/apt/preferences.d/rocm-pin-600 > /dev/null

sudo apt-get update -qq

# 6. Install ROCm
log_info "Installing ROCm HIP runtime (this may take several minutes)..."
sudo apt-get install -y rocm-hip-runtime hip-dev rocm-smi-lib rocinfo

# 7. User groups
sudo usermod -aG render,video "$USER" 2>/dev/null || true

# 8. Environment variables
SHELL_RC="$HOME/.bashrc"
[[ -n "${ZSH_VERSION:-}" ]] && SHELL_RC="$HOME/.zshrc"

if ! grep -q "ROCm Ollama setup" "$SHELL_RC" 2>/dev/null; then
    cat >> "$SHELL_RC" << 'ENVEOF'

# ROCm Ollama setup (wsl2_setup.sh)
export PATH="$PATH:/opt/rocm/bin"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/opt/rocm/lib"
# Uncomment and set for unsupported GPUs (Linux/WSL2 only):
# export HSA_OVERRIDE_GFX_VERSION=10.3.0
export ROCR_VISIBLE_DEVICES=0
export OLLAMA_FLASH_ATTENTION=1
ENVEOF
    log_ok "Environment variables added to $SHELL_RC"
fi

export PATH="$PATH:/opt/rocm/bin"
export LD_LIBRARY_PATH="${LD_LIBRARY_PATH:-}:/opt/rocm/lib"

# 9. Verify ROCm
log_info "Checking ROCm GPU detection..."
if rocinfo 2>/dev/null | grep -q "gfx"; then
    GFX=$(rocinfo 2>/dev/null | grep -m1 "gfx" | grep -oP 'gfx\w+' | head -1)
    log_ok "GPU detected: $GFX"
else
    log_warn "ROCm could not detect AMD GPU."
    log_warn "This may be a /dev/kfd availability issue."
    log_warn "Ollama will install but run on CPU without GPU passthrough."
fi

# 10. Install Ollama
log_info "Installing Ollama..."
if command -v ollama &>/dev/null; then
    log_warn "Ollama already installed: $(ollama --version 2>/dev/null)"
    read -rp "Reinstall? (y/N) " R
    [[ "$R" =~ ^[Yy] ]] && curl -fsSL https://ollama.com/install.sh | sh
else
    curl -fsSL https://ollama.com/install.sh | sh
fi
log_ok "Ollama: $(ollama --version 2>/dev/null)"

# 11. Model storage
MODELS_DIR="$HOME/.ollama/models"
mkdir -p "$MODELS_DIR"
if ! grep -q "OLLAMA_MODELS" "$SHELL_RC" 2>/dev/null; then
    echo "export OLLAMA_MODELS=\"$MODELS_DIR\"" >> "$SHELL_RC"
fi
log_warn "IMPORTANT: Always store models in WSL2 filesystem (~/),"
log_warn "never under /mnt/c/ -- cross-filesystem I/O is very slow."

# 12. Start Ollama
log_info "Starting Ollama..."
ollama serve &>/tmp/ollama_wsl2.log &
OLLAMA_PID=$!
sleep 3
if kill -0 "$OLLAMA_PID" 2>/dev/null; then
    log_ok "Ollama running (PID $OLLAMA_PID) | logs: /tmp/ollama_wsl2.log"
else
    log_error "Ollama failed to start. Check /tmp/ollama_wsl2.log"
    cat /tmp/ollama_wsl2.log
fi

# 13. Port forwarding info
WSL_IP=$(ip addr show eth0 2>/dev/null | grep "inet " | awk '{print $2}' | cut -d/ -f1)

echo ""
echo "=================================================="
echo "  Windows access (run in PowerShell as Admin):   "
echo "=================================================="
echo ""
echo "  netsh interface portproxy add v4tov4 listenport=11434 listenaddress=0.0.0.0 connectport=11434 connectaddress=${WSL_IP:-<wsl-ip>}"
echo ""
echo "  To remove later:"
echo "  netsh interface portproxy delete v4tov4 listenport=11434 listenaddress=0.0.0.0"
echo ""
echo "  Test: ollama run llama3.2:3b"
echo ""
log_ok "Setup complete. Reload env: source $SHELL_RC"
