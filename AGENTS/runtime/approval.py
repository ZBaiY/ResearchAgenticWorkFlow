#!/usr/bin/env python3
import os
import sys


def approval_mode() -> str:
    mode = os.environ.get("APPROVAL_MODE", "interactive").strip().lower()
    if mode in {"yes", "no", "interactive"}:
        return mode
    return "interactive"


def approval_interactive() -> bool:
    env = os.environ.get("APPROVAL_INTERACTIVE", "").strip()
    if env == "1":
        return True
    if env == "0":
        return False
    try:
        return sys.stdin.isatty()
    except Exception:
        return False


def _read_text(question: str, default: str = "") -> str:
    if not approval_interactive():
        return default
    try:
        with open("/dev/tty", "r+", encoding="utf-8") as tty:
            tty.write(question)
            tty.flush()
            val = tty.readline().strip()
    except Exception:
        try:
            sys.stdout.write(question)
            sys.stdout.flush()
            val = input().strip()
        except EOFError:
            return default
    return val if val else default


def confirm(question: str, default: bool = False) -> bool:
    mode = approval_mode()
    if mode == "yes":
        return True
    if mode == "no":
        return False
    if not approval_interactive():
        return default
    try:
        with open("/dev/tty", "r+", encoding="utf-8") as tty:
            tty.write(question)
            tty.flush()
            val = tty.readline().strip().lower()
    except Exception:
        try:
            sys.stdout.write(question)
            sys.stdout.flush()
            val = input().strip().lower()
        except EOFError:
            return default
    return val in {"y", "yes"}


def ask_text(question: str, default: str = "") -> str:
    mode = approval_mode()
    if mode in {"yes", "no"}:
        return default
    return _read_text(question, default=default)


def clarification_policy() -> str:
    p = os.environ.get("SKILL_CLARIFICATION_POLICY", "auto").strip().lower()
    if p in {"ask_user", "auto"}:
        return p
    return "auto"


def clarify_text(question: str, default: str = "") -> str:
    if clarification_policy() != "ask_user":
        return default
    # Clarification gates are policy-driven (ask_user/auto), not approval-mode-driven.
    return _read_text(question, default=default)
