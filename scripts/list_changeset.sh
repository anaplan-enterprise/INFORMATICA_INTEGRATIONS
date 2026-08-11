#!/usr/bin/env bash
# List the change set under a scope: files that differ between prod and dev.
# This is what IICS checked in / updated on dev but is not yet the same on prod —
# including a job and all dependent mappings that were part of that push.
#
# Usage:
#   scripts/list_changeset.sh Explore/IT_EAI/WD_Coupa
#   scripts/list_changeset.sh Explore/IT_EAI/WD_Coupa /tmp/changeset.txt
#
# Env:
#   DEV_BRANCH (default: dev)
#   PROD_BRANCH (default: prod)

set -euo pipefail

SCOPE="${1:?Usage: $0 Explore/<FOLDER>[/<project>] [outfile]}"
OUTFILE="${2:-}"
DEV_BRANCH="${DEV_BRANCH:-dev}"
PROD_BRANCH="${PROD_BRANCH:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$SCOPE" != Explore/* ]]; then
  echo "ERROR: scope must start with Explore/" >&2
  exit 1
fi

git fetch origin "${DEV_BRANCH}" 2>/dev/null || true
git fetch origin "${PROD_BRANCH}" 2>/dev/null || true

DEV_REF="origin/${DEV_BRANCH}"
if ! git rev-parse --verify "$DEV_REF" >/dev/null 2>&1; then
  DEV_REF="${DEV_BRANCH}"
fi
if ! git rev-parse --verify "$DEV_REF" >/dev/null 2>&1; then
  echo "ERROR: cannot find ${DEV_BRANCH}" >&2
  exit 1
fi

PROD_REF=""
if git rev-parse --verify "origin/${PROD_BRANCH}" >/dev/null 2>&1; then
  PROD_REF="origin/${PROD_BRANCH}"
elif git rev-parse --verify "${PROD_BRANCH}" >/dev/null 2>&1; then
  PROD_REF="${PROD_BRANCH}"
fi

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

if [[ -z "$PROD_REF" ]]; then
  # First promote: everything under scope on dev is the change set
  echo "==> No prod branch yet — change set = all files under ${SCOPE} on ${DEV_REF}" >&2
  git ls-tree -r --name-only "$DEV_REF" -- "$SCOPE" > "$TMP"
else
  echo "==> Change set = files different between ${PROD_REF} and ${DEV_REF} under ${SCOPE}" >&2
  # Compare trees: added, modified, deleted under scope
  git diff --name-only "$PROD_REF" "$DEV_REF" -- "$SCOPE" > "$TMP"
fi

# Keep only paths under Explore/
grep -E '^Explore/' "$TMP" > "${TMP}.2" || true
mv "${TMP}.2" "$TMP"

COUNT="$(wc -l < "$TMP" | tr -d ' ')"
if [[ "$COUNT" -eq 0 ]]; then
  echo "ERROR: no differences under ${SCOPE} between prod and dev — nothing to promote" >&2
  exit 2
fi

echo "==> ${COUNT} file(s) in change set:" >&2
cat "$TMP" >&2

if [[ -n "$OUTFILE" ]]; then
  cp "$TMP" "$OUTFILE"
  echo "CHANGESET_FILE=${OUTFILE}"
else
  cat "$TMP"
fi
echo "CHANGESET_COUNT=${COUNT}"
echo "CHANGESET_SCOPE=${SCOPE}"
