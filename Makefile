.PHONY: all check build test run lint fmt clean

all: check

## check: format check, build, and run the tests (what CI runs)
check: lint build test

## build: compile the core, and the Mac app on macOS
build:
	swift build

## run: launch the Mac app scaffold (macOS only)
run:
	swift run TimeBudgetApp

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
