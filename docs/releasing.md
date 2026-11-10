# Releasing this repository

Consumers pin by tag — `…/bake.yml@4.0.0`, never `@main` — so nothing here reaches anyone until a tag exists.

Tags are plain semver with no `v` prefix: `4.0.0`, `3.0.2`, `2.0.0-rc.1`.

## Cutting a release

1. Merge the pull request. This repository merges with merge commits, so every commit on the branch lands in `main`.
2. Tag the merge commit on `main` with the new version and push the tag.

There is nothing to bump before tagging. `bake.yml` reaches its own scripts and `specs.hcl` through the composite
actions under `bake/`, called with the `$/` self-repository syntax, which always resolves to the commit that is
running. A tag can't ship with references to an older one, which is how `3.0.1` shipped without its fix. `lint.yml`
fails when a workflow starts referencing this repository by tag again.

## `specs.hcl`

Consumers get `specs.hcl` from the version of `bake.yml` they call, so a change to it reaches them with the next tag
they move to. It changes what they publish, so check the fixture test diff as carefully as the change itself.
`task test:update` rewrites the expected output of the fixture and pipeline tests.

## Versioning

| Bump  | When                                                                                                                                |
|-------|-------------------------------------------------------------------------------------------------------------------------------------|
| Major | An input is removed or renamed, a job or check is renamed, or a tag rule in `specs.hcl` changes what an existing consumer publishes |
| Minor | A new input, workflow or `specs.hcl` function; new behaviour behind an opt-in                                                       |
| Patch | A fix that leaves every consumer's published output the same                                                                        |

Changing which tags or labels an existing consumer gets is a major bump, even when it is a fix.

## Announcing

`notify-slack-tag.yml` posts the tag to the channel of the webhook. A consuming repository calls it on `push: tags`;
see the [workflow reference](workflows.md#notify-slack-tagyml).

## Keeping actions up to date

Every action is pinned by commit SHA, with its version in a comment. Dependabot checks them weekly and groups the
updates into one pull request. `lint.yml` and `test-bake.yml` run on it; `test-bake.yml` builds a test image through
`bake.yml`, so a bump is exercised before it is released.

The actionlint and zizmor versions are not updated by dependabot. Keep the ones in `lint.yml` in step with
`ACTIONLINT_TAG_VERSION` and `ZIZMOR_VERSION` in `Taskfile.dist.yml`.

`.github/actionlint.yaml` works around what actionlint 1.7.12 doesn't know yet: the `ubuntu-26.04` runner labels, and
the `$/` self-repository syntax `test-bake.yml` uses to call `bake.yml`
([rhysd/actionlint#711](https://github.com/rhysd/actionlint/issues/711)). Remove each part once an actionlint release
supports it.

To exercise the publish job as well, run `test-bake.yml` manually with `push` on. It publishes
`ghcr.io/specsnl/github-actions/e2e` and `…/e2e-cli`.
