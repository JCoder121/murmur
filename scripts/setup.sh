#!/bin/bash
# wispr_clone setup: installs whisper-cpp + model, optionally Ollama + qwen2.5:3b.
# Prints disk cost and asks before every download (machine has limited free space).
set -euo pipefail

MODEL_DIR="$HOME/Library/Application Support/WisprClone/models"
MODEL_FILE="$MODEL_DIR/ggml-large-v3-turbo-q5_0.bin"
MODEL_URL="https://huggingface.co/ggerganov/whisper.cpp/resolve/main/ggml-large-v3-turbo-q5_0.bin"

# Detect Homebrew: use arm64 at /opt/homebrew, fallback to system brew
if [[ -x /opt/homebrew/bin/brew ]]; then
  BREW="arch -arm64 /opt/homebrew/bin/brew"
elif command -v brew >/dev/null; then
  BREW="brew"
else
  BREW=""
fi

confirm() { read -r -p "$1 [y/N] " a; [[ "$a" == "y" || "$a" == "Y" ]]; }

echo "== wispr_clone setup =="
df -h / | awk 'NR==2 {print "Free disk: " $4}'

if [[ -z "$BREW" ]]; then
  echo "ERROR: Homebrew required (https://brew.sh)"; exit 1
fi

# 1. whisper-cpp (~15MB)
if command -v whisper-server >/dev/null; then
  echo "✓ whisper-server already installed"
else
  confirm "Install whisper-cpp via brew (~15MB)?" && $BREW install whisper-cpp
fi

# 2. Whisper model (~574MB)
if [[ -f "$MODEL_FILE" ]]; then
  echo "✓ whisper model already present"
else
  if confirm "Download whisper large-v3-turbo q5_0 model (~574MB)?"; then
    mkdir -p "$MODEL_DIR"
    curl -L --progress-bar -o "$MODEL_FILE" "$MODEL_URL"
  fi
fi

# 3. Ollama + qwen2.5:3b (optional — needed only for Smart mode)
echo ""
echo "Smart mode (LLM cleanup + Chinese→English) needs Ollama + qwen2.5:3b (~2.5GB total)."
echo "Rules mode works without it."
if ! command -v ollama >/dev/null; then
  confirm "Install Ollama via brew (~0.5GB)?" && $BREW install ollama
fi
if command -v ollama >/dev/null; then
  if ollama list 2>/dev/null | grep -q "qwen2.5:3b"; then
    echo "✓ qwen2.5:3b already pulled"
  else
    if confirm "Pull qwen2.5:3b model (~1.9GB)?"; then
      # ollama serve must be running; try to start it if not.
      pgrep -x ollama >/dev/null || (ollama serve >/dev/null 2>&1 &)
      sleep 2
      ollama pull qwen2.5:3b
    fi
  fi
fi

echo ""
echo "Done. Build & run the app with: make run"
echo "Grant Accessibility + Microphone permissions when prompted, then hold Right-Cmd and speak."
