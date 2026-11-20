#!/usr/bin/env bash
# Creates a multi-platform manifest list for every target in $RUNNER_TEMP/bake/bake.json from the digests in the build
# jobs' metadata in $RUNNER_TEMP/metadata, tags it, and copies the target's labels onto it as annotations.
set -euo pipefail

bake="$RUNNER_TEMP/bake/bake.json"
# {"<target>": ["<digest>", ...]}. Bake's metadata has an object per target, and keys that aren't targets.
digests=$(jq -s '
  map(with_entries(select(.value | type == "object")) | to_entries) | add | group_by(.key)
  | map({key: .[0].key, value: map(.value["containerimage.digest"] // error("no digest in the build metadata"))})
  | from_entries
' "$RUNNER_TEMP"/metadata/*.json)

for target in $(jq -r '.target | keys[]' "$bake"); do
  image=$(jq -r --arg t "$target" '.target[$t].tags[0] | sub(":[^:/]*$"; "")' "$bake")
  mapfile -t tags < <(jq -r --arg t "$target" '.target[$t].tags[]' "$bake")
  mapfile -t annotations < <(jq -r --arg t "$target" '
    .target[$t].labels // {} | to_entries[] | "index:\(.key)=\(.value)", "manifest-descriptor:\(.key)=\(.value)"
  ' "$bake")
  mapfile -t sources < <(jq -r --arg t "$target" --arg image "$image" '(.[$t] // [])[] | "\($image)@\(.)"' <<< "$digests")

  expected=$(jq -r --arg t "$target" '.target[$t].platforms | length' "$bake")
  if [ "${#sources[@]}" -ne "$expected" ]; then
    echo "::error::$target has ${#sources[@]} digests for $expected platforms."
    exit 1
  fi

  args=()
  for tag in "${tags[@]}"; do args+=(--tag "$tag"); done
  for annotation in "${annotations[@]}"; do args+=(--annotation "$annotation"); done

  echo "::group::$target"
  docker buildx imagetools create "${args[@]}" "${sources[@]}"
  docker buildx imagetools inspect "${tags[0]}"
  echo "::endgroup::"
done
