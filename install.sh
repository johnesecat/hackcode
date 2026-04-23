#!/usr/bin/env bash
set -euo pipefail
GREEN='\033[38;2;0;255;65m'
DIM='\033[0;2m'
BOLD='\033[1m'
RED='\033[0;31m'
NC='\033[0m'
REPO="johnesecat/hackcode"
INSTALL_DIR="${HOME}/.local/bin"

# ─── Detect Replit ─────────────────────────────────────────────────────────

# Uses a proper if/fi block so set -e can't trip on the test exit code.

IN_REPLIT=false
if [ -n "${REPL_ID:-}" ] || [ -n "${REPLIT_DB_URL:-}" ] || [ -n "${REPLIT_CLUSTER:-}" ]; then
IN_REPLIT=true
fi

echo ""
echo -e "${GREEN} ██╗  ██╗ █████╗  ██████╗██╗  ██╗ ██████╗ ██████╗ ██████╗ ███████╗${NC}"
echo -e "${GREEN} ██║  ██║██╔══██╗██╔════╝██║ ██╔╝██╔════╝██╔═══██╗██╔══██╗██╔════╝${NC}"
echo -e "${GREEN} ███████║███████║██║     █████╔╝ ██║     ██║   ██║██║  ██║█████╗  ${NC}"
echo -e "${GREEN} ██╔══██║██╔══██║██║     ██╔═██╗ ██║     ██║   ██║██║  ██║██╔══╝  ${NC}"
echo -e "${GREEN} ██║  ██║██║  ██║╚██████╗██║  ██╗╚██████╗╚██████╔╝██████╔╝███████╗${NC}"
echo -e "${GREEN} ╚═╝  ╚═╝╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝ ╚═════╝ ╚═════╝ ╚═════╝ ╚══════╝${NC}"
echo -e "${GREEN}  >> AI-Powered Hacking Terminal  |  100% Local  |  No Censorship <<${NC}"
echo ""

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
TAG=$(curl -sL "https://api.github.com/repos/${REPO}/releases/latest" 2>/dev/null | grep ‘"tag_name"' | head -1 | sed -E ‘s/.*"tag_name": *"([^"]+)".*/\1/' || true)
if [ -n "$TAG" ]; then
DOWNLOAD_URL="https://github.com/${REPO}/releases/download/${TAG}/${ARTIFACT}.tar.gz"
TMPDIR_DL=$(mktemp -d)
trap ‘rm -rf "$TMPDIR_DL"' EXIT
HTTP_CODE=$(curl -sL -w "%{http_code}" -o "$TMPDIR_DL/${ARTIFACT}.tar.gz" "$DOWNLOAD_URL" 2>/dev/null || echo "000")
if [ "$HTTP_CODE" = "200" ]; then
cd "$TMPDIR_DL"
tar xzf "${ARTIFACT}.tar.gz"
mkdir -p "$INSTALL_DIR"
mv "$ARTIFACT" "$INSTALL_DIR/hackcode"
chmod +x "$INSTALL_DIR/hackcode"
echo -e "  ${GREEN}Downloaded ${TAG} ✓${NC}"
INSTALLED=true
cd - >/dev/null
fi
fi

# Fall back to building from source

if [ "$INSTALLED" = false ]; then
echo -e "  ${DIM}No pre-built binary available. Building from source…${NC}"

# ── Rust toolchain ────────────────────────────────────────────────────
# On Replit/Nix, rustup is provided by replit.nix but cargo may not be
# on PATH yet.  Source the env file if it exists, otherwise install.
CARGO_ENV="${HOME}/.cargo/env"
if [ -f "$CARGO_ENV" ]; then
    # shellcheck source=/dev/null
    . "$CARGO_ENV"
