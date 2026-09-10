#!/usr/bin/env bash
# One-time install of the CI workflow into .github/workflows/ (the Arena GitHub App is not
# allowed to write that path, so this helper runs with YOUR token).
#
#   brew install gh && gh auth login          # or use the GitHub web UI instead
#   bash ci/install-workflow.sh
#
# After it runs, Actions starts building automatically and the APK lands in
# Releases -> "GloboVerse Android build (latest)".
set -euo pipefail

REPO="${REPO:-nuriddinwoo/GloboVerse}"
BRANCH="${BRANCH:-arena/01a089a3-globoverse}"
SRC="$(cd "$(dirname "$0")" && pwd)/android-apk.yml"
DEST=".github/workflows/android-apk.yml"

content="$(base64 < "$SRC" | tr -d '\n')"
gh api -X PUT "repos/$REPO/contents/$DEST" \
  -f message="ci: install Android APK/AAB build workflow" \
  -f branch="$BRANCH" \
  -f content="$content"

echo "Installed $DEST on $BRANCH. Open:"
echo "https://github.com/$REPO/actions/workflows/android-apk.yml"
