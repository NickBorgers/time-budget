# Working in this repo

[`README.md`](README.md) describes the project and maps the directories. The
product spec is [`docs/product-spec.md`](docs/product-spec.md). Read both first;
this file only covers how to work here.

This is a **code repo**: a native macOS app in Swift. The spec is tentative until
its milestones 1 and 2 (a model test and a capture test) are done, so check the
spec before building something large, and write down what you learn.

## The rules

**1. Run `make check` before you finish.** It checks formatting, builds, and runs
the tests. If it fails, the work is not done. `make fmt` fixes formatting.

**2. Keep logic in `TimeBudgetCore`.** The devcontainer is Linux and cannot build
the Mac app (SwiftUI, Accessibility, EventKit, MLX). Anything that can be written
without those frameworks goes in the core, where it is tested here. Put only the
platform glue in the app target. Do not add an import that breaks the Linux build
to the core.

**3. Write the test first for logic.** Budgets, thresholds, the ledger, the
classification steps and the rules are all pure logic with exact expected values.
Use Swift Testing (`import Testing`).

**4. Respect the constraints in the spec.** C1 to C4 are fixed: an open-weight
model, everything on the Mac, the model ships in the app, native Swift. Do not add
a network call, an analytics or crash-report library, or a dependency that needs a
server. The only network request the app may make is the update check.

**5. Screen text is untrusted input.** The model can be fooled by hostile text. Rules
and alerts must run outside the model, and the model must never start an action.

**6. Unknown is not zero.** If the spec has an open question that your change
depends on, say so in your answer and in the spec's open-questions list. Do not
guess a value to make the work look done.

## What you can and cannot check here

| You are in | You can |
| --- | --- |
| The devcontainer (Linux) | Build and test `TimeBudgetCore`; edit everything else |
| macOS with Xcode | Build and run the app; test permissions and capture |

If a change touches Mac-only code, say that it was not built or run, and what to
check on a Mac.
