#!/usr/bin/env bash
# Removes what your release pipeline created. Run:  ./teardown.sh
# One-time setup:  gh auth refresh -s read:packages,delete:packages
cd "$(dirname "$0")"
command -v gh >/dev/null || { echo "The GitHub CLI (gh) is not installed"; exit 1; }
R=$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
OWNER=${R%%/*}; NAME_LC=$(echo "${R##*/}" | tr '[:upper:]' '[:lower:]')
echo "Repository: $R"
echo "Deleting GitHub Releases and their tags ..."
gh release list -R "$R" --limit 100 --json tagName -q '.[].tagName' | while read -r t; do gh release delete "$t" -R "$R" --cleanup-tag -y >/dev/null 2>&1 && echo "  deleted release $t"; done
echo "Deleting leftover version tags ..."
gh api "repos/$R/git/matching-refs/tags/v" --jq '.[].ref' 2>/dev/null | while read -r ref; do gh api -X DELETE "repos/$R/git/$ref" >/dev/null 2>&1 && echo "  deleted $ref"; done
echo "Deleting the container package ghcr.io/$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')/$NAME_LC ..."
if gh api -X DELETE "/user/packages/container/$NAME_LC" >/dev/null 2>&1; then echo "  deleted"; else echo "  not deleted: it does not exist, or you still need: gh auth refresh -s read:packages,delete:packages"; fi
echo "Deleting artifacts ..."
gh api "repos/$R/actions/artifacts?per_page=100" --jq '.artifacts[].id' 2>/dev/null | while read -r id; do gh api -X DELETE "repos/$R/actions/artifacts/$id" >/dev/null 2>&1; done
echo "Disabling the release workflow ..."
gh workflow disable release.yml -R "$R" >/dev/null 2>&1 && echo "  disabled" || echo "  could not disable (already disabled or missing)"
echo "Done. Now run ./verify-teardown.sh to prove it."
