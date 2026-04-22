#!/usr/bin/env bash

# run.sh -- Replit launcher: start AirLLM server, then exec hackcode.

# On non-Replit systems just run: hackcode

set -euo pipefail

INSTALL_DIR="${HOME}/.local/bin"
export PATH="${INSTALL_DIR}:${HOME}/.cargo/bin:${HOME}/.local/bin:${PATH}"
export OLLAMA_HOST="http://127.0.0.1:11434"

# Locate airllm/ relative to this script

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "${SCRIPT_DIR}/airllm/server.py" ]; then
AIRLLM_PARENT="${SCRIPT_DIR}"
elif [ -f "${HOME}/.hackcode-src/airllm/server.py" ]; then
AIRLLM_PARENT="${HOME}/.hackcode-src"
else
echo "airllm/ not found -- run install.sh first" >&2
exit 1
fi
export PYTHONPATH="${AIRLLM_PARENT}:${PYTHONPATH:-}"

# Resolve Python

PYTHON=""
for _py in python3.12 python3.11 python3.10 python3; do
command -v "$_py" &>/dev/null && PYTHON="$_py" && break
done
[ -z "$PYTHON" ] && { echo "python3 not found" >&2; exit 1; }

# Start AirLLM server if not already running

if ! curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1; then
mkdir -p "${HOME}/.hackcode"
printf ‘\033[38;2;0;255;65m[AirLLM]\033[0m Starting layer-streaming server…\n’
nohup "$PYTHON" -m airllm.server   
>"${HOME}/.hackcode/airllm.log" 2>&1 &
# Wait up to 30 s
for _i in $(seq 1 30); do
sleep 1
curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1 && break
done
curl -sf "${OLLAMA_HOST}/api/tags" >/dev/null 2>&1   
&& printf ‘\033[38;2;0;255;65m[AirLLM]\033[0m Server ready\n’   
|| { printf ‘\033[0;31m[AirLLM] Server failed to start. Check ~/.hackcode/airllm.log\033[0m\n’; exit 1; }
else
printf ‘\033[2m[AirLLM] Server already running\033[0m\n’
fi

exec hackcode "$@"  