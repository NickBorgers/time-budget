# Model test (milestone 1)

**Summary.** The Swift port of OpenJev gives the same labels as the Python
reference. On 18 test slices, every winning option matched, and no probability
differed by more than 0.025. The default is the 4B v5 checkpoint at 8 bits: about
2.1 s and 4.9 GB for each slice on an M4. Two spec values changed. 4-bit
quantization breaks the classifier, so the model is 8-bit, and 4.2 GB on disk. The
memory use, 4.9 GB, is within the 5 GB target, which was raised from 4 GB after
this test.

How to repeat it:

```
make model         # download and convert to Models/openjev-4b-v5 (needs uv)
make model-check   # the Swift classifier on scripts/model-check-cases.jsonl
make reference     # the same inputs in Python (transformers, float32, CPU), compared
```

## Setup

| Item | Value |
| --- | --- |
| Date | 2026-10-08 |
| Mac | Apple M4, 32 GB, macOS 26.6.2, Xcode 27.0, Swift 6.4 |
| Repo | `AlexWortega/openjev` at commit `a20448012c213128955ca0c693e7c943865cab77` |
| Runtime | mlx-swift 0.32.3, mlx-swift-lm 3.32.3 (`Qwen35Model`), swift-transformers 1.3.4 (tokenizer) |
| Conversion | `scripts/convert_openjev.py`: mlx-lm 0.32.0, 8 bits, group size 64. The `score` head stays float32 |
| Reference | transformers 5.19, the original bf16 weights in float32 on the CPU |
| Test set | `scripts/model-check-cases.jsonl`: 18 invented slices, labeled by hand. Five options each: the four starter allocations and `None of these` |

## Results

| Measure | 4B v5, 8-bit | 2B v5, 8-bit |
| --- | --- | --- |
| Same winning option as the Python reference | 18 of 18 | not run |
| Largest probability difference to the reference | 0.025 | not run |
| Inputs with different token ids | 0 of 90 | not run |
| Same label as the hand label | 16 of 18 | 9 of 18 |
| Time for one slice, release build (median / slowest) | 1.97 s / 5.0 s | 0.91 s / 1.1 s |
| Model load | 3.5 s | 1.5 s |
| Process footprint with the model loaded | 4.9 GB | 2.2 GB |
| Size on disk | 4.2 GB | 1.9 GB |

The slowest 4B slice is the first one, which also warms up MLX. The two 4B
misses are both Interrupts. The spec already says that an interrupt is a pattern
in time, and that the screen content does not show it.

## Quantization

The spec planned 4 bits. 4 bits does not work for this model as a classifier.
The test compared each quantization with the bf16 MLX model, on four slices with
five options each:

| Variant (2B unless noted) | Same winner as bf16 | Largest probability difference | Size |
| --- | --- | --- | --- |
| 4-bit, group 64 | 2 of 4 | 0.68 | 1.06 GB |
| 4-bit, group 32 | 1 of 4 | 0.61 | 1.18 GB |
| 4-bit, embedding kept in bf16 | 2 of 4 | 0.68 | 1.79 GB |
| 4-bit, MLP layers only | 4 of 4 | 0.53 | 2.46 GB |
| 6-bit | 3 of 4 | 0.07 | 1.53 GB |
| 8-bit | 4 of 4 | 0.02 | 2.00 GB |
| 4B, 6-bit | 4 of 4 | 0.07 | 3.42 GB |
| 4B, 8-bit | 4 of 4 | 0.03 | 4.47 GB |

At 4 bits the scores go almost flat: every option gets 10 to 40%. The unquantized
MLX model matched transformers to the third decimal, so the conversion itself
is correct.

## How the port works

- The converter loads the text model with mlx-lm, quantizes it, and saves the
  3-by-hidden `score` head on its own. The vision tower is dropped.
- The app replaces the model's `lm_head` with the `score` head. One forward pass
  then returns the three label logits, and the app reads the last position.
- The shared-prefix method from the model card: the inputs of one slice share the
  premise. The app runs the shared tokens once, then continues each option from a
  copy of that state. The shared part is found on the token ids
  (`TokenPrefix`), so the result is the same as one full pass for each option.
- The probability math is `Decision.optionProbabilities` in the core: a softmax
  over each row, the entailment column, then a normalization over the options.
  It is the same as `openjev_decide.py`.

## Checkpoints

The spec names a `qwen3.5-0.8b-nli-v5` checkpoint. The repo has none. The small
checkpoints are `qwen3.5-2b-nli-v5` and `qwen3.5-0.8b-nli-v2s-long`. The 2B v5
checkpoint is fast, but it got half of the test slices wrong, and often fell
below the 0.6 threshold.

## What this test does not show

- 18 slices is a small test set. The spec's proposed target is 99% agreement on a
  fixed set. A larger set from real capture logs is the next step:
  `model-check --log <slices.jsonl> --state <state.json>` scores a capture log
  and compares with the hand labels. Its output holds screen text, so keep it on
  the Mac.
- Accuracy on real work. That is milestone 2.
- CPU use over a work day. The model runs only when a minute's evidence changed,
  but the share of changed minutes is not measured yet.
- An 8 GB or 16 GB Mac. The 4B model needs about 5 GB while it runs.
