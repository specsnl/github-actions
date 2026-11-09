# Handoff: 4.0.0 — build with `docker buildx bake` (HCL), work out metadata once, and clean up the workflows

This is the bake variant of `HANDOFF-single-metadata.md`. Both solve the same problem — metadata worked out in more
than one place — but this one also moves the build definition out of workflow inputs and into an HCL bake file in each
consumer repository. Pick one of the two; don't do both.

## Before you start

- `3.0.2` is the current release. It contains the short-term fix for the empty `org.opencontainers.image.version`
  on platform images (PR #78, plus the internal reference bump in PR #79). Don't use `3.0.1`: its workflows still
  call the `@3.0.0` actions, so the fix isn't active there.
- Start from an up-to-date `main` on a new branch, for example `feat/4.0.0-bake`. Run `git pull --tags` first.
- This is a **major** release. Anything may be renamed or removed if there's a better option: inputs, outputs,
  workflow and action file names, job names and therefore the **required check names**. Don't keep a name just
  because consumers use it today. Write every rename down in the migration guide (see Docs).
- Read the bake docs first: <https://docs.docker.com/build/bake/> — especially the HCL reference (variables, functions,
  `inherits`, `matrix`), `--print`, `--set`, and "Distribute builds across multiple runners" in the GitHub Actions
  section. Check every HCL function used here against the buildx version on the GitHub runners.

---

## What bake changes

Today, **what** to build lives in workflow inputs: `dockerfile`, `context`, `target`, `build-args`, `secrets`,
`title`, `description`, `version-build-arg`, `variant`, `raw-tags`, `flavor`, plus a hand-written runner matrix and a
pair of workflow calls per image or stage. The PHP and Go CLI shims exist only to fill those inputs in.

With bake, **what** to build lives in a `docker-bake.hcl` in the consumer repository, and this repository only provides
**how** to build and publish it in CI:

| Concern                                  | Today (3.x)                        | With bake (4.0.0)                                   |
|------------------------------------------|------------------------------------|-----------------------------------------------------|
| Dockerfile, context, target, build args  | Workflow inputs                    | Consumer's `docker-bake.hcl`                        |
| Image names                              | Workflow inputs                    | HCL                                                 |
| Several images or stages (PHP, variants) | One workflow call per image, shims | HCL targets, a `group`, or a target `matrix`        |
| Platforms                                | Consumer's runner matrix           | HCL `platforms`; the workflow fans out per platform |
| Version build arg (Go CLI)               | `version-build-arg` input          | HCL `args = { SPECS_VERSION = VERSION }`            |
| Tags, labels, annotations                | `metadata-action`, run twice       | Worked out once (see Part 1, step 3)                |
| Reproduce locally                        | Not possible                       | `docker buildx bake` / `docker buildx bake --print` |

The digest pipeline doesn't change: build each platform on its own runner, push by digest, merge with
`docker buildx imagetools create`. Bake only replaces the way each build is described and started.

What consumers gain:

- **Local builds match CI.** `docker buildx bake --print` shows exactly the targets, tags and labels CI will publish.
- **One workflow call per repository**, however many images, stages or variants it publishes.
- **Shared layers.** All targets for one platform build in one job and one bake invocation, so PHP's `runtime` and
  `builder` (or the CLI variants) share work instead of running in separate jobs.

What it costs:

- Every consumer repository has to write a `docker-bake.hcl`. The migration is bigger than renaming inputs.
- If tags are worked out in HCL (step 3, option C), the tag rules that `metadata-action` gives for free have to be
  written and tested in HCL.

---

## Part 1 — Design

### 1. The consumer's `docker-bake.hcl`

Each consumer owns one bake file with:

- a `group "default"` listing the targets to publish;
- one target per published image, with `dockerfile`, `context`, `target`, `args`, `secret` and `platforms`;
- the image name(s) per target;
- `variable` blocks with local defaults for the values CI provides (see 2), so `docker buildx bake` works without CI.

Sketch for a PHP image (names illustrative):

