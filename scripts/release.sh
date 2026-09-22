#!/usr/bin/env bash
# Release a new AppFlowy Olares chart version.
# Usage: ./scripts/release.sh 1.2.2
# Requirements: git push access to https://github.com/abidals/AppFlowy-Olares
# and olares-cli (+ gh CLI optional).
set -euo pipefail

VERSION="${1:?usage: release.sh <version-without-v>}"
REPO="abidals/AppFlowy-Olares"
TAG="v${VERSION}"

cd "$(dirname "$0")/.."

# 1. sanity: versions match
grep -q "^version: ${VERSION}$" appflowy/Chart.yaml || { echo "Chart.yaml version != ${VERSION}"; exit 1; }
grep -q "version: '${VERSION}'" appflowy/OlaresManifest.yaml || { echo "OlaresManifest.yaml metadata.version != ${VERSION}"; exit 1; }
for f in appflowy/i18n/*/OlaresManifest.yaml; do
  grep -q "version: '${VERSION}'" "$f" || { echo "$f metadata.version != ${VERSION}"; exit 1; }
done

# 2. lint + package
olares-cli chart lint appflowy
rm -f "appflowy-${VERSION}.tgz"
olares-cli chart package appflowy

# 3. commit source + tag + push (source only — *.tgz is gitignored, lives in Releases)
if [ -n "$(git status --porcelain -- appflowy README.md PLAN-appflowy.md)" ]; then
  git add appflowy README.md PLAN-appflowy.md
  git commit -m "release ${VERSION}"
fi
git tag -f "${TAG}" -m "AppFlowy Olares chart ${VERSION}"
git push origin main "${TAG}"

# 4. publish the GitHub Release with the .tgz asset
if command -v gh >/dev/null 2>&1; then
  gh release create "${TAG}" "appflowy-${VERSION}.tgz" \
    --title "AppFlowy Olares chart ${TAG}" --generate-notes
else
  echo "gh CLI not found — create the release manually at https://github.com/${REPO}/releases/new"
  echo "and attach appflowy-${VERSION}.tgz (tag: ${TAG})."
fi
echo "Release ${TAG} published."
