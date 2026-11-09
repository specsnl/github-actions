---
description: Safely update this project's dependencies in isolated commits
name: update-project
---

# Goal

Perform a full dependency update in a safe, reproducible way using the repository execution model.

If any step fails, STOP immediately and report the error.

## Phase 1 --- Repository Safety Checks

1. Verify the current branch is `main`. If not, abort and instruct the user to switch to `main` first.
2. Ensure the working (git) tree is clean:
    - No staged changes
    - No unstaged changes
    - No untracked files
    - If not clean: Abort immediately
        - Inform the user to commit or stash changes
3. Synchronize with remote: `git fetch --prune`
4. Prepare branch `vendor-updates`:
    - If branch does not exist → create from `origin/main`
    - If branch exists:
        - If fully merged into `main` → delete locally and recreate from `origin/main`.
        - If behind on `main` and has NO unique commits → reset `vendor-updates` to `origin/main`.
        - If it contains unique commits → abort and notify user.
5. Check if the branch does not already exist on the remote. If it does, abort and inform the user to delete the
remote branch first.

Always branch from latest `origin/main`.

## Phase 2 --- GitHub Actions Updates

1. Scan `.github/workflows/*.yml` for `uses:` action references. They are pinned by commit SHA with the version in a
comment, e.g. `actions/checkout@3d3c42e5aac5ba805825da76410c181273ba90b1 # v7.0.1`.
2. For each external action, use the GitHub Releases API to find the latest release tag. Check every action
individually — a newer major version may exist.
3. If a newer release exists, replace the SHA with the commit SHA of that release's tag and update the version comment.
Use the same SHA and comment everywhere the action is used.
4. Check the `rhysd/actionlint` and `zizmorcore/zizmor` versions too: update the version (and the image digest) in
`.github/workflows/lint.yml` and the matching variables in `Taskfile.dist.yml` together.
5. Check `git status` for all changed files. Commit separately if there are any changes.
Commit message: `chore(deps): Update GitHub Actions versions`.
6. If there are no changes, skip the commit step and move on to the next phase.

Abort on any failure.

## Phase 3 --- License Year Update

1. Check if the `LICENSE` file contains a year range (e.g. `2020-2025`) or a single year (e.g. `2024`).
2. If the current year (2026) is not already the end year:
   - If the LICENSE file contains a single year (e.g. `2024`) → update it to the current year: `2026`.
   - If the LICENSE file contains a year range (e.g. `2020-2025`) → update the end year: `2020-2026`.
3. If the LICENSE file already ends with the current year (e.g. `2024-2026` or `2026`), no update is needed.
4. Commit separately if there are any changes.
Commit message: `chore: Update copyright year`.
5. If there are no changes, skip the commit step.

------------------------------------------------------------------------

## Final State

Abort if there are no changes after all update steps, and inform the user that everything is already up to date.

- There could be up to 2 commits on the `vendor-updates` branch:
    1. GitHub Actions version updates
    2. Copyright year update
- Branch: `vendor-updates`
- Based on latest `origin/main`.
- The working tree should be clean.
- Push the branch to the remote and create a pull request for review and merging targeting `origin/main`. The title
should be `chore: Update dependencies`.
- Add a Pull Request description that lists the changes based on the commits that were made. Stick to the
commit messages, but remove the "chore" prefix. Include a post-merge task section with a checkbox to create the
new git tag. For example:

```md
Updated the following dependencies:

- Updated GitHub Actions versions
- Updated copyright year

## Post-merge tasks

- [ ] Create and push the next patch tag
```
