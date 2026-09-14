# Testing an image in a pull request

`build.yml` pushes by digest, which is right for a release but not for a pull-request guard. The point of checking a
CLI image is *running* the binary: asserting `--version`, that the entrypoint works, that the non-root user can write
into a bind mount. An image that is only compiled and never executed misses most of what can break.

Use the `build-image` action directly for that. The image has to be built and run in the same job, so a reusable
workflow is the wrong level — it would load the image into a daemon the caller cannot reach.

```yaml
name: CI

on: pull_request

jobs:

  image:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
      - uses: docker/setup-buildx-action@v4

      - id: build
        uses: specsnl/github-actions/build-image@2.4.0
        with:
          platform: linux/amd64
          image-name: ghcr.io/specsnl/specs-cli
          dockerfile: Dockerfile
          target: debian
          load: true
          build-args: SPECS_VERSION=ci

      # Proves the ldflag landed: a wrong build arg name would leave this at "dev".
      - name: Smoke test
        env:
          IMAGE: ${{ steps.build.outputs.image }}
        run: test "$(docker run --rm "$IMAGE" --version)" = "ci"
```

## What `load` does

- Builds a **single** platform and loads the result into the runner's Docker daemon, rather than pushing it.
- Tags it `<image-name>:<raw-tag>` — `raw-tag` defaults to `latest` — and reports that reference as the `image`
  output, which is what the step above runs.
- Skips the digest export and artifact upload, since there is no merge phase to feed.

## `load` and `push` are mutually exclusive

`load: true` implies `push: false`. Setting both fails the build with a clear error, because a single build cannot
write to the registry and to the local daemon at once.

`push: false` on its own is a different thing: it builds without writing to the registry, but nothing is loaded either,
so there is no image to run. That is what dependabot already gets by default. A guard that wants to execute the binary
wants `load`.

## Pinning the version under test

Pass whatever version the guard should assert through `build-args`. `SPECS_VERSION=ci` above is deliberate: a literal
the test can compare against exactly, which fails if the build arg name is wrong and the Dockerfile falls back to
`dev`. `${{ github.sha }}` works just as well.
