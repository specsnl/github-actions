# Reusable workflow reference

Every input, per workflow. Call them with `uses: specsnl/github-actions/.github/workflows/<file>@<tag>`.

## `bake.yml`

Builds and publishes every target of the consumer's bake files. See [Building images with bake](bake.md) and
[How the image pipeline works](pipeline.md).

| Input              | Type    | Default           | Description                                                                            |
|--------------------|---------|-------------------|----------------------------------------------------------------------------------------|
| `files`            | string  | `docker-bake.hcl` | The consumer's bake files (multiline), read after `specs-file`                         |
| `specs-file`       | string  | `specs.hcl`       | The vendored copy of `bake/specs.hcl`; an empty string if the bake files don't use it  |
| `targets`          | string  | —                 | Targets or groups to build (multiline); the `default` group when empty                 |
| `version`          | string  | —                 | Overrides `VERSION`; see [how it is worked out](bake.md#the-variables-ci-sets)         |
| `dispatch-tag`     | string  | `latest`          | Tag published by a `workflow_dispatch` run; lowercased                                 |
| `push`             | string  | —                 | `"true"` / `"false"`; see [when nothing is pushed](pipeline.md#when-nothing-is-pushed) |
| `runners`          | string  | —                 | JSON object mapping a platform to its runner, merged over the defaults below           |
| `disable-apparmor` | boolean | `false`           | Disable AppArmor on the build runners before building                                  |
| `timeout-minutes`  | number  | `60`              | Timeout of each build job                                                              |

| Secret          | Required | Description                                                                          |
|-----------------|----------|--------------------------------------------------------------------------------------|
| `build-secrets` | no       | `NAME=value` lines, each masked and exported to the build as an environment variable |

| Output    | Description                                           |
|-----------|-------------------------------------------------------|
| `version` | The `VERSION` the images were built with              |
| `push`    | Whether the images were pushed (`"true"` / `"false"`) |

The default runners are `ubuntu-26.04` for `linux/amd64` and `ubuntu-26.04-arm` for `linux/arm64`. A platform without
a runner fails the plan job. A runner may be a label or a list of labels:

```yaml
    with:
      runners: '{"linux/arm64": ["self-hosted", "arm64"]}'
```

A build secret's value must fit on one line. The bake file refers to it by its name:
`secret = ["id=composer_auth,env=COMPOSER_AUTH"]`. Names of the runner's own variables (`GITHUB_*`, `RUNNER_*`,
`ACTIONS_*`, `PATH`, …) are refused.

The caller has to grant:

```yaml
permissions:
  contents: read
  packages: write
```

| Job       | Check name         | Runs on                      |
|-----------|--------------------|------------------------------|
| `plan`    | `Plan`             | `ubuntu-26.04`               |
| `build`   | `Build <platform>` | The platform's runner        |
| `publish` | `Publish`          | `ubuntu-26.04`, when pushing |
| `status`  | `Image`            | `ubuntu-26.04`, always       |

Require only `Image`.

## `notify-slack-tag.yml`

Posts a Slack message with the tag, repository, actor and a link to the release. The incoming webhook decides the
channel.

| Input     | Type   | Default        | Description |
|-----------|--------|----------------|-------------|
| `runs-on` | string | `ubuntu-26.04` | Runner name |

| Secret              | Required | Description                |
|---------------------|----------|----------------------------|
| `slack-webhook-url` | yes      | Slack incoming webhook URL |

```yaml
on:
  push:
    tags: ['*']

jobs:
  notify:
    uses: specsnl/github-actions/.github/workflows/notify-slack-tag.yml@4.0.0
    secrets:
      slack-webhook-url: ${{ secrets.SLACK_WEBHOOK_URL }}
```
