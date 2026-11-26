#!/usr/bin/env python3
"""The Tenra account on Threads: posts and replies from social/threads.json, published by Actions.

    python3 scripts/threads.py check                 # the file: lengths, rules, ids
    python3 scripts/threads.py me                    # whose token it is (username, id)
    python3 scripts/threads.py post-next [--dry-run] # the next approved post not yet published
    python3 scripts/threads.py replies [--dry-run]   # every approved reply not yet published
    python3 scripts/threads.py refresh               # a new 60-day token; stored as the secret
    python3 scripts/threads.py stats [--days 30]     # views, likes, replies and the account's clicks

Everything is written in Tenra's voice (docs/threads.md) and published only once the founder
approved it (`"approved": true`). `post-next` publishes the first approved post that is not in
social/threads-posted.json and whose `notBefore` date (Almaty) has come: one post a day.
`replies` publishes the approved answers to other people's questions (`replyToId`, the Threads id
of the post answered), at most REPLIES_PER_RUN a run: a question is answered within the day. Both
record what went out in social/threads-posted.json; the workflow commits that file.

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
# A post's video lives in the public site (GitHub Pages serves it as video/mp4; raw.githubusercontent
# does not): docs/public/media/threads/<id>.mp4 at SITE/media/threads/<id>.mp4, deployed on push.
SITE = "https://dkicekeeper.github.io/Tenra"
VIDEO_DIR = "docs/public/media/threads/"
VIDEO_MAX_BYTES = 20 * 1024 * 1024
REPLIES_PER_RUN = 3     # Meta treats a burst of replies with links as spam
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


def load_replies(path: Path = POSTS) -> list[dict]:
    return json.loads(path.read_text(encoding="utf-8")).get("replies", [])


def load_posted(path: Path = POSTED) -> dict:
    return json.loads(path.read_text(encoding="utf-8")) if path.exists() else {}


def problems(posts: list[dict], replies: list[dict] | None = None) -> list[str]:
    """Threads takes 500 characters; Tenra writes without emoji and without em dashes. Ids are
    unique across posts and replies (both are recorded in one file); a reply names its post."""
    found, seen = [], set()
    for reply in replies or []:
        if not str(reply.get("replyToId", "")).strip():
            found.append(f"{reply.get('id', '?')}: a reply without replyToId (the post it answers)")
    for post in [*posts, *(replies or [])]:
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
        found += media_problems(post)
    return found


def media_problems(post: dict, root: Path = ROOT) -> list[str]:
    """An image or a video must be a file of this repository; a video an .mp4 in VIDEO_DIR (the
    site serves it to Meta), at most VIDEO_MAX_BYTES; never both on one post."""
    pid, found = post.get("id", "?"), []
    if post.get("image") and post.get("video"):
        found.append(f"{pid}: an image and a video, Threads takes one")
    for key in ("image", "video"):
        path = post.get(key)
        if path and not (root / path).is_file():
            found.append(f"{pid}: {key} {path} is not in the repository")
    video = post.get("video")
    if video:
        if not video.startswith(VIDEO_DIR) or not video.endswith(".mp4"):
            found.append(f"{pid}: a video is an .mp4 in {VIDEO_DIR}")
        elif (root / video).is_file() and (root / video).stat().st_size > VIDEO_MAX_BYTES:
            found.append(f"{pid}: the video is over {VIDEO_MAX_BYTES // (1024 * 1024)} MB")
    return found


def media_url(post: dict) -> tuple[str | None, str | None]:
    """(kind, public URL) of a post's image or video, or (None, None)."""
    if post.get("video"):
        return "VIDEO", f"{SITE}/{post['video'][len('docs/public/'):]}"
    if post.get("image"):
        # A public file of this public repository: Threads downloads the image from the URL.
        return "IMAGE", f"https://raw.githubusercontent.com/{REPO}/main/{post['image']}"
    return None, None


def next_post(posts: list[dict], posted: dict, today: str) -> dict | None:
    """The first approved post, in the file's order, not published yet and due by `today`."""
    for post in posts:
        if post.get("approved") and post["id"] not in posted and (post.get("notBefore") or "") <= today:
            return post
    return None


