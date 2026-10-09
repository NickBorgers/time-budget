.PHONY: all check build test app run install reset-permissions model model-check reference lint fmt clean

all: check

## check: format check, build, and run the tests (what CI runs)
check: lint build test

## build: compile the core, and the Mac app on macOS
build:
	swift build

APP := .build/TimeBudget.app
# The classifier model that `make app` puts in the bundle. `make model` builds
# it. Override: make model MODEL_CHECKPOINT=qwen3.5-2b-nli-v5 MODEL=openjev-2b-v5
MODEL_CHECKPOINT ?= qwen3.5-4b-nli-v5
MODEL ?= openjev-4b-v5
# The commit of AlexWortega/openjev that the model test used, so the build repeats.
MODEL_REVISION ?= a20448012c213128955ca0c693e7c943865cab77
BUNDLE_ID := io.github.nickborgers.timebudget
# A stable certificate keeps the macOS permission grants through rebuilds. Use
# the first "Apple Development" identity in the keychain, else sign ad hoc
# ("-"), which loses the grants at each build. Override: make app SIGN_ID=...
SIGN_ID ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}'),-)

## app: build the Mac app as a bundle in .build/TimeBudget.app (macOS only).
## Notifications and the macOS permissions need a bundle, not a bare binary.
## A release build: the model runs several times faster than in a debug build.
## The bundle includes Models/$(MODEL) when it exists. Without it, the app runs
## with no classifier and your selection counts.
app:
	swift build -c release --product TimeBudgetApp
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp assets/brand/TimeBudget.icns $(APP)/Contents/Resources/TimeBudget.icns
	cp "$$(swift build -c release --show-bin-path)/TimeBudgetApp" $(APP)/Contents/MacOS/TimeBudget
	@# SwiftPM resource bundles, such as the MLX Metal shaders, go in Resources.
	cp -R "$$(swift build -c release --show-bin-path)"/*.bundle $(APP)/Contents/Resources/
	@# -c clones the files on APFS, so the 4 GB model costs no copy time or space.
	@if [ -d Models/$(MODEL) ]; then \
	  mkdir -p $(APP)/Contents/Resources/Models && \
	  cp -Rc Models/$(MODEL) $(APP)/Contents/Resources/Models/$(MODEL); \
	else echo "No Models/$(MODEL): the app has no classifier. Run make model first."; fi
	cp App/Info.plist $(APP)/Contents/Info.plist
	codesign --force --sign "$(SIGN_ID)" --identifier $(BUNDLE_ID) $(APP)
	@if [ "$(SIGN_ID)" = "-" ]; then echo "Signed ad hoc: permission grants reset at each build. See docs/manual-test.md."; fi

## run: build the bundle and launch it (macOS only)
run: app
	-pkill -x TimeBudget
	open $(APP)

## install: copy the bundle to ~/Applications, to open it from Spotlight or
## Finder with no terminal (macOS only)
install: app
	-pkill -x TimeBudget
	mkdir -p ~/Applications
	rm -rf ~/Applications/TimeBudget.app
	cp -R $(APP) ~/Applications/TimeBudget.app

## reset-permissions: forget the Accessibility and Screen Recording grants.
## An ad-hoc signed build gets a new identity each build, so macOS can keep
## showing an old grant that no longer works. Reset, run, and grant again.
reset-permissions:
	-tccutil reset Accessibility $(BUNDLE_ID)
	-tccutil reset ScreenCapture $(BUNDLE_ID)

## model: download the OpenJev checkpoint and convert it to an 8-bit MLX folder
## in Models/$(MODEL) (macOS only). Needs uv. This is a build step: the app never
## downloads a model.
model:
	uv run scripts/convert_openjev.py $(MODEL_CHECKPOINT) Models/$(MODEL) --revision $(MODEL_REVISION)

## model-check: milestone 1. Run the Swift classifier on the fixed test slices.
## Writes .build/model-check.jsonl for `make reference`.
model-check:
	swift build -c release --product model-check
	"$$(swift build -c release --show-bin-path)/model-check" Models/$(MODEL) \
	  --cases scripts/model-check-cases.jsonl --out .build/model-check.jsonl

## reference: score the same inputs with the Python reference (transformers,
## float32 on the CPU) and compare the winning options. Slow: minutes.
reference:
	uv run scripts/openjev_reference.py .build/model-check.jsonl \
	  --checkpoint $(MODEL_CHECKPOINT)

## test: run the test suite only
test:
	swift test

## lint: fail on any formatting difference
lint:
	swift format lint --strict --recursive Sources Tests Package.swift

## fmt: format the sources in place
fmt:
	swift format format --in-place --recursive Sources Tests Package.swift

clean:
	swift package clean
