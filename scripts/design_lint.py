#!/usr/bin/env python3
"""Design lint: no raw design values in Tenra's Swift code.

Colours, fonts, spacing, corner radii and animations come from DesignKit tokens
(AppColors, AppTypography, AppSpacing, AppRadius, AppAnimation) and its components.
This script finds literal design values in Tenra/ and compares the count per file and
rule with scripts/design-lint-baseline.json:

- more than the baseline: a new raw value, CI fails;
- fewer: the code got cleaner; lower the baseline with --update-baseline;
- a file not in the baseline must have none.

Usage:
    python3 scripts/design_lint.py                    # check (CI)
    python3 scripts/design_lint.py --report           # every hit, grouped by rule
    python3 scripts/design_lint.py --update-baseline  # write the current counts

A justified exception carries `// design-lint:ignore <reason>` on the same line.
Data-driven colours (a category's stored hex, a user's choice) are not design values:
only literals are flagged.
"""

import collections
import json
import os
import re
import sys

ROOT = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..")
SOURCE = os.path.join(ROOT, "Tenra")
BASELINE = os.path.join(ROOT, "scripts", "design-lint-baseline.json")

# Paths (relative to Tenra/) that are not product UI.
EXCLUDED_DIRS = ("Debug/", "Views/Experiments/")
EXCLUDED_SUFFIXES = ("Previews.swift",)

IGNORE_MARK = "design-lint:ignore"

RULES = {
    # Literal colours: Color(red: 0.2, …), Color(hex: "#…"), UIColor(white: 0.9, …), #colorLiteral.
    # Use AppColors / CategoryColors. A colour built from data (Color(hex: category.colorHex)) passes.
    "raw-color": re.compile(
        r'\b(?:Color|UIColor)\(\s*(?:red|green|blue|white|hue)\s*:\s*[\d.]'
        r'|\b(?:Color|UIColor)\(\s*hex\s*:\s*"'
        r'|#colorLiteral'
    ),
    # System palette colours (.red, Color.blue, …) in styling modifiers. Use AppColors
    # (accent, destructive, success, warning, income, expense, …).
    "system-color": re.compile(
        r'(?:foregroundStyle|foregroundColor|tint|background|fill|stroke|strokeBorder)'
        r'\(\s*(?:Color)?\.(?:red|blue|green|orange|yellow|purple|pink|gray|grey|mint|teal|cyan|indigo|brown)\b'
    ),
    # System text styles and literal font sizes. Use AppTypography (Inter, Dynamic Type).
    # `.font(.system(size: AppIconSize.md))` sizes an SF Symbol with a token and passes.
    "system-font": re.compile(
        r'\.font\(\s*(?:Font)?\.(?:system\(\s*size:\s*[\d.]|largeTitle\b|title\b|title2\b|title3\b'
        r'|headline\b|subheadline\b|body\b|callout\b|footnote\b|caption\b|caption2\b)'
        r'|\bFont\.custom\('
    ),
    # Literal padding. Use AppSpacing.
    "raw-padding": re.compile(r'\.padding\(\s*(?:\.[a-zA-Z]+\s*,\s*|\[[^\]]*\]\s*,\s*)?[1-9]\d*(?:\.\d+)?\s*\)'),
    # Literal stack spacing (0 is allowed). Use AppSpacing.
    "raw-spacing": re.compile(r'\bspacing:\s*[1-9]\d*(?:\.\d+)?\b'),
    # Literal corner radius. Use AppRadius.
    "raw-radius": re.compile(r'\bcornerRadius:\s*[1-9]\d*(?:\.\d+)?\b|\.cornerRadius\(\s*[1-9]'),
    # Hand-tuned curves. Use AppAnimation.
    "raw-animation": re.compile(
        r'\.(?:easeIn|easeOut|easeInOut|linear)\(\s*duration:\s*[\d.]'
        r'|\.spring\(\s*(?:response|duration|bounce)\s*:'
        r'|\.interpolatingSpring\('
    ),
}


def swift_files():
    for dirpath, _, files in os.walk(SOURCE):
        for name in sorted(files):
            if not name.endswith(".swift"):
                continue
            path = os.path.join(dirpath, name)
            rel = os.path.relpath(path, SOURCE).replace(os.sep, "/")
            if rel.startswith(EXCLUDED_DIRS) or rel.endswith(EXCLUDED_SUFFIXES):
                continue
            yield rel, path


def scan():
    """{file: {rule: [(line, text), …]}}"""
    hits = collections.defaultdict(lambda: collections.defaultdict(list))
    for rel, path in swift_files():
        with open(path, encoding="utf-8", errors="replace") as source:
            in_preview = False
            for number, line in enumerate(source, 1):
                stripped = line.strip()
                # #Preview blocks are not product UI; they end at the next top-level "}".
                if stripped.startswith("#Preview"):
                    in_preview = True
                if in_preview:
                    if line.startswith("}"):
                        in_preview = False
                    continue
                if stripped.startswith("//") or IGNORE_MARK in line:
                    continue
                for rule, pattern in RULES.items():
                    for _ in pattern.finditer(line):
                        hits[rel][rule].append((number, stripped))
    return hits


def counts(hits):
    return {rel: {rule: len(lines) for rule, lines in sorted(rules.items())}
            for rel, rules in sorted(hits.items())}


def main(argv):
    hits = scan()
    current = counts(hits)

    if "--update-baseline" in argv:
        with open(BASELINE, "w", encoding="utf-8") as out:
            json.dump(current, out, indent=2, sort_keys=True)
            out.write("\n")
        total = sum(sum(rules.values()) for rules in current.values())
        print(f"Baseline written: {total} raw values in {len(current)} files.")
        return 0

    if "--report" in argv:
        by_rule = collections.defaultdict(list)
        for rel, rules in sorted(hits.items()):
            for rule, lines in rules.items():
                by_rule[rule].extend(f"Tenra/{rel}:{n}: {text}" for n, text in lines)
        for rule in RULES:
            print(f"\n{rule} ({len(by_rule[rule])})")
            for entry in by_rule[rule]:
                print(f"  {entry}")
        return 0

    try:
        with open(BASELINE, encoding="utf-8") as source:
            baseline = json.load(source)
    except FileNotFoundError:
        baseline = {}

    failures = 0
    improved = []
    for rel, rules in current.items():
        for rule, count in rules.items():
            allowed = baseline.get(rel, {}).get(rule, 0)
            if count > allowed:
                failures += count - allowed
                for number, text in hits[rel][rule]:
                    print(f"::error file=Tenra/{rel},line={number},title=design-lint {rule}::"
                          f"{count} raw value(s), baseline allows {allowed}: {text}")
            elif count < allowed:
                improved.append(f"Tenra/{rel} {rule}: {allowed} → {count}")
    for rel, rules in baseline.items():
        for rule, allowed in rules.items():
            if rel not in current or rule not in current[rel]:
                improved.append(f"Tenra/{rel} {rule}: {allowed} → 0")

    total = sum(sum(rules.values()) for rules in current.values())
    print(f"design-lint: {total} raw design values in {len(current)} files (baseline "
          f"{sum(sum(r.values()) for r in baseline.values())}).")
    if improved:
        print("Fewer than the baseline (run --update-baseline to lock it in):")
        for entry in improved:
            print(f"  {entry}")
    if failures:
        print(f"\n{failures} new raw design value(s). Use DesignKit tokens (AppColors, AppTypography, "
              "AppSpacing, AppRadius, AppAnimation) or mark a justified exception with "
              "`// design-lint:ignore <reason>`.")
        return 1
    return 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
