#!/usr/bin/env bash
# Deletes the e2e test images of closed pull requests from GHCR. Per package, it deletes every version whose tags all
# belong to closed pull requests (pr-<N> or pr-<N>-<variant>), then every untagged version that no tagged image refers
# to any more: the platform images of those, and of indexes a later push replaced. Untagged versions younger than a day
# are kept, so a run whose platform images aren't in an index yet keeps them.
#
# Reads GH_TOKEN, GITHUB_REPOSITORY, PACKAGES (space-separated, i.e. "github-actions/e2e") and DRY_RUN ("true" only
# lists what it would delete).
set -euo pipefail

owner="${GITHUB_REPOSITORY%%/*}"
cutoff=$(jq -nr 'now - 86400 | todate')
declare -A closed=()

# is_closed <number>: whether the pull request is closed, merged included.
is_closed() {
  [ -n "${closed[$1]:-}" ] || closed[$1]=$(gh api "repos/$GITHUB_REPOSITORY/pulls/$1" --jq '.state == "closed"')
  [ "${closed[$1]}" = true ]
}

# delete <package api> <id> <description>
delete() {
  echo "delete $3"
  [ "${DRY_RUN:-false}" = true ] || gh api --method DELETE "$1/$2" --silent
}

# versions <package api>: [{id, name, updated_at, tags}]
versions() {
  gh api --paginate "$1" --jq '.[] | {id, name, updated_at, tags: .metadata.container.tags}' | jq -s .
}

for package in $PACKAGES; do
  api="orgs/$owner/packages/container/${package//\//%2F}/versions"
  image="ghcr.io/$owner/$package"

  while IFS=$'\t' read -r id tags; do
    stale=true
    for tag in $tags; do
      [[ $tag =~ ^pr-([0-9]+)(-.+)?$ ]] && is_closed "${BASH_REMATCH[1]}" || stale=false
    done
    if $stale; then delete "$api" "$id" "$image:${tags// /, }"; fi
  done < <(versions "$api" | jq -r '.[] | select(.tags != []) | [.id, (.tags | join(" "))] | @tsv')

  # In a dry run the tagged versions above are still there, so their platform images count as referenced.
  versions=$(versions "$api")
  referenced=$(
    for digest in $(jq -r '.[] | select(.tags != []) | .name' <<< "$versions"); do
      docker buildx imagetools inspect --raw "$image@$digest" | jq -r '.manifests[]?.digest'
    done
  )
  while IFS=$'\t' read -r id digest; do
    delete "$api" "$id" "$image@$digest"
  done < <(jq -r --arg cutoff "$cutoff" --arg referenced "$referenced" '
    ($referenced | split("\n")) as $referenced
    | .[] | select(.tags == [] and .updated_at < $cutoff and (.name | IN($referenced[]) | not)) | [.id, .name] | @tsv
  ' <<< "$versions")
done
