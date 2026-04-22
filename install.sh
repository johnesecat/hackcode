#!/usr/bin/env bash
set -euo pipefail
GREEN=’\033[38;2;0;255;65m’
DIM=’\033[0;2m’
BOLD=’\033[1m’
RED=’\033[0;31m’
NC=’\033[0m’
REPO="johnesecat/hackcode"
INSTALL_DIR="${HOME}/.local/bin"

# ── Replit detection (added) ───────────────────────────────────────────────

IN_REPLIT=false
[ -n "${REPL_ID:-}" ] || [ -n "${REPLIT_DB_URL:-}" ] || [ -n "${REPLIT_CLUSTER:-}" ] && IN_REPLIT=true

# ──────────────────────────────────────────────────────────────────────────

echo ""
echo -e "${GREEN} ██╗  ██╗ █████╗  ██████╗██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗${NC}"
echo -e "${GREEN} ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝${NC}"
echo -e "${GREEN} ███████║███████║██║     █████╔╝ ██║     ██║   ██║██║  ██║█████╗  ${NC}"
echo -e "${GREEN} ██╔══██║██╔══██║██║     ██╔═██╗ ██║     ██║   ██║██║  ██║██╔══╝  ${NC}"
echo -e "${GREEN} ██║  ██║██║  ██║╚██████╗██║  ██╗╚██████╗╚██████╔╝██████╔╝███████╗${NC}"
echo -e "${GREEN} ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝${NC}"
echo -e "${GREEN}  >> AI-Powered Hacking Terminal  |  100% Local  |  No Censorship <<${NC}"
echo ""

# ─── Detect platform ──────────────────────────────────────

OS="$(uname -s)"
ARCH="$(uname -m)"
case "$OS" in
Linux)  PLATFORM="linux" ;;
Darwin) PLATFORM="macos" ;;
*)
echo -e "${RED}Error: Unsupported OS: $OS${NC}"
echo "HackCode supports Linux and macOS."
exit 1
;;
esac
case "$ARCH" in
x86_64|amd64)   ARCH_NAME="x64" ;;
arm64|aarch64)  ARCH_NAME="arm64" ;;
*)
echo -e "${RED}Error: Unsupported architecture: $ARCH${NC}"
echo "HackCode supports x86_64 and arm64."
exit 1
;;
esac
ARTIFACT="hackcode-${PLATFORM}-${ARCH_NAME}"
echo -e "${GREEN}[1/5]${NC} Detected: ${BOLD}${OS} ${ARCH}${NC} -> ${ARTIFACT}"

# ─── Try downloading pre-built binary ─────────────────────

echo -e "${GREEN}[2/5]${NC} Getting HackCode…"
INSTALLED=false

# Try GitHub Releases

TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep ‘"tag_name"’ | head -1 | sed -E ‘s/.*"tag_name": *"([^"]+)".*/\1/’ || true)
if [ -n "$TAG" ]; then
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARTIFACT}.tar.gz"
TMPDIR=$(mktemp -d)
trap ‘rm -rf "$TMPDIR"’ EXIT
HTTP_CODE=$(curl -sL -w "%{http_code}" -o "$TMPDIR/${ARTIFACT}.tar.gz" "$DOWNLOAD_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
cd "$TMPDIR"
tar xzf "${ARTIFACT}.tar.gz"
mkdir -p "$INSTALL_DIR"
mv "$ARTIFACT" "$INSTALL_DIR/hackcode"
chmod +x "$INSTALL_DIR/hackcode"
echo -e "  ${GREEN}Downloaded ${TAG} ✓${NC}"
INSTALLED=true
fi
fi

# Fall back to building from source

if [ "$INSTALLED" = false ]; then
echo -e "  ${DIM}No pre-built binary available. Building from source…${NC}"
if ! command -v cargo &>/dev/null; then
echo -e "  ${DIM}Installing Rust toolchain…${NC}"
curl –proto ‘=https’ –tlsv1.2 -sSf https://sh.rustup.rs | sh -s – -y
. "$HOME/.cargo/env"
fi
HACKCODE_SRC="${HOME}/.hackcode-src"
if [ -d "$HACKCODE_SRC/.git" ]; then
git -C "$HACKCODE_SRC" pull –quiet 2>/dev/null || true
else
[ -d "$HACKCODE_SRC" ] && rm -rf "$HACKCODE_SRC"
git clone –quiet "https://github.com/${REPO}.git" "$HACKCODE_SRC"
fi
cd "$HACKCODE_SRC/rust"
# Build with live progress -- disable set -e around the pipe so
# the while-subshell exit doesn’t kill the script before cp runs.
BUILD_LOG=$(mktemp)
echo -e "  ${DIM}Compiling (~200 crates, this may take a few minutes)…${NC}"
set +e
printf "\033[?25l"  # hide cursor during build
cargo build –release -p rusty-claude-cli 2>&1 | tee "$BUILD_LOG" | {
EST=200
BUILT=0
while IFS= read -r line; do
case "$line" in
*Compiling*)
BUILT=$((BUILT + 1))
PCT=$((BUILT * 100 / EST))
[ "$PCT" -gt 99 ] && PCT=99
CRATE=$(echo "$line" | sed ‘s/.*Compiling ([^ ]*).*/\1/’)
printf "\r\033[K  ${GREEN}[%3d%%]${NC} Compiling ${DIM}%s${NC}" "$PCT" "$CRATE"
;;
*Finished*)
printf "\r\033[K  ${GREEN}[100%%]${NC} Build complete\n"
;;
esac
done
}
printf "\033[?25h"  # restore cursor
BUILD_EXIT=${PIPESTATUS[0]:-$?}
set -e
rm -f "$BUILD_LOG"
if [ "$BUILD_EXIT" -ne 0 ] || [ ! -f "target/release/hackcode" ]; then
echo ""
echo -e "  ${RED}Build failed (exit code $BUILD_EXIT)${NC}"
echo -e "  ${DIM}Check that Rust toolchain is up to date: rustup update${NC}"
exit 1
fi
mkdir -p "$INSTALL_DIR"
cp "target/release/hackcode" "$INSTALL_DIR/hackcode"
chmod +x "$INSTALL_DIR/hackcode"
echo -e "  ${GREEN}Built and installed ✓${NC}"
cd - >/dev/null
fi