```hcl
variable "IMAGE" { default = "ghcr.io/specsnl/php84" }

group "default" {
  targets = ["runtime", "builder"]
}

target "_common" {
  dockerfile = "Dockerfile"
  platforms  = ["linux/amd64", "linux/arm64"]
}

target "runtime" {
  inherits    = ["_common"]
  target      = "runtime"
  tags        = specs_tags(["${IMAGE}"], "")
  labels      = specs_labels("PHP 8.4", "")
  annotations = specs_annotations("PHP 8.4", "")
}

target "builder" {
  inherits    = ["_common"]
  target      = "builder"
  tags        = specs_tags(["${IMAGE}/builder"], "")
  labels      = specs_labels("PHP 8.4 builder", "")
  annotations = specs_annotations("PHP 8.4 builder", "")
}
```

Sketch for a Go CLI with variants:

```hcl
variable "VERSION" { default = "dev" }

group "default" {
  targets = ["cli"]
}

target "cli" {
  name      = "cli-${variant}"
  matrix    = { variant = ["debian", "alpine"] }
  target    = variant
  platforms = ["linux/amd64", "linux/arm64"]
  args      = { SPECS_VERSION = VERSION }
  tags      = specs_tags(["ghcr.io/specsnl/specs-cli"], variant == "debian" ? "" : variant)
}
```

`version-build-arg` disappears: the consumer wires `VERSION` to its own ARG in plain sight, and a typo shows up in
`docker buildx bake --print`.

### 2. Context and version: worked out once, passed as bake variables

A `plan` job (the `metadata` job of the other handoff) works out everything that depends on the CI run, once:

- `VERSION`, with the same rules as before:
  1. The explicit `version` input, if given.
  2. On a tag push: the tag without a leading `v`, but only when a digit follows (`v1.2.3` → `1.2.3`; `version-2`
     stays `version-2`).
  3. On a PR: `pr-<number>`. On a branch push: the branch name. On a schedule: `nightly`. On `workflow_dispatch`:
     the lowercased dispatch tag.
  4. Anything else: empty, and the label is left out (never `""`).
- `REF_TYPE`, `REF_NAME`, `EVENT`, `PR_NUMBER`, `IS_STABLE` (a tag with no `-` in the version), `REVISION`
  (`github.sha`), `SOURCE` (repository URL), `CREATED` (one timestamp for the whole run).
- `PUSH`: see Part 2, point 10.

They reach bake as environment variables; bake reads a `variable "X"` from the environment variable `X`. Locally the
defaults apply (`VERSION=dev`, no tags beyond a local one).

### 3. Tags, labels and annotations — decide where they're worked out

**Option A — keep `docker/metadata-action`.** It can write a bake file (`outputs.bake-file`) defining one target
(`bake-target` input, default `docker-metadata-action`) that consumer targets `inherits`. It's the documented
integration and keeps metadata-action's tag rules. But it's one image per metadata-action run: with several images
(PHP stages, variants) the plan job needs one run per image, and the per-image settings (image names, `flavor`, extra
tag rules) need a home outside HCL again — a JSON workflow input or a matrix. Consumers also need empty placeholder
targets (`target "meta-runtime" {}`) so local builds still work.

**Option C — work them out in HCL (recommended).** A shared HCL file with user-defined `function` blocks
(`specs_tags`, `specs_labels`, `specs_annotations`) computes everything from the variables in step 2:

- `specs_tags(images, variant)`: for each image, on a tag push the semver set (`1.2.3`, `1.2` unless `0.0.x`, `1`
  unless `0.x`) with the variant suffix, plus `latest` / the bare variant name only when `IS_STABLE`; on a PR
  `pr-N`; on a branch the branch name; on a schedule `nightly`; on dispatch the dispatch tag; locally just `:local`
  (or `VERSION`). Use `regex`/`split` for the semver parts.
- `specs_labels(title, description)` / `specs_annotations(...)`: the `org.opencontainers.image.*` set (`version`,
  `revision`, `source`, `created`, `title`, `description`), leaving out empty values.

