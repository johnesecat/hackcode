"""airllm/models.py -- model registry and download helpers."""

from **future** import annotations

import os
from pathlib import Path

# Models are stored in ~/.hackcode/models/ to survive Replit workspace resets

MODELS_DIR = Path(os.environ.get("AIRLLM_MODELS_DIR",
Path.home() / ".hackcode" / "models"))

# Registry: model name → HuggingFace repo

# Names match what hackcode’s setup wizard and Modelfile use.

REGISTRY: dict[str, str] = {
"hackcode-uncensored":  "Qwen/Qwen3-4B",   # default alias
"qwen3:4b":             "Qwen/Qwen3-4B",
"qwen3:8b":             "Qwen/Qwen3-8B",
"qwen3:14b":            "Qwen/Qwen3-14B",
"qwen3:30b":            "Qwen/Qwen3-30B-A3B",
"qwen3:32b":            "Qwen/Qwen3-32B",
# Uncensored variants (same architecture, different finetune)
"tripolskypetr/qwen3.5-uncensored-aggressive:4b":  "Qwen/Qwen3-4B",
"tripolskypetr/qwen3.5-uncensored-aggressive:14b": "Qwen/Qwen3-14B",
"tripolskypetr/qwen3.5-uncensored-aggressive:35b": "Qwen/Qwen3-30B-A3B",
}

def model_dir(name: str) -> Path:
"""Local directory for a downloaded model."""
safe = name.replace("/", "*").replace(":", "*")
return MODELS_DIR / safe

def is_downloaded(name: str) -> bool:
d = model_dir(name)
return d.exists() and (d / "config.json").exists()

def download(name: str) -> Path:
"""
Download model from HuggingFace Hub (safetensors only).
Returns the local directory path.
Raises RuntimeError if huggingface_hub is not installed.
"""
try:
from huggingface_hub import snapshot_download
except ImportError:
raise RuntimeError(
"huggingface_hub not installed.\n"
"Run: pip install –user huggingface_hub"
)

```
repo = REGISTRY.get(name)
if repo is None:
    # Treat the name itself as a HuggingFace repo ID
    repo = name

dest = model_dir(name)
dest.mkdir(parents=True, exist_ok=True)

print(f"[AirLLM] Downloading {repo} → {dest}", flush=True)
path = snapshot_download(
    repo_id=repo,
    local_dir=str(dest),
    local_dir_use_symlinks=False,
    # Skip non-safetensors weight formats to save disk space
    ignore_patterns=["*.bin", "*.pt", "flax_*", "tf_*", "onnx/*"],
)
return Path(path)
```

def resolve(name: str) -> Path:
"""Return local model path, downloading if necessary."""
if is_downloaded(name):
return model_dir(name)
return download(name)

def list_local() -> list[dict]:
"""Return Ollama-compatible model list for GET /api/tags."""
found = []
for name in REGISTRY:
d = model_dir(name)
if d.exists() and (d / "config.json").exists():
size = sum(f.stat().st_size for f in d.rglob("*") if f.is_file())
found.append({
"name":        name,
"model":       name,
"modified_at": "2025-01-01T00:00:00Z",
"size":        size,
"digest":      "airllm",
"details": {
"format":  "safetensors",
"family":  "qwen",
"parameter_size": name,
"quantization_level": "INT8" if os.environ.get("AIRLLM_INT8", "1") == "1" else "FP16",
},
})
return found