fi
if ! command -v cargo &>/dev/null; then
    if $IN_REPLIT && command -v rustup &>/dev/null; then
        # Nix provides rustup but not yet a toolchain
        echo -e "  ${DIM}Installing stable Rust toolchain via rustup...${NC}"
        rustup toolchain install stable --no-self-update 2>&1 | tail -3
        rustup default stable
        # Nix rustup puts cargo in ~/.cargo/bin
        export PATH="${HOME}/.cargo/bin:${PATH}"
    else
        echo -e "  ${DIM}Installing Rust toolchain...${NC}"
        curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y --no-modify-path
        . "$CARGO_ENV"
    fi
fi
export PATH="${HOME}/.cargo/bin:${PATH}"

HACKCODE_SRC="${HOME}/.hackcode-src"
if [ -d "$HACKCODE_SRC/.git" ]; then
    git -C "$HACKCODE_SRC" pull --quiet 2>/dev/null || true
else
    [ -d "$HACKCODE_SRC" ] && rm -rf "$HACKCODE_SRC"
    git clone --quiet "https://github.com/${REPO}.git" "$HACKCODE_SRC"
fi
cd "$HACKCODE_SRC/rust"

# On Nix, OpenSSL headers are in the Nix store.  replit.nix sets
# OPENSSL_DIR etc., but when running via curl|bash those env vars
# may not be loaded yet.  Set them explicitly from the Nix store.
if $IN_REPLIT; then
    _OPENSSL=$(nix-build '<nixpkgs>' -A openssl.dev --no-out-link 2>/dev/null || true)
    if [ -n "$_OPENSSL" ]; then
        export OPENSSL_DIR="$_OPENSSL"
        export OPENSSL_INCLUDE_DIR="${_OPENSSL}/include"
        _OPENSSL_OUT=$(nix-build '<nixpkgs>' -A openssl.out --no-out-link 2>/dev/null || true)
        [ -n "$_OPENSSL_OUT" ] && export OPENSSL_LIB_DIR="${_OPENSSL_OUT}/lib"
        export PKG_CONFIG_PATH="${_OPENSSL}/lib/pkgconfig"
    fi
fi

BUILD_LOG=$(mktemp)
echo -e "  ${DIM}Compiling (~200 crates, this may take a few minutes)...${NC}"
set +e
printf "\033[?25l"
cargo build --release -p rusty-claude-cli 2>&1 | tee "$BUILD_LOG" | {
    EST=200
    BUILT=0
    while IFS= read -r line; do
        case "$line" in
            *Compiling*)
                BUILT=$((BUILT + 1))
                PCT=$((BUILT * 100 / EST))
                [ "$PCT" -gt 99 ] && PCT=99
                CRATE=$(echo "$line" | sed 's/.*Compiling \([^ ]*\).*/\1/')
                printf "\r\033[K  ${GREEN}[%3d%%]${NC} Compiling ${DIM}%s${NC}" "$PCT" "$CRATE"
                ;;
            *Finished*)
                printf "\r\033[K  ${GREEN}[100%%]${NC} Build complete\n"
                ;;
        esac
    done
}
printf "\033[?25h"
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
SHELL_NAME=$(basename "${SHELL:-bash}")
RC=""
case "$SHELL_NAME" in
zsh)  RC="${ZDOTDIR:-$HOME}/.zshrc" ;;
bash) RC="$HOME/.bashrc"
[ -f "$HOME/.bash_profile" ] && RC="$HOME/.bash_profile" ;;
fish) RC="$HOME/.config/fish/config.fish" ;;
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

# ─── AI backend ────────────────────────────────────────────────────────────

# Replit: Ollama cannot run (no systemd/root). Use AirLLM — a layer-streaming

# Python server that speaks the same Ollama API on localhost:11434.

# Everywhere else: original Ollama logic, byte-for-byte unchanged.

if $IN_REPLIT; then
echo -e "${GREEN}[4/5]${NC} Installing AirLLM (Ollama-compatible layer-streaming backend)…"

