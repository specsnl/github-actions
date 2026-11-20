# shellcheck shell=bash
# Helpers for the scripts of the plan action. Source it, don't run it.

# output <name> <value>: set a step output. The value may span several lines; the random delimiter keeps it from
# ending the block early or injecting more outputs.
output() {
  local delimiter
  delimiter="EOF_$(openssl rand -hex 16)"
  printf '%s<<%s\n%s\n%s\n' "$1" "$delimiter" "$2" "$delimiter" >> "$GITHUB_OUTPUT"
}

# Reads lines from stdin and writes them trimmed, without the empty ones.
trim_lines() {
  sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//' -e '/^$/d'
}
