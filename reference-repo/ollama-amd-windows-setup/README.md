# Ollama AMD Windows Setup

[![CI](https://github.com/ChharithOeun/ollama-amd-windows-setup/actions/workflows/ci.yml/badge.svg)](https://github.com/ChharithOeun/ollama-amd-windows-setup/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Python 3.10+](https://img.shields.io/badge/python-3.10+-blue.svg)](https://www.python.org/downloads/)
[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-orange.svg)](https://buymeacoffee.com/chharith)

Run Ollama local LLMs on AMD GPU Windows — **Vulkan backend**, REST API, web UI.

## Quick Start

### 1. Install Ollama
```bash
winget install Ollama.Ollama
```

### 2. Verify GPU Setup
```bash
python scripts/verify_gpu.py
```

### 3. Pull a Model
```bash
python scripts/pull_models.py --model llama3.1:8b
```

### 4. Chat
```bash
python scripts/chat.py --model llama3.1:8b
```

## What is Ollama?

Ollama is a local LLM runner with a **simple API and CLI**. It:
- Runs open-source models locally (no cloud)
- Exposes an OpenAI-compatible REST API on `http://localhost:11434`
- Includes a Python SDK and web UIs
- Manages model downloads and VRAM allocation automatically

## AMD GPU on Windows

**Key Point**: Ollama on AMD Windows uses **Vulkan backend** (ROCm is not available on Windows).

- Works with any **Radeon GPU** supporting **Vulkan 1.3+**
- Automatic GPU detection if your AMD driver is installed
- Vulkan 1.3 support: Radeon RX 5000 series and newer, Radeon Pro WX 2100 and newer
- Check your GPU: `vulkaninfo --summary`

## Features

- **REST API** — OpenAI-compatible endpoints (drop-in replacement)
- **CLI Chat** — Simple terminal interface
- **Model Library** — Pull any model from Ollama's registry
- **Python SDK** — Programmatic access with `requests`
- **Web UI** — Open-WebUI for browser-based chat
- **Streaming** — Real-time token-by-token responses

## Usage Examples

### Pull and Run via CLI
```bash
ollama pull mistral:7b
ollama run mistral:7b
# Type your prompt, Ctrl+D to send
```

### REST API with curl
```bash
# Generate
curl -X POST http://localhost:11434/api/generate \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "prompt": "What is the capital of France?",
    "stream": false
  }'

# Chat
curl -X POST http://localhost:11434/api/chat \
  -H "Content-Type: application/json" \
  -d '{
    "model": "llama3.1:8b",
    "messages": [
      {"role": "user", "content": "Hello!"}
    ],
    "stream": false
  }'
```

### Python with requests
```python
import requests

response = requests.post(
    "http://localhost:11434/api/generate",
    json={
        "model": "llama3.1:8b",
        "prompt": "Explain quantum computing in one sentence.",
        "stream": False
    }
)
print(response.json()["response"])
```

### Python SDK (optional)
```bash
pip install ollama
```

```python
import ollama

response = ollama.generate(
    model="llama3.1:8b",
    prompt="What is AI?"
)
print(response["response"])
```

## Recommended Models

| Model | Size | Params | VRAM | Notes |
|-------|------|--------|------|-------|
| `tinyllama` | 272M | 1.1B | ~1 GB | Ultra-fast, good for testing |
| `phi3:mini` | 1.3 GB | 3.8B | ~2 GB | Fast, good quality |
| `llama3.1:8b` | 4.7 GB | 8.0B | ~6 GB | Balanced, recommended default |
| `mistral:7b` | 4.0 GB | 7.2B | ~5 GB | Fast, good reasoning |
| `qwen2.5:7b` | 3.8 GB | 7.6B | ~5 GB | Multilingual, fast |
| `gemma2:9b` | 5.5 GB | 9.2B | ~7 GB | High quality, larger context |

**Estimate VRAM**: Model size + ~2 GB overhead.

## Web UI (Open-WebUI)

Install Open-WebUI for a ChatGPT-like interface:

```bash
pip install open-webui
open-webui serve
```

Then visit `http://localhost:3000` in your browser.

## Python API

### Using requests (pure, no external deps beyond requests)
```python
import requests
import json

def chat_with_ollama(model, prompt):
    response = requests.post(
        "http://localhost:11434/api/generate",
        json={"model": model, "prompt": prompt, "stream": False}
    )
    return response.json()["response"]

result = chat_with_ollama("llama3.1:8b", "Hello!")
print(result)
```

### Using ollama Python library (optional)
```bash
pip install ollama
```

```python
import ollama

stream = ollama.generate(
    model="llama3.1:8b",
    prompt="Explain recursion.",
    stream=True
)

for chunk in stream:
    print(chunk["response"], end="", flush=True)
```

## Common Issues

### GPU Not Detected
- **Check driver**: Update your AMD GPU driver
- **Check Vulkan**: Run `vulkaninfo --summary`
- **Verify Ollama sees it**: `ollama ps` (if Ollama server is running)
- **Force GPU**: Set env var `OLLAMA_GPU_LAYERS=999` before running

### Model Too Slow
- **Reduce context**: Use `-c 512` flag in `ollama run` to limit context window
- **Try smaller model**: Use `tinyllama` or `phi3:mini` for testing
- **Check VRAM**: Run `ollama ps` to see allocated layers

### Out of Memory
- **Check available VRAM**: GPU-Z or AMD Radeon Settings
- **Reduce model context**: `ollama run llama3.1:8b -c 1024`
- **Use smaller model**: `phi3:mini` or `tinyllama`

## VRAM Reference

| GPU | VRAM | Recommended Models |
|-----|------|-------------------|
| Radeon RX 5500 XT | 4 GB | tinyllama, phi3:mini |
| Radeon RX 5700 XT | 8 GB | llama3.1:8b, mistral:7b |
| Radeon RX 6600 XT | 16 GB | gemma2:9b, larger models |
| Radeon RX 7700 XT | 12 GB | llama3.1:8b, mistral:7b |
| Radeon RX 7900 XTX | 24 GB | Multiple large models |

## Related

- **[AMD Windows Toolkit](https://github.com/ChharithOeun/amd-windows-toolkit)** — GPU drivers, monitoring, optimization
- **[Ollama Official](https://ollama.ai/)** — Model library, API docs
- **[Open-WebUI](https://github.com/open-webui/open-webui)** — Self-hosted web UI
- **[Vulkan](https://www.khronos.org/vulkan/)** — Graphics standard (backend for AMD on Windows)

## License

MIT License © 2024 Chharith Oeun

---

**Support this project:**

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-orange.svg)](https://buymeacoffee.com/chharith)