Why C: per-image settings get a natural home (the target), there's no metadata-action step at all, and
`docker buildx bake --print` locally shows exactly what will be published. The rules move out of a third-party action
into code you own and test (see Verify: this repository gets HCL fixture tests).

How consumers get the shared file is a separate decision:

- **Vendored:** consumers copy `bake/specs.hcl` from this repository (a Taskfile task can update it). Local builds work
  offline; updates are explicit. The workflow passes both files to bake.
- **Fetched by the workflow:** the workflow downloads `bake/specs.hcl` at its own ref. Consumers stay in sync, but
  local builds need the file too, and it brings back the "reference this repository by its own tag" problem from Part
  2, point 1.

Recommendation: vendored, with a lint step in the workflow that warns when the consumer's copy differs from the one
at the workflow's version.

### 4. The plan job freezes the definition

After step 2, the plan job runs `docker buildx bake --print` with those variables set and:

- outputs the list of platforms (union over the group's targets) for the build matrix;
- rewrites the printed JSON for CI: per target, `output` becomes
  `type=image,name=<first image name>,push-by-digest=true,name-canonical=true,push=<PUSH>`, and `tags` is kept aside
  for the publish job;
- uploads the result as an artifact (`bake-definition.json`).

Every later job builds from that frozen JSON instead of evaluating the HCL again. That guarantees all platforms and the
publish job see identical tags and labels — including `created`, which would otherwise differ per job.

### 5. Build: one job per platform, all targets at once

`build` runs as a matrix over the plan's platforms. Each job:

- checks out the repository (needed for the local context and secrets; use `source: .` on `docker/bake-action`
  rather than its default Git context, so local and CI builds read the same files);
- downloads `bake-definition.json` and runs `docker/bake-action` on it with
  `--set *.platform=<platform>` and `--set *.cache-from/to=type=gha,scope=<image>-<target>-<platform>`;
- reads each target's digest from bake-action's `metadata` output (`<target>.containerimage.digest`) and uploads the
  digests as `digests-<target>-<platform>`.

A target that doesn't list the job's platform is skipped for that job, so targets can have different platform sets.

### 6. Publish: one job for all targets

`publish` downloads the definition and every digest artifact, and for each target runs
`docker buildx imagetools create` with that target's tags and its labels as `index:` and `manifest-descriptor:`
annotations. Then it inspects the result by the first tag. No metadata-action, no shims.

### 7. Status and check names

Same as the other handoff: a final `status` job with `if: always()` that fails unless `plan`, `build` and `publish`
succeeded or were skipped on purpose. Consumers require that **one** check.

| Job       | Name                                                |
|-----------|-----------------------------------------------------|
| `plan`    | `Plan`                                              |
| `build`   | `Build <platform>`, for example `Build linux/arm64` |
| `publish` | `Publish`                                           |
| `status`  | `Image`                                             |

There's now one call per repository, not per image, so a single `Image` check covers everything it publishes.

### 8. Testing an image in a PR (`load`)

Consumers no longer need an action from this repository for that. They run `docker/bake-action` (or
`docker buildx bake`) themselves with `load: true` and `--set *.platform=linux/amd64` on the target they want to
test, optionally with a dedicated `test` target in their HCL. Rewrite `docs/testing-images.md` around that.

### 9. What remains in this repository

- **One reusable workflow**, for example `bake.yml`: `plan` → `build` (matrix) → `publish` → `status`.
- **Inputs:** `files` (default `docker-bake.hcl`), `targets` (default the `default` group), `version`,
  `dispatch-tag`, `push`, `runners` (JSON override for the platform → runner mapping; defaults `linux/amd64` →
  `ubuntu-24.04`, `linux/arm64` → `ubuntu-24.04-arm`), `disable-apparmor`, `timeout-minutes`.
- **Secrets:** one multiline `build-secrets` secret (`KEY=value` lines). The build job masks each value and exports
  it as an environment variable; the HCL refers to it with `secret = ["id=composer_auth,env=COMPOSER_AUTH"]`.
- **`bake/specs.hcl`:** the shared functions from step 3, plus HCL fixture tests.
- **Gone:** `build-image`, `create-manifest`, `build.yml`, `merge.yml`, `build-php.yml`, `merge-php.yml`,
  `build-go-cli.yml`, `merge-go-cli.yml`. The PHP and Go CLI specifics become example HCL in the docs. Consumers stay on
  `@3.0.2` until they migrate.
- `notify-slack-tag.yml` stays (see Part 2).

---

## Part 2 — General review of the workflows and actions

The same review as the other handoff, adjusted for bake. Items marked **gone** disappear with the design above;
items marked **3.x** don't change anything for consumers and can be released earlier.

### Release safety

1. **Guard the internal references (3.x).** Nothing checks that the workflows' `specsnl/github-actions/...@<ref>`
   references match the release; that's how `3.0.1` shipped without its fix. Add a `lint.yml` check that fails a tag
   whose references don't match it, and warns on a PR that changes an action without bumping them. With bake there are
   no internal action references left, but keep the check if the workflow fetches `bake/specs.hcl` by tag.
2. **Self-reference by tag** — mostly gone. With a vendored `specs.hcl` (Part 1, step 3) the workflow references no
   other file of this repository.

### Security

3. **Secrets as secrets** — solved by the `build-secrets` secret (Part 1, step 9) instead of today's string input.
4. **No inputs in shell scripts.** Pass every `${{ inputs.* }}` / `${{ steps.*.outputs.* }}` through `env:` in the
   new workflow's `run:` steps, especially the plan job, which handles ref names and PR data.
5. **Declare `permissions:`.** `contents: read` at the top of `lint.yml`; in `bake.yml`, `contents: read` everywhere
   and `packages: write` only on `build` and `publish`. Document what callers must grant.
6. **Pin third-party actions by commit SHA** with the version as a comment, at least the small third-party ones
   (`cisagov/action-disable-apparmor`, `slackapi/slack-github-action`).
7. **Drop `ASzc/change-string-case-action`** — lowercase in bash (`${var,,}`) or in HCL (`lower()`).
8. **`persist-credentials: false`** on `actions/checkout`.
9. **Add `zizmor` to `lint.yml`** next to actionlint.

### Correctness

10. **Decide `push` on the event, not on `github.actor`.** `github.actor != 'dependabot[bot]'` breaks when a person
    re-runs a dependabot PR's jobs (the push fails with the read-only token), and doesn't catch PRs from forks at all.
    Push by default only when the token can write: not for dependabot PRs (`github.event.pull_request.user.login`) and
    not for fork PRs (`github.event.pull_request.head.repo.full_name != github.repository`). Work it out once, in the
    plan job.
11. **Don't move `:latest` on prerelease tags.** Built into `specs_tags` (`IS_STABLE`), for every image, not only Go
    CLIs.
12. **Leading `v`:** only strip it when a digit follows (Part 1, step 2).

### Consistency and naming

13. **Same input surface for every image type** — gone: there are no shims, only `bake.yml`.
14. **Naming:** `raw-tag` becomes `dispatch-tag`; `raw-tags`, `flavor` and the per-stage title/description inputs
    disappear into HCL. Pick one style for workflow `name:` values.
15. **Remove the deprecated PHP builder names** (`builder_nodejs`, `node`). `docs/php.md` already announces their
    removal in a later major. Check that no consumer still pulls them.
16. **Make the actionlint version consistent** between `lint.yml` (`latest`) and the Taskfile (`1.7.12`).

### Small improvements

17. **No checkout in the publish job** — it only needs the definition and digest artifacts.
18. **`timeout-minutes`** on every job, with an input for the build.
19. **Cache scope per image, target and platform** (Part 1, step 5). Today two images built from the same Dockerfile
    and target overwrite each other's cache.
20. **Provenance and SBOM.** Today `provenance: false` and no SBOM. In bake they're per-target attributes
    (`attest = ["type=provenance,mode=max", "type=sbom"]`), so consumers could opt in from HCL, or `specs.hcl` could
    turn them on by default. Check how GHCR shows the attestation entries first.
21. **`notify-slack-tag.yml`:** remove the `channel` input (an incoming webhook always posts to its own channel),
    build the payload with `jq` so a `"` in a tag name can't break it, and default `runs-on` to `ubuntu-24.04`.
22. **Dependabot:** group the `github-actions` updates into one PR, and consider weekly instead of daily. Note that
    Dependabot doesn't read bake files: base images stay in the Dockerfiles, where it already finds them.

---

## Docs

- Rewrite `docs/pipeline.md` around plan → build → publish → status, and the frozen definition.
- Replace `docs/actions.md`, `docs/php.md` and `docs/go-cli.md` with a bake guide: the consumer's `docker-bake.hcl`,
  the variables CI provides, the `specs.hcl` functions, and complete example files for a plain image, a PHP image and
  a Go CLI with variants.
- Rewrite `docs/testing-images.md` around `docker/bake-action` with `load: true`.
- Update `docs/workflows.md` for `bake.yml` and `docs/releasing.md` for the reference guard.
- Add a **3.x → 4.0.0 migration guide**: the before and after of a consumer's workflow, a step-by-step for writing the
  HCL from the old inputs, a table of every removed workflow, action and input, and the new required check name
  (`Image`) for branch protection rules or rulesets.

## Verify

- **HCL fixture tests in this repository's CI:** for a set of inputs (tag `v1.2.3`, `v1.2.3-rc.1`, `v0.1.0`,
  `v0.0.5`, PR, branch, schedule, dispatch, local), run `docker buildx bake --print` on example HCL files and compare
  the tags and labels with expected JSON. This replaces the coverage `metadata-action` used to give.
