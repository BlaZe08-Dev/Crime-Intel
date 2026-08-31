# Installation Guide

Complete setup instructions for Ollama on AMD Windows.

## Prerequisites

- **Windows 10 or 11**
- **Python 3.10 or later**
- **AMD Radeon GPU** (RX 5000 series or newer)
- **AMD GPU Driver** with Vulkan 1.3 support

## Step 1: Install Ollama

### Via winget (Recommended)

```bash
winget install Ollama.Ollama
```

Then verify installation:

```bash
ollama --version
```

### Via Direct Download

Visit [ollama.ai](https://ollama.ai/) and download the Windows installer.

## Step 2: Install AMD GPU Drivers

Download and install the latest AMD Radeon drivers:

- **AMD Driver Download**: https://www.amd.com/en/support
- Choose your GPU model (e.g., Radeon RX 5700 XT)
- Download and install the latest driver package

**Important**: The driver must include Vulkan support (1.3 or later).

## Step 3: Verify Vulkan Support

Check if Vulkan is properly installed:

```bash
vulkaninfo --summary
```

Look for:
- Your GPU name (e.g., "RADV" or "AMD")
- API version 1.3 or higher

If Vulkan is not detected:
1. Update AMD drivers
2. Reinstall the driver completely (clean uninstall + install)

## Step 4: Clone or Download This Repository

```bash
git clone https://github.com/ChharithOeun/ollama-amd-windows-setup.git
cd ollama-amd-windows-setup
```

Or download as ZIP: [Download](https://github.com/ChharithOeun/ollama-amd-windows-setup/archive/refs/heads/main.zip)

## Step 5: Install Python Dependencies

```bash
pip install -r requirements.txt
```

This installs `requests`, which is required for the scripts.

## Step 6: Verify Setup

Run the verification script:

```bash
python scripts/verify_gpu.py
```

This checks:
- Ollama installation
- Vulkan support
- GPU detection
- API availability

## Step 7: Pull Your First Model

Start with a small, fast model for testing:

```bash
python scripts/pull_models.py --model tinyllama
```

Or pull a recommended model:

```bash
python scripts/pull_models.py --model llama3.1:8b
```

## Step 8: Start Chatting

### Option A: Interactive Chat

```bash
python scripts/chat.py --model tinyllama
```

Type your message and press Enter. Type `/quit` to exit.

### Option B: Via Menu

```bash
run.bat
```

Select option 3 to chat.

### Option C: Use Ollama CLI Directly

```bash
ollama run tinyllama
```

## Step 9 (Optional): Install Web UI

For a browser-based chat interface:

```bash
pip install open-webui
open-webui serve
```

Then visit `http://localhost:3000` in your browser.

## API Usage

### Start Ollama Server

In a terminal, start the Ollama server:

```bash
ollama serve
```

It will listen on `http://localhost:11434`

### Use curl

```bash
# Generate text
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "prompt": "Hello, world!",
    "stream": false
  }'

# Chat (conversation)
curl -X POST http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [
      {"role": "user", "content": "What is 2+2?"}
    ],
    "stream": false
  }'
```

### Use Python (requests)

```python
import requests

response = requests.post(
    "http://localhost:11434/api/generate",
    json={
        "model": "llama3.1:8b",
        "prompt": "Explain AI in one sentence",
        "stream": False
    }
)

print(response.json()["response"])
```

### Use Python (ollama library)

Optional: Install the Ollama Python library:

```bash
pip install ollama
```

Then:

```python
import ollama

response = ollama.generate(
    model="llama3.1:8b",
    prompt="What is machine learning?"
)

print(response["response"])
```

## Troubleshooting

### GPU Not Detected

1. Check AMD driver installation
2. Verify Vulkan: `vulkaninfo --summary`
3. Update GPU driver to latest version
4. Restart computer and try again

### Models Download Slowly or Fail

- Check internet connection
- Models are hosted on CDN; try again if download fails
- Use `--url` flag if you have a local mirror

### Out of Memory

- Use a smaller model (e.g., `tinyllama` or `phi3:mini`)
- Reduce context window: `ollama run llama3.1:8b -c 512`
- Close other GPU-intensive applications

### Ollama Server Won't Start

- Check if another instance is running
- Try: `taskkill /IM ollama.exe /F` (force kill)
- Restart Ollama

## Next Steps

1. **Explore Models**: Run `python scripts/pull_models.py --list`
2. **Benchmark Performance**: `python scripts/benchmark.py --model tinyllama`
3. **Install Web UI**: For easier access
4. **Read API Docs**: https://github.com/ollama/ollama/blob/main/docs/api.md
5. **Check AMD Toolkit**: https://github.com/ChharithOeun/amd-windows-toolkit

## Support

- Issues: [GitHub Issues](https://github.com/ChharithOeun/ollama-amd-windows-setup/issues)
- Ollama Docs: https://ollama.ai/
- AMD Driver Support: https://www.amd.com/en/support

---

**Support this project**: [![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-orange.svg)](https://buymeacoffee.com/chharith)
