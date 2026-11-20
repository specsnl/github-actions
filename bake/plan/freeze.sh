#!/usr/bin/env bash
# Resolves the bake files, with specs.hcl first, into fixed JSON in $RUNNER_TEMP/bake for the build and publish jobs:
#
#   bake.json               the output of bake --print; the publish job reads the tags, labels and platforms from it
#   definition-<slug>.json  what the build job for one platform builds, see definition.jq
#
# Reads FILES, TARGETS, RUNNERS and PUSH, and passes the environment on to bake for its variables (VERSION, EVENT,
# ...). Sets the output matrix and writes the step summary.
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
docker buildx bake --progress=quiet "${files[@]}" --print "${targets[@]}" > "$dir/bake.json"
if jq -e '(.target // {}) == {}' "$dir/bake.json" > /dev/null; then
  echo "::error::The bake files define no targets to build."
  exit 1
fi

matrix=$(jq -c --argjson override "${RUNNERS:-"{}"}" --arg push "$PUSH" -f "$here/matrix.jq" "$dir/bake.json")
for slug in $(jq -r '.[].slug' <<< "$matrix"); do
  jq --arg platform "$(jq -r --arg slug "$slug" '.[] | select(.slug == $slug) | .platform' <<< "$matrix")" \
    --arg slug "$slug" --arg push "$PUSH" -f "$here/definition.jq" "$dir/bake.json" > "$dir/definition-$slug.json"
done

output matrix "$matrix"

{
  echo '### Bake definition'
  echo
  echo "Version \`${VERSION:-}\`, push \`$PUSH\`."
  echo
  echo '| Target | Platforms | Tags |'
  echo '|--------|-----------|------|'
  jq -r '
    .target | to_entries[]
    | "| `\(.key)` | \(.value.platforms | join(", ")) | \(.value.tags // [] | map("`\(.)`") | join("<br>")) |"
  ' "$dir/bake.json"
} >> "$GITHUB_STEP_SUMMARY"
