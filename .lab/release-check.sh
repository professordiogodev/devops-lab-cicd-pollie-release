#!/usr/bin/env bash
# Checks your release pipeline: the workflow file, the runs GitHub recorded, the Release and the image tags.
cd "$(dirname "$0")/.."
command -v gh >/dev/null || { echo "The GitHub CLI (gh) is not installed: https://cli.github.com, then run: gh auth login"; exit 1; }
if [ -n "${GITHUB_REPOSITORY:-}" ]; then R="$GITHUB_REPOSITORY"; else
  R=$(git remote get-url origin 2>/dev/null | sed -E 's#(git@github.com:|https://github.com/)##; s#\.git$##')
fi
[ -n "$R" ] || { echo "Cannot work out your repository: run this inside your fork"; exit 1; }
OWNER=${R%%/*}; NAME=${R##*/}; NAME_LC=$(echo "$NAME" | tr '[:upper:]' '[:lower:]'); OWNER_LC=$(echo "$OWNER" | tr '[:upper:]' '[:lower:]')
pass=0; failn=0; total=0
check() { local d="$1"; shift; total=$((total+1)); if "$@" >/dev/null 2>&1; then echo "PASS  $d"; pass=$((pass+1)); else echo "FAIL  $d"; failn=$((failn+1)); fi; }
torn=false; grep -qE '^TEARDOWN VERIFIED \(' SUBMISSION.md 2>/dev/null && torn=true
st() { python3 .lab/workflow_lint.py "$1" 2>/dev/null; }

echo "== The workflow file (.github/workflows/release.yml) =="
check "the file exists" test -s .github/workflows/release.yml
check "starts on version tags (v1.2.3) and can be started by hand with a version input" st triggers
check "calls the CI workflow instead of copying it (uses: ./.github/workflows/ci.yml)" st reuse
check "top-level permissions are read-only" st permissions
check "no action pinned to a moving ref (@main, @master, @latest)" st pins
check "contents: write only on the job that creates the Release, packages: write never at the top" st writes
check "scans with Trivy and fails on findings (exit-code 1)" st scan
check "produces a software bill of materials (CycloneDX or SPDX)" st sbom
check "uses the environments staging and production" st envs
check "smoke-tests the published image with compose.ci.yaml and scripts/smoke.sh" st smoke
check "creates a GitHub Release (gh release create or a release action)" st release
check "pushes the version tag, the minor tag and latest" st tags

echo "== What GitHub recorded =="
RUNS=$(gh api "repos/$R/actions/workflows/release.yml/runs?status=completed&per_page=30" 2>/dev/null)
rid=$(echo "$RUNS" | python3 -c 'import json,sys; r=[x for x in json.load(sys.stdin).get("workflow_runs",[]) if x["conclusion"]=="success" and x["event"]=="push"]; print(r[0]["id"] if r else "")' 2>/dev/null)
check "a release run started by a version tag finished green" bash -c "[ -n '$rid' ]"
jobs_ok() {
  gh api "repos/$R/actions/runs/$rid/jobs?per_page=50" 2>/dev/null | python3 -c '
import json,sys
j={x["name"].lower():x["conclusion"] for x in json.load(sys.stdin)["jobs"]}
need=["ci","image","release","staging","production"]
sys.exit(0 if all(any(k in n and c=="success" for n,c in j.items()) for k in need) else 1)'
}
check "in that run ci, image, release, staging and production all succeeded" jobs_ok
check "a manual (rollback) run of the same workflow finished green" bash -c "echo '$RUNS' | python3 -c 'import json,sys; sys.exit(0 if any(x[\"conclusion\"]==\"success\" and x[\"event\"]==\"workflow_dispatch\" for x in json.load(sys.stdin).get(\"workflow_runs\",[])) else 1)'"

echo "== The Release and the image =="
if $torn; then
  echo "PASS  Releases and package are removed by the tear down, as they should be (SUBMISSION.md has the proof)"; pass=$((pass+1)); total=$((total+1))
else
  check "a GitHub Release exists with a software bill of materials attached" bash -c "gh api 'repos/$R/releases?per_page=20' --jq '.[].assets[].name' | grep -Eiq 'sbom|cdx|spdx'"
  tags=$(gh api "users/$OWNER_LC/packages/container/$NAME_LC/versions?per_page=100" --jq '.[].metadata.container.tags[]' 2>/dev/null)
  check "the package has an x.y.z tag (needs read:packages: gh auth refresh -s read:packages)" bash -c "echo '$tags' | grep -Eq '^[0-9]+\.[0-9]+\.[0-9]+\$'"
  check "the package has an x.y tag" bash -c "echo '$tags' | grep -Eq '^[0-9]+\.[0-9]+\$'"
  check "the package has the tag latest" bash -c "echo '$tags' | grep -qx latest"
fi

echo
if [ "$failn" -eq 0 ]; then echo "ALL CHECKS PASSED ($pass/$total)"; else echo "$failn check(s) failed, $pass passed. Fix the FAIL lines and run again."; fi
exit "$failn"
