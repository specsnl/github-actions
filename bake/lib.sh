# shellcheck shell=bash
# Helpers for the scripts of the bake actions. Source it, don't run it.

# output <name> <value>: set a step output. The value may span several lines.
output() {
  _bake_write "$GITHUB_OUTPUT" "$1" "$2"
}

# export_env <name> <value>: set an environment variable for the job's later steps.
export_env() {
  _bake_write "$GITHUB_ENV" "$1" "$2"
}

# The random delimiter keeps a value from ending the block early or injecting more variables.
_bake_write() {
  local delimiter
  delimiter="EOF_$(openssl rand -hex 16)"
  printf '%s<<%s\n%s\n%s\n' "$2" "$delimiter" "$3" "$delimiter" >> "$1"
}

# Reads lines from stdin and writes them trimmed, without the empty ones.
trim_lines() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d'
}
