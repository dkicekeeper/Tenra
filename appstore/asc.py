#!/usr/bin/env python3
"""Tenra in App Store Connect, through the App Store Connect API.

    python3 appstore/asc.py status                  versions, latest builds, in-app products
    python3 appstore/asc.py builds [--limit 15]     builds with processing and TestFlight state
    python3 appstore/asc.py wait-build --build N [--version 1.5] [--wait 40]
                                                    wait until build N of that version is processed
    python3 appstore/asc.py reviews [--limit 20]    latest customer reviews
    python3 appstore/asc.py availability            storefronts, EU trader (DSA) status
    python3 appstore/asc.py crashes [--build N]     TestFlight crash reports (no tester details)
    python3 appstore/asc.py sales [--days 7]        units and proceeds per day (private, see below)

The key comes from the environment:
    ASC_KEY_ID, ASC_ISSUER_ID   the API key's Key ID and Issuer ID;
    ASC_KEY_PATH                the AuthKey_<KeyID>.p8 file, or
    ASC_KEY_P8                  its text (BEGIN/END lines included; one line, "\\n" escapes or
                                base64 of the file are accepted too).
In GitHub Actions they come from the repository secrets (.github/workflows/asc.yml and
testflight.yml); in a Claude cloud session from the environment's variables (docs/asc.md).

Tenra's repository is public, so Actions logs are readable by anyone: `sales` refuses to run in
Actions and nothing here prints contact details, tester names or the key.

Needs PyJWT and cryptography (`pip install pyjwt cryptography`).
"""

import base64
import gzip
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, timedelta
from pathlib import Path

try:
    import jwt
except ImportError:
    sys.exit("Install the dependencies first: pip install pyjwt cryptography")

BUNDLE_ID = "dakacom.Tenra"
VENDOR_NUMBER = os.environ.get("ASC_VENDOR_NUMBER", "94171379")
API = "https://api.appstoreconnect.apple.com"
EU = {"AUT", "BEL", "BGR", "HRV", "CYP", "CZE", "DNK", "EST", "FIN", "FRA", "DEU", "GRC", "HUN",
      "IRL", "ITA", "LVA", "LTU", "LUX", "MLT", "NLD", "POL", "PRT", "ROU", "SVK", "SVN", "ESP", "SWE"}

_token = {"value": "", "exp": 0}


# Key and requests ---------------------------------------------------------------------------------

def private_key() -> str:
    path = os.environ.get("ASC_KEY_PATH")
    if path:
        return Path(path).read_text()
    raw = os.environ.get("ASC_KEY_P8", "").strip().replace("\\n", "\n")
    if not raw:
        sys.exit("No API key: set ASC_KEY_ID, ASC_ISSUER_ID and ASC_KEY_P8 or ASC_KEY_PATH (docs/asc.md).")
    if "BEGIN" not in raw:
        try:
            decoded = base64.b64decode(raw, validate=False).decode()
            if "BEGIN" in decoded:
                return decoded
        except (ValueError, UnicodeDecodeError):
            pass
        body = raw
    else:
        match = re.search(r"-----BEGIN PRIVATE KEY-----(.*?)-----END PRIVATE KEY-----", raw, re.S)
        if not match:
            return raw
        body = match.group(1)
    # A key pasted into a one-line field loses its line breaks: rebuild the PEM.
    body = "".join(body.split())
    lines = "\n".join(body[i:i + 64] for i in range(0, len(body), 64))
    return f"-----BEGIN PRIVATE KEY-----\n{lines}\n-----END PRIVATE KEY-----\n"


def token() -> str:
    now = int(time.time())
    if _token["exp"] - now < 60:
        for name in ("ASC_KEY_ID", "ASC_ISSUER_ID"):
            if not os.environ.get(name):
                sys.exit(f"No {name} in the environment (docs/asc.md).")
        _token["value"] = jwt.encode(
            {"iss": os.environ["ASC_ISSUER_ID"], "iat": now, "exp": now + 1200, "aud": "appstoreconnect-v1"},
            private_key(),
            algorithm="ES256",
            headers={"kid": os.environ["ASC_KEY_ID"], "typ": "JWT"},
        )
        _token["exp"] = now + 1200
    return _token["value"]


class ApiError(Exception):
    def __init__(self, code: int, text: str):
        super().__init__(f"HTTP {code}: {text}")
        self.code = code


