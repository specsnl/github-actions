#!/usr/bin/env bash
# Checks that bake.yml's SPECS_HCL_SHA256 is the hash of bake/specs.hcl. Pass --update to rewrite it instead.
set -euo pipefail

cd "$(dirname "$0")/../.."

workflow=.github/workflows/bake.yml
path='.jobs.plan.steps[] | select(.name == "Compare specs.hcl") | .env.SPECS_HCL_SHA256'

if command -v sha256sum > /dev/null; then
  actual=$(sha256sum bake/specs.hcl | cut -d' ' -f1)
else
  actual=$(shasum -a 256 bake/specs.hcl | cut -d' ' -f1)
fi
expected=$(yq "$path" "$workflow")

if [ "${1:-}" = "--update" ]; then
  sed -i.bak "s/SPECS_HCL_SHA256: $expected/SPECS_HCL_SHA256: $actual/" "$workflow" && rm "$workflow.bak"
  echo "SPECS_HCL_SHA256 is now $actual"
elif [ "$actual" != "$expected" ]; then
  echo "SPECS_HCL_SHA256 in $workflow is $expected, but bake/specs.hcl hashes to $actual. Run: task test:update"
  exit 1
else
  echo "ok      SPECS_HCL_SHA256"
fi
