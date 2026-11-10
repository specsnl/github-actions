#!/usr/bin/env bash
# Masks every build secret and exports it as an environment variable for the build.
#
# Reads BUILD_SECRETS, "NAME=value" lines. Blank lines are skipped. A NAME the runner or the build tooling depends on
# is refused, so a secret can't change how the job runs.
set -euo pipefail

# shellcheck source=../lib.sh
source "$(dirname "$0")/../lib.sh"

while IFS= read -r line || [ -n "$line" ]; do
  [ -z "${line//[[:space:]]/}" ] && continue
  name="${line%%=*}"
  value="${line#*=}"
  if [ "$name" = "$line" ] || [[ ! $name =~ ^[A-Za-z_][A-Za-z0-9_]*$ ]]; then
    echo "::error::Every line of build-secrets must be NAME=value, with a NAME of letters, digits and underscores."
    exit 1
  fi
  case "$name" in
    GITHUB_* | RUNNER_* | ACTIONS_* | BUILDX_* | DOCKER_* | PATH | HOME | BASH_ENV | ENV | NODE_OPTIONS | LD_*)
      echo "::error::build-secrets may not set $name."
      exit 1
      ;;
  esac
  [ -n "$value" ] && echo "::add-mask::$value"
  export_env "$name" "$value"
done <<< "${BUILD_SECRETS:-}"
