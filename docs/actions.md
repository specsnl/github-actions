# Composite action reference

The two composite actions carry the actual work; the [reusable workflows](workflows.md) are the boilerplate around
them. Call a workflow unless you need the image in the same job — which is the case when
[testing an image in a pull request](testing-images.md).

Both assume the job has already checked out, logged in to the registry and set up buildx.

## `build-image`

```yaml
- uses: specsnl/github-actions/build-image@2.4.4
```

| Input         | Default    | Description                                                                            |
|---------------|------------|----------------------------------------------------------------------------------------|
| `platform`    | *required* | Platform, i.e. `linux/amd64`                                                           |
| `image-name`  | *required* | Image name; must already be lowercase                                                  |
| `dockerfile`  | *required* | Dockerfile path                                                                        |
| `context`     | `.`        | Build context path                                                                     |
| `target`      | —          | Dockerfile stage to build; omit for the default (last) stage                           |
| `title`       | —          | Overrides `org.opencontainers.image.title`                                             |
| `description` | —          | Overrides `org.opencontainers.image.description`                                       |
| `secrets`     | —          | Secrets to expose to the build (multiline)                                             |
| `build-args`  | —          | Build-time variables (multiline `KEY=value`)                                           |
| `push`        | —          | `"true"` / `"false"`; defaults to pushing, except for dependabot and when `load` is on |
| `load`        | `"false"`  | Load the image into the local Docker daemon instead of pushing it by digest            |
| `raw-tag`     | `latest`   | Tag used on `workflow_dispatch` runs, and as the local tag when `load` is on           |

| Output    | Description                                                                                       |
|-----------|---------------------------------------------------------------------------------------------------|
| `image`   | Reference of the loaded image, i.e. `ghcr.io/specsnl/specs-cli:latest`. Empty unless `load` is on |
| `imageid` | ID of the built image                                                                             |
| `digest`  | Digest of the built image                                                                         |

Note that `image-name` is not lowercased here — `build.yml` does that before calling. A `GHCR` path with an uppercase
character in it will be rejected by the registry.

`push` and `load` cannot both be true; the action fails with an explicit error rather than letting buildx complain
about conflicting outputs. With `load` on, the digest export and artifact upload are skipped.

## `create-manifest`

```yaml
- uses: specsnl/github-actions/create-manifest@2.4.4
```

| Input         | Default    | Description                                                                                |
|---------------|------------|--------------------------------------------------------------------------------------------|
| `image-name`  | *required* | Image name. Multiline tags one manifest under several names; the first line is the primary |
| `target`      | —          | The target the digests were built from; must match the build                               |
| `title`       | —          | Overrides `org.opencontainers.image.title`                                                 |
| `description` | —          | Overrides `org.opencontainers.image.description`                                           |
| `version`     | —          | Sets `org.opencontainers.image.version`                                                    |
| `raw-tag`     | `latest`   | Tag used on `workflow_dispatch` runs                                                       |
| `raw-tags`    | —          | Extra `metadata-action` tag directives (multiline), appended to the defaults               |
| `flavor`      | —          | `metadata-action` flavor directives (multiline), i.e. `latest=false`                       |

The action downloads the digest artifacts itself, so it has to run in a job that comes after every build job. See
[How the image pipeline works](pipeline.md) for the artifact naming and the default tag set.
