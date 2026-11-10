#!/usr/bin/env python3
"""Tenra's Apple Ads campaigns, through the Apple Ads Platform API.

    python3 appstore/ads.py campaigns [--campaign C]
                                    campaigns (status, countries, placement, daily budget) and
                                    their ad groups
    python3 appstore/ads.py report [--days 7] [--campaign C]
                                    per campaign and ad group: impressions, taps, TTR, installs
                                    (tap-through and view-through), conversion; spend, average
                                    CPT and CPI
    python3 appstore/ads.py daily [--days 30] [--campaign C]
                                    per day: impressions, taps, installs (and per campaign), the
                                    share of the daily budgets spent
    python3 appstore/ads.py search-terms --campaign C [--adgroup G] [--days 7]
                                    what people searched, most taps first; flags terms with taps
                                    and no installs, lists the candidates for negative and exact
                                    keywords
    python3 appstore/ads.py keywords --campaign C [--adgroup G] [--days 7]
                                    targeting keywords: match type, status, bid, impressions,
                                    taps, installs; flags 100+ taps without an install
    python3 appstore/ads.py negatives --campaign C [--adgroup G] [--add "t1, t2"]
                                    [--match EXACT|BROAD] [--apply]
                                    the negative keywords; --add shows what it would add (to the
                                    campaign, or to G), --apply adds it
    python3 appstore/ads.py add-keywords --campaign C --adgroup G --add "t1, t2"
                                    [--match EXACT|BROAD] [--bid 0.40] [--apply]
                                    keywords for an ad group, the same dry run

C and G are an id, a name or a unique part of a name (KZ-Discovery, discovery). The days end
yesterday, in the ad account's time zone. Nothing is written without --apply; --match is EXACT
unless given.

The API user's credentials come from the environment (docs/asc.md, «Apple Ads API»):
    ADS_CLIENT_ID, ADS_TEAM_ID, ADS_KEY_ID   shown in Apple Ads → Account Settings → API once the
                                             public key is uploaded;
    ADS_PRIVATE_KEY                          the text of private-key.pem (BEGIN/END lines
                                             included; one line, "\\n" escapes or base64 of the
                                             file are accepted too);
    ADS_ACCOUNT_ID                           optional: the ad account (or --account), else the
                                             first one whose campaigns the API user can read.
In GitHub Actions they come from the repository secrets (.github/workflows/ads.yml).

This is the Apple Ads Platform API (api.ads.apple.com/v1), not the Campaign Management API v5,
which Apple sunsets on 26 January 2027; the OAuth credentials are the same for both.
https://developer.apple.com/documentation/apple-ads-platform-api

Tenra's repository is public, so Actions logs are readable by anyone: in Actions no money is
printed (spend, CPT, CPI, bids, budgets), and nothing here ever prints the access token, the
client secret or the key.

Needs PyJWT and cryptography (`pip install pyjwt cryptography`). Offline tests:
`python3 -I appstore/test_ads.py`.
"""

import argparse
import base64
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from decimal import Decimal, InvalidOperation

try:
    import jwt
except ImportError:
    sys.exit("Install the dependencies first: pip install pyjwt cryptography")

API = "https://api.ads.apple.com/v1"
TOKEN_URL = "https://appleid.apple.com/auth/oauth2/token"
CREDENTIALS = ("ADS_CLIENT_ID", "ADS_TEAM_ID", "ADS_KEY_ID", "ADS_PRIVATE_KEY")
DISCOVERY = "KZ-Discovery"     # docs/promotion-plan.md §5 B: every exact keyword elsewhere is a negative here
HIDDEN = "hidden"
QUERY_PAGE = 1000              # QueryPagination.pageSize maximum
REPORT_PAGE = 1000             # RequestPagination allows 5000
BULK = 100
RETRY_DELAYS = (5, 15, 45)

_token = {"value": "", "exp": 0}
_account: dict = {}


# Credentials -------------------------------------------------------------------------------------
# https://developer.apple.com/documentation/apple-ads-platform-api/implementing-oauth-for-the-apple-ads-platform-api

def check_credentials() -> None:
    missing = [name for name in CREDENTIALS if not os.environ.get(name, "").strip()]
    if missing:
        sys.exit(f"No Apple Ads API credentials: {', '.join(missing)} not set. They come from the API user "
                 "in Apple Ads (docs/asc.md, «Apple Ads API»).")


def private_key() -> str:
    """ADS_PRIVATE_KEY as PEM. A key pasted into a one-line field loses its line breaks: rebuilt."""
    raw = os.environ.get("ADS_PRIVATE_KEY", "").strip().replace("\\n", "\n")
    if raw and "BEGIN" not in raw:
        try:
            raw = base64.b64decode(raw, validate=False).decode()
        except (ValueError, UnicodeDecodeError):
            pass
    # `openssl ecparam -genkey` without -noout writes an EC PARAMETERS block first: only the key counts.
    match = re.search(r"-----BEGIN ((?:EC )?PRIVATE KEY)-----(.*?)-----END \1-----", raw, re.S)
    if match:
        label, body = match.group(1), "".join(match.group(2).split())
    else:
        label, body = bare_key(raw)
    if not body:
        sys.exit(key_problem(raw))
    lines = "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN {label}-----\n{lines}\n-----END {label}-----\n"


