#!/usr/bin/env python3
"""What Ten is asked and how it goes, as counts (src/stats.ts, docs/domains/assistant.md §8).

Reads the Workers Analytics Engine dataset `tenra_assistant_turns` through Cloudflare's SQL API
and prints Markdown tables: topics by outcome, the topics Ten could not serve, the tools turns
call, languages, plans, model calls per turn and what happened to the drafts. Every value in the
dataset is a label, a tool name, a code or a number, so the output may go to a public log.

    CLOUDFLARE_API_TOKEN=... CLOUDFLARE_ACCOUNT_ID=... python3 scripts/turn_stats.py --days 7

The token needs Account Analytics: Read.
"""

import argparse
import json
import os
import sys
import urllib.error
import urllib.request

DATASET = "tenra_assistant_turns"


def query(sql: str) -> list[dict]:
    account = os.environ.get("CLOUDFLARE_ACCOUNT_ID", "").strip()
    token = os.environ.get("CLOUDFLARE_API_TOKEN", "").strip()
    if not account or not token:
        sys.exit("CLOUDFLARE_ACCOUNT_ID and CLOUDFLARE_API_TOKEN are needed.")
    request = urllib.request.Request(
        f"https://api.cloudflare.com/client/v4/accounts/{account}/analytics_engine/sql",
        data=(sql + " FORMAT JSON").encode(),
        headers={"Authorization": f"Bearer {token}"},
        method="POST",
    )
    try:
        with urllib.request.urlopen(request, timeout=60) as response:
            return json.load(response).get("data", [])
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")[:300]
        hint = " The token needs Account Analytics: Read." if error.code in (401, 403) else ""
        sys.exit(f"SQL API answered {error.code}: {body}{hint}")


def table(title: str, rows: list[dict], columns: list[str]) -> None:
    print(f"\n### {title}\n")
    if not rows:
        print("Nothing counted.")
        return
    print("| " + " | ".join(columns) + " |")
    print("|" + "---|" * len(columns))
    for row in rows:
        print("| " + " | ".join(str(row.get(c, "")) for c in columns) + " |")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--days", type=int, default=7)
    days = max(1, min(parser.parse_args().days, 90))
    since = f"timestamp > NOW() - INTERVAL '{days}' DAY"
    turns = f"FROM {DATASET} WHERE blob1 = 'turn' AND {since}"
    count = "SUM(_sample_interval)"

    total = query(f"SELECT {count} AS turns, SUM(_sample_interval * double2) / SUM(_sample_interval) AS calls {turns}")
    print(f"## Ten's turns, the last {days} days\n")
    if total and total[0].get("turns"):
        print(f"Turns: {int(total[0]['turns'])}; model calls per turn: {float(total[0]['calls']):.1f}.")
    else:
        print("No turns counted (ASSISTANT_TURN_STATS off, or nobody asked).")
        return

    table("Topics", query(f"SELECT blob2 AS topic, {count} AS turns {turns} GROUP BY topic ORDER BY turns DESC"), ["topic", "turns"])
    table(
        "Topics by outcome",
        query(f"SELECT blob2 AS topic, blob3 AS outcome, {count} AS turns {turns} GROUP BY topic, outcome ORDER BY turns DESC LIMIT 60"),
        ["topic", "outcome", "turns"],
    )
    table(
        "What Ten could not do (unsupported, partial, declined)",
        query(
            f"SELECT blob2 AS topic, blob3 AS outcome, blob5 AS tools, {count} AS turns {turns} "
            "AND blob3 IN ('unsupported', 'partial', 'declined') GROUP BY topic, outcome, tools ORDER BY turns DESC LIMIT 40"
        ),
        ["topic", "outcome", "tools", "turns"],
    )
    table("Tool sets", query(f"SELECT blob5 AS tools, {count} AS turns {turns} GROUP BY tools ORDER BY turns DESC LIMIT 40"), ["tools", "turns"])
    table("Languages", query(f"SELECT blob4 AS language, {count} AS turns {turns} GROUP BY language ORDER BY turns DESC"), ["language", "turns"])
    table("Plans", query(f"SELECT blob7 AS plan, {count} AS turns {turns} GROUP BY plan ORDER BY turns DESC"), ["plan", "turns"])
    table("Countries", query(f"SELECT blob8 AS country, {count} AS turns {turns} GROUP BY country ORDER BY turns DESC LIMIT 20"), ["country", "turns"])
    table("Builds", query(f"SELECT blob9 AS build, {count} AS turns {turns} GROUP BY build ORDER BY turns DESC LIMIT 10"), ["build", "turns"])
    table("Moods", query(f"SELECT blob6 AS mood, {count} AS turns {turns} GROUP BY mood ORDER BY turns DESC"), ["mood", "turns"])
    table(
        "Drafts reported with the next question",
        query(
            f"SELECT blob2 AS tool, blob3 AS status, {count} AS drafts FROM {DATASET} "
            f"WHERE blob1 = 'draft' AND {since} GROUP BY tool, status ORDER BY drafts DESC LIMIT 60"
        ),
        ["tool", "status", "drafts"],
    )


if __name__ == "__main__":
    main()
