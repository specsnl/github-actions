#!/usr/bin/env bash
# Creates a multi-platform manifest list for every target in $RUNNER_TEMP/bake/publish.json from the build jobs'
# digests in $RUNNER_TEMP/digests, tags it, and copies the target's labels onto it as annotations.
set -euo pipefail

publish="$RUNNER_TEMP/bake/publish.json"
digests=$(jq -s '
  map(to_entries) | add | group_by(.key) | map({key: .[0].key, value: map(.value)}) | from_entries
' "$RUNNER_TEMP"/digests/digests-*.json)

for target in $(jq -r 'keys[]' "$publish"); do
  image=$(jq -r --arg t "$target" '.[$t].image' "$publish")
  mapfile -t tags < <(jq -r --arg t "$target" '.[$t].tags[]' "$publish")
  mapfile -t annotations < <(jq -r --arg t "$target" '
    .[$t].labels | to_entries[] | "index:\(.key)=\(.value)", "manifest-descriptor:\(.key)=\(.value)"
  ' "$publish")
  mapfile -t sources < <(jq -r --arg t "$target" --arg image "$image" '(.[$t] // [])[] | "\($image)@\(.)"' <<< "$digests")

  expected=$(jq -r --arg t "$target" '.[$t].platforms | length' "$publish")
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
