# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["torch>=2.6", "transformers>=5.17", "mlx==0.32.3", "mlx-lm==0.32.0", "huggingface_hub>=1.0"]
# ///
"""Score the inputs of a `model-check` run again in Python, and compare (milestone 1).

`swift run model-check` writes one JSON line per slice: the model inputs it built,
the logits it got from the Swift port, and the token ids. This script scores the
same input strings with a reference, and reports how often the winning option
agrees. The spec's proposed acceptance target is 99%.

References:
- `transformers` (default): the original bf16 checkpoint, run in float32 on the
  CPU. This is the reference the spec asks for.
- `mlx`: the converted 4-bit folder, run with mlx-lm in Python. If this agrees
  with transformers but Swift does not, the bug is in the Swift port. If this
  also disagrees, the cause is the conversion or the quantization.

Usage:
    uv run scripts/openjev_reference.py results.jsonl --checkpoint qwen3.5-4b-nli-v5
    uv run scripts/openjev_reference.py results.jsonl --mlx Models/openjev-4b-v5-4bit
"""

import argparse
import json
import math
import time
from pathlib import Path

REPO = "AlexWortega/openjev"
ENT = 1


def option_probabilities(rows):
    """The same math as `Decision.optionProbabilities` in TimeBudgetCore."""
    ent = []
    for row in rows:
        top = max(row)
        exps = [math.exp(x - top) for x in row]
        ent.append(exps[ENT] / sum(exps))
    total = sum(ent)
    return [p / total for p in ent]


class TransformersReference:
    def __init__(self, checkpoint, source):
        import torch
        from transformers import AutoModelForSequenceClassification, AutoTokenizer

        kw = {"subfolder": checkpoint}
        path = str(source) if source else REPO
        self.torch = torch
        self.tok = AutoTokenizer.from_pretrained(path, **kw)
        self.model = AutoModelForSequenceClassification.from_pretrained(path, dtype=torch.float32, **kw).eval()

    def tokens(self, text):
        return self.tok(text, add_special_tokens=True)["input_ids"]

    def logits(self, text):
        with self.torch.no_grad():
            ids = self.torch.tensor([self.tokens(text)])
            return self.model(input_ids=ids).logits[0].tolist()


class MLXReference:
    def __init__(self, folder):
        import mlx.core as mx
        from mlx_lm.utils import load_model, load_tokenizer

        self.mx = mx
        self.model, _ = load_model(Path(folder))
        self.tok = load_tokenizer(Path(folder))
        self.score = mx.load(str(Path(folder) / "score.safetensors"))["weight"]

    def tokens(self, text):
        return self.tok.encode(text, add_special_tokens=True)

    def logits(self, text):
        mx = self.mx
        hidden = self.model.language_model.model(mx.array([self.tokens(text)]))
        out = hidden[0, -1].astype(mx.float32) @ self.score.T
        return out.tolist()


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("results", type=Path, help="JSON lines from `model-check --out`")
    parser.add_argument("--checkpoint", default="qwen3.5-4b-nli-v5")
    parser.add_argument("--source", type=Path, help="a local copy of the repo")
    parser.add_argument("--mlx", type=Path, help="score with this converted folder instead")
    parser.add_argument("--limit", type=int, default=None)
    args = parser.parse_args()

    ref = MLXReference(args.mlx) if args.mlx else TransformersReference(args.checkpoint, args.source)
    rows = [json.loads(line) for line in args.results.read_text().splitlines() if line.strip()]
    rows = [r for r in rows if r.get("inputs")][: args.limit]

    agree, token_mismatch, worst = 0, 0, 0.0
    started = time.time()
    for r in rows:
        logits = [ref.logits(text) for text in r["inputs"]]
        for text, ids in zip(r["inputs"], r["tokens"]):
            if ref.tokens(text) != ids:
                token_mismatch += 1
        p_ref = option_probabilities(logits)
        p_swift = r["probabilities"]
        same = p_ref.index(max(p_ref)) == p_swift.index(max(p_swift))
        agree += same
        diff = max(abs(a - b) for a, b in zip(p_ref, p_swift))
        worst = max(worst, diff)
        print(f"{r['case']:<40} {'same' if same else 'DIFFERENT':<9} "
              f"largest probability difference {diff:.3f}")

    n = len(rows)
    print()
    print(f"Slices: {n}. Same winning option: {agree} ({100 * agree / max(n, 1):.1f}%).")
    print(f"Largest probability difference: {worst:.3f}.")
    print(f"Inputs whose token ids differ: {token_mismatch}.")
    print(f"Reference time: {time.time() - started:.0f} s.")


if __name__ == "__main__":
    main()
