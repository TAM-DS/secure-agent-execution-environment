#!/usr/bin/env python3
"""Policy gate: check an action against policy/rules.yaml.

Usage:
    python3 enforce.py <action> <path>

Example:
    python3 enforce.py file_write /workspace/output.py

Exits 0 if the action is ALLOWED, 1 if DENIED, 2 on usage/config errors.
"""

import posixpath
import sys
from pathlib import Path

import yaml

RULES_PATH = Path(__file__).parent / "rules.yaml"


def load_rules(path: Path) -> dict:
    with open(path, "r") as f:
        rules = yaml.safe_load(f) or {}
    rules.setdefault("default", "deny")
    rules.setdefault("allow", [])
    rules.setdefault("deny", [])
    return rules


def matches_prefix(path: str, prefix: str) -> bool:
    """True if normalized `path` falls under `prefix` (a directory-style prefix)."""
    norm_path = posixpath.normpath(path)
    if prefix == "/":
        return norm_path.startswith("/")
    norm_prefix = prefix.rstrip("/")
    return norm_path == norm_prefix or norm_path.startswith(norm_prefix + "/")


def find_matching_rule(rules_list: list, action: str, path: str):
    """Return the most specific rule (longest path_prefix) matching action+path, or None."""
    candidates = [
        rule
        for rule in rules_list
        if rule.get("action") == action and matches_prefix(path, rule.get("path_prefix", "/"))
    ]
    if not candidates:
        return None
    return max(candidates, key=lambda r: len(r.get("path_prefix", "")))


def is_excepted(rule: dict, path: str) -> bool:
    for exception_prefix in rule.get("exceptions", []):
        if matches_prefix(path, exception_prefix):
            return True
    return False


def evaluate(rules: dict, action: str, path: str):
    """Return (decision, description) where decision is 'ALLOWED' or 'DENIED'."""
    deny_rule = find_matching_rule(rules["deny"], action, path)
    if deny_rule is not None and not is_excepted(deny_rule, path):
        return "DENIED", f"deny: {deny_rule}"

    allow_rule = find_matching_rule(rules["allow"], action, path)
    if allow_rule is not None:
        return "ALLOWED", f"allow: {allow_rule}"

    default = rules["default"]
    decision = "ALLOWED" if default == "allow" else "DENIED"
    return decision, f"default: {default}"


def main() -> int:
    if len(sys.argv) != 3:
        print(f"Usage: {sys.argv[0]} <action> <path>", file=sys.stderr)
        return 2

    action, path = sys.argv[1], sys.argv[2]

    try:
        rules = load_rules(RULES_PATH)
    except (OSError, yaml.YAMLError) as e:
        print(f"Failed to load {RULES_PATH}: {e}", file=sys.stderr)
        return 2

    decision, matching_rule = evaluate(rules, action, path)
    print(decision)
    print(f"Matching rule: {matching_rule}")

    return 0 if decision == "ALLOWED" else 1


if __name__ == "__main__":
    sys.exit(main())
