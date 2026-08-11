#!/usr/bin/env bash
# Backup only the listed change-set files from prod (not the whole project).
#
# Usage:
#   scripts/backup_changeset.sh /tmp/changeset.txt
#
# Env: PROD_BRANCH (default: prod)

set -euo pipefail

LIST="${1:?Usage: $0 <changeset-file>}"
PROD_BRANCH="${PROD_BRANCH:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

if [[ ! -f "$LIST" ]]; then
  echo "ERROR: changeset file not found: $LIST" >&2
  exit 1
fi

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
BACKUP_DIR="backups/${TIMESTAMP}-changeset"
mkdir -p "$BACKUP_DIR"

git fetch origin "${PROD_BRANCH}" 2>/dev/null || true
REF=""
if git rev-parse --verify "origin/${PROD_BRANCH}" >/dev/null 2>&1; then
  REF="origin/${PROD_BRANCH}"
elif git rev-parse --verify "${PROD_BRANCH}" >/dev/null 2>&1; then
  REF="${PROD_BRANCH}"
fi

echo "path=changeset" > "${BACKUP_DIR}/BACKUP_META.txt"
echo "timestamp=${TIMESTAMP}" >> "${BACKUP_DIR}/BACKUP_META.txt"
echo "list=$(basename "$LIST")" >> "${BACKUP_DIR}/BACKUP_META.txt"
cp "$LIST" "${BACKUP_DIR}/changeset.txt"

BACKED=0
MISSING=0
if [[ -n "$REF" ]]; then
  echo "prod_ref=${REF}" >> "${BACKUP_DIR}/BACKUP_META.txt"
  echo "prod_sha=$(git rev-parse "$REF")" >> "${BACKUP_DIR}/BACKUP_META.txt"
  while IFS= read -r f || [[ -n "$f" ]]; do
    [[ -z "$f" ]] && continue
    if git cat-file -e "${REF}:${f}" 2>/dev/null; then
      mkdir -p "${BACKUP_DIR}/$(dirname "$f")"
      git show "${REF}:${f}" > "${BACKUP_DIR}/${f}"
      BACKED=$((BACKED + 1))
    else
      # New on dev — nothing to backup on prod
      MISSING=$((MISSING + 1))
    fi
  done < "$LIST"
else
  echo "no-prod-branch" >> "${BACKUP_DIR}/BACKUP_META.txt"
fi

echo "backed_up_files=${BACKED}" >> "${BACKUP_DIR}/BACKUP_META.txt"
echo "new_on_dev_no_prod_copy=${MISSING}" >> "${BACKUP_DIR}/BACKUP_META.txt"
echo "${TIMESTAMP}" > backups/.last_backup

echo "==> Backed up ${BACKED} existing prod file(s); ${MISSING} are new on dev only"
echo "BACKUP_PATH=changeset"
echo "BACKUP_DIR=${BACKUP_DIR}"
echo "BACKUP_COUNT=${BACKED}"
