# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2024-04-19

### Added

- Initial release of Ollama AMD Windows Setup
- **Scripts**:
  - `verify_gpu.py` - Verify Ollama, Vulkan, and GPU setup
  - `chat.py` - Interactive Python chat client with streaming support
  - `pull_models.py` - Pull models from Ollama registry via REST API
  - `benchmark.py` - Benchmark model performance (tokens/sec)
- **Documentation**:
  - `README.md` - Complete setup and usage guide with badges
  - `INSTALL.md` - Step-by-step installation instructions
  - `CONTRIBUTING.md` - Contribution guidelines
  - `CHANGELOG.md` - This file
- **Configuration**:
  - `requirements.txt` - Python dependencies (requests)
  - `run.bat` - Interactive menu for Windows users
  - `.gitignore` - Standard Python/Ollama ignores
  - `LICENSE` - MIT License
- **CI/CD**:
  - `.github/workflows/ci.yml` - Automated testing (Ubuntu, Windows, macOS)
  - `.github/workflows/changelog.yml` - Auto-changelog on main push
- **Issue Templates**:
  - `.github/ISSUE_TEMPLATE/bug_report.md` - Bug report template
  - `.github/ISSUE_TEMPLATE/feature_request.md` - Feature request template

### Features

- **AMD GPU Support**: Vulkan backend (not ROCm, as it's unavailable on Windows)
- **REST API Integration**: Pure requests-based scripts (no llama_cpp dependency)
- **Streaming Support**: Chat and API streaming responses
- **Model Management**: Pull, list, and manage Ollama models
- **Performance Benchmarking**: Measure tokens/second for models
- **GPU Diagnostics**: Verify Vulkan, GPU detection, and Ollama setup
- **Web UI Integration**: Open-WebUI support instructions
- **Cross-Platform CI**: Test matrix: Ubuntu, Windows, macOS × Python 3.10-3.12

### Documentation

- Quick start guide
- Recommended models with VRAM requirements
- Common troubleshooting solutions
- API usage examples (curl, Python)
- Detailed installation instructions
- Contributing guidelines

### Known Limitations

- Ollama on Windows uses Vulkan backend (ROCm unavailable)
- Requires Radeon GPU with Vulkan 1.3 support
- Model performance depends on GPU VRAM

---

## Roadmap

### Future Versions

- Model caching improvements
- Performance profiling tools
- Integration with AMD monitoring tools
- Windows service installation option
- GUI launcher (optional)
- Multi-model concurrent serving

---

**Support**: [![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-orange.svg)](https://buymeacoffee.com/chharith)
