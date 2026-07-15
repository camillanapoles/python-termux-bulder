#!/usr/bin/env bash
# scripts/install-local-termux.sh
# Helper to trigger the termux-wheel workflow and install the resulting wheel locally in Termux.
#
# Prerequisites (inside Termux):
#   - gh (GitHub CLI) installed and authenticated (pkg install gh && gh auth login)
#   - pip (from Termux Python) available
#
# Usage:
#   ./scripts/install-local-termux.sh <package> [version] [python_version] [arch]
#   Example: ./scripts/install-local-termux.sh jiter 0.12.0 3.12 aarch64
#
# Optional environment variables:
#   GH_REPO   default: "camillanapoles/python-termux-bulder"
#   WORKFLOW  default: "termux-wheel.yml"
#
set -euo pipefail

REPO="${GH_REPO:-camillanapoles/python-termux-bulder}"
WORKFLOW="${WORKFLOW:-termux-wheel.yml}"

if [ $# -lt 1 ]; then
  echo "Usage: $0 <package> [version] [python_version] [arch]"
  exit 1
fi

PKG="$1"
VER="${2:-}"
PYVER="${3:-3.12}"
ARCH="${4:-aarch64}"

# Validate arch
case "$ARCH" in
  aarch64|x86_64|armv7l|i686) ;;
  *) echo "Error: unsupported architecture '$ARCH'"; exit 1 ;;
esac

# Ensure gh is available
if ! command -v gh >/dev/null 2>&1; then
  echo "Error: GitHub CLI (gh) not found. Install with: pkg install gh"
  exit 1
fi

# Ensure we are authenticated
if ! gh auth status >/dev/null 2>&1; then
  echo "Error: gh is not authenticated. Run: gh auth login"
  exit 1
fi

# Trigger workflow
echo "Triggering workflow $WORKFLOW in $REPO ..."
gh workflow run "$WORKFLOW" --repo "$REPO" \
  -f package_name="$PKG" \
  ${VER:+-f package_version="$VER"} \
  -f python_version="$PYVER" \
  -f arch="$ARCH" \
  > /dev/null || {
    echo "Failed to start workflow run."
    exit 1
  }
# Give GitHub a moment to register the run
sleep 2
RUN_ID=$(gh run list --repo "$REPO" --workflow "$WORKFLOW" --limit 1 --json databaseId --jq '.[0].databaseId') || {
    echo "Failed to retrieve workflow run ID."
    exit 1
}
echo "Workflow run ID: $RUN_ID"
if ! gh run watch "$RUN_ID" --repo "$REPO"; then
  echo "Workflow failed or was interrupted."
  exit 1
fi

# Check conclusion
CONCLUSION=$(gh run view "$RUN_ID" --repo "$REPO" --json conclusion --jq '.conclusion')
if [ "$CONCLUSION" != "success" ]; then
  echo "Workflow completed with conclusion: $CONCLUSION"
  exit 1
fi

# Determine artifact name
ARTIFACT="${PKG}-android-${ARCH}"
case "$ARCH" in
  aarch64) ABI="arm64_v8a" ;;
  x86_64)  ABI="x86_64" ;;
  armv7l)  ABI="armeabi_v7a" ;;
  i686)    ABI="x86" ;;
esac
ARTIFACT="${PKG}-android-${ABI}"

# Download artifact
TMPDIR=$(mktemp -d)
trap 'rm -rf "$TMPDIR"' EXIT
echo "Downloading artifact '$ARTIFACT' ..."
if ! gh run download "$RUN_ID" --repo "$REPO" -n "$ARTIFACT" -d "$TMPDIR"; then
  echo "Failed to download artifact."
  exit 1
fi

WHEEL=$(find "$TMPDIR" -name '*.whl' | head -n 1)
if [ -z "$WHEEL" ]; then
  echo "No .whl file found in the downloaded artifact."
  exit 1
fi
echo "Found wheel: $(basename "$WHEEL")"

# Install wheel
echo "Installing wheel with pip ..."
if pip install --force-reinstall "$WHEEL"; then
  echo "Successfully installed $(basename "$WHEEL")"
else
  echo "Failed to install wheel."
  exit 1
fi