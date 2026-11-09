# Migrating from 3.x to 4.0.0

4.0.0 replaces every build and merge workflow, and both composite actions, with one reusable workflow, `bake.yml`. What
to build moves out of workflow inputs into a `docker-bake.hcl` in the consuming repository. A repository that hasn't
migrated keeps working on `@3.0.2`; there is no need to move every repository at once.

The migration per repository:

1. Copy `specs.hcl` in — see [Getting `specs.hcl`](bake.md#getting-specshcl).
2. Write `docker-bake.hcl` from the old inputs (below).
3. Check it locally with `docker buildx bake -f specs.hcl -f docker-bake.hcl --print`, with the
   [CI variables](bake.md#building-locally) of a release set, against the tags the last 3.x release published.
4. Replace every build and merge job with one `bake.yml` call.
5. Update the required checks in the same change: `image / Image` replaces the `Build Image` and `Merge Images`
   checks.

## Before and after

`specsnl/utils`, a plain image, had a build and a merge job in each of its `main.yml`, `pr.yml` and `tag.yml`:

```yaml
jobs:
  build:
    name: Build
    uses: specsnl/github-actions/.github/workflows/build.yml@3.0.2
    strategy:
      fail-fast: false
      matrix:
        runs-on:
          - os: ubuntu-26.04
            platform: linux/amd64
          - os: ubuntu-26.04-arm
            platform: linux/arm64
    with:
      runs-on: ${{ matrix.runs-on.os }}
      platform: ${{ matrix.runs-on.platform }}
      image-name: ghcr.io/${{ github.repository }}

  merge:
    name: Merge
    uses: specsnl/github-actions/.github/workflows/merge.yml@3.0.2
    needs: build
    with:
      runs-on: ubuntu-26.04
      image-name: ghcr.io/${{ github.repository }}
```

With 4.0.0 the platforms and the image name move to `docker-bake.hcl`:

```hcl
target "default" {
  platforms   = ["linux/amd64", "linux/arm64"]
  tags        = specs_tags(["ghcr.io/specsnl/utils"], "")
  labels      = specs_labels("", "")
  annotations = specs_annotations("", "")
}
```

and each workflow keeps one job:

```yaml
jobs:
  image:
    uses: specsnl/github-actions/.github/workflows/bake.yml@4.0.0
```

The runners `ubuntu-26.04` and `ubuntu-26.04-arm` are the defaults, so the runner matrix disappears entirely.

The PHP and Go CLI repositories follow the same pattern with the [PHP](bake.md#a-php-image) and
[Go CLI](bake.md#a-go-cli-with-variants) examples. For `specsnl/php84` that turns a build matrix of three Dockerfiles
times two runners, and a merge matrix of three images, into one call.

## From the old inputs to HCL

| 3.x input                                          | 4.0.0                                                                                                   |
|----------------------------------------------------|---------------------------------------------------------------------------------------------------------|
| `runs-on` + `platform` (the runner matrix)         | `platforms` per target; `runners` input only to change a platform's runner                              |
| `image-name`                                       | The image names given to `specs_tags`; lowercased for you                                               |
| `image-name` with several lines                    | Several image names in one `specs_tags` call                                                            |
| `dockerfile`                                       | `dockerfile` on the target                                                                              |
| `context`                                          | `context` on the target                                                                                 |
| `target`                                           | `target` on the target                                                                                  |
| `build-args`                                       | `args` on the target                                                                                    |
| `secrets` (string input)                           | The `build-secrets` secret, plus `secret = ["id=…,env=…"]` on the target                                |
| `version-build-arg` (Go CLI)                       | `args = { SPECS_VERSION = VERSION }`                                                                    |
| `title`, `description`, `title-*`, `description-*` | The arguments of `specs_labels` and `specs_annotations`                                                 |
| `variant` (Go CLI)                                 | The second argument of `specs_tags`                                                                     |
| `latest` (Go CLI)                                  | Gone: a stable release always moves `latest`. Leave out `specs_tags` and write your own tags to opt out |
| `raw-tag`                                          | The `dispatch-tag` input                                                                                |
| `raw-tags`, `flavor`                               | Gone: append tags in HCL, i.e. `concat(specs_tags(…), ["${IMAGE}:extra"])`                              |
| `version`                                          | The `version` input, once, instead of on the build and merge separately                                 |
| `push`                                             | The `push` input, once                                                                                  |
| `load` (`build-image`)                             | `docker/bake-action` with `load: true`; see [Testing an image](testing-images.md)                       |
| `disable-apparmor`                                 | The `disable-apparmor` input                                                                            |

## What was removed

| Removed                                       | Replaced by                                                         |
|-----------------------------------------------|---------------------------------------------------------------------|
| `build-image` action                          | The build job of `bake.yml`; for tests, `docker/bake-action`        |
| `create-manifest` action                      | The publish job of `bake.yml`                                       |
| `build.yml`, `merge.yml`                      | `bake.yml`                                                          |
| `build-php.yml`, `merge-php.yml`              | `bake.yml` and the [PHP example](bake.md#a-php-image)               |
| `build-go-cli.yml`, `merge-go-cli.yml`        | `bake.yml` and the [Go CLI example](bake.md#a-go-cli-with-variants) |
| `notify-slack-tag.yml`'s `channel` input      | Nothing: an incoming webhook always posts to its own channel        |
| The `builder_nodejs` and `node` builder names | The PHP repository's own HCL, as long as it wants them              |

## What publishes differently

Check these against your last 3.x release before you merge the migration:

- **No `v`-prefixed tag.** 3.x tagged the git tag verbatim (`v1.2.3`); 4.0.0 tags the version without the `v`.
- **The semver set for every image.** `1.2.3`, `1.2` and `1` (withheld under `0.x` and `0.0.x`), which 3.x only gave
  the Go CLI shims. Under 3.x a PHP tag `0.5.8` published `0.5.8` and `latest`; now it also publishes `0.5`.
- **A prerelease never moves `latest`**, for every image, not only Go CLIs.
- **`org.opencontainers.image.version` is the version without the `v`**, on a plain image too, and it is the same in
  the config labels, the platform manifests, the index and its descriptors.
- **The same label keys, with the same value everywhere.** `specs_labels` sets the keys metadata-action did —
  `title` and `description` (falling back to the repository's, as before), `licenses`, `version`, `revision`, `source`,
  `url` and `created`. What changes is that the index, its descriptors, the platform manifests and the config labels
  now agree: 3.x left `version` empty (or `latest`) on the platform images, and wrote a different `created` in each
  place.
- **Push follows the event**, not `github.actor`: pull requests from forks and dependabot pull requests that a person
  re-runs no longer try to push. See [when nothing is pushed](pipeline.md#when-nothing-is-pushed).
- **The PHP builder's old names are yours to publish.** 3.x tagged `/builder_nodejs` and `/node` from `merge-php.yml`.
  Projects still pull `/builder_nodejs`, so the [PHP example](bake.md#a-php-image) keeps tagging both.

## Checks and permissions

There is now one call per repository, and one check to require: `<calling job> / Image` — with the job id `image` used
throughout these docs, `image / Image`. The old `Build Image (…)` and `Merge Images (…)` checks no longer exist, so
update the branch protection rules or ruleset in the same pull request, or nothing will satisfy them.

The caller grants `contents: read` and `packages: write`. `actions: write` isn't needed.