def request(path: str, accept: str = "application/json") -> bytes:
    url = path if path.startswith("http") else API + path
    req = urllib.request.Request(url, headers={"Authorization": "Bearer " + token(), "Accept": accept})
    try:
        with urllib.request.urlopen(req, timeout=60) as response:
            return response.read()
    except urllib.error.HTTPError as error:
        details = error.read().decode(errors="replace")
        try:
            errors = json.loads(details).get("errors", [])
            details = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors) or details
        except ValueError:
            pass
        raise ApiError(error.code, details[:600]) from None


def get(path: str, params: dict | None = None) -> dict:
    if params:
        path += ("&" if "?" in path else "?") + urllib.parse.urlencode(params)
    raw = request(path)
    return json.loads(raw) if raw else {}


def get_all(path: str, params: dict | None = None, pages: int = 10) -> tuple[list, list]:
    """Every page of a list endpoint: (data, included)."""
    data, included = [], []
    response = get(path, params)
    for _ in range(pages):
        data += response.get("data", [])
        included += response.get("included", [])
        next_url = response.get("links", {}).get("next")
        if not next_url:
            break
        response = json.loads(request(next_url))
    return data, included


def app_id() -> str:
    apps = get("/v1/apps", {"filter[bundleId]": BUNDLE_ID})["data"]
    if not apps:
        sys.exit(f"{BUNDLE_ID} is not in App Store Connect, or the key has no access to it.")
    return apps[0]["id"]


# Output -------------------------------------------------------------------------------------------

def table(title: str, header: list[str], rows: list[list]) -> None:
    lines = ["| " + " | ".join(header) + " |", "|" + "---|" * len(header)]
    lines += ["| " + " | ".join(str(cell) for cell in row) + " |" for row in rows]
    text = f"### {title}\n\n" + ("\n".join(lines) if rows else "_none_") + "\n"
    print(text)
    summary = os.environ.get("GITHUB_STEP_SUMMARY")
    if summary:
        with open(summary, "a", encoding="utf-8") as f:
            f.write(text + "\n")


# Commands -----------------------------------------------------------------------------------------

def builds(app: str, limit: int = 15) -> list[dict]:
    response = get("/v1/builds", {
        "filter[app]": app, "sort": "-uploadedDate", "limit": limit,
        "include": "preReleaseVersion,buildBetaDetail",
    })
    included = {(item["type"], item["id"]): item["attributes"] for item in response.get("included", [])}
    result = []
    for build in response["data"]:
        rel, attrs = build["relationships"], build["attributes"]
        version = (rel.get("preReleaseVersion") or {}).get("data")
        beta = (rel.get("buildBetaDetail") or {}).get("data")
        beta_attrs = included.get(("buildBetaDetails", beta["id"]), {}) if beta else {}
        result.append({
            "id": build["id"],
            "number": attrs["version"],
            "version": included.get(("preReleaseVersions", version["id"]), {}).get("version", "?") if version else "?",
            "processing": "EXPIRED" if attrs.get("expired") else attrs.get("processingState", "?"),
            "uploaded": (attrs.get("uploadedDate") or "")[:16].replace("T", " "),
            "internal": beta_attrs.get("internalBuildState", "?"),
            "external": beta_attrs.get("externalBuildState", "?"),
        })
    return result


def show_builds(app: str, limit: int) -> None:
    table("Builds", ["Build", "Version", "Uploaded (UTC)", "Processing", "TestFlight internal", "External"],
          [[b["number"], b["version"], b["uploaded"], b["processing"], b["internal"], b["external"]]
           for b in builds(app, limit)])


def status(app: str) -> None:
    versions, _ = get_all(f"/v1/apps/{app}/appStoreVersions", {"limit": 10})
    versions.sort(key=lambda v: v["attributes"].get("createdDate") or "", reverse=True)
    table("App Store versions", ["Version", "Platform", "State", "Release", "Created"],
          [[v["attributes"].get("versionString"), v["attributes"].get("platform"),
            v["attributes"].get("appVersionState") or v["attributes"].get("appStoreState"),
            v["attributes"].get("releaseType", ""), (v["attributes"].get("createdDate") or "")[:10]]
           for v in versions[:5]])
    show_builds(app, 8)

    products = []
    try:
        iaps, _ = get_all(f"/v1/apps/{app}/inAppPurchasesV2", {"limit": 50})
        products += [[p["attributes"].get("productId"), p["attributes"].get("inAppPurchaseType"),
                      p["attributes"].get("state")] for p in iaps]
    except ApiError as error:
        print(f"In-app purchases: {error}")
    try:
        groups, included = get_all(f"/v1/apps/{app}/subscriptionGroups", {"limit": 20, "include": "subscriptions"})
        products += [[s["attributes"].get("productId"), "AUTO_RENEWABLE", s["attributes"].get("state")]
                     for s in included if s["type"] == "subscriptions"]
    except ApiError as error:
        print(f"Subscriptions: {error}")
    table("In-app products", ["Product", "Type", "State"], products)