# ─── Add to PATH ──────────────────────────────────────────

echo -e "${GREEN}[3/5]${NC} Adding hackcode to PATH…"
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
zsh)  RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
bash) RC="$HOME/.bashrc" ; [ -f "$HOME/.bash_profile" ] && RC="$HOME/.bash_profile" ;;
fish) RC="$HOME/.config/fish/config.fish" ;;
*)    RC="" ;;
esac
if [ -n "$RC" ]; then
if ! grep -Fq "$INSTALL_DIR" "$RC" 2>/dev/null; then
echo "" >> "$RC"
echo "# HackCode" >> "$RC"
if [ "$SHELL_NAME" = "fish" ]; then
echo "fish_add_path $INSTALL_DIR" >> "$RC"
else
echo "export PATH="$INSTALL_DIR:$PATH"" >> "$RC"
fi
echo -e "  ${GREEN}Added to $RC ✓${NC}"
else
echo -e "  ${DIM}Already in PATH ✓${NC}"
fi
fi
export PATH="$INSTALL_DIR:$PATH"

# ─── AI backend ───────────────────────────────────────────

# On Replit: Ollama cannot run (no systemd). Use AirLLM instead --

# a layer-streaming Python server that exposes the same API on :11434.

# On every other platform: original Ollama logic, unchanged.

if $IN_REPLIT; then
# ── AirLLM (Replit / Nix shell) ───────────────────────────────────────
echo -e "${GREEN}[4/5]${NC} Installing AirLLM (layer-streaming backend for Replit)…"

```
# Locate Python 3.10+
PYTHON=""
for _py in python3.12 python3.11 python3.10 python3; do
    if command -v "$_py" &>/dev/null; then
        _ver=$("$_py" -c "import sys; print(f'{sys.version_info.major}{sys.version_info.minor}')" 2>/dev/null || echo "0")
        if [ "$_ver" -ge 310 ] 2>/dev/null; then PYTHON="$_py"; break; fi
    fi
done
if [ -z "$PYTHON" ]; then
    echo -e "  ${RED}Python 3.10+ not found${NC}"
    echo -e "  ${DIM}Add python3 to replit.nix deps and re-run install${NC}"
    exit 1
fi
echo -e "  ${GREEN}$("$PYTHON" --version) ✓${NC}"

# Locate airllm/ -- either next to this script or inside the cloned repo
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" 2>/dev/null && pwd || pwd)"
if [ -f "${SCRIPT_DIR}/airllm/server.py" ]; then
    AIRLLM_SRC="${SCRIPT_DIR}/airllm"
else
    # clone repo to get airllm/ if it isn't already present
    HACKCODE_SRC="${HOME}/.hackcode-src"
    if [ ! -d "$HACKCODE_SRC/.git" ]; then
        git clone --quiet "https://github.com/${REPO}.git" "$HACKCODE_SRC"
    fi
    AIRLLM_SRC="${HACKCODE_SRC}/airllm"
fi

# Install Python deps (CPU-only torch to keep download ~700 MB)
echo -e "  ${DIM}Installing torch + safetensors (CPU wheels)...${NC}"
"$PYTHON" -m pip install --user --quiet \
    torch --index-url https://download.pytorch.org/whl/cpu
"$PYTHON" -m pip install --user --quiet \
    safetensors transformers huggingface_hub tokenizers accelerate
echo -e "  ${GREEN}Python deps installed ✓${NC}"

# Write PYTHONPATH and OLLAMA_HOST into shell rc so they persist
AIRLLM_PARENT="$(dirname "$AIRLLM_SRC")"
if [ -n "$RC" ] && ! grep -Fq "AIRLLM" "$RC" 2>/dev/null; then
    {
        echo ""
        echo "# HackCode AirLLM"
        echo "export PYTHONPATH=\"${AIRLLM_PARENT}:\${PYTHONPATH:-}\""
        echo "export OLLAMA_HOST=\"http://127.0.0.1:11434\""
    } >> "$RC"
fi
export PYTHONPATH="${AIRLLM_PARENT}:${PYTHONPATH:-}"
export OLLAMA_HOST="http://127.0.0.1:11434"

echo -e "${GREEN}[5/5]${NC} AirLLM configured ✓"
echo -e "  ${DIM}Models are downloaded from HuggingFace on first use${NC}"
echo -e "  ${DIM}Start with: bash run.sh  (launches AirLLM server then hackcode)${NC}"
```

