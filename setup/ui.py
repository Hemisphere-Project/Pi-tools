"""Terminal UI helpers for Pi-tools installer."""

import sys

# ANSI colors
RESET = '\033[0m'
BOLD = '\033[1m'
RED = '\033[31m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
BLUE = '\033[34m'
CYAN = '\033[36m'
DIM = '\033[2m'


def banner():
    print(f"""
{BOLD}{CYAN}╔══════════════════════════════════════╗
║           Pi-tools Setup             ║
╚══════════════════════════════════════╝{RESET}
""")


def header(text):
    print(f"\n{BOLD}{BLUE}── {text} ──{RESET}")


def info(text):
    print(f"  {text}")


def success(text):
    print(f"  {GREEN}✓{RESET} {text}")


def warn(text):
    print(f"  {YELLOW}⚠{RESET} {text}")


def error(text):
    print(f"  {RED}✗{RESET} {text}")


def skip(text):
    print(f"  {DIM}· {text}{RESET}")


def ask_yn(prompt, default=True):
    """Ask yes/no question. Returns bool."""
    suffix = " [Y/n] " if default else " [y/N] "
    try:
        answer = input(f"  {YELLOW}?{RESET} {prompt}{suffix}").strip().lower()
    except (EOFError, KeyboardInterrupt):
        print()
        return default
    if not answer:
        return default
    return answer.startswith('y')


def ask_text(prompt, default=''):
    """Ask for text input."""
    suffix = f" [{default}]" if default else ""
    try:
        answer = input(f"  {YELLOW}?{RESET} {prompt}{suffix}: ").strip()
    except (EOFError, KeyboardInterrupt):
        print()
        return default
    return answer or default
