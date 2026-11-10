#!/usr/bin/env bash
# Writes the image digest of every target in bake's build metadata to $RUNNER_TEMP/digests/digests-$SLUG.json, as
# {"<target>": "<digest>"}.
#
# Reads METADATA and SLUG.
set -euo pipefail

dir="$RUNNER_TEMP/digests"
mkdir -p "$dir"
jq '
  with_entries(select(.value | type == "object"))
  | map_values(.["containerimage.digest"] // error("no digest in the build metadata"))
' <<< "$METADATA" > "$dir/digests-$SLUG.json"
cat "$dir/digests-$SLUG.json"