def bare_key(raw: str) -> tuple[str, str]:
    """The key's base64 without its BEGIN and END lines (copied from the middle of the file): the
    DER of an EC key (SEC1) or of PKCS#8, told apart by their first bytes. ("", "") otherwise."""
    body = "".join(raw.split())
    if not body or not re.fullmatch(r"[A-Za-z0-9+/]+={0,2}", body):
        return "", ""
    try:
        der = base64.b64decode(body, validate=True)
    except ValueError:
        return "", ""
    if der[:1] != b"\x30" or len(der) < 32:
        return "", ""
    if der[2:5] == b"\x02\x01\x01" or der[1:2] == b"\x77":
        return "EC PRIVATE KEY", body
    if der[2:6] == b"\x02\x01\x00\x30" or der[3:7] == b"\x02\x01\x00\x30":
        return "PRIVATE KEY", body
    return "", ""


def key_problem(raw: str) -> str:
    """What is in ADS_PRIVATE_KEY instead of the key, named without quoting any of it (the log is public)."""
    hint = "paste all of private-key.pem, BEGIN and END lines included (docs/asc.md, «Apple Ads API»)"
    if "PUBLIC KEY" in raw:
        return f"ADS_PRIVATE_KEY holds the public key (public-key.pem), which goes to Apple Ads: {hint}."
    if "SEARCHADS." in raw or "clientId" in raw or "keyId" in raw:
        return f"ADS_PRIVATE_KEY holds the clientId/teamId/keyId block from Apple Ads: {hint}."
    labels = sorted(set(re.findall(r"-----BEGIN ([A-Z0-9 ]+)-----", raw)))
    if any("PRIVATE KEY" in label for label in labels) or ("BEGIN" in raw) != ("END" in raw):
        return f"ADS_PRIVATE_KEY is cut short (a BEGIN or END line is missing): {hint}."
    if labels:
        return f"ADS_PRIVATE_KEY has only {', '.join(labels)}, no private key: {hint}."
    return f"ADS_PRIVATE_KEY is not a private key ({len(raw)} characters, no BEGIN line): {hint}."


def client_secret(now: int) -> str:
    """The client secret: a JWT signed ES256 with the private key, kid = keyId, sub = clientId,
    iss = teamId. Apple accepts one for up to 180 days; a run needs an hour."""
    claims = {
        "sub": os.environ["ADS_CLIENT_ID"].strip(),
        "aud": "https://appleid.apple.com",
        "iat": now,
        "exp": now + 3600,
        "iss": os.environ["ADS_TEAM_ID"].strip(),
    }
    key = private_key()
    try:
        return jwt.encode(claims, key, algorithm="ES256", headers={"kid": os.environ["ADS_KEY_ID"].strip()})
    except Exception as error:  # the message is not shown: it could quote the key
        sys.exit(f"ADS_PRIVATE_KEY cannot sign the client secret ({type(error).__name__}): it must be the EC P-256 "
                 "key made by `openssl ecparam -genkey -name prime256v1` (docs/asc.md).")


def token_request(now: int) -> urllib.request.Request:
    """POST appleid.apple.com/auth/oauth2/token, client credentials grant, scope searchadsorg."""
    form = {
        "grant_type": "client_credentials",
        "client_id": os.environ["ADS_CLIENT_ID"].strip(),
        "client_secret": client_secret(now),
        "scope": "searchadsorg",
    }
    return urllib.request.Request(TOKEN_URL, data=urllib.parse.urlencode(form).encode(), method="POST",
                                  headers={"Content-Type": "application/x-www-form-urlencoded", "Accept": "application/json"})


def access_token(force: bool = False) -> str:
    now = int(time.time())
    if force or _token["exp"] - now < 60:
        check_credentials()
        try:
            with urllib.request.urlopen(token_request(now), timeout=60) as response:
                answer = json.loads(response.read())
        except urllib.error.HTTPError as error:
            reason = error.read().decode(errors="replace")
            try:
                reason = json.loads(reason).get("error", reason)
            except (ValueError, AttributeError):
                pass
            sys.exit(f"Apple refused the API credentials (HTTP {error.code}: {str(reason)[:200]}). Check ADS_CLIENT_ID, "
                     "ADS_TEAM_ID and ADS_KEY_ID against Apple Ads → Account Settings → API, and that the public key "
                     "uploaded there is the one of ADS_PRIVATE_KEY.")
        except (TimeoutError, ConnectionError, urllib.error.URLError) as error:
            sys.exit(f"appleid.apple.com did not answer: {error}")
        _token.update(value=answer["access_token"], exp=now + int(answer.get("expires_in", 3600)))
    return _token["value"]