def check() -> None:
    posts, replies, posted = load_posts(), load_replies(), load_posted()
    for kind, items in (("posts", posts), ("replies", replies)):
        out = [i for i in items if i["id"] in posted]
        waiting = [i for i in items if i.get("approved") and i["id"] not in posted]
        drafts = [i for i in items if not i.get("approved")]
        print(f"{len(items)} {kind}: {len(out)} published, {len(waiting)} approved and waiting, {len(drafts)} drafts.")
    found = problems(posts, replies)
    if found:
        sys.exit("social/threads.json:\n  " + "\n  ".join(found))


# Threads API ------------------------------------------------------------------------------------

def me() -> None:
    profile = call("GET", f"{API}/me", {"fields": "id,username,name", "access_token": token()})
    print(f"Threads account: @{profile.get('username')} ({profile.get('name')}), id {profile.get('id')}")


def publish(text: str, media: tuple[str | None, str | None] = (None, None), reply_to: str | None = None) -> str:
    kind, url = media
    params = {"media_type": kind or "TEXT", "text": text, "access_token": token()}
    if kind == "IMAGE":
        params["image_url"] = url
    elif kind == "VIDEO":
        params["video_url"] = url
    if reply_to:
        params["reply_to_id"] = reply_to
    container = call("POST", f"{API}/me/threads", params)["id"]
    wait_until_ready(container, video=kind == "VIDEO")
    return call("POST", f"{API}/me/threads_publish", {"creation_id": container, "access_token": token()})["id"]


def wait_until_ready(container: str, video: bool) -> None:
    """Meta processes a container before it can be published: a few seconds for text, up to a few
    minutes for a video. Polls its status (10 s apart, about 6 minutes at most for a video)."""
    time.sleep(5)
    for _ in range(36 if video else 6):
        status = call("GET", f"{API}/{container}", {"fields": "status,error_message", "access_token": token()})
        state = status.get("status")
        if state in (None, "FINISHED", "PUBLISHED"):
            return
        if state in ("ERROR", "EXPIRED"):
            raise ThreadsError(f"the container is {state}: {status.get('error_message', '')}")
        time.sleep(10)
    raise ThreadsError("the container was not ready in time; the post waits for the next run")


def record(posted: dict, item_id: str, media_id: str) -> None:
    posted[item_id] = {"media": media_id, "at": datetime.now(timezone.utc).isoformat(timespec="seconds")}
    POSTED.write_text(json.dumps(posted, ensure_ascii=False, indent=2) + "\n", encoding="utf-8")


def post_next(dry_run: bool) -> None:
    posts = load_posts()
    found = problems(posts, load_replies())
    if found:
        sys.exit("social/threads.json:\n  " + "\n  ".join(found))
    posted = load_posted()
    today = datetime.now(ALMATY).date().isoformat()
    post = next_post(posts, posted, today)
    if not post:
        print("Nothing to post: no approved post is waiting.")
        return
    media = media_url(post)
    if dry_run:
        print(f"Dry run: would post {post['id']} ({len(post['text'])} characters"
              + (f", {media[0].lower()} {media[1]}" if media[0] else "") + ").")
        return
    media_id = publish(post["text"], media)
    record(posted, post["id"], media_id)
    print(f"Posted {post['id']} (media {media_id}).")


def waiting_replies(replies: list[dict], posted: dict) -> list[dict]:
    """The approved replies not published yet, in the file's order, REPLIES_PER_RUN at most."""
    return [r for r in replies if r.get("approved") and r["id"] not in posted][:REPLIES_PER_RUN]


def publish_replies(dry_run: bool) -> None:
    replies = load_replies()
    found = problems(load_posts(), replies)
    if found:
        sys.exit("social/threads.json:\n  " + "\n  ".join(found))
    posted = load_posted()
    batch = waiting_replies(replies, posted)
    if not batch:
        print("No approved reply is waiting.")
        return
    for reply in batch:
        if dry_run:
            print(f"Dry run: would reply {reply['id']} to {reply.get('replyTo') or reply['replyToId']} "
                  f"({len(reply['text'])} characters).")
            continue
        media_id = publish(reply["text"], reply_to=str(reply["replyToId"]))
        record(posted, reply["id"], media_id)
        print(f"Replied {reply['id']} (media {media_id}).")


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
        elif command == "replies":
            publish_replies("--dry-run" in args)
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
