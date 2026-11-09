# Testing an image in a pull request

`bake.yml` pushes by digest, which is right for a release but not for a pull request test. The point of testing an
image is *running* it: asserting `--version`, that the entrypoint works, that the non-root user can write into a bind
mount. An image that is only built and never run misses most of what can break.

The image has to be built and run in the same job, so a reusable workflow is the wrong level. Run
`docker/bake-action` yourself, with `load: true`, on the same bake files:

```yaml
name: CI

on: pull_request

permissions:
  contents: read

jobs:

  image:
    runs-on: ubuntu-24.04
    steps:
      - uses: actions/checkout@v7
        with:
          persist-credentials: false

      - uses: docker/setup-buildx-action@v4

      - uses: docker/bake-action@v7
        env:
          VERSION: ci
        with:
          source: .
          files: |
            specs.hcl
            docker-bake.hcl
          targets: cli-debian
          load: true
          set: '*.platform=linux/amd64'

      # Proves the ldflag landed: a wrong build arg name would leave this at "dev".
      - name: Smoke test
        run: test "$(docker run --rm ghcr.io/specsnl/specs-cli:local --version)" = "ci"
```

## What this does

- `source: .` builds from the checked-out files, the same ones CI and a local build read, instead of bake-action's
  default Git context.
- `load: true` loads the result into the runner's Docker daemon instead of pushing it. That works for one platform at
  a time, hence `*.platform=linux/amd64`.
- None of the CI variables are set, so `specs_tags` gives the local tag: `<image>:local`. That is the reference to
  run.
- `VERSION` is a bake variable, read from the environment. `ci` above is deliberate: a literal the test can compare
  against exactly, which fails if the build arg name is wrong and the Dockerfile falls back to `dev`. `${{ github.sha }}`
  works just as well.

## A dedicated test target

When the test needs something the published image doesn't — test tools, a different entrypoint — give it a target of
its own, outside the `default` group so CI never publishes it:

```hcl
target "test" {
  inherits = ["cli-debian"]
  target   = "test"
  tags     = ["specs-cli:test"]
}
```

and build that with `targets: test`.
