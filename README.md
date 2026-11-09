# Github Actions Workflows

This repository contains the Specsnl organisation collection of reusable GitHub Actions workflows.

Consumers pin by tag, i.e. `specsnl/github-actions/.github/workflows/bake.yml@4.0.0`.

## What is in here

| Kind              | Name                   | Purpose                                                                  |
|-------------------|------------------------|--------------------------------------------------------------------------|
| Reusable workflow | `bake.yml`             | Build and publish every image a repository's `docker-bake.hcl` describes |
| Bake file         | `bake/specs.hcl`       | The shared tag, label and annotation rules, vendored by each consumer    |
| Reusable workflow | `notify-slack-tag.yml` | Posts a Slack message when a tag is created                              |

What to build — Dockerfiles, stages, image names, platforms, build args — lives in the consuming repository's
`docker-bake.hcl`. This repository only provides how it is built and published in CI, so
`docker buildx bake --print` on a laptop shows exactly what CI will publish.

## Documentation

- [Building images with bake](docs/bake.md) — the consumer's `docker-bake.hcl`, `specs.hcl`, and complete examples
- [How the image pipeline works](docs/pipeline.md) — plan, build, publish, status, and the frozen definition
- [Testing an image in a pull request](docs/testing-images.md) — building, loading and running a target
- [Base images](docs/base-images.md) — why the consumer owns its Dockerfile stages
- [Reusable workflow reference](docs/workflows.md) — every input, per workflow
- [Migrating from 3.x to 4.0.0](docs/migration-4.0.md) — what changed and how to move a repository over
- [Releasing this repository](docs/releasing.md) — cutting a tag consumers can pin

## Development

```bash
task lint     # actionlint
task zizmor   # zizmor, online audits when GH_TOKEN is set
task test     # specs.hcl fixture tests, plan job tests, SPECS_HCL_SHA256
```