# Requests ----------------------------------------------------------------------------------------
# https://developer.apple.com/documentation/apple-ads-platform-api/calling-apple-ads-platform-api

class ApiError(Exception):
    def __init__(self, code: int, text: str):
        super().__init__(f"HTTP {code}: {text}" if code else text)
        self.code = code


def in_actions() -> bool:
    return bool(os.environ.get("GITHUB_ACTIONS"))


def error_text(error) -> str:
    """The API's Error object ({code, message, details}), or a raw body that holds one. The gateway
    answers an unauthenticated call in the older shape, {"error": {"errors": [{messageCode, …}]}}."""
    if isinstance(error, (str, bytes)):
        try:
            parsed = json.loads(error)
        except ValueError:
            parsed = None
        error = parsed.get("error") if isinstance(parsed, dict) and isinstance(parsed.get("error"), dict) else error
    if isinstance(error, dict):
        parts = [": ".join(str(p) for p in (error.get("code"), error.get("message")) if p)]
        for detail in (error.get("details") or []) + (error.get("errors") or []):
            field = (detail.get("info") or {}).get("field") or detail.get("field")
            parts.append(": ".join(str(p) for p in (detail.get("code") or detail.get("messageCode"), detail.get("message")) if p)
                         + (f" ({field})" if field else ""))
        text = "; ".join(p for p in parts if p)
    else:
        text = error.decode(errors="replace") if isinstance(error, bytes) else str(error)
    if in_actions():
        text = re.sub(r"\d+\.\d+", "#", text)  # a bid or budget quoted back
    return text[:1500]


def build_request(method: str, path: str, body: dict | None, token: str, account_id) -> urllib.request.Request:
    headers = {"Authorization": "Bearer " + token, "Accept": "application/json"}
    if account_id is not None:
        headers["X-AP-Context"] = f"adAccountId={account_id}"
    data = None
    if body is not None:
        data = json.dumps(body).encode()
        headers["Content-Type"] = "application/json"
    return urllib.request.Request(API + path, data=data, method=method, headers=headers)


def wait_seconds(headers, default: int) -> float:
    """A 429 says when to come back (Applying Rate Limits): Retry-After, else RateLimit-Reset."""
    for name in ("Retry-After", "RateLimit-Reset"):
        try:
            return min(max(float(headers.get(name)), 1), 60)
        except (TypeError, ValueError):
            continue
    return default


def call(method: str, path: str, body: dict | None = None, retry: bool = False, scoped: bool = True) -> dict:
    """One API call. `retry` marks a call that only reads (a GET, a /query, a report): a 5xx or a
    dropped connection is retried. A create is not, it may have landed. A 429 always is: a
    throttled request was not processed."""
    attempt, refreshed = 0, False
    while True:
        req = build_request(method, path, body, access_token(), account()["id"] if scoped else None)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                raw = response.read()
            return json.loads(raw) if raw else {}
        except urllib.error.HTTPError as error:
            details = error_text(error.read())
            if error.code == 401 and not refreshed:
                access_token(force=True)
                refreshed = True
                continue
            if attempt < len(RETRY_DELAYS) and (error.code == 429 or (error.code >= 500 and retry)):
                delay = wait_seconds(error.headers, RETRY_DELAYS[attempt]) if error.code == 429 else RETRY_DELAYS[attempt]
                print(f"  {method} {path}: HTTP {error.code}, retrying in {delay:g} s", flush=True)
                time.sleep(delay)
                attempt += 1
                continue
            raise ApiError(error.code, f"{method} {path}: {details}") from None
        except (TimeoutError, ConnectionError, urllib.error.URLError) as error:
            if retry and attempt < len(RETRY_DELAYS):
                print(f"  {method} {path}: {type(error).__name__}, retrying in {RETRY_DELAYS[attempt]} s", flush=True)
                time.sleep(RETRY_DELAYS[attempt])
                attempt += 1
                continue
            raise ApiError(0, f"{method} {path}: {error}") from None


def eq(field: str, value) -> dict:
    return {"field": field, "operator": "EQUALS", "value": value}


def query(path: str, filters: list | None = None) -> list[dict]:
    """Every page of a POST …/query endpoint (QueryRequest, QueryResponse)."""
    items, offset = [], 0
    while True:
        body = {"pagination": {"offset": offset, "pageSize": QUERY_PAGE, "fetchTotalCount": True}}
        if filters:
            body["filters"] = filters
        response = call("POST", path, body, retry=True)
        page = response.get("result") or []
        items += page
        offset += len(page)
        total = (response.get("pagination") or {}).get("totalCount")
        if len(page) < QUERY_PAGE or (total is not None and offset >= total):
            return items


