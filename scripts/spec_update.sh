#!/usr/bin/env bash
# Moves the pin to the specification's latest commit, or to the commit given,
# and copies that commit's example files into the spec fixtures. Run it after
# reviewing what scripts/spec_watch.sh reported.
#
#   scripts/spec_update.sh [COMMIT]
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/spec_common.sh

work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

clone_spec "$work/spec"
commit="$(git -C "$work/spec" rev-parse "${1:-HEAD}")"
git -C "$work/spec" checkout --quiet "$commit"

rm -rf "$FIXTURES"
cp -R "$work/spec/$FIXTURE_SOURCE" "$FIXTURES"
{ grep '^#' "$LOCK_FILE"; echo "$commit"; } > "$work/lock"
mv "$work/lock" "$LOCK_FILE"

echo "Pinned ${commit:0:12}. Run the specs, then commit $LOCK_FILE and $FIXTURES."
