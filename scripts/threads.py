#!/usr/bin/env python3
"""Ten's account on Threads: posts from social/threads.json, published one a day by Actions.

    python3 scripts/threads.py check                 # the posts file: lengths, rules, ids
    python3 scripts/threads.py me                    # whose token it is (username, id)
    python3 scripts/threads.py post-next [--dry-run] # the next approved post not yet published
    python3 scripts/threads.py refresh               # a new 60-day token; stored as the secret
    python3 scripts/threads.py stats [--days 30]     # views, likes, replies and the account's clicks

Posts are written in Ten's voice (docs/threads.md) and published only once the founder approved
them (`"approved": true`). `post-next` publishes the first approved post that is not in
social/threads-posted.json and whose `notBefore` date (Almaty) has come, then records it there;
the workflow commits that file. One post per run: the workflow runs once a day.

The token is THREADS_ACCESS_TOKEN (a long-lived Threads user token: 60 days, refreshed while it is
at least a day old). `refresh` writes the token Meta returns back into the repository secret when
GH_SECRETS_TOKEN (a fine-grained token with this repository's Secrets: read and write) is set;
without it the refresh only works if Meta returns the same token. Tokens are never printed.
"""
import base64
import json
import os
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import datetime, timedelta, timezone
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
POSTS = ROOT / "social" / "threads.json"
POSTED = ROOT / "social" / "threads-posted.json"
API = "https://graph.threads.net/v1.0"
REFRESH = "https://graph.threads.net/refresh_access_token"
REPO = "dkicekeeper/Tenra"
SECRET = "THREADS_ACCESS_TOKEN"
TEXT_MAX = 500
ALMATY = timezone(timedelta(hours=5))
EMOJI = range(0x1F300, 0x1FAFF + 1)


class ThreadsError(Exception):
    pass


def token() -> str:
    value = os.environ.get(SECRET, "").strip()
    if not value:
        sys.exit(f"No {SECRET}: set up the Threads token (docs/threads.md).")
    return value


def call(method: str, url: str, params: dict) -> dict:
    """A Graph API call. The token travels in the query and is never echoed back in an error."""
    query = urllib.parse.urlencode(params)
    req = urllib.request.Request(f"{url}?{query}" if method == "GET" else url, method=method,
                                 data=None if method == "GET" else query.encode())
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return json.loads(response.read() or b"{}")
    except urllib.error.HTTPError as error:
        body = error.read().decode(errors="replace")
        try:
            message = json.loads(body).get("error", {}).get("message", body)
        except ValueError:
            message = body
        raise ThreadsError(f"HTTP {error.code}: {message[:300]}") from None


# Posts -------------------------------------------------------------------------------------------

def load_posts(path: Path = POSTS) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8"))["posts"]


def load_posted(path: Path = POSTED) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def problems(posts: list[dict]) -> list[str]:
    """Threads takes 500 characters; Ten writes without emoji and without em dashes."""
    found, seen = [], set()
    for post in posts:
        pid = post.get("id", "?")
        if pid in seen:
            found.append(f"{pid}: the id is used twice")
        seen.add(pid)
        text = post.get("text", "")
        if not text.strip():
            found.append(f"{pid}: no text")
        if len(text) > TEXT_MAX:
            found.append(f"{pid}: {len(text)} characters, Threads takes {TEXT_MAX}")
        if "—" in text:
            found.append(f"{pid}: an em dash")
        if any(ord(ch) in EMOJI for ch in text):
            found.append(f"{pid}: an emoji (Ten writes without them)")
        if post.get("notBefore"):
            try:
                datetime.fromisoformat(post["notBefore"])
            except ValueError:
                found.append(f"{pid}: notBefore is not a date (YYYY-MM-DD)")
    return found


def next_post(posts: list[dict], posted: dict, today: str) -> dict | None:
    """The first approved post, in the file's order, not published yet and due by `today`."""
    for post in posts:
        if post.get("approved") and post["id"] not in posted and (post.get("notBefore") or "") <= today:
            return post
    return None


def check() -> None:
    posts = load_posts()
    found = problems(posts)
    posted = load_posted()
    waiting = [p for p in posts if p.get("approved") and p["id"] not in posted]
    drafts = [p for p in posts if not p.get("approved")]
    print(f"{len(posts)} posts: {len(posted)} published, {len(waiting)} approved and waiting, {len(drafts)} drafts.")
    if found:
        sys.exit("social/threads.json:\n  " + "\n  ".join(found))


# Threads API ------------------------------------------------------------------------------------

def me() -> None:
    profile = call("GET", f"{API}/me", {"fields": "id,username,name", "access_token": token()})
    print(f"Threads account: @{profile.get('username')} ({profile.get('name')}), id {profile.get('id')}")


def publish(text: str, image_url: str | None) -> str:
    params = {"media_type": "IMAGE" if image_url else "TEXT", "text": text, "access_token": token()}
    if image_url:
        params["image_url"] = image_url
    container = call("POST", f"{API}/me/threads", params)["id"]
    # Meta asks to give the container time to process before publishing (an image takes longer).
    time.sleep(30 if image_url else 5)
    return call("POST", f"{API}/me/threads_publish", {"creation_id": container, "access_token": token()})["id"]


