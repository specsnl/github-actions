# Building images with bake

A repository publishes its images with one call to [`bake.yml`](workflows.md#bakeyml). What to build lives in the
repository itself, in two bake files:

| File              | Owner                    | Contents                                                     |
|-------------------|--------------------------|--------------------------------------------------------------|
| `specs.hcl`       | This repository          | The tag, label and annotation rules, copied in unchanged     |
| `docker-bake.hcl` | The consuming repository | The targets: Dockerfile, stage, platforms, args, image names |

Read the [bake documentation](https://docs.docker.com/build/bake/) for the HCL syntax: variables, functions,
`inherits` and `matrix` are all used below.

## Getting `specs.hcl`

Copy `bake/specs.hcl` from this repository, at the tag you pin `bake.yml` at, to `specs.hcl` in the root of the
consuming repository:

```bash
curl -fsSLo specs.hcl https://raw.githubusercontent.com/specsnl/github-actions/4.0.0/bake/specs.hcl
```

Don't edit the copy. The plan job compares it with the one its own version expects and warns in the run summary when
they differ, so update it whenever you move `bake.yml` to a new tag. Put it somewhere else by setting the
`specs-file` input.

A Taskfile task keeps both in one place:

```yaml
vars:
  SPECS_ACTIONS_VERSION: "4.0.0"

tasks:
  specs-hcl:
    desc: Update specs.hcl to the version of bake.yml in use
    cmd: curl -fsSLo specs.hcl https://raw.githubusercontent.com/specsnl/github-actions/{{.SPECS_ACTIONS_VERSION}}/bake/specs.hcl
```

## Building locally

```bash
docker buildx bake -f specs.hcl -f docker-bake.hcl --print   # what would be built, with every tag and label
docker buildx bake -f specs.hcl -f docker-bake.hcl            # build it
```

Locally the variables below keep their defaults: every image is tagged `:local` and labelled with version `dev`. To see
what a release would publish, set the variables the plan job would set:

```bash
EVENT=push REF_TYPE=tag VERSION=1.2.3 IS_STABLE=true \
  docker buildx bake -f specs.hcl -f docker-bake.hcl --print
```

## The variables CI sets

The plan job works these out once per run and passes them to bake as environment variables. Use them in your own HCL
too — `VERSION` is the usual one, for a version build arg.

| Variable       | Local default | In CI                                                                                    |
|----------------|---------------|------------------------------------------------------------------------------------------|
| `VERSION`      | `dev`         | See below                                                                                |
| `EVENT`        | *empty*       | The event name: `push`, `pull_request`, `schedule`, `workflow_dispatch`, …               |
| `REF_TYPE`     | *empty*       | `tag` or `branch`                                                                        |
| `REF_NAME`     | *empty*       | The tag or branch name                                                                   |
| `PR_NUMBER`    | *empty*       | The pull request number                                                                  |
| `DISPATCH_TAG` | `latest`      | The `dispatch-tag` input, lowercased                                                     |
| `IS_STABLE`    | `false`       | `true` on a tag push whose version has no `-` in it                                      |
| `REVISION`     | *empty*       | The commit SHA                                                                           |
| `SOURCE`       | *empty*       | The repository URL                                                                       |
| `CREATED`      | *empty*       | One timestamp for the whole run, so every platform and every target carries the same one |

`VERSION` is, in this order:

1. The `version` input, if given.
2. On a tag push: the tag, without a leading `v` when a digit follows it — `v1.2.3` becomes `1.2.3`, `version-2`
   stays `version-2`. This is the string GoReleaser injects too, so an image never disagrees with the binary cut
   from the same tag.
3. On a pull request: `pr-<number>`. On a branch push: the branch name. On a schedule: `nightly`. On
   `workflow_dispatch`: the dispatch tag.
4. Anything else: empty, and the version label is left out.

## The `specs.hcl` functions

### `specs_tags(images, variant)`

Every image name in `images`, lowercased, crossed with the tags this run publishes:

| Run                                  | Tags                                                           |
|--------------------------------------|----------------------------------------------------------------|
| Tag push, stable semver (`v1.2.3`)   | `1.2.3`, `1.2`, `1`, `latest`                                  |
| Tag push, `v0.x` (`v0.5.3`)          | `0.5.3`, `0.5`, `latest` — `0` would promise nothing under 0.x |
| Tag push, `v0.0.x` (`v0.0.5`)        | `0.0.5`, `latest`                                              |
| Tag push, prerelease (`v1.2.3-rc.1`) | `1.2.3-rc.1` only: no moving tags, no `latest`                 |
| Tag push, not semver (`2026.11`)     | The version, plus `latest` when it has no `-`                  |
| Pull request                         | `pr-<number>`                                                  |
| Branch push                          | The branch name, i.e. `main`                                   |
| Schedule                             | `nightly`                                                      |
| `workflow_dispatch`                  | The dispatch tag, `latest` by default                          |
| Local build                          | `local`                                                        |
| Any other event                      | None — nothing to push, so the run builds without pushing      |

A non-empty `variant` is appended to every tag as a suffix — `1.2.3-alpine`, `1.2-alpine`, `pr-12-alpine` — and on a
stable release the bare variant name takes the place of `latest`: `alpine`. That is how `node`, `python` and
`postgres` publish their variants: one image name, tag suffixes.

Characters a tag can't hold are replaced with `-`, so the branch `feature/foo` is tagged `feature-foo`.

### `specs_labels(title, description)`

The `org.opencontainers.image.*` labels: `version`, `revision`, `source`, `url`, `created`, and the given `title` and
`description`. An empty value is left out rather than written as `""`. `source` is what links the package to its
repository on GHCR.

### `specs_annotations(title, description)`

The same values as `specs_labels`, as annotations on each platform's image manifest. The publish job copies the labels
onto the multi-platform index and its descriptors as well, so every level reports the same version.

## Writing `docker-bake.hcl`

- The `default` group lists what CI publishes. Use the `targets` input to build something else.
- Every target needs `platforms`: the build fans out over them, one job per platform.
- Set `tags`, `labels` and `annotations` with the functions above. The first image name of a target is the one it is
  pushed under; the others are tagged from the same manifest.
- Don't set `output` or `cache-from` / `cache-to`: CI replaces them with a push by digest and a GitHub Actions cache
  per image, target and platform. Locally they work as usual.
- Build secrets come from the `build-secrets` secret, as environment variables:
  `secret = ["id=composer_auth,env=COMPOSER_AUTH"]`.
- Provenance and SBOM attestations are off by default. Turn them on per target with
  `attest = ["type=provenance,mode=max", "type=sbom"]`; GHCR lists each one as an extra `unknown/unknown` platform.

## Examples

Each example is a complete `docker-bake.hcl`, used next to `specs.hcl`.

### A plain image

One Dockerfile, one stage, one image — `specsnl/utils`:

```hcl
target "default" {
  platforms   = ["linux/amd64", "linux/arm64"]
  tags        = specs_tags(["ghcr.io/specsnl/utils"], "")
  labels      = specs_labels("utils", "")
  annotations = specs_annotations("utils", "")
}
```

A tag push of `v1.19.0` publishes `utils:1.19.0`, `utils:1.19`, `utils:1` and `utils:latest`.

### A PHP image

`specsnl/php84` publishes three flavours, each with a `runtime` and a `builder` stage, from three Dockerfiles. All six
images build from one call, and per platform in one job, so a flavour's two stages share their layers.

```hcl
variable "IMAGE" {
  default = "ghcr.io/specsnl/php84"
}

variable "FLAVOURS" {
  default = [
    { name = "fpm", image = "" },
    { name = "apache", image = "/apache" },
    { name = "frankenphp", image = "/frankenphp" },
  ]
}

group "default" {
  targets = ["runtime", "builder"]
}

target "_php" {
  platforms = ["linux/amd64", "linux/arm64"]
}

target "runtime" {
  name        = "runtime-${flavour.name}"
  matrix      = { flavour = FLAVOURS }
  inherits    = ["_php"]
  dockerfile  = "${flavour.name}/Dockerfile"
  target      = "runtime"
  tags        = specs_tags(["${IMAGE}${flavour.image}"], "")
  labels      = specs_labels("PHP 8.4 ${flavour.name}", "")
  annotations = specs_annotations("PHP 8.4 ${flavour.name}", "")
}

target "builder" {
  name       = "builder-${flavour.name}"
  matrix     = { flavour = FLAVOURS }
  inherits   = ["_php"]
  dockerfile = "${flavour.name}/Dockerfile"
  target     = "builder"
  tags = specs_tags([
    "${IMAGE}${flavour.image}/builder",
    "${IMAGE}${flavour.image}/builder_nodejs",
    "${IMAGE}${flavour.image}/node",
  ], "")
  labels      = specs_labels("PHP 8.4 ${flavour.name} builder", "")
  annotations = specs_annotations("PHP 8.4 ${flavour.name} builder", "")
}
```

The runtime stage is the image itself; the builder is a separate, nested package with its own `:latest`. That is the
right shape here — a builder image is a different product from the runtime, not a variant of it.

`builder_nodejs` and `node` are the builder's old names. Projects still pull them — the Dockerfiles generated from
`specsnl/specs-laravel-project` use `/builder_nodejs` — so keep tagging them until those have moved to `/builder`, then
drop the two lines.

### A Go CLI with variants

`specsnl/specs-cli` with a `debian` and an `alpine` stage, and its version passed to the Dockerfile as a build arg:

```hcl
group "default" {
  targets = ["cli"]
}

target "cli" {
  name        = "cli-${variant}"
  matrix      = { variant = ["debian", "alpine"] }
  target      = variant
  platforms   = ["linux/amd64", "linux/arm64"]
  args        = { SPECS_VERSION = VERSION }
  tags        = specs_tags(["ghcr.io/specsnl/specs-cli"], variant == "debian" ? "" : variant)
  labels      = specs_labels("specs-cli", "")
  annotations = specs_annotations("specs-cli", "")
}
```

A tag push of `v1.2.3` publishes `1.2.3`, `1.2`, `1` and `latest` from `debian`, and `1.2.3-alpine`, `1.2-alpine`,
`1-alpine` and `alpine` from `alpine`. A prerelease publishes only `1.2.3-rc.1` and `1.2.3-rc.1-alpine`.

The Dockerfile keeps ownership of the ldflag, and its own fallback for local builds without bake:

```dockerfile
ARG GO_MODULE=github.com/specsnl/specs-cli
ARG SPECS_VERSION=dev

RUN CGO_ENABLED=0 go build \
        -ldflags "-s -w -X ${GO_MODULE}/internal/cmd.Version=${SPECS_VERSION}" -o ./specs
```

A wrong arg name shows up in `docker buildx bake --print`, and buildx warns about an unused build arg. Assert the
version in a [pull request test](testing-images.md) as well, so it can't ship.

On an event without a version (see above) `VERSION` is empty, and `SPECS_VERSION = VERSION` passes it empty. Write
`args = VERSION == "" ? {} : { SPECS_VERSION = VERSION }` if the Dockerfile's fallback should stand then.

## Calling the workflow

```yaml
name: Image

on:
  push:
    branches: [main]
    tags: ['v*']
  pull_request:
  workflow_dispatch:
    inputs:
      tag:
        description: Tag to publish
        default: latest

permissions:
  contents: read
  packages: write

concurrency:
  group: ${{ github.workflow }}-${{ github.ref }}
  cancel-in-progress: true

jobs:
  image:
    uses: specsnl/github-actions/.github/workflows/bake.yml@4.0.0
    with:
      dispatch-tag: ${{ inputs.tag }}
    secrets:
      build-secrets: |
        COMPOSER_AUTH=${{ secrets.COMPOSER_AUTH }}
```

The caller grants `contents: read` and `packages: write`. Require the check `image / Image` — the calling job's name,
then the workflow's `Image` job — in the branch protection rules or ruleset. It covers every image the call publishes.

See [How the image pipeline works](pipeline.md) for what happens inside, and the
[workflow reference](workflows.md#bakeyml) for every input.
