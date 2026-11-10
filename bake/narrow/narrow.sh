#!/usr/bin/env bash
# Narrows $RUNNER_TEMP/bake/definition.json to one platform, see narrow.jq.
#
# Reads PLATFORM and SLUG. Sets the output file to the narrowed definition.
set -euo pipefail

here=$(cd "$(dirname "$0")" && pwd)
# shellcheck source=../lib.sh
source "$here/../lib.sh"

dir="$RUNNER_TEMP/bake"
jq --arg platform "$PLATFORM" --arg slug "$SLUG" --slurpfile publish "$dir/publish.json" -f "$here/narrow.jq" \
  "$dir/definition.json" > "$dir/definition-$SLUG.json"
output file "$dir/definition-$SLUG.json"