else
# ─── Original Ollama + Model (unchanged) ──────────────────────────────
echo -e "${GREEN}[4/5]${NC} Pulling AI model…"
OLLAMA_BIN=""
if command -v ollama &>/dev/null; then
OLLAMA_BIN="ollama"
elif [ -x "/Applications/Ollama.app/Contents/Resources/ollama" ]; then
OLLAMA_BIN="/Applications/Ollama.app/Contents/Resources/ollama"
fi
if [ -n "$OLLAMA_BIN" ]; then
echo -e "  ${GREEN}Ollama found ✓${NC}"
# Check if hackcode-uncensored alias already exists
if $OLLAMA_BIN list 2>/dev/null | grep -q "hackcode-uncensored"; then
echo -e "  ${GREEN}hackcode-uncensored model ready ✓${NC}"
else
# Pick best model based on available RAM
RAM_GB=8
case "$PLATFORM" in
macos) RAM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk ‘{printf "%d", $1/1073741824}’) ;;
linux) RAM_GB=$(awk ‘/MemTotal/{printf "%d", $2/1048576}’ /proc/meminfo 2>/dev/null) ;;
esac
# Try models in order of preference (largest that fits → smallest fallback)
BASE_MODEL=""
MODEL_DESC=""
if [ "$RAM_GB" -ge 24 ]; then
BASE_MODEL="tripolskypetr/qwen3.5-uncensored-aggressive:35b"
MODEL_DESC="Qwen3.5-35B-A3B MoE Uncensored (~21GB)"
elif [ "$RAM_GB" -ge 8 ]; then
BASE_MODEL="qwen3:8b"
MODEL_DESC="Qwen3-8B (~5GB)"
else
BASE_MODEL="tripolskypetr/qwen3.5-uncensored-aggressive:4b"
MODEL_DESC="Qwen3.5-4B Uncensored (~3GB)"
fi
echo ""
echo -e "  ${DIM}RAM: ${RAM_GB}GB -- pulling ${BOLD}${MODEL_DESC}${NC}"
echo ""
PULLED=false
# Try primary pick, then fallbacks
for TRY_MODEL in "$BASE_MODEL" "qwen3:8b" "tripolskypetr/qwen3.5-uncensored-aggressive:4b" "qwen3:4b"; do
if $OLLAMA_BIN pull "$TRY_MODEL"; then
BASE_MODEL="$TRY_MODEL"
PULLED=true
break
fi
echo -e "  ${DIM}$TRY_MODEL not available, trying next…${NC}"
done
if [ "$PULLED" = true ]; then
echo -e "  ${GREEN}Model pulled ✓${NC}"
# Step 5: Create hackcode-uncensored alias
echo -e "${GREEN}[5/5]${NC} Creating hackcode-uncensored model…"
HACKCODE_CFG="${HOME}/.config/hackcode"
mkdir -p "$HACKCODE_CFG"
cat > "${HACKCODE_CFG}/Modelfile" << MODELFILE
FROM ${BASE_MODEL}
PARAMETER temperature 0.7
PARAMETER num_ctx 32768
MODELFILE
$OLLAMA_BIN create hackcode-uncensored -f "${HACKCODE_CFG}/Modelfile"
echo -e "  ${GREEN}hackcode-uncensored ready ✓${NC}"
else
echo -e "  ${RED}Could not pull any model${NC}"
echo -e "  ${DIM}Run: ollama pull qwen3:8b && hackcode –setup${NC}"
fi
fi
else
echo -e "  ${RED}Ollama not found${NC} -- required for local AI"
if [ "$PLATFORM" = "macos" ]; then
echo -e "  ${DIM}Install: brew install ollama  ${NC}or${DIM}  https://ollama.ai/download${NC}"
else
echo -e "  ${DIM}Install: curl -fsSL https://ollama.ai/install.sh | sh${NC}"
fi
fi
fi

# ─── Done ─────────────────────────────────────────────────

echo ""
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo -e "${GREEN}[HackCode]${NC} Installation complete!"
echo ""
echo -e "  ${BOLD}hackcode${NC}          ${DIM}# Start hacking${NC}"
echo -e "  ${BOLD}hackcode –help${NC}   ${DIM}# Show all commands${NC}"
echo ""
echo -e "  ${DIM}Open a new terminal or run:${NC}"
echo -e "  ${BOLD}export PATH="$INSTALL_DIR:$PATH"${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""