#!/usr/bin/env bash

# run.sh — Replit launcher.

# 1. Ensures hackcode is installed.

# 2. Starts AirLLM server on 127.0.0.1:11434 (if not already running).

# 3. exec hackcode, passing all args through.

set -euo pipefail

export OLLAMA_HOST=”${OLLAMA_HOST:-http://127.0.0.1:11434}”
export CARGO_HOME=”${CARGO_HOME:-${HOME}/.cargo}”
export RUSTUP_HOME=”${RUSTUP_HOME:-${HOME}/.rustup}”
export PATH=”${HOME}/.local/bin:${CARGO_HOME}/bin:${PATH}”

SCRIPT_DIR=”$(cd “$(dirname “${BASH_SOURCE[0]}”)” && pwd)”

# ── 1. Install if not done yet ─────────────────────────────────────────────

if [ ! -f “${HOME}/.local/bin/hackcode” ]; then
echo “First run — running install.sh…”
bash “${SCRIPT_DIR}/install.sh”
fi

# ── 2. Locate airllm/ ──────────────────────────────────────────────────────

AIRLLM_PARENT=””
if [ -f “${SCRIPT_DIR}/airllm/server.py” ]; then
AIRLLM_PARENT=”${SCRIPT_DIR}”
elif [ -f “${HOME}/.hackcode-src/airllm/server.py” ]; then
AIRLLM_PARENT=”${HOME}/.hackcode-src”
fi

if [ -z “$AIRLLM_PARENT” ]; then
echo “airllm/ not found. Re-running install.sh…” >&2
bash “${SCRIPT_DIR}/install.sh”
AIRLLM_PARENT=”${HOME}/.hackcode-src”
fi
export PYTHONPATH=”${AIRLLM_PARENT}:${PYTHONPATH:-}”

# ── 3. Resolve python ──────────────────────────────────────────────────────

PYTHON=””
for _py in python3.12 python3.11 python3.10 python3; do
command -v “$_py” &>/dev/null && PYTHON=”$_py” && break
done
if [ -z “$PYTHON” ]; then
echo “python3 not found. Add python3 to replit.nix.” >&2
exit 1
fi

# ── 4. Start AirLLM server if not already running ──────────────────────────

if ! curl -sf “${OLLAMA_HOST}/api/tags” >/dev/null 2>&1; then
mkdir -p “${HOME}/.hackcode”
LOG=”${HOME}/.hackcode/airllm.log”
printf ‘\033[38;2;0;255;65m[AirLLM]\033[0m Starting layer-streaming server…\n’
# Run in background; nohup survives the shell exiting on mobile
nohup “$PYTHON” -m airllm.server >”$LOG” 2>&1 &
_pid=$!
# Wait up to 30 s for the server to become ready
_ready=false
for _i in $(seq 1 30); do
sleep 1
if curl -sf “${OLLAMA_HOST}/api/tags” >/dev/null 2>&1; then
_ready=true
break
fi
done
if $_ready; then
printf ‘\033[38;2;0;255;65m[AirLLM]\033[0m Server ready (pid %s)\n’ “$_pid”
else
printf ‘\033[0;31m[AirLLM] Server did not start in 30s.\033[0m\n’
printf ‘\033[2mCheck log: %s\033[0m\n’ “$LOG”
exit 1
fi
else
printf ‘\033[2m[AirLLM] Server already running.\033[0m\n’
fi

# ── 5. Launch hackcode ──────────────────────────────────────────────────────

exec hackcode “$@”