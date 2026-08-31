# Contributing

We welcome contributions! Help us improve Ollama on AMD Windows.

## Ways to Contribute

### 1. Report Bugs

Found an issue? [Open a GitHub issue](https://github.com/ChharithOeun/ollama-amd-windows-setup/issues/new?template=bug_report.md)

Include:
- GPU model and driver version
- Windows version
- Python version
- Ollama version
- Error message or unexpected behavior
- Steps to reproduce

### 2. Request Features

Have an idea? [Open a feature request](https://github.com/ChharithOeun/ollama-amd-windows-setup/issues/new?template=feature_request.md)

Describe:
- What you want to accomplish
- Why it would be useful
- Suggested implementation (optional)

### 3. Improve Documentation

- Fix typos or unclear explanations
- Add usage examples
- Improve troubleshooting guides
- Create tutorials

### 4. Add Scripts or Tools

Help expand the toolkit:
- New helper scripts (e.g., model management, monitoring)
- Performance optimization tools
- Integration examples
- Windows-specific enhancements

### 5. Test on Different Hardware

Test and report results on:
- Different Radeon GPU models
- Different Windows versions
- Different Python versions

## Getting Started

1. **Fork the repository**
   ```bash
   git clone https://github.com/YOUR_USERNAME/ollama-amd-windows-setup.git
   cd ollama-amd-windows-setup
   ```

2. **Create a feature branch**
   ```bash
   git checkout -b feature/your-feature-name
   ```

3. **Make your changes**
   - Follow existing code style (PEP 8)
   - Add docstrings to functions
   - Update README if needed

4. **Test your changes**
   ```bash
   python scripts/verify_gpu.py
   python scripts/chat.py
   ```

5. **Commit and push**
   ```bash
   git add .
   git commit -m "Add feature: description"
   git push origin feature/your-feature-name
   ```

6. **Open a pull request**
   - Reference any related issues
   - Describe your changes clearly
   - Explain why the change is needed

## Code Style

- Python: Follow [PEP 8](https://www.python.org/dev/peps/pep-0008/)
- Use docstrings for all functions and classes
- Use type hints where practical
- Keep lines under 100 characters

Example:

```python
def calculate_tokens_per_second(tokens: int, elapsed_seconds: float) -> float:
    """
    Calculate tokens per second.

    Args:
        tokens: Number of tokens generated
        elapsed_seconds: Elapsed time in seconds

    Returns:
        Tokens per second (float)
    """
    if elapsed_seconds <= 0:
        return 0.0
    return tokens / elapsed_seconds
```

## Testing

Before submitting:

1. **Test locally**
   ```bash
   python scripts/verify_gpu.py
   python scripts/benchmark.py --model tinyllama --runs 1
   ```

2. **Verify Python syntax**
   ```bash
   python -m py_compile scripts/*.py
   ```

3. **Check dependencies**
   ```bash
   pip install -r requirements.txt
   ```

## Pull Request Process

1. Ensure code follows style guidelines
2. Update documentation if needed
3. Include any new dependencies in requirements.txt
4. Reference issues in your PR description
5. Be responsive to feedback

## Community

- **Discuss**: [GitHub Discussions](https://github.com/ChcharithOeun/ollama-amd-windows-setup/discussions)
- **Report Issues**: [GitHub Issues](https://github.com/ChharithOeun/ollama-amd-windows-setup/issues)
- **AMD Toolkit**: [Related Project](https://github.com/ChharithOeun/amd-windows-toolkit)

## License

By contributing, you agree that your contributions will be licensed under the MIT License (see LICENSE file).

---

**Thank you for contributing!** Your work helps the entire community. Support this project:

[![Buy Me A Coffee](https://img.shields.io/badge/Buy%20Me%20A%20Coffee-☕-orange.svg)](https://buymeacoffee.com/chharith)
