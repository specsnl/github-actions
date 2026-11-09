# Handoff: 4.0.0 — work out image metadata once, and clean up the workflows

## Before you start

- `3.0.2` is the current release. It contains the short-term fix for the empty `org.opencontainers.image.version`
  on platform images (PR #78, plus the internal reference bump in PR #79). Don't use `3.0.1`: its workflows still
  call the `@3.0.0` actions, so the fix isn't active there.
- Start from an up-to-date `main` on a new branch, for example `feat/4.0.0`. Run `git pull --tags` first.
- This is a **major** release. Anything may be renamed or removed if there's a better option: inputs, outputs,
  workflow and action file names, job names and therefore the **required check names**. Don't keep a name just
  because consumers use it today. Write every rename down in the migration guide (see Docs).
- Part 1 is the main goal. Part 2 covers the findings from a general review of all workflows and actions; do them
  in the same major. A few of them (marked **3.x**) don't change anything for consumers and can be released earlier
  as a minor or patch if you want them sooner.

---

## Part 1 — Work out the metadata once

### Problem

The image metadata (tags, version, labels, annotations) is worked out in more than one place, and those places
must agree:

- `build-image` runs `docker/metadata-action` once per platform build. That sets the config labels and the
  per-platform manifest annotations.
- `create-manifest` runs it again at the merge. That sets the tags and the index and descriptor annotations.

3.0.2 gave `build-image` the same default tag rules and a `version` input. But consistency still depends on
discipline:

- `raw-tags` and `flavor` exist only on the merge. If a caller uses them, the build's version can differ from the
  index's (`v1.2.3` against `1.2.3`, `1.2.3` against `1.2.3-alpine`). The workaround is "pass the same `version` to
  both"; forgetting it fails silently.
- The `push` default (no push for dependabot) is also worked out twice, in `build-image` and in `merge.yml`, and the
  docs warn that they must match.
- metadata-action runs once per platform plus once at the merge, and each copy has its own tag rules, `raw-tag`
  lowercasing and empty-value filtering.

### Goal

Work out the metadata — and every other decision that has to be the same for the builds and the merge, such as
`push` — **once**, in one job, and pass the result on. Nothing downstream works it out itself.

Also treat the **version as a value of its own**, not as a side effect of whichever tag metadata-action ranks
highest.

### 1. Version first

Work out one version, in this order:

1. The explicit `version` input, if given.
2. On a tag push: the tag without a leading `v`, but only when a digit follows (`v1.2.3` → `1.2.3`; `version-2`
   stays `version-2`). Today's Go CLI shims strip any leading `v`, which turns `version-2` into `ersion-2`.
3. On a PR: `pr-<number>`.
4. On a branch push: the branch name.
5. On a schedule: `nightly`.
6. On `workflow_dispatch`: the lowercased dispatch tag.
7. Anything else: no version. Leave the key out; never write `""`.

Tags are derived from it or next to it. A variant (`suffix=-alpine`) changes the tags only, never the version. Set
`version` explicitly in metadata-action's `labels:`/`annotations:`, so its own guess never wins.

### 2. A `metadata` composite action

New action `metadata/action.yml`, the only place metadata-action is called:

- **Inputs:** `image-name` (multiline; first line is the primary name), `version`, the dispatch tag, extra tag
  rules, `flavor`, `title`, `description`, `push`.
- **Steps:** lowercase the image names (in bash, see Part 2), work out the version (see 1) and `push` (see Part 2),
  run metadata-action, drop empty values (the `jq` filter from 3.0.2).
- **Outputs:** `image-name` (lowercased primary), `version`, `push`, `tags`, `labels`, `annotations` (multiline),
  and `json` (the filtered `DOCKER_METADATA_OUTPUT_JSON`).

It's a composite action, not only a job, so the single-job `load: true` case (see 5) can use it too.

### 3. `build-image` becomes "build with these labels"

- Remove: the metadata-action step, lowercasing, the `raw-tag`/`title`/`description`/`version` inputs and the
  empty-value filter.
- Add: `labels` and `annotations` inputs (multiline), passed straight to `docker/build-push-action`.
- Keep: digest push or `load`, the cache, the digest artifact.
- `load` needs a local tag. Take it from a `tag` input (default: the first metadata tag).

### 4. `create-manifest` takes the metadata as input

- Remove the metadata-action step and its inputs.
- Take the metadata JSON (or `tags` and `labels`) as input and build the `-t` and
  `--annotation index:/manifest-descriptor:` arguments from it, as today.
- Inspect the result by the first tag or the pushed digest, not by `:<version>`. The version isn't always a tag.
- Fail clearly when there are no tags, instead of letting `imagetools create` fail on its own.
- Consider a better name now that it also publishes, such as `publish-manifest`.

### 5. Workflows

The metadata job has to run **before** the builds, and its outputs must reach both the builds and the merge. With
separate `build.yml` and `merge.yml`, every consumer would have to add and wire a third job. So:

- **One reusable workflow, for example `image.yml`**: `metadata` → `build` (matrix over platforms) → `merge` →
  `status`.
  - **Platforms as input.** Accept a plain list, `platforms: linux/amd64,linux/arm64`, and choose the runner per
    platform by default (`linux/amd64` → `ubuntu-24.04`, `linux/arm64` → `ubuntu-24.04-arm`). Allow a JSON override
    for custom runners. This replaces the `runner` matrix every consumer writes today, and the per-job `runs-on`
    input.
  - Metadata flows through `needs.metadata.outputs.*`. Multiline outputs are fine; the 1 MB job output limit is far
    more than needed.
- **Shims:** `image-php.yml` (one `image.yml` call per stage) and `image-go-cli.yml` (version build arg on the build,
  semver tag set and variant suffix on the metadata). Both pass every common input through, not a hand-picked
  subset (see Part 2).
- The single-job `load` case (`docs/testing-images.md`) uses the actions directly: `metadata` → `build-image` with
  `load: true`.
- Remove `build.yml`, `merge.yml`, `build-php.yml`, `merge-php.yml`, `build-go-cli.yml` and `merge-go-cli.yml` in
  4.0.0. Consumers stay on `@3.0.2` until they migrate.

### 6. Required checks: one stable check per image

Today the required checks are `Build Image (<target>)` per platform and `Merge Images (<target>)`, which needs a
per-step skip workaround so a skipped merge still reports success. Nested in a consumer's matrix, the full names
also become long and depend on the matrix values.

Better: add a final **`status`** job to `image.yml` with `if: always()` and `needs: [metadata, build, merge]`. It
fails unless every job it depends on succeeded or was skipped on purpose (dependabot, `push: false`). Consumers
require that **one** check per image, no matter how many platforms or targets. The merge can then be skipped with a
plain job-level `if:`, and the "Skip merge" step pattern in `merge.yml` can go.

Suggested job names (check names):

| Job        | Name                                                |
|------------|-----------------------------------------------------|
| `metadata` | `Metadata`                                          |
| `build`    | `Build <platform>`, for example `Build linux/arm64` |
| `merge`    | `Publish`                                           |
| `status`   | `Image`                                             |

The target is already in the caller's job name (`runtime / Image`, `builder / Image`), so it doesn't need repeating.
Check the final names in a real consumer run before writing them into the docs.

### 7. Digests

The digest artifact naming (`digests-<image>-<target>-<platform>`) can stay. Within one `image.yml` run it matters
less, but it still keeps several calls in one run apart (the PHP stages, CLI variants).

---

## Part 2 — General review of the workflows and actions

Ordered by importance.

### Release safety

1. **Guard the internal action references (3.x).** The reusable workflows call `build-image`/`create-manifest` by
   tag, and nothing checks that the reference matches the release. That's how `3.0.1` shipped without its fix. Add
   two checks to `lint.yml`:
   - On a tag push: fail if any `specsnl/github-actions/...@<ref>` in `.github/workflows/` isn't `@<the tag>`.
   - On a PR: warn (or fail) if `build-image/`, `create-manifest/` (later also `metadata/`) changed but the internal
     references didn't.
2. **Look for a way to stop self-referencing by tag.** The best fix is not needing the bump commit at all. Investigate
   whether a reusable workflow can check out this repository at its own ref (the `job_workflow_sha` claim in the
   OIDC token, or a context that exposes it) and run the actions from a local path. If that doesn't work cleanly,
   keep the guard from point 1.

### Security

3. **Pass build secrets as secrets, not as a string input.** `build.yml` takes `secrets` as a `type: string` input,
   so callers put secret values into an input. Declare them under `on.workflow_call.secrets` (for example one
   multiline `build-secrets` secret), so they're handled as secrets end to end.
4. **Don't interpolate inputs into shell scripts.** `build-image`'s `Prepare` and `Export digest` steps and
   `create-manifest`'s `Prepare` and `Create manifest` steps put `${{ inputs.* }}` / `${{ steps.*.outputs.* }}`
   straight into `run:`. Pass them through `env:` instead. The values come from callers, but this is the standard
   protection against script injection and costs nothing.
5. **Declare `permissions:`.** No workflow sets them. Set `contents: read` at the top of `lint.yml`. In the reusable
   workflows, set minimal job permissions (`contents: read`, `packages: write` only where something is pushed), and
   document what callers must grant.
6. **Pin third-party actions by commit SHA**, with the version as a comment (`@<sha> # v8.0.0`). Today they're pinned
   by moving major tags (`@v8`, `@v1`). Dependabot keeps SHA pins up to date. Official `actions/*` and `docker/*` can
   stay on tags if you prefer, but at least pin the small third-party ones (`ASzc/change-string-case-action`,
   `cisagov/action-disable-apparmor`, `slackapi/slack-github-action`).
7. **Drop `ASzc/change-string-case-action`.** It's only used for lowercasing, which bash does with `${var,,}`. One
   third-party dependency less.
8. **Set `persist-credentials: false`** on `actions/checkout`. Nothing after it needs git credentials.
9. **Add `zizmor` to `lint.yml`** next to actionlint. It catches points 4, 5, 6 and 8 automatically from now on.

### Correctness

10. **Decide `push` on the event, not on `github.actor`.** `github.actor != 'dependabot[bot]'` breaks in two cases:
    - When a person re-runs a dependabot PR's jobs, the actor becomes that person, so the build tries to push with
      the read-only token dependabot PRs get, and fails.
    - PRs from forks also get a read-only token, but aren't caught at all.

    Push by default only when the token can write: not for dependabot PRs (check
    `github.event.pull_request.user.login`) and not for PRs from forks
    (`github.event.pull_request.head.repo.full_name != github.repository`). Work this out once, in the metadata job.
11. **Don't move `:latest` on prerelease tags by default.** metadata-action's `latest=auto` moves `:latest` on any
    tag, `-rc` included. Only `merge-go-cli.yml` guards against that. Make the safe behaviour the default for every
    image: `latest=false`, plus a `latest` tag only on stable tags, as the Go CLI shim does.
12. **The Go CLI version strips any leading `v`** — see Part 1, point 1.

### Consistency and naming

13. **Give the shims the same input surface.** `build-php.yml` has no `context`, `build-args` or `push`;
    `merge-php.yml` has no `push`, `version`, `raw-tags` or `flavor`. With `image.yml` there's one set of common
    inputs; every shim passes all of them through.
14. **Rename confusing inputs:**
    - `raw-tag` (the tag used on `workflow_dispatch`, and the local tag with `load`) against `raw-tags` (extra tag
      rules) differ by one letter and mean different things. Suggested: `dispatch-tag` and `extra-tags`.
    - `title-runtime`, `description-builder` and so on in `merge-php.yml`: `runtime-title`, `builder-description`
      read better, or take them per stage.
    - Workflow `name:` values have mixed styles ("Build Images", "Merge images to manifest", "Merge Go CLI images to
      manifest"). Pick one style.
15. **Remove the deprecated PHP builder names.** `docs/php.md` says `builder_nodejs` and `node` are deprecated and will
    be removed in a later major. This is that major. Check that no consumer still pulls them first.
16. **Make the lint version consistent.** `lint.yml` runs `rhysd/actionlint:latest`; the Taskfile pins `1.7.12`. Pin
    both to the same version (and let dependabot bump it, or bump it with the Taskfile).

### Small improvements

17. **Remove `actions/checkout` from the merge job.** metadata-action takes its context from the event, and
    `create-manifest` only needs the digest artifacts, so the checkout isn't used.
18. **Add `timeout-minutes`** to every job. The default is 6 hours; a stuck build should fail long before that. Make
    the build's timeout an input.
19. **Include the image name in the build cache scope.** It's `<dockerfile>-<platform>-<target>` now, so two images
    built from the same Dockerfile and target share and overwrite each other's cache.
20. **Consider provenance and SBOM.** `provenance: false` is set and there's no SBOM. With `provenance: mode=max` and
    `sbom: true`, the attestations are pushed with each platform image and kept by `imagetools create`. Alternatively,
    use `actions/attest-build-provenance` on the final digest. Check that GHCR shows them sensibly ("unknown/unknown"
    platform entries) before turning it on by default.
21. **`notify-slack-tag.yml`:**
    - The `channel` input does nothing: an incoming webhook always posts to the channel it was created for. Remove
      it, or switch to a bot token, which does support choosing a channel.
    - The tag name is put straight into the JSON payload, so a tag containing `"` breaks it. Build the payload with
      `jq` in a step before it.
    - `runs-on` could default to `ubuntu-24.04`; it's a trivial job.
22. **Dependabot:** group the `github-actions` updates (`groups:`) into one PR. Every update here needs an internal
    reference bump and a release anyway, so one PR per action is mostly noise. Weekly instead of daily is probably
    enough.

---

## Docs

- Rewrite `docs/pipeline.md` around the phases metadata → build → publish → status. Remove the "pass the same
  version to both" warnings added in 3.0.2.
- Update `docs/actions.md` (new `metadata` action, slimmer `build-image` and `create-manifest`), `docs/workflows.md`,
  `docs/php.md`, `docs/go-cli.md`, `docs/testing-images.md` and `docs/releasing.md` (the new reference guard).
- Add a **3.x → 4.0.0 migration guide**: the before and after for a consumer's workflow (two jobs with a runner
  matrix → one call with `platforms`), a table of every renamed or removed input, workflow and action, and the new
  required check names consumers have to update in their branch protection rules or rulesets.
- Follow `docs/releasing.md`: bump the internal references (and the docs examples) before tagging.

## Verify

For each of these, check that the index annotation, the descriptor annotations, the platform manifest annotations
and the config labels all have the same `org.opencontainers.image.version`, and that the tags are as expected:

- A tag push of a plain image (`specsnl/utils`): version `1.19.0`.
- A tag push of a Go CLI, with and without a variant (`specsnl/specs-cli`): version `1.2.3`; tags `1.2.3`, `1.2`,
  `1`, `latest`, and `1.2.3-alpine`, `alpine` for the variant. A prerelease (`v1.2.3-rc.1`) doesn't move `latest`.
- A PHP image (`specsnl/php84`): `runtime` and `builder`.
- A PR (`pr-N`), a branch push (branch name), a `workflow_dispatch` (dispatch tag, lowercased) and a scheduled run
  (`nightly`).
- A dependabot PR, and a person re-running one: builds without pushing, and the `Image` check reports success.
- A PR from a fork: builds without pushing.
- A `load: true` guard: builds, loads and runs with the expected local tag.
- The new lint guard fails on a tag whose internal references don't match.

Commands:

```sh
docker buildx imagetools inspect <ref> --raw | jq .annotations
d=$(docker buildx imagetools inspect <ref> --raw | jq -r '.manifests[0].digest')
docker buildx imagetools inspect <image>@$d --raw | jq .annotations
docker buildx imagetools inspect <ref> --format '{{json .Image}}' | jq '."linux/amd64".config.Labels'
```

## Rollout

Release `4.0.0`, then migrate the consumers one by one: `specsnl/utils`, `specsnl/specs-cli`, and the PHP image
repos (`specsnl/php84` and siblings). Update each one's required checks in the same change. Until a consumer has
migrated, it stays on `@3.0.2`.