def wait_build(app: str, number: str, version: str | None, minutes: int) -> None:
    # Build numbers restart with each version (1.4 (1), 1.5 (1)), so a number alone can match an
    # old build that is long processed.
    deadline = time.time() + minutes * 60
    while True:
        build = next((b for b in builds(app, 20)
                      if b["number"] == number and (version is None or b["version"] == version)), None)
        if build and build["processing"] != "PROCESSING":
            break
        if time.time() > deadline:
            break
        print(f"Build {number}: {build['processing'] if build else 'not visible yet'}, waiting…", flush=True)
        time.sleep(60)
    show_builds(app, 6)
    if not build:
        sys.exit(f"Build {number} did not show up in App Store Connect within {minutes} min.")
    if build["processing"] == "PROCESSING":
        print(f"Build {number} is still processing; App Store Connect will email when it is done.")
    elif build["processing"] != "VALID":
        sys.exit(f"Build {number}: {build['processing']} (App Store Connect emails the reason).")


def reviews(app: str, limit: int) -> None:
    data = get(f"/v1/apps/{app}/customerReviews", {"sort": "-createdDate", "limit": limit})["data"]
    rows = []
    for review in data:
        a = review["attributes"]
        text = " ".join(f"{a.get('title') or ''}. {a.get('body') or ''}".split()).replace("|", "/")
        rows.append([(a.get("createdDate") or "")[:10], a.get("territory"), "★" * int(a.get("rating") or 0), text[:300]])
    table("Customer reviews (with text; star-only ratings are not in the API)", ["Date", "Store", "Rating", "Review"], rows)


def availability(app: str) -> None:
    holder = get(f"/v1/apps/{app}/appAvailabilityV2")["data"]
    items, included = get_all(f"/v2/appAvailabilities/{holder['id']}/territoryAvailabilities",
                              {"limit": 200, "include": "territory"})
    territory = {}
    for item in items:
        rel = (item.get("relationships", {}).get("territory", {}) or {}).get("data") or {}
        territory[item["id"]] = rel.get("id", "?")
    available = [territory[i["id"]] for i in items if i["attributes"].get("available")]
    statuses: dict[str, list[str]] = {}
    for item in items:
        for content_status in item["attributes"].get("contentStatuses") or []:
            statuses.setdefault(content_status, []).append(territory[item["id"]])
    print(f"Available in {len(available)} of {len(items)} storefronts.")
    eu_available = sorted(t for t in available if t in EU)
    print(f"EU: available in {len(eu_available)} of {len(EU)}" + (f" ({', '.join(eu_available)})" if eu_available else ""))
    table("Storefront statuses", ["Status", "Storefronts", "Examples"],
          [[s, len(t), ", ".join(sorted(t)[:12])] for s, t in sorted(statuses.items(), key=lambda kv: -len(kv[1]))])


# Lines of a crash report header that can point at a device or a person: never printed.
PRIVATE_HEADER = ("Incident Identifier", "CrashReporter Key", "Beta Identifier", "Anonymized UUID",
                  "Sleep/Wake UUID", "Report Version", "Coalition")


def crash_excerpt(text: str, limit: int = 90) -> str:
    """Exception type and reason, and the crashed thread's (or last exception's) backtrace."""
    lines = text.splitlines()
    keep = [line for line in lines[:60]
            if line.startswith(("Hardware Model", "OS Version", "Version:", "Exception Type", "Exception Codes",
                                "Exception Note", "Termination Reason", "Triggered by Thread", "Crashed Thread"))
            and not line.startswith(PRIVATE_HEADER)]
    start = next((i for i, line in enumerate(lines)
                  if line.startswith("Last Exception Backtrace") or (line.startswith("Thread") and " Crashed:" in line)), None)
    if start is not None:
        keep += [""] + lines[start:start + limit]
    if not keep:
        keep = [line for line in lines[:limit] if not line.strip().startswith(tuple(f'"{h}' for h in PRIVATE_HEADER))]
    return "\n".join(keep)


