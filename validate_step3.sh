#!/usr/bin/env bash
# validate_step3.sh — verify the most recent workflow run produced a
# linux/arm64 image in GHCR with the current commit's short SHA tag.
set -e

echo "=== Step 3 validator: ARM64 image in GHCR ==="
REPO=$(gh repo view --json nameWithOwner --jq .nameWithOwner)
SHA=$(git rev-parse --short HEAD)
OWNER=$(echo "$REPO" | cut -d/ -f1)
# Package name in GHCR == the repo name (since the workflow's
# `images: ghcr.io/${{ github.repository }}` line uses just <owner>/<repo>).
PKG=$(echo "$REPO" | cut -d/ -f2)

# GHCR registry paths must be all lowercase even when the GitHub repo
# name has uppercase chars (Docker registry spec). `docker manifest
# inspect` rejects mixed-case paths with "no such manifest", so we
# lowercase the path here for the manifest check while keeping $REPO
# in its original case for the GitHub API calls below (which ARE
# case-insensitive).
REPO_LC=$(echo "$REPO" | tr '[:upper:]' '[:lower:]')
IMAGE="ghcr.io/$REPO_LC"

echo "Looking for $IMAGE:sha-$SHA"

# 1. Wait for the build job to finish (up to 50 min — QEMU is slow)
for i in {1..600}; do
    STATUS=$(gh run list --workflow=ci.yml --limit 1 --json status,conclusion --jq '.[0]')
    S=$(echo "$STATUS" | jq -r .status)
    C=$(echo "$STATUS" | jq -r .conclusion)
    if [ "$S" = "completed" ]; then
        [ "$C" = "success" ] || { echo "FAIL: workflow conclusion=$C"; exit 1; }
        echo "PASS: workflow completed successfully"
        break
    fi
    [ $((i % 12)) -eq 0 ] && echo "  ...$((i*5/60)) min elapsed, status=$S"
    sleep 5
done

# 2. Check the package exists in GHCR via the GitHub API. The endpoint
#    differs for personal accounts vs. organisation accounts, so detect
#    the owner type first via gh's /users/{owner} → .type field.
OWNER_TYPE=$(gh api "/users/$OWNER" --jq .type 2>/dev/null || echo "User")
if [ "$OWNER_TYPE" = "Organization" ]; then
    PKG_PATH="/orgs/$OWNER/packages/container/$PKG/versions"
else
    PKG_PATH="/users/$OWNER/packages/container/$PKG/versions"
fi

gh api "$PKG_PATH" --jq '.[0].metadata.container.tags' \
    > /tmp/tags.json 2>/dev/null \
    || { echo "FAIL: cannot read GHCR package metadata at $PKG_PATH. Did the build push succeed?"; exit 1; }

if grep -q "sha-$SHA" /tmp/tags.json; then
    echo "PASS: GHCR has tag sha-$SHA"
else
    echo "FAIL: no sha-$SHA tag found. Got: $(cat /tmp/tags.json)"
    exit 1
fi

# 3. Verify the manifest reports linux/arm64. `docker manifest inspect`
#    yields either a manifest *list* (multi-arch, fields under .manifests[])
#    or a single manifest (.architecture at the top level). Inspect once,
#    extract whatever arch fields are present, and look for arm64.
#
# Private GHCR packages need an authenticated `docker login` before the
# manifest call works. If your package is private, run:
#     echo $(gh auth token) | docker login ghcr.io -u <user> --password-stdin
# Or change the package visibility to Public in the GHCR web UI.
if ! MANIFEST=$(docker manifest inspect "$IMAGE:sha-$SHA" 2>&1); then
    echo "WARN: docker manifest inspect failed. Raw error:"
    echo "      $MANIFEST"
    echo "      verify manually in the GHCR web UI: https://github.com/$REPO/pkgs/container/$PKG"
else
    ARCHES=$(echo "$MANIFEST" | jq -r '.manifests[]?.platform.architecture, .architecture' 2>/dev/null | grep -v '^null$' | sort -u)
    if echo "$ARCHES" | grep -qE '^(arm64|aarch64)$'; then
        echo "PASS: manifest reports arm64"
    else
        echo "FAIL: manifest is not arm64 (saw: $ARCHES)"
        exit 1
    fi
fi

echo "=== Step 3 PASS ==="