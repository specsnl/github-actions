#!/usr/bin/env bash
# Runs bake/plan/vars.sh for a set of GitHub contexts and checks its outputs.
set -euo pipefail

cd "$(dirname "$0")/../.."

failed=0

# check <description> <expected outputs> <environment...>
check() {
  local description="$1" expected="$2"
  shift 2

  local output status=0 actual
  output=$(mktemp)
  env -i PATH="$PATH" GITHUB_OUTPUT="$output" GITHUB_REPOSITORY=specsnl/example "$@" bake/plan/vars.sh > /dev/null 2>&1 || status=$?

  if [ "$status" -ne 0 ]; then
    actual="exit=$status"
  else
    actual=$(awk '
      /^created<</ { getline; getline; next }
      /<<EOF_/ { key = substr($0, 1, index($0, "<<") - 1); getline value; printf "%s=%s ", key, value; getline; next }
    ' "$output" | sed 's/ $//')
  fi
  rm -f "$output"

  if [ "$actual" = "$expected" ]; then
    echo "ok      $description"
  else
    echo "FAILED  $description"
    echo "  expected: $expected"
    echo "  actual:   $actual"
    failed=1
  fi
}

check 'stable tag' \
  'version=1.2.3 dispatch-tag=latest is-stable=true push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3
check 'prerelease tag' \
  'version=1.2.3-rc.1 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=v1.2.3-rc.1
check 'tag without v' \
  'version=2.0.0 dispatch-tag=latest is-stable=true push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=2.0.0
check 'tag starting with v and a letter' \
  'version=version-2 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=tag GITHUB_REF_NAME=version-2
check 'branch push' \
  'version=main dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
check 'branch named like a version' \
  'version=v1.2.3 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=v1.2.3
check 'push to a dependabot branch' \
  'version=dependabot/docker/foo dispatch-tag=latest is-stable=false push=false' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=dependabot/docker/foo
check 'pull request' \
  'version=pr-42 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=pull_request GITHUB_REF_TYPE=branch GITHUB_REF_NAME=42/merge \
  PR_NUMBER=42 PR_AUTHOR=someone PR_HEAD_REPOSITORY=specsnl/example
check 'pull request from dependabot, also when a person re-runs it' \
  'version=pr-42 dispatch-tag=latest is-stable=false push=false' \
  GITHUB_EVENT_NAME=pull_request GITHUB_REF_TYPE=branch GITHUB_REF_NAME=42/merge GITHUB_ACTOR=someone \
  PR_NUMBER=42 'PR_AUTHOR=dependabot[bot]' PR_HEAD_REPOSITORY=specsnl/example
check 'pull request from a fork' \
  'version=pr-42 dispatch-tag=latest is-stable=false push=false' \
  GITHUB_EVENT_NAME=pull_request GITHUB_REF_TYPE=branch GITHUB_REF_NAME=42/merge \
  PR_NUMBER=42 PR_AUTHOR=someone PR_HEAD_REPOSITORY=someone/example
check 'schedule' \
  'version=nightly dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=schedule GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
check 'workflow_dispatch' \
  'version=testing dispatch-tag=testing is-stable=false push=true' \
  GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main INPUT_DISPATCH_TAG=Testing
check 'workflow_dispatch without a dispatch tag' \
  'version=latest dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=workflow_dispatch GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main
check 'explicit version' \
  'version=9.9.9 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main INPUT_VERSION=9.9.9
check 'explicit push on a dependabot pull request' \
  'version=pr-42 dispatch-tag=latest is-stable=false push=true' \
  GITHUB_EVENT_NAME=pull_request GITHUB_REF_TYPE=branch GITHUB_REF_NAME=42/merge \
  PR_NUMBER=42 'PR_AUTHOR=dependabot[bot]' PR_HEAD_REPOSITORY=specsnl/example INPUT_PUSH=true
check 'explicit push=false' \
  'version=main dispatch-tag=latest is-stable=false push=false' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main INPUT_PUSH=false
check 'invalid push' \
  'exit=1' \
  GITHUB_EVENT_NAME=push GITHUB_REF_TYPE=branch GITHUB_REF_NAME=main INPUT_PUSH=yes
check 'event the tag rules do not cover' \
  'version= dispatch-tag=latest is-stable=false push=false' \
  GITHUB_EVENT_NAME=merge_group GITHUB_REF_TYPE=branch GITHUB_REF_NAME=gh-readonly-queue/main/pr-1

exit "$failed"