```
# ── Find Python 3.10+ ─────────────────────────────────────────────────
PYTHON=""
for _py in python3.12 python3.11 python3.10 python3; do
    if command -v "$_py" &>/dev/null; then
        _maj=$("$_py" -c "import sys; print(sys.version_info.major)" 2>/dev/null || echo 0)
        _min=$("$_py" -c "import sys; print(sys.version_info.minor)" 2>/dev/null || echo 0)
        if [ "$_maj" -ge 3 ] && [ "$_min" -ge 10 ]; then
            PYTHON="$_py"
            break
        fi
    fi
done
if [ -z "$PYTHON" ]; then
    echo -e "  ${RED}Python 3.10+ not found. Add python3 to replit.nix and rerun.${NC}"
    exit 1
fi
echo -e "  ${GREEN}$("$PYTHON" --version) ✓${NC}"

# ── Locate airllm/ ─────────────────────────────────────────────────────
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]:-install.sh}")" 2>/dev/null && pwd || pwd)"
if [ -f "${SCRIPT_DIR}/airllm/server.py" ]; then
    AIRLLM_PARENT="$SCRIPT_DIR"
else
    # Ensure the repo is cloned so airllm/ is available
    HACKCODE_SRC="${HOME}/.hackcode-src"
    if [ ! -d "$HACKCODE_SRC/.git" ]; then
        git clone --quiet "https://github.com/${REPO}.git" "$HACKCODE_SRC"
    fi
    AIRLLM_PARENT="$HACKCODE_SRC"
fi

# ── Install Python deps ────────────────────────────────────────────────
echo -e "  ${DIM}Installing Python dependencies (CPU torch + safetensors)...${NC}"
# --user so we don't need root; Nix's pip is in the Python package
"$PYTHON" -m pip install --user -q --upgrade pip
"$PYTHON" -m pip install --user -q \
    torch --index-url https://download.pytorch.org/whl/cpu
"$PYTHON" -m pip install --user -q \
    safetensors transformers huggingface_hub tokenizers accelerate
echo -e "  ${GREEN}Python dependencies installed ✓${NC}"

# ── Persist env vars in RC ─────────────────────────────────────────────
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
echo -e "  ${DIM}Models download from HuggingFace on first use (~3-20 GB depending on model)${NC}"
echo -e "  ${DIM}Run: bash run.sh   (starts AirLLM server then launches hackcode)${NC}"
```

else
# ─── Original Ollama + Model logic (unchanged) ──────────────────────
echo -e "${GREEN}[4/5]${NC} Pulling AI model…"
OLLAMA_BIN=""
if command -v ollama &>/dev/null; then
OLLAMA_BIN="ollama"
elif [ -x "/Applications/Ollama.app/Contents/Resources/ollama" ]; then
OLLAMA_BIN="/Applications/Ollama.app/Contents/Resources/ollama"
fi
if [ -n "$OLLAMA_BIN" ]; then
echo -e "  ${GREEN}Ollama found ✓${NC}"
if $OLLAMA_BIN list 2>/dev/null | grep -q "hackcode-uncensored"; then
echo -e "  ${GREEN}hackcode-uncensored model ready ✓${NC}"
else
RAM_GB=8
case "$PLATFORM" in
macos) RAM_GB=$(sysctl -n hw.memsize 2>/dev/null | awk ‘{printf "%d", $1/1073741824}') ;;
linux) RAM_GB=$(awk ‘/MemTotal/{printf "%d", $2/1048576}' /proc/meminfo 2>/dev/null) ;;
esac
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
echo -e "  ${DIM}RAM: ${RAM_GB}GB — pulling ${BOLD}${MODEL_DESC}${NC}"
echo ""
PULLED=false
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
echo -e "  ${RED}Ollama not found${NC} — required for local AI"
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
echo -e "  ${BOLD}hackcode${NC}         ${DIM}# Start hacking${NC}"
echo -e "  ${BOLD}hackcode –help${NC}   ${DIM}# Show all commands${NC}"
echo ""
echo -e "  ${DIM}Open a new terminal or run:${NC}"
echo -e "  ${BOLD}export PATH="$INSTALL_DIR:$PATH"${NC}"
echo -e "${GREEN}━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━${NC}"
echo ""