def crashes(app: str, number: str | None) -> None:
    result = get(f"/v1/apps/{app}/betaFeedbackCrashSubmissions", {
        "limit": "10", "sort": "-createdDate", "include": "build",
        "fields[betaFeedbackCrashSubmissions]": "createdDate,deviceModel,osVersion,build,crashLog",
        "fields[builds]": "version",
    })
    versions = {b["id"]: b["attributes"].get("version") for b in result.get("included", []) if b["type"] == "builds"}
    shown = 0
    for item in result.get("data", []):
        build_id = (item.get("relationships", {}).get("build", {}).get("data") or {}).get("id")
        version = versions.get(build_id, "?")
        if number and version != number:
            continue
        a = item.get("attributes", {})
        print(f"### Crash: build {version}, {a.get('createdDate', '')}, {a.get('deviceModel', '')}, iOS {a.get('osVersion', '')}")
        try:
            log = get(f"/v1/betaFeedbackCrashSubmissions/{item['id']}/crashLog")
            text = log.get("data", {}).get("attributes", {}).get("logText", "")
        except ApiError as error:
            text = f"(report unavailable: {error})"
        print(crash_excerpt(text) + "\n")
        shown += 1
    if not shown:
        print("No crash reports" + (f" for build {number}" if number else "")
              + ": they appear when a tester sends crash feedback from TestFlight.")


def product_kind(code: str) -> str:
    if code.startswith("IA") or code.startswith("FI"):
        return "in-app"
    if code.startswith("7"):
        return "update"
    if code.startswith("3"):
        return "re-download"
    return "download"


def sales(days: int) -> None:
    if os.environ.get("GITHUB_ACTIONS") == "true" and not os.environ.get("ASC_ALLOW_PUBLIC_SALES"):
        sys.exit("Not in Actions: Tenra's Actions logs are public. Run `sales` from a Claude cloud session (docs/asc.md).")
    rows, totals = [], {}
    for offset in range(1, days + 1):
        day = (date.today() - timedelta(days=offset)).isoformat()
        try:
            raw = request("/v1/salesReports?" + urllib.parse.urlencode({
                "filter[frequency]": "DAILY", "filter[reportType]": "SALES", "filter[reportSubType]": "SUMMARY",
                "filter[vendorNumber]": VENDOR_NUMBER, "filter[reportDate]": day, "filter[version]": "1_1",
            }), accept="application/a-gzip")
        except ApiError as error:
            if error.code == 404:
                rows.append([day, "", "", "", "", "no sales or report not ready"])
                continue
            raise
        lines = gzip.decompress(raw).decode("utf-8").splitlines()
        header = lines[0].split("\t")
        col = {name: header.index(name) for name in header}
        for line in lines[1:]:
            f = line.split("\t")
            if len(f) < len(header):
                continue
            units = int(float(f[col["Units"]] or 0))
            proceeds = float(f[col["Developer Proceeds"]] or 0) * units
            currency = f[col["Currency of Proceeds"]]
            kind = product_kind(f[col["Product Type Identifier"]])
            rows.append([day, kind, f[col["SKU"]] or f[col["Title"]], f[col["Country Code"]], units,
                         f"{proceeds:.2f} {currency}" if proceeds else ""])
            if proceeds:
                totals[currency] = totals.get(currency, 0) + proceeds
    table(f"Sales, last {days} days (Apple's daily reports, US Pacific days)",
          ["Day", "Kind", "Product", "Country", "Units", "Proceeds"], rows)
    if totals:
        print("Proceeds: " + ", ".join(f"{amount:.2f} {currency}" for currency, amount in totals.items()))


def main(argv: list[str]) -> None:
    if not argv or argv[0] in ("-h", "--help"):
        print(__doc__)
        return
    command, args = argv[0], argv[1:]

    def option(name: str, default=None):
        return args[args.index(name) + 1] if name in args and args.index(name) + 1 < len(args) else default

    if command == "sales":
        sales(int(option("--days", 7)))
        return
    app = app_id()
    if command == "status":
        status(app)
    elif command == "builds":
        show_builds(app, int(option("--limit", 15)))
    elif command == "wait-build":
        number = option("--build")
        if not number:
            sys.exit("wait-build needs --build N")
        wait_build(app, number, option("--version"), int(option("--wait", 40)))
    elif command == "reviews":
        reviews(app, int(option("--limit", 20)))
    elif command == "availability":
        availability(app)
    elif command == "crashes":
        crashes(app, option("--build"))
    else:
        sys.exit(f"Unknown command {command!r}; see `python3 appstore/asc.py --help`.")


if __name__ == "__main__":
    try:
        main(sys.argv[1:])
    except ApiError as error:
        hint = " (the key's role may not allow this)" if error.code in (401, 403) else ""
        sys.exit(f"App Store Connect API: {error}{hint}")