def account() -> dict:
    """The ad account every call is scoped to (X-AP-Context: adAccountId=…). GET /v1/acls lists the
    ad accounts the API user reaches and its roles there; it takes no X-AP-Context."""
    if not _account:
        acls = (call("GET", "/acls", retry=True, scoped=False).get("result") or {}).get("acls") or []
        if not acls:
            sys.exit("The API user reaches no ad account: check its role in Apple Ads → Account Settings → User Management.")
        listing = ", ".join(f"{(a.get('adAccount') or {}).get('name', '')} ({(a.get('adAccount') or {}).get('id')})" for a in acls)
        wanted = os.environ.get("ADS_ACCOUNT_ID", "").strip()
        if wanted:
            found = [a for a in acls if str((a.get("adAccount") or {}).get("id")) == wanted]
            if not found:
                sys.exit(f"ADS_ACCOUNT_ID {wanted} is not among the API user's ad accounts: {listing}.")
            use_account(found[0])
        elif len(acls) == 1:
            use_account(acls[0])
        else:
            # An API user often reaches an Apple Ads Basic account too, whose campaigns the API does
            # not serve (403): the first account that lets it read campaigns is the one meant.
            for acl in acls:
                use_account(acl)
                try:
                    call("POST", "/campaigns/query", {"pagination": {"offset": 0, "pageSize": 1}}, retry=True)
                    break
                except ApiError as error:
                    if error.code != 403:
                        raise
                    _account.clear()
            if not _account:
                sys.exit(f"None of the API user's ad accounts lets it read campaigns ({listing}): give it an API "
                         "role on the account with the campaigns (Account Settings → User Management).")
            print(f"The API user reaches {len(acls)} ad accounts: {listing}. Using {_account['name']} "
                  f"({_account['id']}), the first whose campaigns it can read; ADS_ACCOUNT_ID or --account picks another.")
        say(f"Ad account: {_account['name']} ({_account['id']}), role: {_account['roles']}")
    return _account


def use_account(acl: dict) -> None:
    ad = acl.get("adAccount") or {}
    _account.clear()
    _account.update(id=ad["id"], name=ad.get("name", ""), roles=", ".join(acl.get("roles") or []) or "?")


def account_currency() -> str:
    if "currency" not in _account:
        _account["currency"] = (call("GET", f"/ad-accounts/{account()['id']}", retry=True).get("result") or {}).get("currency", "")
    return _account["currency"]


# Reports -----------------------------------------------------------------------------------------
# https://developer.apple.com/documentation/apple-ads-platform-api/reports

def period(days: int, today: date | None = None) -> tuple[date, date]:
    end = (today or date.today()) - timedelta(days=1)
    return end - timedelta(days=days - 1), end


def report_body(days: int, filters: list | None, offset: int = 0, today: date | None = None) -> dict:
    """AppsReportingRequest. ORTZ (the ad account's time zone) is the only zone the search terms
    report takes. The granularity follows Apple's examples (one day: none; DAILY covers up to 90
    days, WEEKLY needs at least 14); only totalMetrics is read."""
    start, end = period(days, today)
    time_range = {"start": start.isoformat(), "end": end.isoformat(), "timeZone": "ORTZ"}
    if days > 1:
        time_range["granularity"] = "DAILY" if days <= 90 else "WEEKLY"
    body = {"timeRange": time_range, "pagination": {"offset": offset, "pageSize": REPORT_PAGE}}
    if filters:
        body["filters"] = filters
    return body


def report_rows(entity: str, days: int, filters: list | None = None) -> list[dict]:
    """POST /v1/reports/apps/{campaigns|adgroups|keywords|searchterms}/query, every page. All but
    the campaigns report need a campaignId filter."""
    rows, offset = [], 0
    while True:
        response = call("POST", f"/reports/apps/{entity}/query", report_body(days, filters, offset), retry=True)
        page = (response.get("result") or {}).get("rows") or []
        rows += page
        offset += len(page)
        total = (response.get("pagination") or {}).get("totalCount")
        if len(page) < REPORT_PAGE or (total is not None and offset >= total):
            return rows


COUNTS = ("impressions", "taps", "tapInstalls", "viewInstalls", "totalInstalls")


def metrics(row: dict | None) -> dict:
    """A report row's totalMetrics (AppsMetrics): counts, spend (localSpend) as a Decimal."""
    m = (row or {}).get("totalMetrics") or {}
    out = {name: int(m.get(name) or 0) for name in COUNTS}
    if not m.get("totalInstalls"):
        out["totalInstalls"] = out["tapInstalls"] + out["viewInstalls"]
    spend = m.get("localSpend") or {}
    out["spend"] = Decimal(str(spend.get("amount") or 0))
    out["currency"] = spend.get("currency", "")
    return out


def add(a: dict, b: dict) -> dict:
    out = {name: a[name] + b[name] for name in (*COUNTS, "spend")}
    out["currency"] = a["currency"] or b["currency"]
    return out


ZERO = metrics(None)


# Output ------------------------------------------------------------------------------------------

def cash(money: dict | None) -> str:
    """A Money object ({amount, currency}). Never shown in Actions: the log is public."""
    if in_actions():
        return HIDDEN
    if not money or money.get("amount") in (None, ""):
        return "-"
    return f"{Decimal(str(money['amount'])):.2f} {money.get('currency', '')}".strip()


