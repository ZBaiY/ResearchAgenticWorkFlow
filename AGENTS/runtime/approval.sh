#!/usr/bin/env bash
set -euo pipefail

approval_mode() {
  local mode="${APPROVAL_MODE:-interactive}"
  case "$mode" in
    yes|no|interactive) printf '%s\n' "$mode" ;;
    *) printf 'interactive\n' ;;
  esac
}

approval_interactive() {
  if [[ "${APPROVAL_INTERACTIVE:-}" == "1" ]]; then
    printf '1\n'
    return 0
  fi
  if [[ "${APPROVAL_INTERACTIVE:-}" == "0" ]]; then
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

approval_stage_confirm() {
  local stage_mode="${AGENTHUB_STAGE_APPROVAL:-}"
  case "$stage_mode" in
    yes) return 0 ;;
    no) return 1 ;;
  esac
  approval_confirm "${1:-Proceed? (y/N) }"
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

  approval_raw_text "$prompt" "$default_val"
}

approval_raw_text() {
  # usage: approval_raw_text "<prompt>" "<default>"
  local prompt="${1:-}"
  local default_val="${2:-}"
  local interactive ans
  interactive="$(approval_interactive)"
  if [[ "$interactive" != "1" ]]; then
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
    if IFS= read -r ans 2>/dev/null; then
      :
    fi
  fi
  if [[ -z "$ans" ]]; then
    printf '%s\n' "$default_val"
  else
    printf '%s\n' "$ans"
  fi
}

approval_clarification_policy() {
  local p="${SKILL_CLARIFICATION_POLICY:-auto}"
  case "$p" in
    ask_user|auto) printf '%s\n' "$p" ;;
    *) printf 'auto\n' ;;
  esac
}

approval_clarify_text() {
  # usage: approval_clarify_text "<prompt>" "<default>"
  local policy
  policy="$(approval_clarification_policy)"
  if [[ "$policy" != "ask_user" ]]; then
    printf '%s\n' "${2:-}"
    return 0
  fi
  # Clarification is policy-driven, regardless of APPROVAL_MODE.
  approval_raw_text "${1:-}" "${2:-}"
}