def post_next(dry_run: bool) -> None:
    posts = load_posts()
    found = problems(posts)
    if found:
        sys.exit("social/threads.json:\n  " + "\n  ".join(found))
    posted = load_posted()
    today = datetime.now(ALMATY).date().isoformat()
    post = next_post(posts, posted, today)
    if not post:
        print("Nothing to post: no approved post is waiting.")
        return
    image_url = None
    if post.get("image"):
        # A public file of this public repository: Threads downloads the image from the URL.
        image_url = f"https://raw.githubusercontent.com/{REPO}/main/{post['image']}"
    if dry_run:
        print(f"Dry run: would post {post['id']} ({len(post['text'])} characters"
              + (f", image {post['image']}" if image_url else "") + ").")
        return
    media_id = publish(post["text"], image_url)
    posted[post["id"]] = {"media": media_id, "at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    POSTED.write_text(json.dumps(posted, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")
    print(f"Posted {post['id']} (media {media_id}).")


def store_secret(value: str) -> None:
    """Write the token into the repository secret: sealed with the repository's public key."""
    from nacl import encoding, public  # PyNaCl, installed by the workflow
    gh = os.environ["GH_SECRETS_TOKEN"]
    headers = {"Authorization": f"Bearer {gh}", "Accept": "application/vnd.github+json",
               "X-GitHub-Api-Version": "2022-11-28"}
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/actions/secrets/public-key", headers=headers)
    with urllib.request.urlopen(req, timeout=30) as response:
        key = json.loads(response.read())
    box = public.SealedBox(public.PublicKey(key["key"].encode(), encoding.Base64Encoder()))
    sealed = base64.b64encode(box.encrypt(value.encode())).decode()
    body = json.dumps({"encrypted_value": sealed, "key_id": key["key_id"]}).encode()
    req = urllib.request.Request(f"https://api.github.com/repos/{REPO}/actions/secrets/{SECRET}", data=body,
                                 method="PUT", headers={**headers, "Content-Type": "application/json"})
    with urllib.request.urlopen(req, timeout=30):
        pass


def refresh() -> None:
    old = token()
    answer = call("GET", REFRESH, {"grant_type": "th_refresh_token", "access_token": old})
    new, days = answer.get("access_token", ""), round(int(answer.get("expires_in", 0)) / 86400)
    if not new:
        sys.exit("Meta returned no token.")
    if new == old:
        print(f"Token refreshed in place: valid for {days} more days.")
    elif os.environ.get("GH_SECRETS_TOKEN"):
        store_secret(new)
        print(f"New token stored as {SECRET}: valid for {days} days.")
    else:
        sys.exit(f"Meta returned a new token (valid {days} days) and GH_SECRETS_TOKEN is not set, so it could not be "
                 f"stored: the old token runs out on its own date. Add GH_SECRETS_TOKEN (docs/threads.md).")


def stats(days: int) -> None:
    until = datetime.now(timezone.utc)
    since = until - timedelta(days=days)
    media = call("GET", f"{API}/me/threads", {"fields": "id,text,timestamp,permalink", "limit": 50,
                                              "since": int(since.timestamp()), "access_token": token()})
    rows = []
    for item in media.get("data", []):
        values = {}
        try:
            insights = call("GET", f"{API}/{item['id']}/insights",
                            {"metric": "views,likes,replies,reposts,quotes,shares", "access_token": token()})
            for metric in insights.get("data", []):
                values[metric["name"]] = (metric.get("values") or [{}])[0].get("value", 0)
        except ThreadsError as error:
            values["error"] = str(error)
        rows.append((item.get("timestamp", "")[:10], (item.get("text") or "")[:40].replace("\n", " "), values))
    print(f"### Ten on Threads, last {days} days\n")
    print("| Day | Post | Views | Likes | Replies | Reposts | Quotes | Shares |\n|---|---|---|---|---|---|---|---|")
    for day, text, v in rows:
        print(f"| {day} | {text} | " + " | ".join(str(v.get(k, "-")) for k in
                                                ("views", "likes", "replies", "reposts", "quotes", "shares")) + " |")
    account = call("GET", f"{API}/me/threads_insights", {
        "metric": "views,clicks,followers_count", "since": int(since.timestamp()),
        "until": int(until.timestamp()), "access_token": token()})
    totals = {}
    for metric in account.get("data", []):
        if "total_value" in metric:
            totals[metric["name"]] = metric["total_value"].get("value")
        else:
            totals[metric["name"]] = sum(v.get("value", 0) for v in metric.get("values", []))
    print(f"\nAccount: views {totals.get('views', '-')}, link clicks {totals.get('clicks', '-')}, "
          f"followers {totals.get('followers_count', '-')}")


def main(argv: list[str]) -> None:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return
    command, args = argv[0], argv[1:]
    try:
        if command == "check":
            check()
        elif command == "me":
            me()
        elif command == "post-next":
            post_next("--dry-run" in args)
        elif command == "refresh":
            refresh()
        elif command == "stats":
            stats(int(args[args.index("--days") + 1]) if "--days" in args else 30)
        else:
            sys.exit(f"Unknown command {command!r}; see `python3 scripts/threads.py --help`.")
    except ThreadsError as error:
        sys.exit(f"Threads API: {error}")


if __name__ == "__main__":
    main(sys.argv[1:])
