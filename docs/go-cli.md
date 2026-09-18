# Go CLI images

`build-go-cli.yml` and `merge-go-cli.yml` publish a Go binary as a container image. They are thin shims over
[`build.yml` and `merge.yml`](workflows.md): the build shim only composes the version build arg, the merge shim only
adds the tag set a CLI release wants. Everything else — checkout, login, buildx, digests, the manifest — is the
generic pipeline described in [How the image pipeline works](pipeline.md).

## A release workflow

```yaml
name: Release

on:
  push:
    tags: ['v*']

permissions:
  contents: read
  packages: write

jobs:

  build:
    uses: specsnl/github-actions/.github/workflows/build-go-cli.yml@2.4.2
    strategy:
      fail-fast: false
      matrix:
        runner:
          - os: ubuntu-24.04
            platform: linux/amd64
          - os: ubuntu-24.04-arm
            platform: linux/arm64
    with:
      runs-on: ${{ matrix.runner.os }}
      platform: ${{ matrix.runner.platform }}
      image-name: ghcr.io/specsnl/specs-cli
      target: debian
      version-build-arg: SPECS_VERSION

  merge:
    needs: build
    uses: specsnl/github-actions/.github/workflows/merge-go-cli.yml@2.4.2
    with:
      runs-on: ubuntu-24.04
      image-name: ghcr.io/specsnl/specs-cli
      target: debian
```

`target` is the Dockerfile stage to publish. The consuming repository owns its stages — see
[Base images](base-images.md) for why that is not an input here.

## Version injection

Go CLIs carry their version in an ldflag, so it has to be known at build time or the image reports its fallback
(`dev`). `build-go-cli.yml` passes it to the Dockerfile as the build arg named by `version-build-arg`; the Dockerfile
keeps ownership of the ldflag itself, which is how every Go repository in the org is already written:

```dockerfile
ARG GO_MODULE=github.com/specsnl/specs-cli
ARG SPECS_VERSION=dev

RUN CGO_ENABLED=0 go build \
        -ldflags "-s -w -X ${GO_MODULE}/internal/cmd.Version=${SPECS_VERSION}" -o ./specs
```

On a tag push the version defaults to **the tag without its leading `v`** — `v1.2.3` becomes `1.2.3` — so the
examples above pass no `version` at all. That default is not cosmetic. Every Go repository in the org also releases
through GoReleaser, which strips the `v` when it injects the same ldflag; passing `${{ github.ref_name }}` straight
through would publish an image reporting `v1.2.3` while the binary from that very tag reports `1.2.3`.

Pass `version` explicitly to override it — to build a release from something other than its tag, or to stamp a version
on a branch build. On any trigger that is not a tag push the default is empty, and the build arg is then omitted
rather than passed empty, so the Dockerfile's own fallback stands.

`version-build-arg` has no default on purpose, and is the one input here that genuinely cannot have one. The arg is
named after the binary and differs per repository (`SPECS_VERSION`, `LABELSYNC_VERSION`, …), and a wrong value fails
silently: buildx warns about an unused build arg, the build succeeds, and the image reports `dev`. Assert the version
in a [pull-request guard](testing-images.md) so that stays impossible to ship.

Anything else the Dockerfile needs goes through `build-args`, which is appended to the version arg.

`merge-go-cli.yml` needs no `version` either: `metadata-action` already labels the image
`org.opencontainers.image.version` with the version it computed. The input is there to override that, which is rarely
what anyone wants.

## Tags

On top of what [`merge.yml` already emits](pipeline.md#tags):

| Tag                          | When                                                                   |
|------------------------------|------------------------------------------------------------------------|
| `1.2.3`                      | Every `v*` tag, prereleases included                                   |
| `1.2`, `1`                   | Stable tags only; `1` is skipped for `v0.*` and `1.2` for `v0.0.*`     |
| `latest`                     | Stable tags only — set `latest: false` to never move it                |
| `v1.2.3`                     | From `merge.yml`'s `type=ref,event=tag`; the same digest, `v`-prefixed |
| `main`, `pr-12`, `<raw-tag>` | From `merge.yml`, for branch, pull request and dispatch runs           |

A prerelease never moves `latest` and never publishes `1.2` or `1`:

- `metadata-action` collapses every semver pattern to the full version when the tag is a prerelease, so
  `pattern={{major}}` yields `1.2.0-rc.1` rather than `1`.
- `:latest` would otherwise still move, because `type=ref,event=tag` sets it under the default `latest=auto`. This
  workflow passes `flavor: latest=false` and re-adds `latest` itself, guarded on the tag being stable.

That guard treats any tag containing a `-` as a prerelease — `v1.2.0-rc.1`, `v1.2.0-beta.3`.

A moving tag is a compatibility promise, so it is withheld where semver does not make one. `1` means nothing under
`v0.*` — every minor may break. `1.2` means nothing under `v0.0.*` for the same reason one level down, since `0.0.x` is
the range where every release is free to break. `v0.5.3` still publishes `0.5`, because patches within `0.5.x` are
expected to be compatible.

Both `flavor` and `raw-tags` are still available and are appended *after* what this workflow sets, so a caller can
override the flavor (`latest=auto` restores the default behaviour) and add tags of its own.

## Publishing variants

A repository that publishes more than one base image variant publishes them as **tag suffixes on one image name**, the
way `node`, `python` and `postgres` do — not as a second, nested image name with its own `:latest`, which is what the
[PHP pair](php.md) does for its builder stages. A CLI is one thing; `alpine` is a property of the image it ships in,
not a different product.

Run the build and merge jobs once per variant, each with its own `target`:

```yaml
  build-alpine:
    uses: specsnl/github-actions/.github/workflows/build-go-cli.yml@2.4.2
    strategy:
      fail-fast: false
      matrix:
        runner:
          - os: ubuntu-24.04
            platform: linux/amd64
          - os: ubuntu-24.04-arm
            platform: linux/arm64
    with:
      runs-on: ${{ matrix.runner.os }}
      platform: ${{ matrix.runner.platform }}
      image-name: ghcr.io/specsnl/specs-cli
      target: alpine
      version-build-arg: SPECS_VERSION

  merge-alpine:
    needs: build-alpine
    uses: specsnl/github-actions/.github/workflows/merge-go-cli.yml@2.4.2
    with:
      runs-on: ubuntu-24.04
      image-name: ghcr.io/specsnl/specs-cli
      target: alpine
      variant: alpine
```

`variant: alpine` yields `specs-cli:1.2.3-alpine` and a bare `specs-cli:alpine`, alongside the unsuffixed primary
variant from the jobs above. The digests do not collide: they are namespaced per target.

Under the hood that is `flavor: suffix=-alpine,onlatest=true` for the version tags, plus a `type=raw` tag carrying an
empty `suffix=` so the bare `:alpine` does not come out as `alpine-alpine`.

## Consumers

- **specsnl/specs-cli** — the first consumer, debian-only for now.
- **specsnl/labelsync** — same layout and a `Dockerfile` already, no image pipeline yet.
- **specsnl/specsdeployd** — a daemon installed from a GitHub release onto a host systemd unit. Its `Dockerfile` stops
  at `export` and ships only the binary, so it is not a consumer unless that changes.
