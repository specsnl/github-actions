# How the image pipeline works

`bake.yml` runs four jobs: plan, build, publish and status.

```
plan ──► build linux/amd64 ──┐
     └─► build linux/arm64 ──┴─► publish ──► status ("Image")
```

## Plan — work everything out once

The plan job works out everything that depends on the run, once:

- the bake variables — `VERSION`, the event, the ref, `IS_STABLE`, the revision, one `CREATED` timestamp, and the
  repository's name, description and license (see [the variables CI sets](bake.md#the-variables-ci-sets));
- whether to push (see [below](#when-nothing-is-pushed)).

It then runs `docker buildx bake --print` on the consumer's bake files with those variables set, and **freezes** the
result: the printed JSON, with each target's `output` replaced by a push by digest to its first image name, and its
tags set aside for the publish job. Both go into one artifact.

Every later job builds from that frozen definition instead of evaluating the HCL again. That is what guarantees every
platform and the publish job see identical tags and labels — including `created`, which would otherwise differ per
job.

The plan job also:

- outputs the platforms, the union over all targets, as the build matrix, each with its runner from the `runners`
  input;
- reads `specs.hcl` from this repository, at the version of the workflow, before the consumer's bake files;
- fails early, with the target named, when a target has no `platforms`, or has no tags for an event it would push.

The run summary shows every target, its platforms and its tags.

## Build — one job per platform, all targets at once

`build` runs once per platform, named `Build <platform>`. Each job checks out the repository, narrows the frozen
definition to the targets that list its platform, and builds all of them in one `docker/bake-action` run, so stages
of the same Dockerfile share their layers. A target without that platform is skipped by that job, so targets can have
different platform sets.

Each image is pushed **by digest**: no tags, just the manifest. Nothing is tagged yet, so a half-finished run never
leaves a `:latest` pointing at one architecture. The digests are read from bake's metadata and uploaded as one
artifact per platform.

Each target gets its own GitHub Actions cache scope, `<image>-<target>-<platform>`, so two images built from the same
Dockerfile and stage no longer overwrite each other's cache.

## Publish — one job for all targets

`publish` downloads the frozen definition and every digest artifact, and for each target runs
`docker buildx imagetools create` with the target's digests, tags, and labels as `index:` and `manifest-descriptor:`
annotations. It then inspects the result by its first tag, so the log shows what was actually published.

It doesn't check out the repository: it only needs the artifacts.

## Status — one check

`status`, named `Image`, always runs and fails unless plan succeeded and build and publish succeeded or were skipped.
Require that one check: there is one call per repository, so it covers every image the repository publishes. A caller
sees it as `<calling job> / Image`.

## Metadata, in every place

The version and the other `org.opencontainers.image.*` values come from `specs_labels` and end up in four places, all
from the same frozen definition:

| Where                        | Set by                                                    |
|------------------------------|-----------------------------------------------------------|
| The image config labels      | The build, from the target's `labels`                     |
| The platform manifest        | The build, from the target's `annotations`                |
| The index                    | Publish, from the target's labels as `index:` annotations |
| The descriptors in the index | Publish, as `manifest-descriptor:` annotations            |

To check a published image:

```bash
docker buildx imagetools inspect <ref> --raw | jq .annotations
d=$(docker buildx imagetools inspect <ref> --raw | jq -r '.manifests[0].digest')
docker buildx imagetools inspect <image>@$d --raw | jq .annotations
docker buildx imagetools inspect <ref> --format '{{json .Image}}' | jq '."linux/amd64".config.Labels'
```

## When nothing is pushed

`push` defaults to `true`, except for:

- a pull request opened by dependabot — also when a person re-runs its jobs, because the token stays read-only;
- a pull request from a fork, whose token is read-only too;
- a push to a `dependabot/…` branch;
- an event the [tag rules](bake.md#specs_tagsimages-variant) don't cover, such as `merge_group`.

Set the `push` input to override it. Without a push the build still runs — with `type=cacheonly` output, filling the
cache — and publish is skipped, so a dependency bump still has to build before it can be merged. `Image` reports
success.

## Artifacts

The definition and digest artifacts are named `bake-<id>-definition` and `bake-<id>-digests-<platform>`, where `<id>`
is derived from the `files` and `targets` inputs, so one run can call the workflow more than once. They
are kept for one day: they belong to a single run, not to a build record.
