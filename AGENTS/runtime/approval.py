#!/usr/bin/env python3
import os
import sys


def approval_mode() -> str:
    mode = os.environ.get("AGENTHUB_APPROVAL", "prompt").strip().lower()
    if mode in {"yes", "no", "prompt"}:
        return mode
    return "prompt"


def approval_interactive() -> bool:
    env = os.environ.get("AGENTHUB_INTERACTIVE", "").strip()
    if env == "1":
        return True
    if env == "0":
        return False
    try:
        return sys.stdin.isatty()
    except Exception:
        return False


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
