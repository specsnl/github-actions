# Releasing this repository

Consumers pin by tag — `…/build.yml@2.2.0`, never `@main` — so nothing here reaches anyone until a tag exists.

Tags are plain semver with no `v` prefix: `2.2.0`, `2.1.0`, `2.0.0-rc.1`.

## Cutting a release

1. Merge the pull request. This repository merges with merge commits, so every commit on the branch lands in `main`.
2. Tag the merge commit on `main` with the new version and push the tag.

Bumping the internal references is part of the change, not of the tagging: the reusable workflows call the composite
actions by tag too, so a pull request that changes an action **must** end with a commit moving
`.github/workflows/build.yml` and `merge.yml` to the version about to be cut. See commit `3765927` for the shape.

That ordering means the reference is briefly ahead of reality — `build.yml` on `main` points at a tag that does not
exist yet. Cutting the tag immediately after merging closes that window. Until then, `main` is not usable, which is
another reason consumers pin.

## Versioning

| Bump  | When                                                                                   |
|-------|----------------------------------------------------------------------------------------|
| Major | An input is removed or renamed, or a default changes what an existing caller publishes |
| Minor | A new input, workflow or action; new behaviour behind an opt-in                        |
| Patch | A fix that leaves every caller's published output the same                             |

Adding an input with a default that preserves current behaviour is a minor bump — `build-image`'s `load` and `push`
are the example. Changing which tags an existing caller gets is not.

## Announcing

`notify-slack-tag.yml` posts the tag to `#releases`. A consuming repository calls it on `push: tags`; see the
[workflow reference](workflows.md#notify-slack-tagyml).

## Keeping actions up to date

Dependabot runs daily against `github-actions` here and opens pull requests for the third-party actions used inside
the workflows and composite actions. `actionlint` is the only check that runs on them; nothing in this repository
builds an image, so a bump is only exercised for real once a consumer runs it.

Such a bump still needs a release before it reaches anyone, and it is a normal change: it needs the internal reference
commit and a tag like any other. In the consuming repositories the same dependabot updates the pin on these workflows,
and those pull requests build without publishing — see [what dependabot gets](pipeline.md#what-dependabot-gets).
