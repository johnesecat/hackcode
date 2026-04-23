“”“airllm/models.py — Model registry and HuggingFace download.”””
from **future** import annotations
import os
from pathlib import Path

MODELS_DIR = Path(os.environ.get(“AIRLLM_MODELS_DIR”,
Path.home() / “.hackcode” / “models”))

# Maps names hackcode uses → HuggingFace repo

REGISTRY: dict[str, str] = {
“hackcode-uncensored”:                                    “Qwen/Qwen3-4B”,
“qwen3:4b”:                                               “Qwen/Qwen3-4B”,
“qwen3:8b”:                                               “Qwen/Qwen3-8B”,
“qwen3:14b”:                                              “Qwen/Qwen3-14B”,
“qwen3:30b”:                                              “Qwen/Qwen3-30B-A3B”,
“qwen3:32b”:                                              “Qwen/Qwen3-32B”,
“tripolskypetr/qwen3.5-uncensored-aggressive:4b”:  “Qwen/Qwen3-4B”,
“tripolskypetr/qwen3.5-uncensored-aggressive:14b”: “Qwen/Qwen3-14B”,
“tripolskypetr/qwen3.5-uncensored-aggressive:35b”: “Qwen/Qwen3-30B-A3B”,
}

def *dir(name: str) -> Path:
return MODELS_DIR / name.replace(”/”, “*”).replace(”:”, “_”)

def is_downloaded(name: str) -> bool:
d = _dir(name)
return d.exists() and (d / “config.json”).exists()

def download(name: str) -> Path:
try:
from huggingface_hub import snapshot_download
except ImportError:
raise RuntimeError(“Run: pip install –user huggingface_hub”)
repo = REGISTRY.get(name, name)
dest = *dir(name)
dest.mkdir(parents=True, exist_ok=True)
print(f”[AirLLM] Downloading {repo} → {dest}”, flush=True)
path = snapshot_download(
repo_id=repo,
local_dir=str(dest),
local_dir_use_symlinks=False,
ignore_patterns=[”*.bin”, “*.pt”, “flax**”, “tf_*”, “onnx/*”],
)
return Path(path)

def resolve(name: str) -> Path:
if is_downloaded(name):
return _dir(name)
return download(name)

def list_local() -> list[dict]:
found = []
for name in REGISTRY:
d = _dir(name)
if d.exists() and (d / “config.json”).exists():
size = sum(f.stat().st_size for f in d.rglob(”*”) if f.is_file())
found.append({
“name”: name, “model”: name,
“modified_at”: “2025-01-01T00:00:00Z”,
“size”: size, “digest”: “airllm”,
“details”: {“format”: “safetensors”, “family”: “qwen”,
“parameter_size”: name,
“quantization_level”: “INT8” if os.environ.get(“AIRLLM_INT8”,“1”)==“1” else “FP16”},
})
return found