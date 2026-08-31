---
name: Bug report
about: Report an issue with Ollama AMD Windows Setup
title: "[BUG] "
labels: bug
assignees: ''

---

## Describe the bug
A clear and concise description of what the bug is.

## Environment
- **GPU Model**: (e.g., Radeon RX 5700 XT)
- **GPU Driver Version**: (e.g., Adrenalin 24.1)
- **Windows Version**: (e.g., Windows 11 22H2)
- **Python Version**: (e.g., 3.11.0)
- **Ollama Version**: (run `ollama --version`)

## Steps to reproduce
1. ...
2. ...
3. ...

## Expected behavior
What you expected to happen.

## Actual behavior
What actually happened.

## Error output
```
Paste the full error message or traceback here
```

## GPU Detection
Please run and paste output of:
```bash
python scripts/verify_gpu.py
```

## Ollama Status
If Ollama server is running, paste output of:
```bash
ollama ps
```

## Vulkan Information
```bash
vulkaninfo --summary
```

## Additional context
Any other information that might be helpful (e.g., recently updated driver, other GPU-intensive apps running, etc.)

## Possible solution
If you have an idea how to fix this, please describe it.

---

**Helpful links:**
- [AMD Driver Downloads](https://www.amd.com/en/support)
- [Ollama Documentation](https://ollama.ai/)
- [Project Issues](https://github.com/ChharithOeun/ollama-amd-windows-setup/issues)
