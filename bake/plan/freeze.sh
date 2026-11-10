#!/usr/bin/env bash
# Resolves the bake files, with specs.hcl first, into fixed JSON in $RUNNER_TEMP/bake for the build and publish jobs:
#
#   definition.json  the targets to build, see definition.jq
#   publish.json     the images, tags, labels and platforms to publish, see publish.jq
#   matrix.json      the build jobs, see matrix.jq
#
# Reads FILES, TARGETS, RUNNERS and PUSH, and passes the environment on to bake for its variables (VERSION, EVENT,
# ...). Sets the outputs matrix and artifact, and writes the step summary.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib.sh
source "$here/../lib.sh"

specs="$here/../specs.hcl"
if [ ! -f "$specs" ]; then
  echo "::error::$specs not found next to the bake actions."
  exit 1
fi

files=(-f "$specs")
while IFS= read -r file; do files+=(-f "$file"); done < <(printf '%s\n' "${FILES:-}" | trim_lines)
mapfile -t targets < <(printf '%s\n' "${TARGETS:-}" | trim_lines)

dir="$RUNNER_TEMP/bake"
mkdir -p "$dir"
docker buildx bake --progress=quiet "${files[@]}" --print "${targets[@]}" > "$dir/print.json"
if jq -e '(.target // {}) == {}' "$dir/print.json" > /dev/null; then
  echo "::error::The bake files define no targets to build."
  exit 1
fi

jq --arg push "$PUSH" -f "$here/definition.jq" "$dir/print.json" > "$dir/definition.json"
jq -f "$here/publish.jq" "$dir/print.json" > "$dir/publish.json"
jq --argjson override "${RUNNERS:-"{}"}" -f "$here/matrix.jq" "$dir/print.json" > "$dir/matrix.json"

output matrix "$(jq -c . "$dir/matrix.json")"
# Unique per call, so a caller can use bake.yml more than once in a run.
output artifact "bake-$(printf '%s\n' "${FILES:-}" "${TARGETS:-}" | sha256sum | cut -c1-12)"

{
  echo '### Bake definition'
  echo
  echo "Version \`${VERSION:-}\`, push \`$PUSH\`."
  echo
  echo '| Target | Platforms | Tags |'
  echo '|--------|-----------|------|'
  jq -r '
    to_entries[]
    | "| `\(.key)` | \(.value.platforms | join(", ")) | \(.value.tags | map("`\(.)`") | join("<br>")) |"
  ' "$dir/publish.json"
} >> "$GITHUB_STEP_SUMMARY"
