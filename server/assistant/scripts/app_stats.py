#!/usr/bin/env python3
"""How far new people get in the app and whether they come back (src/events.ts, docs/plan-sales.md §4).

Reads the Workers Analytics Engine dataset `tenra_app_events` through Cloudflare's SQL API and
prints Markdown tables: the funnel by install week, where people are lost on their first day,
who comes back on days 1, 2, 3, 7, 14 and 30 (and in the second week) by how far they got on
day 0, by the evening reminder and auto-capture, how soon the first entry comes, the paywall by
step, gate and plan, trials, features and opens. The app sends milestones once per install and
no identifier, so each milestone's count in a week is the number of installs that reached it.
Every value is a label from a fixed list, so the output may go to a public log.

    CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... python3 scripts/app_stats.py --days 28

The token needs Account Analytics: Read.
"""

import argparse
import os
import sys

sys.path.insert(0, os.path.dirname(__file__))

from turn_stats import query, table  # noqa: E402

DATASET = "tenra_app_events"

# The funnel, in order: (name, value); value None sums every value of the name. The first day's
# steps come from the app's `path` milestones, which count a skipped step as passed, so a step is
# never above the one before it.
FUNNEL = [
    ("installed", ""),
    ("path", "welcome"),
    ("path", "currency"),
    ("path", "account"),
    ("path", "categories"),
    ("path", "capture"),
    ("path", "onboarding_done"),
    ("path", "entry"),
    ("path", "reminder"),
    ("entries", "5"),
    ("entries", "10"),
    ("paywall_first", None),
    ("trial_started", ""),
    ("converted", ""),
]

# The first day's path, as the app's `furthest0` names it, with the milestone that marks it: the
# app sends `path:<step>` for every step passed on day 0, skipped ones included, so these counts
# only fall along the path and base(X) = passed X minus passed the next step.
PATH = [
    ("none", ("installed", "")),
    ("welcome", ("path", "welcome")),
    ("currency", ("path", "currency")),
    ("account", ("path", "account")),
    ("categories", ("path", "categories")),
    ("capture", ("path", "capture")),
    ("onboarding_done", ("path", "onboarding_done")),
    ("entry", ("path", "entry")),
    ("reminder", ("path", "reminder")),
]

RETURNS = ["1", "2", "3", "7", "14", "30", "week2"]


def _int(value) -> int:
    return int(float(value or 0))


def _pct(part: float, whole: float) -> str:
    return f"{round(100 * part / whole)}%" if whole else ""


def _counts(rows: list[dict]) -> dict:
    """{cohort: {(name, value): count}} from counted rows."""
    counts: dict = {}
    for row in rows:
        counts.setdefault(row["cohort"], {})
        key = (row["name"], row["value"])
        counts[row["cohort"]][key] = counts[row["cohort"]].get(key, 0) + _int(row["count"])
    return counts


def _reached(cohort_counts: dict, name: str, value) -> int:
    if value is None:
        return sum(count for (n, _), count in cohort_counts.items() if n == name)
    return cohort_counts.get((name, value), 0)


def _label(name: str, value) -> str:
    if name == "path":
        return value
    return name if not value else f"{name}:{value}"


def funnel(rows: list[dict]) -> list[dict]:
    """Each cohort's steps with their counts, against the step before and the installs."""
    out = []
    for cohort, counts in sorted(_counts(rows).items()):
        installs = counts.get(("installed", ""), 0)
        if not installs:
            continue
        previous = None
        for name, value in FUNNEL:
            reached = _reached(counts, name, value)
            if not reached:
                continue
            out.append({
                "cohort": cohort,
                "step": _label(name, value),
                "count": reached,
                "of_previous": _pct(reached, previous) if previous else "",
                "of_installs": _pct(reached, installs),
            })
            previous = reached
    return out


def _day0_reach(counts: dict) -> list[tuple[str, int]]:
    return [(step, _reached(counts, *milestone)) for step, milestone in PATH]


def drop_off(day0: list[dict]) -> list[dict]:
    """Per cohort, how many reached each step of the first day but not the next, biggest first."""
    out = []
    for cohort, counts in sorted(_counts(day0).items()):
        installs = counts.get(("installed", ""), 0)
        if not installs:
            continue
        reach = _day0_reach(counts)
        steps = []
        for index, (step, reached) in enumerate(reach[:-1]):
            lost = max(0, reached - reach[index + 1][1])
            label = "installed" if step == "none" else step
            steps.append({"cohort": cohort, "step": label, "reached": reached, "lost": lost, "of_installs": _pct(lost, installs)})
        out.extend(sorted(steps, key=lambda row: -row["lost"]))
    return out


