# How the image pipeline works

Every image in this repository is published in the same two phases, whichever workflow pair you call.

## Phase 1 — build, one job per platform

`build.yml` builds a single platform and pushes it to the registry **by digest**: no tags, just a manifest blob. It
then writes the digest to a file and uploads it as an artifact.

Nothing is tagged yet, so a half-finished matrix never leaves a `:latest` pointing at one architecture.

## Phase 2 — merge, one job for all platforms

`merge.yml` downloads every digest artifact from phase 1 and runs `docker buildx imagetools create` to build one
multi-arch manifest from them, tagged with everything `metadata-action` produced. It finishes by inspecting the result,
so the job log shows what was actually published.

Run the build job once per platform (a matrix) and the merge job once, with `needs:` on the build job.

## Digests are namespaced per image and per target

The artifact is named `digests-<image-name>-<target>-<platform>`, with `/` replaced by `-` and an absent target
recorded as `_NO_TARGET_`. The merge job downloads with the pattern `digests-<image-name>-<target>-*`.

That namespacing is what lets a single run publish several images without them bleeding into each other — the three
PHP stages, or a `debian` and an `alpine` variant of the same CLI. Each build/merge pair only ever sees its own
digests.

Artifacts are kept for one day. They are an implementation detail of a single run, not a build record.

## Tags

Tagging happens entirely in phase 2, from `metadata-action`. `create-manifest` always emits:

| Directive                 | Produces                                             |
|---------------------------|------------------------------------------------------|
| `type=schedule`           | `nightly` on a scheduled run                         |
| `type=ref,event=branch`   | The branch name, i.e. `main`                         |
| `type=ref,event=tag`      | The tag name verbatim, i.e. `v1.2.3` or `2.2.0`      |
| `type=ref,event=pr`       | `pr-<number>`                                        |
| `type=raw`, on dispatch   | The `raw-tag` input, lowercased, `latest` by default |

That last one is filtered with `enable=${{ github.event_name == 'workflow_dispatch' }}`, not
`event=workflow_dispatch`. `event=` belongs to `type=ref`; `type=raw` takes only `enable`, `priority`, `prefix`,
`suffix` and `value`. An `event=` written on a `type=raw` directive does not fail — metadata-action ignores the
attribute it does not know, and the tag silently becomes unconditional. That is worth remembering when editing
either tags block: the mistake has no symptom until a tag lands somewhere it should not.

`build-image` carries the same directive, where it has no effect on the registry — that build pushes by digest, so
its computed tags are never applied. It is the only directive in that block, so what it does decide is
`org.opencontainers.image.version` on the per-architecture images. Filtered to dispatch runs, tag and branch builds
now leave that label unset and `metadata-action` logs `No Docker tag has been generated`. `build-image` takes no
`version` input, so there is nothing truer to put there; the manifest gets its own version from `create-manifest`.

Two inputs extend that:

- `raw-tags` is appended to the directives above, for anything else you want tagged — i.e. the semver set
  `merge-go-cli.yml` adds.
- `flavor` is passed to `metadata-action`'s flavor block: `latest=false` to stop a tag from moving `:latest`,
  `prefix=` / `suffix=` to publish a variant under the same image name.

`:latest` is worth understanding. `metadata-action` defaults to `latest=auto`, and under `auto` a
`type=ref,event=tag` match sets it — for *any* tag, prereleases included. If you publish an `-rc` channel, pass
`flavor: latest=false` and add your own guarded `latest` tag through `raw-tags`, which is what
[`merge-go-cli.yml`](go-cli.md) does.

Note that `flavor: latest=false` only governs the implicit `:latest` that `type=ref` and `type=semver` bring with
them. It has no effect on an explicit `type=raw,value=latest`, which is why the dispatch directive above needs a
filter of its own rather than relying on the flavor.

## Labels and annotations

`title`, `description` and `version` override the corresponding `org.opencontainers.image.*` values. Anything left
empty falls back to what `metadata-action` derives from the repository.

`create-manifest` applies them to the manifest as both `index:` and `manifest-descriptor:` annotations, so they show up
whether a tool reads the index or the descriptor pointing at it.

## Several image names for one manifest

`create-manifest` accepts a multiline `image-name`. The first line is the primary name — the one the digests were
pushed under and the one the inspect step reports — and every line is tagged from the same manifest. `merge-php.yml`
uses this to publish `builder_nodejs` under a shorter `node` alias as well.

## What dependabot gets

Dependabot pull requests only ever build; they never publish.

- The registry login step in `build.yml` is skipped.
- `build-image` defaults `push` to false, so the build runs but writes nothing to the registry.
- The whole `merge.yml` job is skipped, so nothing is tagged.

The point is that the build itself still has to succeed before a dependency bump can be merged.
