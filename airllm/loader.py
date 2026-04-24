"""
airllm/loader.py — Layer-streaming causal-LM inference.

Loads one transformer block at a time from memory-mapped safetensors,
runs the forward pass, then immediately frees the weights before loading
the next block.  Peak RAM = one block + hidden states, independent of
total model size.

Supports:
Qwen2 / Qwen2.5 / Qwen3  (GQA, SwiGLU, RoPE, optional q/k head norms)
LLaMA-2/3, Mistral, Gemma 2  (same weight naming convention)

Quantisation:
AIRLLM_INT8=1 (default)  →  symmetric per-row int8, ~2× RAM reduction
AIRLLM_INT8=0            →  fp16, full precision
"""
from **future** import annotations
import gc
import json
import math
import os
from pathlib import Path
from typing import Iterator

import torch
import torch.nn.functional as F
from safetensors import safe_open
from transformers import AutoConfig, AutoTokenizer

INT8 = os.environ.get("AIRLLM_INT8", "1") == "1"

# ── Math ───────────────────────────────────────────────────────────────────

def _rms_norm(x: torch.Tensor, w: torch.Tensor, eps: float) -> torch.Tensor:
    return w * x * torch.rsqrt(x.pow(2).mean(-1, keepdim=True) + eps)

def _rotate_half(x: torch.Tensor) -> torch.Tensor:
    h = x.shape[-1] // 2
    return torch.cat([-x[…, h:], x[…, :h]], dim=-1)

def _apply_rope(q: torch.Tensor, k: torch.Tensor,
    seq: int, head_dim: int, theta: float) -> tuple[torch.Tensor, torch.Tensor]:
    dev = q.device
    inv = 1.0 / (theta ** (torch.arange(0, head_dim, 2, dtype=torch.float32, device=dev) / head_dim))
    t   = torch.arange(seq, dtype=torch.float32, device=dev)
    emb = torch.cat([torch.outer(t, inv)] * 2, dim=-1)
    cos, sin = emb.cos()[None, None], emb.sin()[None, None]
    return q * cos + _rotate_half(q) * sin, k * cos + _rotate_half(k) * sin

# ── Quantisation ───────────────────────────────────────────────────────────

def _quant(t: torch.Tensor) -> tuple[torch.Tensor, torch.Tensor]:
    s = t.abs().max(-1, keepdim=True).values.clamp(min=1e-8) / 127.0
    return (t / s).round().clamp(-128, 127).to(torch.int8), s.to(torch.float16)

def _dequant(w: torch.Tensor, s: torch.Tensor) -> torch.Tensor:
    return w.to(torch.float16) * s

def _linear(x: torch.Tensor, w: torch.Tensor,
    s: torch.Tensor | None, b: torch.Tensor | None = None) -> torch.Tensor:
    return F.linear(x, _dequant(w, s) if s is not None else w, b)

# ── Shard index ─────────────────────────────────────────────────────────────

def _index(model_path: Path) -> dict[str, Path]:
    idx = model_path / "model.safetensors.index.json"
    if idx.exists():
        with open(idx) as f:
            return {k: model_path / v for k, v in json.load(f)["weight_map"].items()}
    single = model_path / "model.safetensors"
    if single.exists():
        with safe_open(single, framework="pt") as f:
            return {k: single for k in f.keys()}
    raise FileNotFoundError(f"No safetensors weights in {model_path}")

# ── Loader ──────────────────────────────────────────────────────────────────