def retention(returned: list[dict], day0: list[dict]) -> list[dict]:
    """Per cohort, the share back on each return day, for all installs and by the furthest day-0 step."""
    back: dict = {}
    for row in returned:
        key = (row["cohort"], row["furthest0"], row["value"])
        back[key] = back.get(key, 0) + _int(row["count"])
    out = []
    for cohort, counts in sorted(_counts(day0).items()):
        installs = counts.get(("installed", ""), 0)
        if not installs:
            continue
        reach = _day0_reach(counts)
        bases = [("all", installs)]
        for index, (step, reached) in enumerate(reach):
            following = reach[index + 1][1] if index + 1 < len(reach) else 0
            bases.append((step, max(0, reached - following)))
        for furthest, base in bases:
            if not base:
                continue
            row = {"cohort": cohort, "furthest0": furthest, "installs": base}
            for day in RETURNS:
                came = sum(c for (co, f, v), c in back.items() if co == cohort and v == day and (furthest == "all" or f == furthest))
                row["week2" if day == "week2" else f"d{day}"] = _pct(came, base)
            out.append(row)
    return out


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=28)
    days = max(1, min(parser.parse_args().days, 90))
    since = f"timestamp > NOW() - INTERVAL '{days}' DAY"
    count = "SUM(_sample_interval)"
    milestones = f"FROM {DATASET} WHERE blob1 = 'm' AND {since}"
    counters = f"FROM {DATASET} WHERE blob1 = 'c' AND {since}"

    print(f"## The app's counts, the last {days} days\n")
    rows = query(f"SELECT blob4 AS cohort, blob2 AS name, blob3 AS value, {count} AS count {milestones} GROUP BY cohort, name, value")
    if not rows:
        print("Nothing counted (APP_EVENTS off, or no app with the counts yet).")
        return
    day0 = query(f"SELECT blob4 AS cohort, blob2 AS name, blob3 AS value, {count} AS count {milestones} AND double2 = 0 GROUP BY cohort, name, value")
    returned = query(
        f"SELECT blob4 AS cohort, blob3 AS value, blob10 AS furthest0, {count} AS count {milestones} "
        "AND blob2 = 'returned' GROUP BY cohort, value, furthest0"
    )
    cols = ["cohort", "furthest0", "installs"] + [("week2" if d == "week2" else f"d{d}") for d in RETURNS]

    table("Funnel by install week", funnel(rows), ["cohort", "step", "count", "of_previous", "of_installs"])
    table("Where they leave on the first day (biggest loss first)", drop_off(day0), ["cohort", "step", "reached", "lost", "of_installs"])
    table("Back on day N, by the furthest step of day 0", retention(returned, day0), cols)
    table(
        "Back on day N, by the evening reminder and auto-capture",
        query(
            f"SELECT blob3 AS day, blob7 AS reminder, blob8 AS capture, {count} AS installs {milestones} "
            "AND blob2 = 'returned' GROUP BY day, reminder, capture ORDER BY day, reminder, capture"
        ),
        ["day", "reminder", "capture", "installs"],
    )
    table(
        "First entry by day since install",
        query(f"SELECT double2 AS day, {count} AS installs {milestones} AND blob2 = 'entries' AND blob3 = '1' GROUP BY day ORDER BY day"),
        ["day", "installs"],
    )
    table(
        "Paywall: step, gate and plan",
        query(f"SELECT blob3 AS step_gate_plan, {count} AS times {counters} AND blob2 = 'paywall' GROUP BY step_gate_plan ORDER BY times DESC LIMIT 60"),
        ["step_gate_plan", "times"],
    )
    table(
        "Trials by install week",
        query(
            f"SELECT blob4 AS cohort, blob2 AS milestone, {count} AS installs {milestones} "
            "AND blob2 IN ('trial_started', 'renewal_off', 'converted') GROUP BY cohort, milestone ORDER BY cohort, milestone"
        ),
        ["cohort", "milestone", "installs"],
    )
    table(
        "Features used (days with a use) by plan",
        query(f"SELECT blob3 AS feature, blob5 AS plan, {count} AS days {counters} AND blob2 = 'feature' GROUP BY feature, plan ORDER BY days DESC"),
        ["feature", "plan", "days"],
    )
    table(
        "Opens, entries, Ten and moments",
        query(
            f"SELECT blob2 AS counter, blob3 AS value, {count} AS times {counters} "
            "AND blob2 IN ('open', 'entry', 'ten', 'moment') GROUP BY counter, value ORDER BY counter, times DESC"
        ),
        ["counter", "value", "times"],
    )


if __name__ == "__main__":
    main()
