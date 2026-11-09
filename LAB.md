# LAB | GitHub Actions: Cut a Release You Can Roll Back

## The situation

Yesterday your pipeline stopped bad changes from reaching `main`. Today the product owner asks a different question: *"Which version is in production right now, what is inside it, and can we go back to the previous one in five minutes if it breaks?"*

Nobody can answer. "Latest" is not a version, nobody knows which libraries ship in the image, and "going back" means rebuilding from an old commit and hoping.

A **release** is a promise: this exact, tested, scanned artifact has a name (`v1.2.3`), a list of ingredients and a written history, and the same artifact that passed staging is the one that reaches production. You will build the pipeline that makes that promise.

> **Your mission**
> - Write `.github/workflows/release.yml`: it starts when you push a tag like `v1.0.0`
> - Reuse the provided CI (`lint` and `test`) instead of copying it
> - Build, scan and publish a versioned image (`1.2.3`, `1.2`, `latest`) and attach a **software bill of materials** to a GitHub Release
> - Run the *published image* as a whole stack and smoke test it in a `staging` environment, then promote it in `production`
> - Redeploy an older version to staging in one click (the rollback path)

**Time:** 105-120 min | **Cost:** free | **You need:** a GitHub account, git, the GitHub CLI (`gh`), Docker and a terminal. `./teardown.sh` removes what the pipeline created.

---

## Part 0 - Set the scene

1. **Fork** this repository (keep it **public**), enable Actions in your fork (Actions tab, *I understand my workflows, go ahead and enable them*) and clone it.
2. Log in and add the package permissions (needed by the checks and the tear down):

```bash
gh auth login
gh auth refresh -s read:packages,delete:packages
```

3. Look at what is provided:

| File | What it is |
|------|------------|
| `Dockerfile` | the image, as before |
| `.github/workflows/ci.yml` | **lint and test**, written to be *called* by another workflow (`on: workflow_call`) |
| `compose.ci.yaml` | Pollie as a stack (API, worker, PostgreSQL, Redis) from the image named in `$IMAGE` |
| `scripts/smoke.sh` | creates a poll, votes, waits for the worker to count it |

---

## Part 1 - The trigger and the reuse

Create `.github/workflows/release.yml`:

1. Start on pushes of tags that look like `v1.2.3` (`on: push: tags: ["v[0-9]+.[0-9]+.[0-9]+"]`), **and** on `workflow_dispatch` with a required text input `version` (for the rollback, Part 7).
2. Top-level `permissions: contents: read`.
3. A job `ci` that **calls** the provided workflow: `uses: ./.github/workflows/ci.yml`. Only on tag pushes (`if: github.event_name == 'push'`).

> **Think** Copying the lint and test jobs into the release workflow works today and drifts tomorrow: someone fixes one copy. A *reusable workflow* is a function. What would you pass as parameters if `ci.yml` had to test two Python versions?

---

## Part 2 - The `image` job: build, scan, bill of materials, publish

Add a job `image` (`needs: ci`) with `permissions: contents: read` and `packages: write` (**job level**, never at the top). It must:

1. Work out the version from the tag: `v1.2.3` gives `VERSION=1.2.3` and `MINOR=1.2`. (`${GITHUB_REF_NAME#v}` and `${V%.*}` in bash.) Registry name in lower case, as in the last lab.
2. Build the image **once** with Buildx (`APP_VERSION` build argument = the version, GHA cache) into a tarball: `outputs: type=docker,dest=/tmp/pollie-image.tar`.
3. Scan the tarball with Trivy (container `aquasec/trivy:0.75.0`), failing on fixable HIGH or CRITICAL findings, exactly as before.
4. Produce the **SBOM**: the same Trivy container with `--format cyclonedx --output /tmp/sbom.cdx.json`. Upload it as an artifact.
5. Log in to `ghcr.io` and push the **scanned** image with three tags: `1.2.3`, `1.2` and `latest`.

> **Think** A software bill of materials lists every package inside the image. When the next critical library vulnerability is announced at 17:00 on a Friday, what do you do with it that you cannot do with a plain image?

> **Think** If `v1.2.3` ever pointed at different content tomorrow, what would "rollback to 1.2.3" mean? Why are version tags immutable by convention, and which of your three tags is allowed to move?

---

## Part 3 - The Release

Add a job `release` (`needs: image`) with `permissions: contents: write` (**the only job that can write to the repository**). It downloads the SBOM artifact and creates the GitHub Release:

```bash
gh release create "$GITHUB_REF_NAME" sbom.cdx.json --repo "$GITHUB_REPOSITORY" --title "$GITHUB_REF_NAME" --generate-notes
```

`--generate-notes` writes the changelog from the merged pull requests and commits since the last release. (`gh` needs `GH_TOKEN: ${{ github.token }}` in the environment of the step.)

---

## Part 4 - Staging: test the artifact, not the code

Add a job `staging` (`needs: release`) in the environment `staging` (`environment: staging`) that:

1. checks out the repository (for `compose.ci.yaml` and the smoke script);
2. logs in to `ghcr.io` (the package is **private by default**, and a job needs `packages: read` to pull it);
3. runs `docker compose -f compose.ci.yaml up -d --wait` with `IMAGE` set to **the image you just published**, then `scripts/smoke.sh http://localhost:8000`, then `docker compose -f compose.ci.yaml down -v`.

