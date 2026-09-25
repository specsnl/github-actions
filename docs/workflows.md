# Reusable workflow reference

Every input, per workflow. Call them with
`uses: specsnl/github-actions/.github/workflows/<file>@<tag>`.

## `build.yml`

Builds one platform and pushes it by digest. Run it once per platform.

| Input              | Type    | Default      | Description                                                      |
|--------------------|---------|--------------|------------------------------------------------------------------|
| `runs-on`          | string  | *required*   | Runner name, i.e. `ubuntu-24.04` or `ubuntu-24.04-arm`           |
| `platform`         | string  | *required*   | Platform, i.e. `linux/amd64`                                     |
| `image-name`       | string  | *required*   | Image name; lowercased before use                                |
| `dockerfile`       | string  | `Dockerfile` | Dockerfile path                                                  |
| `context`          | string  | `.`          | Build context path                                               |
| `target`           | string  | —            | Dockerfile stage to build; omit for the default (last) stage     |
| `title`            | string  | —            | Overrides `org.opencontainers.image.title`                       |
| `description`      | string  | —            | Overrides `org.opencontainers.image.description`                 |
| `secrets`          | string  | —            | Secrets to expose to the build (multiline)                       |
| `build-args`       | string  | —            | Build-time variables (multiline `KEY=value`)                     |
| `push`             | string  | —            | `"true"` / `"false"`; defaults to pushing, except for dependabot |
| `disable-apparmor` | boolean | `false`      | Disable AppArmor on the runner before building                   |

The registry login step is skipped for dependabot, which is why `push` defaults the way it does.

## `merge.yml`

Merges the digests from `build.yml` into one tagged multi-arch manifest. Run it once, with `needs:` on the build job.
When `push` is off — by default for dependabot — the job still runs but skips every step, so a required `Merge Images`
check reports success.

| Input         | Type   | Default    | Description                                                          |
|---------------|--------|------------|----------------------------------------------------------------------|
| `runs-on`     | string | *required* | Runner name                                                          |
| `image-name`  | string | *required* | Image name; multiline tags one manifest under several names          |
| `target`      | string | —          | The target the digests were built from; must match the build job     |
| `title`       | string | —          | Overrides `org.opencontainers.image.title`                           |
| `description` | string | —          | Overrides `org.opencontainers.image.description`                     |
| `version`     | string | —          | Sets `org.opencontainers.image.version`                              |
| `raw-tag`     | string | `latest`   | Tag used on `workflow_dispatch` runs                                 |
| `raw-tags`    | string | —          | Extra `metadata-action` tag directives (multiline), appended         |
| `flavor`      | string | —          | `metadata-action` flavor directives (multiline), i.e. `latest=false` |
| `push`        | string | —          | `"true"` / `"false"`; defaults to pushing, except for dependabot     |

See [How the image pipeline works](pipeline.md#tags) for what gets tagged by default.

## `build-php.yml`

Fans out into one `build.yml` call per PHP stage. See [PHP images](php.md).

| Input              | Type    | Default      | Description                                    |
|--------------------|---------|--------------|------------------------------------------------|
| `runs-on`          | string  | *required*   | Runner name                                    |
| `platform`         | string  | *required*   | Platform                                       |
| `image-name`       | string  | *required*   | Base image name; stages nest under it          |
| `dockerfile`       | string  | `Dockerfile` | Dockerfile path                                |
| `title`            | string  | —            | Applied to all three stages                    |
| `description`      | string  | —            | Applied to all three stages                    |
| `secrets`          | string  | —            | Secrets to expose to the build                 |
| `disable-apparmor` | boolean | `false`      | Disable AppArmor on the runner before building |

## `merge-php.yml`

Fans out into one `merge.yml` call per PHP stage.

| Input                        | Type   | Default    | Description                        |
|------------------------------|--------|------------|------------------------------------|
| `runs-on`                    | string | *required* | Runner name                        |
| `image-name`                 | string | *required* | Base image name                    |
| `title-runtime`              | string | —          | Title for the runtime image        |
| `description-runtime`        | string | —          | Description for the runtime image  |
| `title-builder`              | string | —          | Title for the builder image        |
| `description-builder`        | string | —          | Description for the builder image  |
| `title-builder_nodejs`       | string | —          | Title for the nodejs builder image |
| `description-builder_nodejs` | string | —          | Description for the nodejs builder |
| `raw-tag`                    | string | `latest`   | Tag used on `workflow_dispatch`    |

## `build-go-cli.yml`

`build.yml` plus the version build arg. See [Go CLI images](go-cli.md).

| Input               | Type    | Default      | Description                                                      |
|---------------------|---------|--------------|------------------------------------------------------------------|
| `runs-on`           | string  | *required*   | Runner name                                                      |
| `platform`          | string  | *required*   | Platform                                                         |
| `image-name`        | string  | *required*   | Image name                                                       |
| `version`           | string  | *required*   | Version injected into the binary, i.e. the release tag           |
| `version-build-arg` | string  | *required*   | Dockerfile ARG the version is passed to, i.e. `SPECS_VERSION`    |
| `dockerfile`        | string  | `Dockerfile` | Dockerfile path                                                  |
| `context`           | string  | `.`          | Build context path                                               |
| `target`            | string  | —            | Dockerfile stage to publish                                      |
| `title`             | string  | —            | Overrides `org.opencontainers.image.title`                       |
| `description`       | string  | —            | Overrides `org.opencontainers.image.description`                 |
| `build-args`        | string  | —            | Additional build-time variables, appended to the version arg     |
| `secrets`           | string  | —            | Secrets to expose to the build                                   |
| `push`              | string  | —            | `"true"` / `"false"`; defaults to pushing, except for dependabot |
| `disable-apparmor`  | boolean | `false`      | Disable AppArmor on the runner before building                   |

## `merge-go-cli.yml`

`merge.yml` plus the semver tag set a CLI release wants.

| Input         | Type    | Default    | Description                                                               |
|---------------|---------|------------|---------------------------------------------------------------------------|
| `runs-on`     | string  | *required* | Runner name                                                               |
| `image-name`  | string  | *required* | Image name                                                                |
| `target`      | string  | —          | The target the digests were built from                                    |
| `variant`     | string  | —          | Publish as a tag-suffixed variant, i.e. `alpine`                          |
| `version`     | string  | —          | Sets `org.opencontainers.image.version`                                   |
| `title`       | string  | —          | Overrides `org.opencontainers.image.title`                                |
| `description` | string  | —          | Overrides `org.opencontainers.image.description`                          |
| `latest`      | boolean | `true`     | Move `:latest` (or `:<variant>`); only ever applies to a stable tag       |
| `raw-tag`     | string  | `latest`   | Tag used on `workflow_dispatch` runs                                      |
| `raw-tags`    | string  | —          | Extra tag directives, appended after this workflow's                      |
| `flavor`      | string  | —          | Extra flavor directives, appended after this workflow's, so they override |
| `push`        | string  | —          | `"true"` / `"false"`; defaults to pushing, except for dependabot          |

## `notify-slack-tag.yml`

Posts a Slack message with the tag, repository, actor and a link to the release.

| Input     | Type   | Default     | Description             |
|-----------|--------|-------------|-------------------------|
| `runs-on` | string | *required*  | Runner name             |
| `channel` | string | `#releases` | Slack channel to notify |

| Secret              | Required | Description                |
|---------------------|----------|----------------------------|
| `slack-webhook-url` | yes      | Slack incoming webhook URL |
