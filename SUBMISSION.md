# Submission

Fork URL: <!-- paste the URL of your fork here -->

## Files to commit

- [ ] `.github/workflows/release.yml`: your release pipeline

## Questions

Answer in your own words. Where a question asks for output, paste it in a code block.

### Q1. Paste the URL of your successful release run for `v1.0.0` and the list of its jobs. Why does the release workflow call `ci.yml` (`workflow_call`) instead of copying its jobs?

**Your answer:**

<!-- replace this line with your answer -->

### Q2. Paste `docker image ls` or the GHCR tag list for your release. Which tags exist for `v1.2.3` (`1.2.3`, `1.2`, `latest`?) and who is each tag for? Why must a version tag never be re-pushed?

**Your answer:**

<!-- replace this line with your answer -->

### Q3. Paste the URL of your GitHub Release and the name of the attached SBOM file. What does a software bill of materials give a security team when the next big CVE is announced?

**Your answer:**

<!-- replace this line with your answer -->

### Q4. Paste the staging smoke-test output (poll created, vote counted). Why does it test the stack of containers with real PostgreSQL and Redis rather than the Python code?

**Your answer:**

<!-- replace this line with your answer -->

### Q5. Describe your `staging` and `production` environments. What does a required reviewer or a wait timer protect, and why is the approval an environment setting and not part of the YAML?

**Your answer:**

<!-- replace this line with your answer -->

### Q6. Run the workflow manually with `version=1.0.0` after publishing `v1.1.0` (the rollback path). Paste the run URL and say what it deployed. What is the difference between rolling back by redeploying an old artifact and reverting the commit and releasing again?

**Your answer:**

<!-- replace this line with your answer -->

### Q7. Show the `permissions:` of each job. Which job needs `contents: write` and why only that one?

**Your answer:**

<!-- replace this line with your answer -->

### Q8. Paste the output of `./verify.sh`. It must end with **ALL CHECKS PASSED**.

**Your answer:**

<!-- replace this line with your answer -->

### Q9. **Tear down.** Paste the output of `./verify-teardown.sh`. It must end with **TEARDOWN VERIFIED**.

**Your answer:**

<!-- replace this line with your answer -->
