"""Static checks on .github/workflows/release.yml. Usage: workflow_lint.py <check>. Exit 0 = pass."""
import re
import sys

import yaml

raw = open(".github/workflows/release.yml").read()
w = yaml.safe_load(raw)
on = w.get(True, w.get("on", {})) or {}
jobs = w.get("jobs", {})
check = sys.argv[1]


def find_job(word):
    return [k for k in jobs if word in k.lower() or word in str(jobs[k].get("name", "")).lower()]


def perm(j, key):
    p = jobs[j].get("permissions", {})
    return p.get(key) if isinstance(p, dict) else None


if check == "triggers":
    tags = str((on.get("push") or {}).get("tags", ""))
    wd = on.get("workflow_dispatch")
    ok = "v" in tags and isinstance(wd, dict) and bool(wd.get("inputs"))
elif check == "reuse":
    ok = bool(re.search(r"uses:\s*\./\.github/workflows/ci\.yml", raw))
elif check == "permissions":
    p = w.get("permissions")
    ok = p is not None and (p == "read-all" or (isinstance(p, dict) and all(v in ("read", "none") for v in p.values())))
elif check == "pins":
    ok = not re.search(r"uses:\s*\S+@(main|master|latest)\s*$", raw, re.M)
elif check == "writes":
    top = w.get("permissions", {})
    top_bad = isinstance(top, dict) and ("packages" in top and top["packages"] == "write" or top.get("contents") == "write")
    rel = find_job("release")
    ok = not top_bad and bool(rel) and any(perm(j, "contents") == "write" for j in rel)
    others = [k for k in jobs if k not in rel and perm(k, "contents") == "write"]
    ok = ok and not others
elif check == "scan":
    ok = bool(re.search(r"trivy", raw, re.I)) and bool(re.search(r"--exit-code[ =]1|exit-code:\s*[\"']?1", raw))
elif check == "sbom":
    ok = bool(re.search(r"cyclonedx|spdx|sbom", raw, re.I))
elif check == "envs":
    ok = bool(re.search(r"environment:\s*staging", raw)) and bool(re.search(r"environment:\s*production", raw))
elif check == "smoke":
    ok = "compose.ci.yaml" in raw and "smoke.sh" in raw
elif check == "release":
    ok = bool(re.search(r"gh release create|softprops/action-gh-release|actions/create-release", raw))
elif check == "tags":
    ok = bool(re.search(r"latest", raw)) and bool(re.search(r"MINOR|minor|%\.\*|major\.minor|semver|metadata-action", raw))
else:
    ok = False
sys.exit(0 if ok else 1)
