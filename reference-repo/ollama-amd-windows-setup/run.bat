@echo off
REM Ollama AMD Windows Setup - Interactive Menu
REM Requires: Python 3.10+, Ollama installed

setlocal enabledelayedexpansion

:menu
cls
echo ============================================================
echo  Ollama AMD Windows Setup - Menu
echo ============================================================
echo.
echo  1. Verify GPU/Ollama Setup
echo  2. Pull Models
echo  3. Chat with a Model
echo  4. Benchmark Model Performance
echo  5. Start Ollama Server
echo  6. Exit
echo.
echo ============================================================
set /p choice="Select an option (1-6): "

if "%choice%"=="1" (
    echo.
    echo Running GPU verification...
    echo.
    python scripts/verify_gpu.py
    pause
    goto menu
)

if "%choice%"=="2" (
    echo.
    echo Available models: tinyllama, phi3:mini, llama3.1:8b, mistral:7b, qwen2.5:7b, gemma2:9b
    echo.
    set /p model="Enter model name (or press Enter for default 'tinyllama'): "
    if "%model%"=="" (
        python scripts/pull_models.py
    ) else (
        python scripts/pull_models.py --model %model%
    )
    pause
    goto menu
)

if "%choice%"=="3" (
    echo.
    set /p model="Enter model name (default: llama3.1:8b): "
    if "%model%"=="" (
        python scripts/chat.py
    ) else (
        python scripts/chat.py --model %model%
    )
    pause
    goto menu
)

if "%choice%"=="4" (
    echo.
    set /p model="Enter model to benchmark (default: tinyllama): "
    if "%model%"=="" (
        python scripts/benchmark.py
    ) else (
        python scripts/benchmark.py --model %model%
    )
    pause
    goto menu
)

if "%choice%"=="5" (
    echo.
    echo Starting Ollama server...
    echo (Press Ctrl+C to stop)
    echo.
    ollama serve
    pause
    goto menu
)

if "%choice%"=="6" (
    echo.
    echo Goodbye!
    exit /b 0
)

echo Invalid choice. Please select 1-6.
pause
goto menu