- **Local matches CI:** `docker buildx bake --print` in a consumer with the CI variables set gives the same tags and
  labels the run publishes.
- **Every place has the same version:** the index annotation, the descriptor annotations, the platform manifest
  annotations and the config labels all have the same `org.opencontainers.image.version`, and `created` is identical
  across platforms.
- **Tags as expected:**
  - A plain image (`specsnl/utils`) on a tag push: version and tag `1.19.0`.
  - A Go CLI with variants (`specsnl/specs-cli`): tags `1.2.3`, `1.2`, `1`, `latest`, plus `1.2.3-alpine`,
    `1.2-alpine`, `1-alpine`, `alpine`. A prerelease doesn't move `latest` or `alpine`.
  - A PHP image (`specsnl/php84`): `runtime` and `builder` from one call, sharing layers per platform.
- **Events:** a PR (`pr-N`), a branch push, a `workflow_dispatch` (dispatch tag, lowercased) and a scheduled run
  (`nightly`).
- **No push:** a dependabot PR, a person re-running one, and a PR from a fork all build without pushing, and `Image`
  reports success.
- **Secrets:** a build secret reaches the Dockerfile and is masked in the log.
- **`load`:** a consumer's PR test builds, loads and runs the target.

Commands:

```sh
docker buildx bake --print
docker buildx imagetools inspect <ref> --raw | jq .annotations
d=$(docker buildx imagetools inspect <ref> --raw | jq -r '.manifests[0].digest')
docker buildx imagetools inspect <image>@$d --raw | jq .annotations
docker buildx imagetools inspect <ref> --format '{{json .Image}}' | jq '."linux/amd64".config.Labels'
```

## Rollout

1. Release `4.0.0` with `bake.yml`, `bake/specs.hcl` and the docs.
2. Migrate one consumer first, ideally `specsnl/utils` (one image, one stage), and compare its published tags, labels
   and annotations with its last `3.0.2` release.
3. Then `specsnl/specs-cli` (variants and the version build arg) and the PHP repos (`specsnl/php84` and siblings).
   Each one adds a `docker-bake.hcl`, replaces its build and merge jobs with one `bake.yml` call, and updates its
   required checks in the same change.

Consumers that haven't migrated stay on `@3.0.2`.
