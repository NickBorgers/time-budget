# /// script
# requires-python = ">=3.11,<3.14"
# dependencies = ["mlx==0.32.3", "mlx-lm==0.32.0", "huggingface_hub>=1.0"]
# ///
"""Convert an OpenJev checkpoint to an 8-bit MLX folder that the app loads.

The checkpoint is Qwen3_5ForSequenceClassification: the Qwen3.5 text model, a
vision tower, and a `score` head (3 x hidden) that reads the hidden state of the
last token. The app needs only the text model and the head.

The output folder holds:

- `model.safetensors` and `config.json`: the text model, quantized by mlx-lm
  the same way as the mlx-community Qwen3.5 conversions. mlx-swift-lm loads it
  with `Qwen35Model`.
- `score.safetensors`: the head, unquantized, as `weight`.
- the tokenizer files, and the model card's license.

The default is 8 bits. 4 bits breaks the classifier: on test slices the
scores went almost flat, and half of the winning options changed. 8 bits stays
within 0.03 of the bf16 scores. See docs/model-test.md.

Usage:
    uv run scripts/convert_openjev.py qwen3.5-4b-nli-v5 Models/openjev-4b-v5

The script downloads the checkpoint into the Hugging Face cache if it is not
there. This is a build step: the app itself never downloads anything.
"""

import argparse
import json
import shutil
from pathlib import Path

import mlx.core as mx
from huggingface_hub import snapshot_download
from mlx_lm.utils import _get_classes, quantize_model, save_config, save_model

REPO = "AlexWortega/openjev"
TOKENIZER_FILES = ["tokenizer.json", "tokenizer_config.json", "chat_template.jinja"]


def main():
    parser = argparse.ArgumentParser(description=__doc__.split("\n")[0])
    parser.add_argument("checkpoint", help="subfolder of the repo, e.g. qwen3.5-4b-nli-v5")
    parser.add_argument("output", type=Path)
    parser.add_argument("--revision", default=None, help="a commit of the repo, for a repeatable build")
    parser.add_argument("--source", type=Path, default=None,
                        help="a local copy of the repo, instead of the Hugging Face cache")
    parser.add_argument("--bits", type=int, default=8)
    parser.add_argument("--group-size", type=int, default=64)
    args = parser.parse_args()

    root = args.source or Path(snapshot_download(
        REPO, revision=args.revision, allow_patterns=[f"{args.checkpoint}/*", "README.md"]))
    source = root / args.checkpoint
    config = json.loads((source / "config.json").read_text())
    assert config["architectures"] == ["Qwen3_5ForSequenceClassification"], config["architectures"]
    assert config["id2label"] == {"0": "contradiction", "1": "entailment", "2": "neutral"}, config["id2label"]

    weights = {}
    for f in sorted(source.glob("*.safetensors")):
        weights.update(mx.load(str(f)))
    score = weights.pop("score.weight")
    assert score.shape == (3, config["text_config"]["hidden_size"]), score.shape
    assert not any(k.startswith("score.") for k in weights), "the head has more than one weight"

    model_class, args_class = _get_classes(config)
    model = model_class(args_class.from_dict(config))
    weights = model.sanitize(weights)
    # strict: every weight of the text model must come from the checkpoint.
    model.load_weights(list(weights.items()), strict=True)
    mx.eval(model.parameters())

    model, config = quantize_model(model, config, args.group_size, args.bits)

    out = args.output
    if out.exists():
        shutil.rmtree(out)
    out.mkdir(parents=True)
    save_model(out, model, donate_model=True)
    save_config(config, config_path=out / "config.json")
    mx.save_safetensors(str(out / "score.safetensors"), {"weight": score.astype(mx.float32)})
    for name in TOKENIZER_FILES:
        if (source / name).exists():
            shutil.copy(source / name, out / name)
    if (root / "README.md").exists():
        shutil.copy(root / "README.md", out / "MODEL_CARD.md")
    (out / "SOURCE.json").write_text(
        json.dumps(
            {"repo": REPO, "checkpoint": args.checkpoint, "revision": args.revision or "main",
             "bits": args.bits, "group_size": args.group_size},
            indent=2) + "\n")
    print(f"Wrote {out}")


if __name__ == "__main__":
    main()
