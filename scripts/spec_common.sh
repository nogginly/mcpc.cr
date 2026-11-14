# Shared by spec_watch.sh and spec_update.sh. Source it; do not run it.

SPEC_REPO="https://github.com/modelcontextprotocol/modelcontextprotocol.git"
LOCK_FILE="spec/upstream.lock"
FIXTURES="spec/fixtures/2026-07-28"
FIXTURE_SOURCE="schema/2026-07-28/examples"

# The paths the client depends on. A change to any of them fails the watch.
WATCHED_PATHS=(
  schema/2025-11-25
  schema/2026-07-28
  docs/specification/2025-11-25/basic
  docs/specification/2026-07-28/basic
)

# The next revision. Changes are reported but do not fail the watch.
DRAFT_PATHS=(schema/draft docs/specification/draft)

pinned_commit() {
  grep -v '^#' "$LOCK_FILE" | tr -d '[:space:]'
}

# Clones the spec repository into $1 with full history but no file contents
# until they are needed.
clone_spec() {
  git clone --quiet --filter=blob:none --no-checkout "$SPEC_REPO" "$1"
}
