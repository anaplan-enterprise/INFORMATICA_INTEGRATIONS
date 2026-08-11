#!/usr/bin/env bash
# Restore a path-only or change-set prod backup onto the prod branch.
#
# Usage:
#   scripts/rollback_prod.sh backups/20260806T120000Z-changeset
#   scripts/rollback_prod.sh backups/20260806T120000Z-Explore-IT_EAI-WD_Coupa

set -euo pipefail

SOURCE="${1:?Usage: $0 <backup-dir|timestamp-name> [Explore/path]}"
PATH_ARG="${2:-}"
PROD_BRANCH="${PROD_BRANCH:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

git fetch origin "${PROD_BRANCH}" || true

TREE="$SOURCE"
if [[ ! -d "$TREE" ]]; then
  TREE="backups/${SOURCE}"
fi
if [[ ! -d "$TREE" ]]; then
  echo "ERROR: backup directory not found: ${SOURCE} (also tried backups/${SOURCE})" >&2
  exit 1
fi

git checkout -B "${PROD_BRANCH}" "origin/${PROD_BRANCH}" 2>/dev/null || git checkout -B "${PROD_BRANCH}"

# Change-set backup: restore every Explore file stored under the backup tree
if [[ -f "${TREE}/changeset.txt" ]] || [[ "$(awk -F= '/^path=/{print $2; exit}' "${TREE}/BACKUP_META.txt" 2>/dev/null || true)" == "changeset" ]]; then
  echo "==> Restoring change-set files from ${TREE}"
  if [[ -d "${TREE}/Explore" ]]; then
    # Copy each backed-up file back
    while IFS= read -r -d '' f; do
      REL="${f#${TREE}/}"
      mkdir -p "$(dirname "$REL")"
      cp "$f" "$REL"
      git add -A "$REL"
    done < <(find "${TREE}/Explore" -type f -print0)
  else
    echo "WARN: no Explore/ files in backup (maybe only new-on-dev assets)"
  fi
  git commit -m "rollback: restore change-set from $(basename "$TREE")" || echo "No changes to commit"
  echo "Committed change-set rollback locally. Review and: git push origin ${PROD_BRANCH}"
  exit 0
fi

if [[ -z "$PATH_ARG" && -f "${TREE}/BACKUP_META.txt" ]]; then
  PATH_ARG="$(awk -F= '/^path=/{print $2; exit}' "${TREE}/BACKUP_META.txt")"
fi
if [[ -z "$PATH_ARG" || "$PATH_ARG" == "changeset" ]]; then
  echo "ERROR: pass Explore path as 2nd arg, or ensure BACKUP_META.txt has path=" >&2
  exit 1
fi

RESTORE_FROM="${TREE}/${PATH_ARG}"
if [[ ! -e "$RESTORE_FROM" ]]; then
  echo "ERROR: ${RESTORE_FROM} not found in backup" >&2
  exit 1
fi

echo "==> Restoring ONLY ${PATH_ARG} from ${TREE}"
mkdir -p "$(dirname "$PATH_ARG")"
rm -rf "$PATH_ARG"
cp -R "$RESTORE_FROM" "$PATH_ARG"
git add -A "$PATH_ARG"
git commit -m "rollback: restore ${PATH_ARG} from $(basename "$TREE")" || echo "No changes to commit"
echo "Committed path-only rollback locally. Review and: git push origin ${PROD_BRANCH}"
echo "Then pull again in IICS Prod."