def money_note() -> str:
    return " (money hidden in Actions: the log is public)" if in_actions() else ""


def ratio(part: int, whole: int) -> str:
    return f"{part / whole * 100:.1f}%" if whole else "-"


def per(m: dict, count: str) -> str:
    return cash({"amount": m["spend"] / m[count], "currency": m["currency"]} if m[count] else None)


PERF = ["Impr.", "Taps", "TTR", "Installs (tap)", "Installs (view)", "Conv. (tap)", "Spend", "Avg CPT", "CPI (tap)", "CPI (all)"]


def perf_cells(m: dict) -> list:
    return [m["impressions"], m["taps"], ratio(m["taps"], m["impressions"]), m["tapInstalls"], m["viewInstalls"],
            ratio(m["tapInstalls"], m["taps"]), cash({"amount": m["spend"], "currency": m["currency"]}),
            per(m, "taps"), per(m, "tapInstalls"), per(m, "totalInstalls")]


def say(text: str) -> None:
    print(text + "\n", flush=True)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n\n")


def table(title: str, header: list[str], rows: list[list]) -> None:
    cell = lambda value: str(value).replace("|", "\\|").replace("\n", " ")
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(cell(value) for value in row) + " |" for row in rows]
    say(f"### {title}\n\n" + ("\n".join(lines) if rows else "_none_"))


# Campaigns, ad groups, terms ---------------------------------------------------------------------

def find(items: list[dict], wanted: str, kind: str) -> dict:
    """An id, a name or a unique part of a name, case-insensitively."""
    wanted = wanted.strip()
    for item in items:
        if str(item.get("id")) == wanted:
            return item
    folded = wanted.casefold()
    for matches in ([i for i in items if i.get("name", "").casefold() == folded],
                    [i for i in items if folded in i.get("name", "").casefold()]):
        if len(matches) == 1:
            return matches[0]
        if matches:
            break
    names = ", ".join(f"{i.get('name')} ({i.get('id')})" for i in items) or "none"
    sys.exit(f"No single {kind} matches {wanted!r}; there are: {names}.")


def campaign_groups(campaign: dict) -> list[dict]:
    return query("/adgroups/query", [eq("campaignId", campaign["id"])])


def target(args, need_group: bool = False) -> tuple[dict, dict | None]:
    if not args.campaign:
        sys.exit(f"{args.command} needs --campaign (an id, a name or a unique part of one).")
    if need_group and not args.adgroup:
        sys.exit(f"{args.command} needs --adgroup (an id, a name or a unique part of one).")
    campaign = find(query("/campaigns/query"), args.campaign, "campaign")
    group = find(campaign_groups(campaign), args.adgroup, f"ad group of {campaign['name']}") if args.adgroup else None
    return campaign, group


def split_terms(text: str) -> list[str]:
    terms, seen = [], set()
    for term in re.split(r"[,\n]", text or ""):
        term = " ".join(term.split())
        if term and term.casefold() not in seen:
            seen.add(term.casefold())
            terms.append(term)
    return terms


def bulk_body(items: list[dict]) -> dict:
    """KeywordCreateBulkRequest / NegativeKeywordCreateBulkRequest. allowPartialSuccess: a duplicate
    fails alone instead of rejecting the batch."""
    return {"allowPartialSuccess": True, "items": [{"correlationId": i, "data": data} for i, data in enumerate(items)]}


def bulk_create(path: str, items: list[dict]) -> list[list]:
    """POST /v1/keywords/bulk-create or /v1/negative-keywords/bulk-create (Bulk Operations
    Endpoints). Never retried on a 5xx: the items may have been created."""
    rows = []
    for start in range(0, len(items), BULK):
        chunk = items[start:start + BULK]
        response = call("POST", path, bulk_body(chunk))
        if response.get("error"):
            raise ApiError(0, f"POST {path}: {error_text(response['error'])}")
        for item in response.get("result") or []:
            data = chunk[int(item.get("correlationId") or 0)]
            outcome = "added" if item.get("success") else "failed: " + error_text(item.get("error") or {})
            rows.append([data["text"], data.get("matchType", ""), outcome])
    return rows


def write(title: str, path: str, terms: list[str], have: set, match: str, data_for, apply: bool) -> list[str]:
    """The dry run, and with `apply` the bulk create. `have` holds (casefolded text, match type)."""
    new = [t for t in terms if (t.casefold(), match) not in have]
    table(title, ["Term", "Match", "Action"], [[t, match, "add" if t in new else "already there"] for t in terms])
    if new and not apply:
        say(f"Dry run: nothing written. With --apply {len(new)} would be added.")
    elif new:
        table("Result", ["Term", "Match", "Result"], bulk_create(path, [data_for(t) for t in new]))
    return new


# Commands ----------------------------------------------------------------------------------------

def include(targeting: dict, key: str) -> list[str]:
    return (targeting.get(key) or {}).get("include") or []


