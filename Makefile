.PHONY: all check build test app run install reset-permissions lint fmt clean

all: check

## check: format check, build, and run the tests (what CI runs)
check: lint build test

## build: compile the core, and the Mac app on macOS
build:
	swift build

APP := .build/TimeBudget.app
BUNDLE_ID := io.github.nickborgers.timebudget
# A stable certificate keeps the macOS permission grants through rebuilds. Use
# the first "Apple Development" identity in the keychain, else sign ad hoc
# ("-"), which loses the grants at each build. Override: make app SIGN_ID=...
SIGN_ID ?= $(or $(shell security find-identity -v -p codesigning 2>/dev/null | awk -F'"' '/Apple Development/ {print $$2; exit}'),-)

## app: build the Mac app as a bundle in .build/TimeBudget.app (macOS only).
## Notifications and the macOS permissions need a bundle, not a bare binary.
app:
	swift build --product TimeBudgetApp
	rm -rf $(APP)
	mkdir -p $(APP)/Contents/MacOS $(APP)/Contents/Resources
	cp assets/brand/TimeBudget.icns $(APP)/Contents/Resources/TimeBudget.icns
	cp "$$(swift build --show-bin-path)/TimeBudgetApp" $(APP)/Contents/MacOS/TimeBudget
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
