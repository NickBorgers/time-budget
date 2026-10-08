# time-budget

A macOS menu bar app that measures real work against a time budget for each type
of work, and tells you when a budget is spent. One open-weight model sorts the
work, it ships inside the app, and no data leaves the Mac.

Status: early. The design is in [`docs/product-spec.md`](docs/product-spec.md) and
is tentative until its first two milestones (a model test and a capture test) are
done. The code here so far is the platform-neutral core.

## Layout

| Path | What is in it |
| --- | --- |
| `docs/product-spec.md` | The product spec: goals, requirements, options, milestones, open questions |
| `Sources/TimeBudgetCore/` | Platform-neutral logic: allocations, budget status, alert thresholds |
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

## What builds where

The devcontainer is Linux, so it builds only the core. The Mac app itself needs
macOS 14 or later and Xcode: SwiftUI, the Accessibility API, EventKit, and the MLX
model runtime do not exist on Linux. Keep logic that does not need those in
`TimeBudgetCore`, so it is tested in the devcontainer. CI builds and tests on both.