def campaigns(args) -> None:
    """POST /v1/campaigns/query and /v1/adgroups/query (all non-deleted ones of the ad account)."""
    account()
    items = query("/campaigns/query")
    if args.campaign:
        items = [find(items, args.campaign, "campaign")]
    rows = []
    for c in sorted(items, key=lambda c: c.get("name", "")):
        targeting, reasons = c.get("targeting") or {}, c.get("systemStatusReasons") or []
        rows.append([c["id"], c.get("name", ""),
                     (c.get("displayStatus") or c.get("status", "")) + (f" ({', '.join(reasons)})" if reasons else ""),
                     ", ".join(include(targeting, "countryOrRegion")),
                     ", ".join(p.removeprefix("APPSTORE_").lower() for p in include(targeting, "supplyPlacement")),
                     (c.get("bidStrategy") or {}).get("bidStrategyType", ""),
                     cash((c.get("dailyBudget") or {}).get("value"))])
    table("Campaigns" + money_note(), ["ID", "Campaign", "Status", "Countries", "Placement", "Bidding", "Daily budget"], rows)
    names = {c["id"]: c.get("name", "") for c in items}
    groups = sorted((g for g in query("/adgroups/query") if g.get("campaignId") in names),
                    key=lambda g: (names[g["campaignId"]], g.get("name", "")))
    table("Ad groups" + money_note(), ["Campaign", "ID", "Ad group", "Status", "Search Match", "Default bid"],
          [[names[g["campaignId"]], g["id"], g.get("name", ""), g.get("displayStatus") or g.get("status", ""),
            "on" if g.get("automatedKeywordsOptIn") else "off", cash((g.get("bidStrategy") or {}).get("bid"))]
           for g in groups])


def report(args) -> None:
    account()
    items = query("/campaigns/query")
    if args.campaign:
        items = [find(items, args.campaign, "campaign")]
    groups = query("/adgroups/query")
    by_campaign = {str((r.get("metadata") or {}).get("id")): metrics(r)
                   for r in report_rows("campaigns", args.days, [eq("campaignId", str(items[0]["id"]))] if args.campaign else None)}
    rows, grand = [], ZERO
    for c in sorted(items, key=lambda c: c.get("name", "")):
        m = by_campaign.get(str(c["id"]), ZERO)
        grand = add(grand, m)
        rows.append([f"**{c.get('name', '')}**", "all", *perf_cells(m)])
        by_group = {str((r.get("metadata") or {}).get("id")): metrics(r)
                    for r in report_rows("adgroups", args.days, [eq("campaignId", str(c["id"]))])}
        for g in sorted((g for g in groups if g.get("campaignId") == c["id"]), key=lambda g: g.get("name", "")):
            rows.append(["", g.get("name", ""), *perf_cells(by_group.get(str(g["id"]), ZERO))])
    if len(items) > 1:
        rows.append(["**Total**", "", *perf_cells(grand)])
    start, end = period(args.days)
    table(f"Apple Ads, {start} to {end} ({args.days} days, ad account time zone){money_note()}",
          ["Campaign", "Ad group", *PERF], rows)
    say("Conv. (tap) = tap-through installs / taps. CPI (tap) = spend / tap-through installs, CPI (all) = spend / all installs.")


def daily(args) -> None:
    """Per day of the campaigns report (granularMetrics, DAILY): impressions, taps, installs, the
    installs of each campaign, and how much of today's daily budgets the day spent (a share, so it
    shows in Actions too). The budgets are today's: a day before a budget change compares with the
    new one."""
    if args.days < 2 or args.days > 90:
        sys.exit("daily takes --days from 2 to 90 (Apple's DAILY granularity).")
    account()
    items = query("/campaigns/query")
    if args.campaign:
        items = [find(items, args.campaign, "campaign")]
    names = {str(c["id"]): c.get("name", "") for c in items}
    budget = sum(Decimal(str(((c.get("dailyBudget") or {}).get("value") or {}).get("amount") or 0)) for c in items)
    per_day: dict[str, dict[str, dict]] = {}
    for r in report_rows("campaigns", args.days, [eq("campaignId", str(items[0]["id"]))] if args.campaign else None):
        cid = str((r.get("metadata") or {}).get("id"))
        if cid not in names:
            continue
        for point in r.get("granularMetrics") or []:
            if point.get("date"):
                per_day.setdefault(point["date"], {})[cid] = metrics({"totalMetrics": point})
    order = sorted(names, key=lambda i: names[i])
    rows = []
    for day in sorted(per_day):
        total = ZERO
        for m in per_day[day].values():
            total = add(total, m)
        rows.append([day, total["impressions"], total["taps"], ratio(total["taps"], total["impressions"]),
                     total["tapInstalls"], ratio(total["tapInstalls"], total["taps"]),
                     *[per_day[day].get(i, ZERO)["tapInstalls"] for i in order],
                     f"{total['spend'] / budget * 100:.0f}%" if budget else "-",
                     cash({"amount": total["spend"], "currency": total["currency"]})])
    start, end = period(args.days)
    table(f"Apple Ads by day, {start} to {end} (ad account time zone){money_note()}",
          ["Date", "Impr.", "Taps", "TTR", "Installs (tap)", "Conv. (tap)",
           *[f"{names[i]} (inst.)" for i in order], "Spent of daily budgets", "Spend"], rows)
    say("Spent of daily budgets: the day's spend over the sum of today's daily budgets of these campaigns; "
        "near 100% means the budget, not the bids, capped the day.")


