#!/usr/bin/env bash
# Restore a path-only prod backup onto the prod branch.
# Restores ONLY the backed-up Explore path — does not reset the whole branch.
#
# Usage:
#   scripts/rollback_prod.sh backups/20260806T120000Z-Explore-IT_EAI-WD_Coupa
#   scripts/rollback_prod.sh 20260806T120000Z-Explore-IT_EAI-WD_Coupa Explore/IT_EAI/WD_Coupa

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

if [[ -z "$PATH_ARG" && -f "${TREE}/BACKUP_META.txt" ]]; then
  PATH_ARG="$(awk -F= '/^path=/{print $2; exit}' "${TREE}/BACKUP_META.txt")"
fi
if [[ -z "$PATH_ARG" ]]; then
  echo "ERROR: pass Explore path as 2nd arg, or ensure BACKUP_META.txt has path=" >&2
  exit 1
fi

RESTORE_FROM="${TREE}/${PATH_ARG}"
if [[ ! -e "$RESTORE_FROM" ]]; then
  echo "ERROR: ${RESTORE_FROM} not found in backup" >&2
  exit 1
fi

echo "==> Restoring ONLY ${PATH_ARG} from ${TREE}"
git checkout -B "${PROD_BRANCH}" "origin/${PROD_BRANCH}" 2>/dev/null || git checkout -B "${PROD_BRANCH}"

mkdir -p "$(dirname "$PATH_ARG")"
rm -rf "$PATH_ARG"
cp -R "$RESTORE_FROM" "$PATH_ARG"
git add -A "$PATH_ARG"
git commit -m "rollback: restore ${PATH_ARG} from $(basename "$TREE")" || echo "No changes to commit"
echo "Committed path-only rollback locally. Review and: git push origin ${PROD_BRANCH}"
echo "Then pull again in IICS Prod."
