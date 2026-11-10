#!/usr/bin/env bash
# Reads the repository's name, description and SPDX license from the GitHub API, the fallbacks specs_labels uses.
#
# Reads GH_TOKEN and GITHUB_REPOSITORY. Sets the outputs name, description and license.
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

repository=$(gh api "repos/$GITHUB_REPOSITORY")

output name "$(jq -r '.name' <<< "$repository")"
output description "$(jq -r '.description // ""' <<< "$repository")"
# GitHub reports a license it doesn't recognise as NOASSERTION, which isn't a license.
output license "$(jq -r '.license.spdx_id // "" | select(. != "NOASSERTION")' <<< "$repository")"
