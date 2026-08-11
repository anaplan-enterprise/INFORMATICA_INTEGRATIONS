#!/usr/bin/env bash
# Backup ONLY the given Explore path from the prod branch before promotion.
# Does NOT snapshot the entire prod branch — only the promoted folder/project.
#
# Example:
#   scripts/backup_prod.sh Explore/IT_EAI/WD_Coupa
#   → backups/<timestamp>/Explore/IT_EAI/WD_Coupa/...
#
# Usage:
#   scripts/backup_prod.sh Explore/IT_EAI
#   scripts/backup_prod.sh Explore/IT_EAI/WD_Coupa

set -euo pipefail

PATH_ARG="${1:?Usage: $0 Explore/<FOLDER>[/<project>]}"
PROD_BRANCH="${PROD_BRANCH:-prod}"
REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
cd "$REPO_ROOT"

TIMESTAMP="$(date -u +%Y%m%dT%H%M%SZ)"
# Encode path in backup folder name for clarity, keep timestamp for uniqueness
SAFE_PATH="$(echo "$PATH_ARG" | tr '/' '-')"
BACKUP_DIR="backups/${TIMESTAMP}-${SAFE_PATH}"

if [[ "$PATH_ARG" != Explore/* ]]; then
  echo "ERROR: path must start with Explore/" >&2
  exit 1
fi

echo "==> Fetching ${PROD_BRANCH}"
git fetch origin "${PROD_BRANCH}:${PROD_BRANCH}" 2>/dev/null || git fetch origin "${PROD_BRANCH}" || true

if ! git rev-parse --verify "origin/${PROD_BRANCH}" >/dev/null 2>&1 \
  && ! git rev-parse --verify "${PROD_BRANCH}" >/dev/null 2>&1; then
  echo "WARN: ${PROD_BRANCH} does not exist yet — creating empty backup marker"
  mkdir -p "${BACKUP_DIR}/${PATH_ARG}"
  echo "no-prod-branch" > "${BACKUP_DIR}/README.txt"
  echo "path=${PATH_ARG}" > "${BACKUP_DIR}/BACKUP_META.txt"
  echo "${TIMESTAMP}" > backups/.last_backup
  echo "BACKUP_PATH=${PATH_ARG}"
  echo "BACKUP_DIR=${BACKUP_DIR}"
  exit 0
fi

REF="origin/${PROD_BRANCH}"
if ! git rev-parse --verify "$REF" >/dev/null 2>&1; then
  REF="${PROD_BRANCH}"
fi

echo "==> Backing up ONLY ${PATH_ARG} from ${REF} → ${BACKUP_DIR}"
mkdir -p "${BACKUP_DIR}"
echo "path=${PATH_ARG}" > "${BACKUP_DIR}/BACKUP_META.txt"
echo "prod_ref=${REF}" >> "${BACKUP_DIR}/BACKUP_META.txt"
echo "prod_sha=$(git rev-parse "${REF}")" >> "${BACKUP_DIR}/BACKUP_META.txt"
echo "timestamp=${TIMESTAMP}" >> "${BACKUP_DIR}/BACKUP_META.txt"

if git cat-file -e "${REF}:${PATH_ARG}" 2>/dev/null \
  || git ls-tree -r --name-only "${REF}" "${PATH_ARG}" 2>/dev/null | grep -q .; then
  git archive "${REF}" "${PATH_ARG}" | tar -x -C "${BACKUP_DIR}"
  echo "==> Path-only backup complete"
else
  echo "WARN: ${PATH_ARG} not found on ${REF} — nothing to copy (first promote of this path?)"
  echo "path-missing-on-prod" >> "${BACKUP_DIR}/BACKUP_META.txt"
  mkdir -p "${BACKUP_DIR}/${PATH_ARG}"
fi

echo "${TIMESTAMP}" > backups/.last_backup
echo "BACKUP_PATH=${PATH_ARG}"
echo "BACKUP_DIR=${BACKUP_DIR}"
echo "PROD_SHA=$(git rev-parse "${REF}")"
