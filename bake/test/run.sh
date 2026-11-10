#!/usr/bin/env bash
# Runs `docker buildx bake --print` on test/docker-bake.hcl for every case in test/cases and compares the tags,
# labels, annotations and args with the expected JSON. Pass --update to rewrite the expected files instead.
set -euo pipefail

cd "$(dirname "$0")"

variables=(VERSION EVENT REF_TYPE REF_NAME PR_NUMBER DISPATCH_TAG IS_STABLE REVISION SOURCE CREATED REPOSITORY_NAME REPOSITORY_DESCRIPTION LICENSES)
update=false
[ "${1:-}" = "--update" ] && update=true

failed=0
for case_file in cases/*.env; do
  name=$(basename "$case_file" .env)
  expected="cases/$name.json"

  actual=$(
    for variable in "${variables[@]}"; do unset "$variable"; done
    while IFS= read -r line || [ -n "$line" ]; do
      case "$line" in '' | '#'*) continue ;; esac
      export "${line?}"
    done < "$case_file"
    docker buildx bake --progress=quiet -f ../specs.hcl -f docker-bake.hcl --print 2> /dev/null |
      jq --sort-keys '.target | map_values({tags, labels, annotations, args} | with_entries(select(.value != null)))'
  )

  if $update; then
    printf '%s\n' "$actual" > "$expected"
    echo "updated $name"
  elif diff -u --label "$expected" --label "actual" "$expected" <(printf '%s\n' "$actual"); then
    echo "ok      $name"
  else
    echo "FAILED  $name"
    failed=1
  fi
done

exit "$failed"