class AirLLMLoader:
    def __init__(self, model_path: str | Path):
        self.path = Path(model_path)
        self.cfg  = AutoConfig.from_pretrained(self.path)
        self.tok  = AutoTokenizer.from_pretrained(self.path)
        self._idx = _index(self.path)
    
    
        c = self.cfg
        self.n_layers  = c.num_hidden_layers
        self.n_heads   = c.num_attention_heads
        self.n_kv      = getattr(c, "num_key_value_heads", self.n_heads)
        self.hidden    = c.hidden_size
        self.head_dim  = self.hidden // self.n_heads
        self.theta     = float(getattr(c, "rope_theta", 1_000_000.0))
        self.eps       = float(getattr(c, "rms_norm_eps", 1e-6))
        self.eos       = self.tok.eos_token_id or -1
    
    # ── Tensor helpers ──────────────────────────────────────────────────────

    def _load(self, name: str) -> tuple[torch.Tensor, torch.Tensor | None]:
        with safe_open(self._idx[name], framework="pt", device="cpu") as f:
            t = f.get_tensor(name).to(torch.float16)
        return _quant(t) if INT8 else (t, None)
    
    def _maybe(self, name: str) -> tuple[torch.Tensor | None, torch.Tensor | None]:
        return self._load(name) if name in self._idx else (None, None)

    # ── Forward blocks ──────────────────────────────────────────────────────

    def _embed(self, ids: torch.Tensor) -> torch.Tensor:
        w, s = self._load("model.embed_tokens.weight")
        out  = F.embedding(ids, _dequant(w, s) if s is not None else w)
        del w, s; gc.collect()
        return out
    
    def _attn(self, h: torch.Tensor, i: int, seq: int) -> torch.Tensor:
        p   = f"model.layers.{i}.self_attn"
        bsz = h.shape[0]
    
        qw, qs = self._load(f"{p}.q_proj.weight")
        kw, ks = self._load(f"{p}.k_proj.weight")
        vw, vs = self._load(f"{p}.v_proj.weight")
        qb, _  = self._maybe(f"{p}.q_proj.bias")
        kb, _  = self._maybe(f"{p}.k_proj.bias")
        vb, _  = self._maybe(f"{p}.v_proj.bias")
    
        q = _linear(h, qw, qs, qb).view(bsz, seq, self.n_heads, self.head_dim).transpose(1, 2)
        k = _linear(h, kw, ks, kb).view(bsz, seq, self.n_kv,   self.head_dim).transpose(1, 2)
        v = _linear(h, vw, vs, vb).view(bsz, seq, self.n_kv,   self.head_dim).transpose(1, 2)
        del qw, qs, kw, ks, vw, vs, qb, kb, vb; gc.collect()
    
        # Qwen3 per-head norms
        for attr, tensor_name, norm_name in [("q", "q", f"{p}.q_norm.weight"),
                                              ("k", "k", f"{p}.k_norm.weight")]:
            nw, _ = self._maybe(norm_name)
            if nw is not None:
                if attr == "q": q = _rms_norm(q, nw.to(q.dtype), self.eps)
                else:           k = _rms_norm(k, nw.to(k.dtype), self.eps)
                del nw; gc.collect()
    
        q, k = _apply_rope(q, k, seq, self.head_dim, self.theta)
    
        if self.n_kv != self.n_heads:
            g = self.n_heads // self.n_kv
            k = k.repeat_interleave(g, 1)
            v = v.repeat_interleave(g, 1)
    
        try:
            out = F.scaled_dot_product_attention(q, k, v, is_causal=(seq > 1))
        except Exception:
            sc  = math.sqrt(self.head_dim)
            a   = torch.matmul(q, k.transpose(-2, -1)) / sc
            if seq > 1:
                a += torch.triu(torch.full((seq, seq), float("-inf")), 1).to(a.device)
            a   = F.softmax(a.float(), dim=-1).to(q.dtype)
            out = torch.matmul(a, v); del a
        del q, k, v; gc.collect()
    
        out = out.transpose(1, 2).contiguous().view(bsz, seq, self.hidden)
        ow, os_ = self._load(f"{p}.o_proj.weight")
        out = _linear(out, ow, os_)
        del ow, os_; gc.collect()
        return out
    
    def _mlp(self, h: torch.Tensor, i: int) -> torch.Tensor:
        p      = f"model.layers.{i}.mlp"
        gw, gs = self._load(f"{p}.gate_proj.weight")
        uw, us = self._load(f"{p}.up_proj.weight")
        mid    = F.silu(_linear(h, gw, gs)) * _linear(h, uw, us)
        del gw, gs, uw, us; gc.collect()
        dw, ds = self._load(f"{p}.down_proj.weight")
        out    = _linear(mid, dw, ds)
        del dw, ds, mid; gc.collect()
        return out
    
    def _block(self, h: torch.Tensor, i: int) -> torch.Tensor:
        p   = f"model.layers.{i}"
        seq = h.shape[1]
        nw, _ = self._load(f"{p}.input_layernorm.weight")
        h = h + self._attn(_rms_norm(h, nw.to(h.dtype), self.eps), i, seq)
        del nw; gc.collect()
        nw, _ = self._load(f"{p}.post_attention_layernorm.weight")
        h = h + self._mlp(_rms_norm(h, nw.to(h.dtype), self.eps), i)
        del nw; gc.collect()
        return h
    
    def _head(self, h: torch.Tensor) -> torch.Tensor:
        nw, _ = self._load("model.norm.weight")
        h     = _rms_norm(h[:, -1:, :], nw.to(h.dtype), self.eps)
        del nw; gc.collect()
        key      = "lm_head.weight" if "lm_head.weight" in self._idx else "model.embed_tokens.weight"
        lw, ls   = self._load(key)
        logits   = _linear(h, lw, ls).squeeze(1)
        del lw, ls; gc.collect()
        return logits
    
    # ── Sampling ────────────────────────────────────────────────────────────
    
    @staticmethod
    def _sample(logits: torch.Tensor, temp: float, top_p: float, top_k: int) -> int:
        logits = logits.float()
        if temp <= 0:
            return int(logits.argmax(-1).item())
        logits /= temp
        if top_k > 0:
            v, _ = torch.topk(logits, min(top_k, logits.size(-1)))
            logits = logits.masked_fill(logits < v[..., -1:], float("-inf"))
        probs = F.softmax(logits, dim=-1)
        if top_p < 1.0:
            sp, si = torch.sort(probs, descending=True)
            sp[sp.cumsum(-1) - sp > top_p] = 0.0
            sp /= sp.sum()
            probs = torch.zeros_like(probs).scatter_(-1, si, sp)
        return int(torch.multinomial(probs, 1).item())
    
    # ── Public API ──────────────────────────────────────────────────────────
    
    def generate(self,
                 messages: list[dict],
                 max_new_tokens: int = 512,
                 temperature: float  = 0.7,
                 top_p: float        = 0.95,
                 top_k: int          = 40) -> Iterator[str]:
        """Layer-stream generation; yields decoded token strings."""
        prompt = self.tok.apply_chat_template(
            messages, tokenize=False, add_generation_prompt=True)
        ids = self.tok(prompt, return_tensors="pt").input_ids
    
        for _ in range(max_new_tokens):
            h = self._embed(ids)
            for i in range(self.n_layers):
                h = self._block(h, i)
            logits  = self._head(h)
            del h; gc.collect()
    
            nxt = self._sample(logits[0], temperature, top_p, top_k)
            del logits; gc.collect()
    
            if nxt == self.eos:
                break
    
            ids = torch.cat([ids, torch.tensor([[nxt]])], dim=-1)
            yield self.tok.decode([nxt], skip_special_tokens=True,
                                  clean_up_tokenization_spaces=False)
            gc.collect()