> **Think** The unit tests ran against the *code*. The smoke test runs the *image*, with its real start command, user, environment variables, healthcheck and dependencies. Name one bug a unit test cannot see and this test can. (Hint: look at what happens if the worker keeps the API's health check.)

Add `production` (`needs: staging`, `environment: production`, only for tag pushes, `packages: write`) that **promotes** the tested version without rebuilding it: pull `1.2.3`, tag it `stable`, push it.

In your fork: **Settings → Environments → production**, add yourself as **Required reviewer**. From now on the `production` job waits for a click.

> **Think** Why is the approval an *environment setting* in GitHub and not an `if:` in the YAML? Who can change each of them?

---

## Part 5 - First release

```bash
git switch -c release-pipeline
git add .github/workflows/release.yml && git commit -m "Add release pipeline"
git push -u origin release-pipeline
gh pr create --fill && gh pr merge --squash --delete-branch
git switch main && git pull
git tag v1.0.0 && git push origin v1.0.0
```

Watch it (`gh run watch`). Approve `production` when it waits. Then:

- the **Releases** page of your fork shows `v1.0.0` with the SBOM attached;
- **Packages** shows `1.0.0`, `1.0`, `latest` and `stable`;
- `gh release view v1.0.0` prints the notes.

If something fails, fix the workflow and push a **new** tag (`v1.0.1`). Do not move a tag that already published an image.

---

## Part 6 - A second release

Change something visible (for example a line in `CHANGELOG.md` or a comment in the API), merge it through a pull request, and tag `v1.1.0`. The new release notes now list that pull request.

---

## Part 7 - Roll back

Version `1.1.0` is in staging. A customer reports a problem. In the **Actions** tab (or `gh workflow run release.yml -f version=1.0.0`), run the release workflow **manually** with `version=1.0.0`.

Only `staging` runs: it pulls `1.0.0`, brings the stack up and smoke tests it. No build, no new tag, no change to the code. Compare how long this takes with "revert the commit, wait for a new build, tag, release".

> **Think** Rolling back by redeploying an *old artifact* is fast and safe because the artifact was already tested. What would make rolling back **unsafe** even so? (Think about the database.)

---

## Part 8 - Prove it

```bash
./verify.sh
```

It checks the workflow file, then what GitHub recorded: a green release run from a tag with all five jobs, a green manual run, a GitHub Release with an SBOM attached, and the `x.y.z`, `x.y` and `latest` tags in the registry. Fix what is red and run it again until it ends with **ALL CHECKS PASSED**.

> **Stuck?** `gh run view <id> --log-failed`. `unauthorized` when pulling means the staging job did not log in or lacks `packages: read`. `Resource not accessible by integration` means a job needs a permission it does not have. `repository name must be lowercase` means exactly that. `unhealthy` on a container: check which port its health check probes.

---

## Level up (optional)

- Let `release` build the notes from conventional commits (`type: feat`, `fix`) and group them.
- Sign the image with `cosign` (keyless, with the workflow's identity) and verify the signature in the staging job.
- Add a job that opens an issue when `staging` fails after a release.
- Add `docker/metadata-action` instead of computing the tags yourself. What does it do that your bash does not?

<!-- teardown:start (generated by labs.py, do not edit) -->
## Tear down (mandatory)

Resources left behind cost money, keep doors open and pollute the next lab. Removing what you created is part of the job, so it is part of the submission: **you must prove it is gone**.

Do this **last**, after you have pasted your `verify` output into `SUBMISSION.md` (once you tear down, the lab can no longer be verified).

1. Run `gh auth refresh -s read:packages,delete:packages` once, then `./teardown.sh`. It deletes the GitHub Releases and tags you created, the container package, the artifacts and disables your release workflow. Code and answers stay.

Then run the proof:

```bash
./verify-teardown.sh
```

It prints a list of checks and must end with **TEARDOWN VERIFIED**. If it reports leftovers, remove them and run it again. Paste the full output in your submission.
<!-- teardown:end -->

<!-- submission:start (generated by labs.py, do not edit) -->
## Submission

Answer the questions in `SUBMISSION.md` in **your fork** (paste output in code blocks where asked), push, then submit the **URL of your fork**.

**Files to commit**

- `.github/workflows/release.yml`: your release pipeline

**Questions to answer**

1. Paste the URL of your successful release run for `v1.0.0` and the list of its jobs. Why does the release workflow call `ci.yml` (`workflow_call`) instead of copying its jobs?
2. Paste `docker image ls` or the GHCR tag list for your release. Which tags exist for `v1.2.3` (`1.2.3`, `1.2`, `latest`?) and who is each tag for? Why must a version tag never be re-pushed?
3. Paste the URL of your GitHub Release and the name of the attached SBOM file. What does a software bill of materials give a security team when the next big CVE is announced?
4. Paste the staging smoke-test output (poll created, vote counted). Why does it test the stack of containers with real PostgreSQL and Redis rather than the Python code?
5. Describe your `staging` and `production` environments. What does a required reviewer or a wait timer protect, and why is the approval an environment setting and not part of the YAML?
6. Run the workflow manually with `version=1.0.0` after publishing `v1.1.0` (the rollback path). Paste the run URL and say what it deployed. What is the difference between rolling back by redeploying an old artifact and reverting the commit and releasing again?
7. Show the `permissions:` of each job. Which job needs `contents: write` and why only that one?
8. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.
9. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.
<!-- submission:end -->
