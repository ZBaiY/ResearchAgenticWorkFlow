#!/usr/bin/env bash
set -euo pipefail

approval_mode() {
  local mode="${AGENTHUB_APPROVAL:-prompt}"
  case "$mode" in
    yes|no|prompt) printf '%s\n' "$mode" ;;
    *) printf 'prompt\n' ;;
  esac
}

approval_interactive() {
  if [[ "${AGENTHUB_INTERACTIVE:-}" == "1" ]]; then
    printf '1\n'
    return 0
  fi
  if [[ "${AGENTHUB_INTERACTIVE:-}" == "0" ]]; then
    printf '0\n'
    return 0
  fi
  if [[ -t 0 ]]; then
    printf '1\n'
  else
    printf '0\n'
  fi
}

approval_confirm() {
  # usage: approval_confirm "<prompt>"
  local prompt="${1:-Proceed? (y/N) }"
  local mode interactive ans
  mode="$(approval_mode)"
  interactive="$(approval_interactive)"

  if [[ "$mode" == "yes" ]]; then
    return 0
  fi
  if [[ "$mode" == "no" ]]; then
    return 1
  fi
  if [[ "$interactive" != "1" ]]; then
    return 1
  fi

  ans=""
  if [[ -r /dev/tty ]]; then
    if { printf "%s" "$prompt" > /dev/tty && IFS= read -r ans < /dev/tty; } 2>/dev/null; then
      :
    fi
  fi
  ans="$(printf '%s' "$ans" | tr '[:upper:]' '[:lower:]')"
  [[ "$ans" == "y" || "$ans" == "yes" ]]
}

approval_text() {
  # usage: approval_text "<prompt>" "<default>"
  local prompt="${1:-}"
  local default_val="${2:-}"
  local mode interactive ans
  mode="$(approval_mode)"
  interactive="$(approval_interactive)"

  if [[ "$mode" == "yes" || "$mode" == "no" || "$interactive" != "1" ]]; then
    printf '%s\n' "$default_val"
    return 0
  fi

  ans=""
  if [[ -r /dev/tty ]]; then
    if { printf "%s" "$prompt" > /dev/tty && IFS= read -r ans < /dev/tty; } 2>/dev/null; then
      :
    fi
  fi
  if [[ -z "$ans" ]]; then
    printf '%s\n' "$default_val"
  else
    printf '%s\n' "$ans"
  fi
}
