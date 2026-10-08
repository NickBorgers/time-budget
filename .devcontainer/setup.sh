#!/usr/bin/env bash
# Clone -> open in devcontainer -> `make check` works. Nothing else required.
set -euo pipefail

# Fetch and compile dependencies once, so the first `make check` is not also the
# first download.
swift package resolve

# jq is what carries the host's Claude Code identity into the container: the
# util bootstrap skips system packages inside a container (UTIL_SKIP_PACKAGES),
# so seed_claude_identity finds no jq, says so, and leaves you to log in again.
# Installing it here - before dcs/dcr runs that bootstrap - avoids the prompt.
# make runs the checks; curl and ca-certificates are what the bootstrap uses to install the agent CLIs
# and gh; the Swift image is missing some of them.
missing=""
for tool in make jq curl; do
  command -v "$tool" >/dev/null 2>&1 || missing="$missing $tool"
done
if [ -n "$missing" ]; then
  sudo apt-get update -qq
  # shellcheck disable=SC2086
  sudo apt-get install -y -qq $missing ca-certificates
fi

echo
echo "time-budget is ready."
echo "  make check   # format check, build, and run the tests"
echo "  make test    # tests only"
echo "  make fmt     # format the sources in place"
echo
echo "Only the platform-neutral core builds here. The Mac app itself (SwiftUI,"
echo "Accessibility, MLX) needs macOS and Xcode; CI builds it on a macOS runner."
echo