def search_terms(args) -> None:
    campaign, group = target(args)
    filters = [eq("campaignId", str(campaign["id"]))] + ([eq("adGroupId", str(group["id"]))] if group else [])
    found = []
    for row in report_rows("searchterms", args.days, filters):
        meta, keyword = row.get("metadata") or {}, (row.get("metadata") or {}).get("keyword") or {}
        if keyword.get("text"):
            matched = f"{keyword['text']} ({str(keyword.get('matchType', '')).lower()})"
        else:
            matched = "Search Match" if meta.get("searchTermSource") == "AUTO" else ""
        found.append((meta.get("searchTermText") or "", (meta.get("adGroup") or {}).get("name", ""), matched, metrics(row)))
    found.sort(key=lambda f: (-f[3]["taps"], -f[3]["totalInstalls"], -f[3]["impressions"], f[0]))

    def flag(m: dict) -> str:
        return "taps, no installs" if m["taps"] and not m["totalInstalls"] else ("installs" if m["totalInstalls"] else "")

    start, end = period(args.days)
    scope = campaign.get("name", "") + (f" / {group.get('name', '')}" if group else "")
    table(f"Search terms, {scope}, {start} to {end}{money_note()}",
          ["Search term", "Ad group", "Matched by", "Impr.", "Taps", "Installs (tap)", "Installs (all)", "Spend", "Flag"],
          [[text or "(low volume, withheld by Apple)", group_name, matched, m["impressions"], m["taps"], m["tapInstalls"],
            m["totalInstalls"], cash({"amount": m["spend"], "currency": m["currency"]}), flag(m)]
           for text, group_name, matched, m in found])
    junk = [text for text, _, _, m in found if text and m["taps"] and not m["totalInstalls"]]
    good = [text for text, _, _, m in found if text and m["totalInstalls"]]
    say("Taps and no installs, candidates for negative keywords: " + (", ".join(junk) or "none"))
    # A search for another app (a bank, госуслуги) installs Tenra by mistake: such a term is a
    # negative too, whatever its installs (the first KZ-Discovery report, 2026-11-10).
    say("With installs, candidates for exact keywords if they look for an app like Tenra "
        "(a search for another app, a bank or a government service, is a negative): " + (", ".join(good) or "none"))


def keywords(args) -> None:
    campaign, group = target(args)
    names = {g["id"]: g.get("name", "") for g in ([group] if group else campaign_groups(campaign))}
    items = query("/keywords/query", [eq("adGroupId", group["id"])] if group else [eq("campaignId", campaign["id"])])
    filters = [eq("campaignId", str(campaign["id"]))] + ([eq("adGroupId", str(group["id"]))] if group else [])
    performance = {str((r.get("metadata") or {}).get("id")): metrics(r) for r in report_rows("keywords", args.days, filters)}
    rows = []
    for k in items:
        m = performance.get(str(k.get("id")), ZERO)
        note = "100+ taps, no installs: pause?" if m["taps"] >= 100 and not m["totalInstalls"] else ""
        rows.append([names.get(k.get("adGroupId"), k.get("adGroupId")), k.get("text", ""), k.get("matchType", ""),
                     k.get("status", ""), cash(k.get("bid")), m["impressions"], m["taps"], m["tapInstalls"],
                     m["totalInstalls"], note])
    rows.sort(key=lambda r: (str(r[0]), -r[6], r[1]))
    start, end = period(args.days)
    table(f"Keywords, {campaign.get('name', '')}, {start} to {end}{money_note()}",
          ["Ad group", "Keyword", "Match", "Status", "Bid (- = ad group's)", "Impr.", "Taps", "Installs (tap)",
           "Installs (all)", "Note"], rows)


