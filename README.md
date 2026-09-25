# Github Actions Workflows and Composite Actions

This repository contains the Specsnl organisation collection of GitHub Actions workflows and composite actions that can
be reused to automate various tasks in GitHub repositories.

Consumers pin by tag, i.e. `specsnl/github-actions/.github/workflows/build.yml@2.4.4`.

## What is in here

| Kind              | Name                   | Purpose                                                                        |
|-------------------|------------------------|--------------------------------------------------------------------------------|
| Composite action  | `build-image`          | Build one platform of an image and push it by digest, or load it for testing   |
| Composite action  | `create-manifest`      | Merge the per-platform digests into one multi-arch manifest and tag it         |
| Reusable workflow | `build.yml`            | `build-image` plus the checkout / login / buildx boilerplate around it         |
| Reusable workflow | `merge.yml`            | `create-manifest` plus the same boilerplate                                    |
| Reusable workflow | `build-php.yml`        | Builds the PHP stages (`runtime`, `builder`, `builder_nodejs`) via `build.yml` |
| Reusable workflow | `merge-php.yml`        | Merges those same stages via `merge.yml`                                       |
| Reusable workflow | `build-go-cli.yml`     | Builds a Go CLI image via `build.yml`, injecting the version as a build arg    |
| Reusable workflow | `merge-go-cli.yml`     | Merges it via `merge.yml` with the semver tag set a CLI release wants          |
| Reusable workflow | `notify-slack-tag.yml` | Posts a Slack message when a tag is created                                    |

The language-specific workflows are thin shims: they hold only the part that is actually specific to that language and
delegate everything else to the generic pair.

## Documentation

- [How the image pipeline works](docs/pipeline.md) — the two phases, digests, tags and what dependabot gets
- [Go CLI images](docs/go-cli.md) — version injection, the tag set, publishing variants
- [PHP images](docs/php.md) — which stages are published and under what name
- [Base images](docs/base-images.md) — why these workflows take a Dockerfile target and not a base image
- [Testing an image in a pull request](docs/testing-images.md) — building without pushing and running the result
- [Reusable workflow reference](docs/workflows.md) — every input, per workflow
- [Composite action reference](docs/actions.md) — every input and output, per action
- [Releasing this repository](docs/releasing.md) — cutting a tag consumers can pin

## Linting

```bash
task lint
```
