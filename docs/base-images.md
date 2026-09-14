# Base images

These workflows take a `target` — the Dockerfile stage to publish — and nothing else. They deliberately do **not**
offer a menu of base images to pick from.

## Why there is no `base-image` input

The tempting design is a menu: let the caller pick `scratch`, `debian`, `debian-slim` or `alpine`. That is the wrong
abstraction, because the choice is not a preference. It is a property of what the binary does at runtime, and nothing
in a workflow can validate it:

| Variant              | Only works when                                                                                          |
|----------------------|----------------------------------------------------------------------------------------------------------|
| `scratch`/distroless | The binary is genuinely self-contained — no shelling out, no NSS lookups, CA bundle copied in explicitly |
| `debian-slim`        | A real userland is needed. Ships **no** CA bundle, so one must be copied from the builder or HTTPS fails |
| `alpine`             | Same, smaller, but musl — safe only with `CGO_ENABLED=0`, and busybox utilities differ from the GNU ones |

specs-cli, for instance, cannot use a scratch variant at all: it runs template hooks through `bash -c` and refuses to
run them when bash is absent from `PATH`. A workflow offering `scratch` as a menu item would hand that repository an
image that is broken for most of its templates, and nothing in the workflow could detect it.

So the consuming repository owns its Dockerfile stages, and therefore its base image. It is the only place that knows
what the binary needs.

## Variants are a per-repository decision too

The [capability to publish variants](go-cli.md#publishing-variants) lives here; whether to use it does not.

An `alpine` variant of specs-cli would not be `apk add --no-cache bash` and done. That part is one line. The part that
is not fixable in a line: template hooks are arbitrary user-written shell, and busybox `sed` and `grep` differ from the
GNU ones a hook was written against. The two images would not behave the same for the thing specs-cli exists to do, so
it stays debian-only.

A Go CLI that does not shell out has no such problem and can publish both freely.

## If a shared Dockerfile is wanted later

That is a separate concern. It is worth starting by not encoding a choice that would then have to be unpicked — a
`target` input stays correct either way, because a shared Dockerfile still has stages.
