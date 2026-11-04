# PHP images

`build-php.yml` and `merge-php.yml` publish the two stages of a Specs PHP image. They are thin shims over
[`build.yml` and `merge.yml`](workflows.md), holding only the PHP-specific part: which stages get published, and under
what name.

```yaml
jobs:

  build:
    uses: specsnl/github-actions/.github/workflows/build-php.yml@2.4.4
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
      image-name: ghcr.io/${{ github.repository }}

  merge:
    needs: build
    uses: specsnl/github-actions/.github/workflows/merge-php.yml@2.4.4
    with:
      runs-on: ubuntu-24.04
      image-name: ghcr.io/${{ github.repository }}
```

Each shim fans out into one `build.yml` / `merge.yml` call per stage, so a single call publishes both.

A repository publishing several flavours of the same PHP version — `fpm`, `apache`, `frankenphp` — adds a second
matrix dimension over `dockerfile` / `image-name` pairs, and matches it with a matrix over `image-name` on the merge
job. `specsnl/php84` is the reference.

## What gets published

| Dockerfile target | Image name             | Also tagged as                                     |
|-------------------|------------------------|----------------------------------------------------|
| `runtime`         | `<image-name>`         | —                                                  |
| `builder`         | `<image-name>/builder` | `<image-name>/builder_nodejs`, `<image-name>/node` |

The runtime stage is the image itself; the builder is a separate, nested package with its own `:latest`. That
is the right shape here — a builder image is a different product from the runtime, not a variant of it. A CLI that
ships several base images does the opposite and uses [tag suffixes on one name](go-cli.md#publishing-variants).

The builder includes Node.js. It used to be split into a `builder` stage without Node.js and a `builder_nodejs` stage
with it, published as `/builder_nodejs` and `/node`. Those names are now tagged from the same manifest as `/builder`,
so projects that still pull them keep working; they are deprecated and will be removed in a later major version.

## Titles and descriptions

`build-php.yml` takes one `title` / `description` pair for both stages. `merge-php.yml` takes them per stage —
`title-runtime`, `title-builder` and their `description-*` counterparts — because that is where the manifest is tagged
and where the labels end up mattering per package. The builder's pair applies to all three of its names.

## AppArmor

`disable-apparmor: true` disables AppArmor on the runner before building, for images whose build steps it interferes
with. It is forwarded to `build.yml` unchanged.
