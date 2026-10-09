# time-budget

A macOS menu bar app that measures real work against a time budget for each type
of work, and tells you when a budget is spent. One open-weight model sorts the
work, it ships inside the app, and no data leaves the Mac.

Status: early. The design is in [`docs/product-spec.md`](docs/product-spec.md) and
is tentative until its first two milestones (a model test and a capture test) are
done.

The current build is a test version. The app captures evidence each minute, and
the OpenJev model sorts each minute into an allocation, on the Mac. The app keeps
the ledger and sends the budget alerts. You can also choose the work type by
hand: both labels go to the capture log, so they can be compared. See
[`docs/manual-test.md`](docs/manual-test.md). The model test (milestone 1) is in
[`docs/model-test.md`](docs/model-test.md).

## Layout

| Path | What is in it |
| --- | --- |
| `docs/product-spec.md` | The product spec: goals, requirements, options, milestones, open questions |
| `docs/manual-test.md` | How to build, run, and check the current Mac app by hand |
| `docs/test-results.md` | What each manual test session showed works, and what is still untested |
| `docs/model-test.md` | Milestone 1: the Swift model against the Python reference, speed, memory, quantization |
| `Sources/TimeBudgetCore/` | Platform-neutral logic: allocations, ledger, alerts, exclude list, slice rules, classification steps, model prompt and math, pinned rules, capture log format |
| `Sources/TimeBudgetModel/` | The OpenJev model on MLX (macOS only) |
| `Sources/ModelCheck/` | `model-check`: runs the model on test slices or a capture log (macOS only) |
| `scripts/` | Model conversion, the Python reference check, and the test slices |
| `Models/` | Converted models from `make model`. Not in git |
| `Sources/TimeBudgetApp/` | The Mac app itself (macOS only): menu bar panel, settings, capture, notifications |
| `App/Info.plist` | The bundle settings that `make app` puts in `.build/TimeBudget.app` |
| `Tests/TimeBudgetCoreTests/` | Tests for the core, using Swift Testing |
| `.devcontainer/` | Linux dev environment with the Swift toolchain |
| `.github/workflows/ci.yml` | CI: `make check` on Linux, build and test on macOS |

## Getting started

Clone, open in the devcontainer, run the checks. Nothing else is required:

```
make check   # format check, build, and run the tests
```

Start the devcontainer with `dcr` (or `dcs` to reuse a running one) from
[`~/code/util`](https://github.com/NickBorgers/util). It adds the shell profile,
the Claude Code and Codex CLIs and logins, `gh`, and this project's Claude memory.
`make fmt` formats the sources in place.

Without a devcontainer: install Swift 6.0 or later and run the same `make` targets.

## Building the Mac app

The Mac app needs macOS 14 or later and full Xcode, not only the Command Line
Tools. Install Xcode from the Mac App Store.

After Xcode finishes installing, run these three commands once, in a real
Terminal. Each needs your password, so an agent session cannot run them for
you:

```
sudo xcode-select -s /Applications/Xcode.app/Contents/Developer
sudo xcodebuild -license accept
sudo xcodebuild -runFirstLaunch
```

Check it worked:

```
xcodebuild -version   # prints a version, instead of a Command Line Tools error
```

Xcode 27 also needs its Metal Toolchain, to build the MLX shaders. Install it
once:

```
xcodebuild -downloadComponent MetalToolchain
```

The classifier model is not in git. Build it once. It downloads about 9 GB from
Hugging Face and needs [uv](https://docs.astral.sh/uv/):

```
make model   # converts OpenJev 4B v5 to Models/openjev-4b-v5 (8-bit, 4.2 GB)
```

Then the same `make` targets as the core build the app too, plus more to run it:

```
make build   # builds TimeBudgetCore, TimeBudgetApp and model-check
make check   # format check, build, and test
make app     # wraps the app in .build/TimeBudget.app, signed ad hoc
make run     # builds the bundle and opens it
make install # copies the bundle to ~/Applications, for Spotlight or Finder
make model-check  # milestone 1: the model on the test slices
make reference    # the same inputs in Python, compared (slow)
```

Without `Models/openjev-4b-v5`, `make app` still builds. The app then has no
classifier, and your selection counts.

Use `make run`, not `swift run`. Notifications and the macOS permissions need
an app bundle. A bundle also makes macOS ask for permissions for Time Budget,
not for your terminal. After a rebuild, an old Accessibility grant can stop
working: run `make reset-permissions`, then grant again.

`Package.swift` guards the app target with `#if os(macOS)`, so the
devcontainer's Linux `swift build` still sees only `TimeBudgetCore`.

## What builds where

The devcontainer is Linux, so it builds only the core. The Mac app itself needs
macOS 14 or later and Xcode: SwiftUI, the Accessibility API, EventKit, and the MLX
model runtime do not exist on Linux. On Linux, `Package.swift` lists no
dependency at all. Keep logic that does not need those in
`TimeBudgetCore`, so it is tested in the devcontainer. CI builds and tests on both.
