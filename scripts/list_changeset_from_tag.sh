#!/usr/bin/env bash
# List the change set from a Git tag (IICS check-in indicator).
# Files changed in the tagged commit (vs its parent), filtered by Explore scope.
#
# Tag naming convention:
#   promote/<project>-<job-or-ticket>-<date>
#   e.g. promote/WD_Coupa-SyncVendors-20260811
#
# Usage:
#   scripts/list_changeset_from_tag.sh promote/WD_Coupa-JobA-20260811 Explore/IT_EAI/WD_Coupa
#   scripts/list_changeset_from_tag.sh promote/WD_Coupa-JobA-20260811 Explore/IT_EAI/WD_Coupa /tmp/changeset.txt

set -euo pipefail

TAG="${1:?Usage: $0 <tag> Explore/<scope> [outfile]}"
SCOPE="${2:?Usage: $0 <tag> Explore/<scope> [outfile]}"
OUTFILE="${3:-}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ "$SCOPE" != Explore/* ]]; then
  echo "ERROR: scope must start with Explore/" >&2
  exit 1
fi

echo "==> Fetching tags"
git fetch origin --tags --force 2>/dev/null || git fetch --tags --force 2>/dev/null || true

if ! git rev-parse --verify "$TAG" >/dev/null 2>&1 \
  && ! git rev-parse --verify "refs/tags/${TAG}" >/dev/null 2>&1; then
  echo "ERROR: tag not found: ${TAG}" >&2
  echo "Create a tag on the IICS check-in commit, e.g.:" >&2
  echo "  git tag promote/WD_Coupa-JobA-20260811 <commit-sha>" >&2
  echo "  git push origin promote/WD_Coupa-JobA-20260811" >&2
  exit 1
fi

TAG_REF="$TAG"
if ! git rev-parse --verify "$TAG_REF" >/dev/null 2>&1; then
  TAG_REF="refs/tags/${TAG}"
fi

TAG_SHA="$(git rev-parse "$TAG_REF")"
echo "==> Tag ${TAG} → ${TAG_SHA}" >&2

TMP="$(mktemp)"
trap 'rm -f "$TMP"' EXIT

# Prefer files introduced/changed in the tagged commit (the IICS push commit)
if git rev-parse --verify "${TAG_REF}^" >/dev/null 2>&1; then
  echo "==> Change set = files changed in tagged commit under ${SCOPE}" >&2
  git diff --name-only "${TAG_REF}^" "${TAG_REF}" -- "$SCOPE" > "$TMP"
else
  echo "==> Tag has no parent — change set = all files under ${SCOPE} at tag" >&2
  git ls-tree -r --name-only "$TAG_REF" -- "$SCOPE" > "$TMP"
fi

grep -E '^Explore/' "$TMP" > "${TMP}.2" || true
mv "${TMP}.2" "$TMP"

COUNT="$(wc -l < "$TMP" | tr -d ' ')"
if [[ "$COUNT" -eq 0 ]]; then
  echo "ERROR: no Explore files under ${SCOPE} in tag ${TAG} — nothing to promote" >&2
  exit 2
fi

echo "==> ${COUNT} file(s) in tag change set:" >&2
cat "$TMP" >&2

if [[ -n "$OUTFILE" ]]; then
  cp "$TMP" "$OUTFILE"
  echo "CHANGESET_FILE=${OUTFILE}"
else
  cat "$TMP"
fi
echo "CHANGESET_COUNT=${COUNT}"
echo "CHANGESET_SCOPE=${SCOPE}"
echo "CHANGESET_TAG=${TAG}"
echo "CHANGESET_TAG_SHA=${TAG_SHA}"
