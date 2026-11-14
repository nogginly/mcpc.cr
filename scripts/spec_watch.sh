#!/usr/bin/env bash
# Fails when the MCP specification has changed since the pinned commit in
# the paths this client depends on, or has gained a protocol revision.
# Changes to the draft revision are reported without failing.
#
#   scripts/spec_watch.sh
#
# Writes a Markdown summary to $GITHUB_STEP_SUMMARY when that is set.
set -euo pipefail
cd "$(dirname "$0")/.."
source scripts/spec_common.sh

summary="${GITHUB_STEP_SUMMARY:-/dev/null}"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT

clone_spec "$work/spec"
spec() { git -C "$work/spec" "$@"; }

pinned="$(pinned_commit)"
latest="$(spec rev-parse HEAD)"
failed=0

say() { echo "$1"; echo "$1" >> "$summary"; }

say "## MCP specification watch"
say ""
say "Pinned \`${pinned:0:12}\`, upstream \`${latest:0:12}\`."
say ""

# Steps: list revisions at both commits, report any that are new.
revisions_at() { spec ls-tree --name-only "$1" schema/ | sed 's#^schema/##' | grep -v '^draft$' | sort; }
new_revisions="$(comm -13 <(revisions_at "$pinned") <(revisions_at "$latest"))"
if [[ -n "$new_revisions" ]]; then
  failed=1
  say "### New protocol revisions"
  say ""
  say "$(sed 's/^/- /' <<< "$new_revisions")"
  say ""
fi

# Steps: diff the watched paths; any change fails.
changes="$(spec diff --stat "$pinned" "$latest" -- "${WATCHED_PATHS[@]}")"
if [[ -n "$changes" ]]; then
  failed=1
  say "### Changes the client may need to follow"
  say ""
  say '```'
  say "$changes"
  say '```'
  say ""
  echo "Full diff:"
  spec diff "$pinned" "$latest" -- "${WATCHED_PATHS[@]}"
fi

# Steps: diff the draft; report only.
draft="$(spec diff --stat "$pinned" "$latest" -- "${DRAFT_PATHS[@]}")"
if [[ -n "$draft" ]]; then
  say "### Draft revision changes (not a failure)"
  say ""
  say '```'
  say "$draft"
  say '```'
  say ""
fi

# Steps: check the fixtures still match the pinned commit.
spec worktree add --quiet --detach "$work/pinned" "$pinned"
if ! diff -r --brief "$FIXTURES" "$work/pinned/$FIXTURE_SOURCE" > "$work/fixtures.txt"; then
  failed=1
  say "### Fixtures differ from the pinned commit"
  say ""
  say '```'
  say "$(cat "$work/fixtures.txt")"
  say '```'
  say ""
fi

if [[ "$failed" == 1 ]]; then
  say "Review the changes, update the client if needed, then run \`scripts/spec_update.sh\`."
  exit 1
fi
say "No changes the client depends on."
