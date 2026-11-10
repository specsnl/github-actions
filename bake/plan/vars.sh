#!/usr/bin/env bash
# Works out the run's version, dispatch tag, stability and whether to push, from the event and the inputs.
#
# Reads INPUT_VERSION, INPUT_DISPATCH_TAG, INPUT_PUSH, PR_NUMBER, PR_AUTHOR, PR_HEAD_REPOSITORY and the GITHUB_*
# variables of the event. Sets the outputs version, dispatch-tag, is-stable, push and created.
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

dispatch_tag="${INPUT_DISPATCH_TAG:-}"
dispatch_tag="${dispatch_tag,,}"
dispatch_tag="${dispatch_tag:-latest}"

version="${INPUT_VERSION:-}"
if [ -z "$version" ]; then
  case "${GITHUB_EVENT_NAME:-}" in
    push)
      version="$GITHUB_REF_NAME"
      if [ "$GITHUB_REF_TYPE" = tag ] && [[ $version =~ ^v[0-9] ]]; then
        version="${version#v}"
      fi
      ;;
    pull_request | pull_request_target) version="pr-${PR_NUMBER:-}" ;;
    schedule) version=nightly ;;
    workflow_dispatch) version="$dispatch_tag" ;;
  esac
fi

is_stable=false
if [ "${GITHUB_EVENT_NAME:-}" = push ] && [ "${GITHUB_REF_TYPE:-}" = tag ] && [[ $version != *-* ]]; then
  is_stable=true
fi

push="${INPUT_PUSH:-}"
if [ -z "$push" ]; then
  push=true
  case "${GITHUB_EVENT_NAME:-}" in
    pull_request | pull_request_target)
      if [ "${PR_AUTHOR:-}" = 'dependabot[bot]' ] || [ "${PR_HEAD_REPOSITORY:-}" != "${GITHUB_REPOSITORY:-}" ]; then
        push=false
      fi
      ;;
    push)
      if [ "${GITHUB_REF_TYPE:-}" = branch ] && [[ ${GITHUB_REF_NAME:-} == dependabot/* ]]; then
        push=false
      fi
      ;;
    schedule | workflow_dispatch) ;;
    *) push=false ;;
  esac
fi
if [ "$push" != true ] && [ "$push" != false ]; then
  echo "::error::push must be \"true\" or \"false\", got \"$push\"."
  exit 1
fi

output version "$version"
output dispatch-tag "$dispatch_tag"
output is-stable "$is_stable"
output push "$push"
output created "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
