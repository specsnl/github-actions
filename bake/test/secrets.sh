#!/usr/bin/env bash
# Runs bake/secrets/secrets.sh on a set of build-secrets inputs and checks the variables it exports and masks.
set -euo pipefail

cd "$(dirname "$0")/../.."

failed=0

# check <description> <expected> <build secrets>
check() {
  local description="$1" expected="$2" secrets="$3"

  local env stdout status=0 actual
  env=$(mktemp)
  stdout=$(env -i PATH="$PATH" GITHUB_ENV="$env" BUILD_SECRETS="$secrets" bake/secrets/secrets.sh 2>&1) || status=$?

  if [ "$status" -ne 0 ]; then
    actual="exit=$status $stdout"
  else
    actual=$(
      {
        printf '%s\n' "$stdout"
        awk '/<<EOF_/ { key = substr($0, 1, index($0, "<<") - 1); getline value; print key "=" value; getline }' "$env"
      } | sed '/^$/d' | paste -sd ' ' -
    )
  fi
  rm -f "$env"

  if [ "$actual" = "$expected" ]; then
    echo "ok      $description"
  else
    echo "FAILED  $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failed=1
  fi
}

check 'no secrets' \
  '' \
  ''
check 'one secret' \
  '::add-mask::s3cret TOKEN=s3cret' \
  'TOKEN=s3cret'
check 'blank lines and a last line without a newline' \
  '::add-mask::a ::add-mask::b A=a B=b' \
  $'\n  \nA=a\n\nB=b'
check 'a value with = in it' \
  '::add-mask::x=y==z KEY=x=y==z' \
  'KEY=x=y==z'
check 'an empty value is exported but not masked' \
  'EMPTY=' \
  'EMPTY='
check 'a line without =' \
  'exit=1 ::error::Every line of build-secrets must be NAME=value, with a NAME of letters, digits and underscores.' \
  'TOKEN'
check 'a name with a dash' \
  'exit=1 ::error::Every line of build-secrets must be NAME=value, with a NAME of letters, digits and underscores.' \
  'MY-TOKEN=x'
check 'a name starting with a digit' \
  'exit=1 ::error::Every line of build-secrets must be NAME=value, with a NAME of letters, digits and underscores.' \
  '1TOKEN=x'
for name in GITHUB_TOKEN RUNNER_TEMP ACTIONS_RUNTIME_TOKEN BUILDX_BUILDER DOCKER_HOST PATH HOME BASH_ENV ENV \
  NODE_OPTIONS LD_PRELOAD; do
  check "the reserved name $name" \
    "exit=1 ::error::build-secrets may not set $name." \
    "$name=x"
done

exit "$failed"