def negatives(args) -> None:
    """POST /v1/negative-keywords/query: adGroupId IS_NULL with campaignId gives the campaign's own,
    IS_NOT_NULL its ad groups'. A campaign-level negative sets campaignId and no adGroupId, an ad
    group's the reverse (Managing Keywords and Negative Keywords)."""
    campaign, group = target(args)
    own = query("/negative-keywords/query", [eq("campaignId", campaign["id"]), {"field": "adGroupId", "operator": "IS_NULL"}])
    of_groups = query("/negative-keywords/query", [eq("campaignId", campaign["id"]), {"field": "adGroupId", "operator": "IS_NOT_NULL"}])
    names = {g["id"]: g.get("name", "") for g in campaign_groups(campaign)} if of_groups else {}
    rows = [["campaign", n.get("text", ""), n.get("matchType", ""), n.get("status", "")] for n in own]
    rows += [[f"ad group {names.get(n.get('adGroupId'), n.get('adGroupId'))}", n.get("text", ""), n.get("matchType", ""),
              n.get("status", "")] for n in of_groups]
    table(f"Negative keywords, {campaign.get('name', '')}", ["Level", "Negative keyword", "Match", "Status"],
          sorted(rows, key=lambda r: (r[0] != "campaign", r[0], r[1].casefold())))
    if not args.add:
        return
    level = own if not group else [n for n in of_groups if n.get("adGroupId") == group["id"]]
    scope = {"adGroupId": group["id"]} if group else {"campaignId": campaign["id"]}
    write(f"Negative keywords to add to {group.get('name', '') if group else campaign.get('name', '')}",
          "/negative-keywords/bulk-create", split_terms(args.add),
          {(n.get("text", "").casefold(), n.get("matchType")) for n in level}, args.match,
          lambda term: {**scope, "text": term, "matchType": args.match, "status": "ENABLED"}, args.apply)


def add_keywords(args) -> None:
    terms = split_terms(args.add)
    if not terms:
        sys.exit('add-keywords needs --add "term one, term two".')
    try:
        amount = Decimal(args.bid) if args.bid else None
    except InvalidOperation:
        amount = Decimal(0)
    if amount is not None and not (amount.is_finite() and amount > 0):
        sys.exit("--bid is an amount in the ad account's currency, e.g. 0.40.")
    campaign, group = target(args, need_group=True)
    bid = None
    if amount:
        currency = ((group.get("bidStrategy") or {}).get("bid") or {}).get("currency") or account_currency()
        bid = {"amount": f"{amount:.2f}", "currency": currency}
    existing = query("/keywords/query", [eq("adGroupId", group["id"])])
    new = write(f"Keywords to add to {campaign.get('name', '')} / {group.get('name', '')}"
                + (f", bid {cash(bid)}" if bid else ", the ad group's bid"),
                "/keywords/bulk-create", terms, {(k.get("text", "").casefold(), k.get("matchType")) for k in existing},
                args.match, lambda term: {"adGroupId": group["id"], "text": term, "matchType": args.match,
                                          "status": "ENABLED", **({"bid": bid} if bid else {})}, args.apply)
    if new and args.match == "EXACT" and DISCOVERY.casefold() not in campaign.get("name", "").casefold():
        say(f"Plan §5 B: a new exact keyword is a negative in {DISCOVERY} too: "
            f'negatives --campaign {DISCOVERY} --add "{", ".join(new)}" --apply')


def days_arg(text: str) -> int:
    try:
        value = int(text)
    except ValueError:
        value = 0
    if value < 1:
        raise argparse.ArgumentTypeError("a whole number of days, 1 or more")
    return value


def main(argv: list[str]) -> None:
    common = argparse.ArgumentParser(add_help=False)
    common.add_argument("--campaign", help="campaign: id, name or a unique part of the name")
    common.add_argument("--adgroup", help="ad group of that campaign: id, name or a unique part")
    common.add_argument("--days", type=days_arg, default=7, help="days of data, up to yesterday (default 7)")
    common.add_argument("--account", help="ad account id (else ADS_ACCOUNT_ID, else the first whose campaigns the API user can read)")
    writes = argparse.ArgumentParser(add_help=False)
    writes.add_argument("--add", help='comma-separated terms, e.g. "учет расходов, бюджет"')
    writes.add_argument("--match", choices=("EXACT", "BROAD"), default="EXACT", type=str.upper)
    writes.add_argument("--apply", action="store_true", help="write; without it only shows what would change")
    parser = argparse.ArgumentParser(prog="python3 appstore/ads.py", description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    commands = parser.add_subparsers(dest="command", metavar="command", required=True)
    handlers = {
        "campaigns": (campaigns, "campaigns and ad groups"),
        "report": (report, "per campaign and ad group performance"),
        "daily": (daily, "per day: impressions, taps, installs by campaign, share of the daily budgets spent"),
        "search-terms": (search_terms, "a campaign's search terms"),
        "keywords": (keywords, "a campaign's keywords"),
        "negatives": (negatives, "a campaign's negative keywords; --add, --apply"),
        "add-keywords": (add_keywords, "keywords for an ad group; --add, --apply"),
    }
    for name, (_, help_text) in handlers.items():
        sub = commands.add_parser(name, parents=[common] + ([writes] if name in ("negatives", "add-keywords") else []),
                                  help=help_text)
        if name == "add-keywords":
            sub.add_argument("--bid", help="keyword bid in the ad account's currency (default: the ad group's)")
    args = parser.parse_args(argv)
    if args.account:
        os.environ["ADS_ACCOUNT_ID"] = args.account.strip()
    handlers[args.command][0](args)


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except ApiError as error:
        hint = " (the API user's role may not allow this: writes need API Account Manager)" if error.code in (401, 403) else ""
        sys.exit(f"Apple Ads API: {error}{hint}")
