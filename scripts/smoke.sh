#!/usr/bin/env bash
# Provided. Smoke test of a running Pollie API: create a poll, vote, see the vote counted.
# Usage: scripts/smoke.sh [base-url]      (default http://localhost:8000)
set -u
B=${1:-http://localhost:8000}
j() { python3 -c "import json,sys;print(json.load(sys.stdin)$1)"; }
poll=$(curl -fsS -X POST -H 'content-type: application/json' -d '{"question":"Smoke test?","options":["yes","no"]}' "$B/polls") || { echo "FAIL: cannot create a poll"; exit 1; }
pid=$(echo "$poll" | j '["id"]'); oid=$(echo "$poll" | j '["options"][0]["id"]')
body=$(printf '{"option_id":%s,"voter_id":"smoke-%s"}' "$oid" "$$")
code=$(curl -s -o /dev/null -w '%{http_code}' -X POST -H 'content-type: application/json' -d "$body" "$B/polls/$pid/votes")
[ "$code" = 202 ] || { echo "FAIL: vote answered $code"; exit 1; }
for i in $(seq 1 20); do
  n=$(curl -fsS "$B/polls/$pid/results" | j '["total_votes"]')
  [ "$n" = 1 ] && { echo "OK: poll $pid created, vote queued, worker stored it (total_votes=1)"; exit 0; }
  sleep 1
done
echo "FAIL: the vote was never counted (is the worker running?)"; exit 1
