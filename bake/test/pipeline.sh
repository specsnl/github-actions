#!/usr/bin/env bash
# Runs the scripts of the bake actions in the order bake.yml does (freeze, narrow, digests, publish) on
# test/e2e/docker-bake.hcl, with fake build digests and a docker that only records the imagetools calls. Compares
# everything they write with test/pipeline/<case>.txt; pass --update to rewrite those files instead. Also checks that
# freeze.sh refuses bake files it can't build.
set -euo pipefail

cd "$(dirname "$0")/../.."

update=false
[ "${1:-}" = "--update" ] && update=true

work=$(mktemp -d)
trap 'rm -rf "$work"' EXIT

# A docker that records the imagetools calls and passes everything else to the real one.
mkdir "$work/bin"
cat > "$work/bin/docker" <<STUB
#!/usr/bin/env bash
if [ "\$1 \$2" = "buildx imagetools" ]; then
  { echo docker; printf '  %q\\n' "\$@"; } >> "\$DOCKER_LOG"
  exit 0
fi
exec $(command -v docker) "\$@"
STUB
chmod +x "$work/bin/docker"

# run <case env> <dir> <variable=value...>: the environment of a step, with the case's bake variables.
run() {
  local case_file="$1" dir="$2"
  shift 2
  local vars=()
  while IFS= read -r line || [ -n "$line" ]; do
    case "$line" in '' | '#'*) continue ;; esac
    vars+=("$line")
  done < "$case_file"
  env -i PATH="$work/bin:$PATH" HOME="$HOME" RUNNER_TEMP="$dir" GITHUB_OUTPUT="$dir/output" \
    GITHUB_STEP_SUMMARY="$dir/summary" DOCKER_LOG="$dir/docker" SOURCE_DATE_EPOCH=1762689600 "${vars[@]}" "$@"
}

# section <title> <file...>
section() {
  local title="$1" file
  shift
  for file in "$@"; do
    echo "== $title${file:+ $(basename "$file")}"
    if [[ $file == *.json ]]; then jq --sort-keys . "$file"; else cat "$file"; fi
    echo
  done
}

# pipeline <case env> <push>: everything the scripts write, as one document.
pipeline() {
  local case_file="$1" push="$2" dir slug
  dir="$work/$(basename "$case_file" .env)"
  mkdir -p "$dir"
  : > "$dir/docker"

  run "$case_file" "$dir" FILES=$'\n  bake/test/e2e/docker-bake.hcl\n' PUSH="$push" \
    RUNNERS='{"linux/arm64": "arm-runner"}' bake/plan/freeze.sh
  sed 's/^\(.*\)<<EOF_.*/\1<<EOF/; s/^EOF_.*/EOF/' "$dir/output" > "$dir/outputs.txt"
  : > "$dir/output"

  for slug in $(jq -r '.[].slug' "$dir/bake/matrix.json"); do
    run "$case_file" "$dir" PLATFORM="$(jq -r --arg s "$slug" '.[] | select(.slug == $s) | .platform' "$dir/bake/matrix.json")" \
      SLUG="$slug" bake/narrow/narrow.sh
    # What docker/bake-action reports: an object per target, and keys that aren't targets.
    run "$case_file" "$dir" SLUG="$slug" METADATA="$(jq --arg slug "$slug" '
      .target | with_entries(.value = {"containerimage.digest": "sha256:\(.key)-\($slug)"})
      | . + {"buildx.build.warnings": []}
    ' "$dir/bake/definition-$slug.json")" bake/digests/digests.sh > /dev/null
  done

  if [ "$push" = true ]; then
    run "$case_file" "$dir" bake/publish/publish.sh > /dev/null
  fi

  section outputs "$dir/outputs.txt"
  section summary "$dir/summary"
  section bake "$dir"/bake/definition.json "$dir"/bake/publish.json "$dir"/bake/matrix.json \
    "$dir"/bake/definition-*.json
  if [ "$push" = true ]; then
    section digests "$dir"/digests/*.json
    section docker "$dir/docker"
  fi
}

failed=0

for spec in tag-stable:true pr:false; do
  name="${spec%%:*}"
  expected="bake/test/pipeline/$name.txt"
  actual=$(pipeline "bake/test/cases/$name.env" "${spec#*:}")
  if $update; then
    printf '%s\n' "$actual" > "$expected"
    echo "updated pipeline $name"
  elif diff -u --label "$expected" --label actual "$expected" <(printf '%s\n' "$actual"); then
    echo "ok      pipeline $name"
  else
    echo "FAILED  pipeline $name"
    failed=1
  fi
done

# refuse <description> <expected error> <case env> <bake file content> <variable=value...>
refuse() {
  local description="$1" expected="$2" case_file="$3" content="$4" dir status=0 actual
  shift 4
  dir=$(mktemp -d "$work/refuse.XXXXXX")
  printf '%s\n' "$content" > "$dir/docker-bake.hcl"
  actual=$(run "$case_file" "$dir" FILES="$dir/docker-bake.hcl" "$@" bake/plan/freeze.sh 2>&1) || status=$?
  if [ "$status" -ne 0 ] && [[ $actual == *"$expected"* ]]; then
    echo "ok      refuses $description"
  else
    echo "FAILED  refuses $description"
    echo "  expected: $expected"
    echo "  actual:   exit=$status $actual"
    failed=1
  fi
}

refuse 'bake files without targets' \
  'The bake files define no targets to build.' \
  bake/test/cases/tag-stable.env 'group "default" { targets = [] }' PUSH=true
refuse 'a target without platforms' \
  'target default has no platforms' \
  bake/test/cases/tag-stable.env 'target "default" { tags = specs_tags(["ghcr.io/specsnl/app"], "") }' PUSH=true
refuse 'pushing a target without tags' \
  'target default has no tags for this event' \
  bake/test/cases/unknown-event.env \
  'target "default" {
    platforms = ["linux/amd64"]
    tags = specs_tags(["ghcr.io/specsnl/app"], "")
  }' PUSH=true
refuse 'a platform without a runner' \
  'no runner for platform linux/riscv64' \
  bake/test/cases/tag-stable.env \
  'target "default" {
    platforms = ["linux/riscv64"]
    tags = specs_tags(["ghcr.io/specsnl/app"], "")
  }' PUSH=true

exit "$failed"
