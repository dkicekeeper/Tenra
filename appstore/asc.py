#!/usr/bin/env python3
"""Tenra in App Store Connect, through the App Store Connect API.

    python3 appstore/asc.py status                  versions, latest builds, in-app products
    python3 appstore/asc.py builds [--limit 15]     builds with processing and TestFlight state
    python3 appstore/asc.py wait-build --build N [--version 1.5] [--wait 40]
                                                    wait until build N of that version is processed
    python3 appstore/asc.py prepare-version --version 1.5 [--build N] [--wait 30]
                                                    create the version, What's New from
                                                    docs/release-notes.md, select build N (no submit)
    python3 appstore/asc.py keywords [--locale ru,en-US]
                                                    the app's keywords (custom pages link to them)
    python3 appstore/asc.py metadata [--version 1.7]
                                                    per locale: name, subtitle, promotional text,
                                                    description and keyword lengths, and the primary
                                                    language (what a storefront without its own
                                                    language falls back to); keywords themselves only
                                                    outside Actions
    python3 appstore/asc.py push-metadata [--apply] the texts in appstore/metadata.json: name and
                                                    subtitle (a version in preparation), promotional
                                                    text, keywords, description; creates a missing
                                                    locale from its `copyFrom`. Without --apply it
                                                    only shows what would change
    python3 appstore/asc.py custom-pages            custom product pages and their review state
    python3 appstore/asc.py review-submissions      the latest review submissions, their items and
                                                    states; the creative images by state
    python3 appstore/asc.py push-custom-pages [--submit]
                                                    create/update the pages in product-pages.json
    python3 appstore/asc.py push-experiment [--submit | --start | --stop]
                                                    the product page test in product-pages.json
                                                    (--stop ends a running test: a new app version
                                                    does not end it)
    python3 appstore/asc.py age-rating [--apply]    the age rating answers; --apply sets Tenra's
                                                    (needs a version in preparation)
    python3 appstore/asc.py push-version-screenshots --version 1.6 [--locale ru,en-US]
                                                    the version's own 6.9" screenshots, the frames
                                                    of `defaultOrder` in screenshot_captions.json
                                                    (en-GB takes kk's: `screenshotsFrom` in
                                                    metadata.json)
    python3 appstore/asc.py store-pages [--version 1.6]
                                                    what each storefront page shows: the version's
                                                    screenshots per locale against screenshots/final,
                                                    the page tests, the custom pages' languages
    python3 appstore/asc.py push-creatives [--version 1.6] [--locale ru,en-US] [--pages] [--submit]
                                                    the iOS 27 header and search art from
                                                    screenshots/art/<locale>/ on the version (the
                                                    live one by default) and, with --pages, on the
                                                    custom pages; --submit sends them for review
    python3 appstore/asc.py subscription-prices [--territory KAZ]
                                                    each subscription's price there, scheduled
                                                    changes included
    python3 appstore/asc.py push-price --product tenra.pro.annual --price 7990 [--territory KAZ]
                                   [--start YYYY-MM-DD] [--apply]
                                                    a new price (a price point of the territory),
                                                    at once or from a date; current subscribers
                                                    keep theirs
    python3 appstore/asc.py review-notes --version 1.7 [--apply]
                                                    the App Review notes from docs/release-notes.md
    python3 appstore/asc.py prepare-review --version 1.7
                                                    a draft review submission with the version and
                                                    the custom pages in preparation, NOT submitted
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
import hashlib
import json
import os
import re
import sys
import time
import urllib.error
import urllib.parse
import urllib.request
from datetime import date, datetime, timedelta, timezone
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


# Requests that are safe to send again after App Store Connect answers with a 5xx, times out or
# drops the connection: a POST could create a second resource, so it is never retried.
RETRIED_METHODS = ("GET", "PATCH", "DELETE")
RETRY_DELAYS = (5, 15, 45)


def request(path: str, accept: str = "application/json", method: str = "GET", body: dict | None = None) -> bytes:
    url = path if path.startswith("http") else API + path
    data = None if body is None else json.dumps(body).encode()
    attempt = 0
    while True:
        headers = {"Authorization": "Bearer " + token(), "Accept": accept}
        if data is not None:
            headers["Content-Type"] = "application/json"
        req = urllib.request.Request(url, data=data, method=method, headers=headers)
        try:
            with urllib.request.urlopen(req, timeout=120) as response:
                return response.read()
        except urllib.error.HTTPError as error:
            details = error.read().decode(errors="replace")
            try:
                errors = json.loads(details).get("errors", [])
                details = "; ".join(f"{e.get('title', '')}: {e.get('detail', '')}" for e in errors) or details
            except ValueError:
                pass
            if error.code >= 500 and method in RETRIED_METHODS and attempt < len(RETRY_DELAYS):
                print(f"  {method} {path.split('?')[0]}: HTTP {error.code}, retrying in {RETRY_DELAYS[attempt]} s", flush=True)
                time.sleep(RETRY_DELAYS[attempt])
                attempt += 1
                continue
            # A DELETE whose earlier attempt went through on the server despite the 5xx.
            if error.code == 404 and method == "DELETE" and attempt > 0:
                return b""
            raise ApiError(error.code, f"{method} {path.split('?')[0]}: {details[:600]}") from None
        except (TimeoutError, ConnectionError, urllib.error.URLError) as error:
            # No HTTP status at all: a read timeout or a dropped connection.
            if method in RETRIED_METHODS and attempt < len(RETRY_DELAYS):
                print(f"  {method} {path.split('?')[0]}: {type(error).__name__}, retrying in {RETRY_DELAYS[attempt]} s", flush=True)
                time.sleep(RETRY_DELAYS[attempt])
                attempt += 1
                continue
            raise ApiError(0, f"{method} {path.split('?')[0]}: {error}") from None


def get(path: str, params: dict | None = None) -> dict:
    if params:
        path += ("&" if "?" in path else "?") + urllib.parse.urlencode(params)
    raw = request(path)
    return json.loads(raw) if raw else {}


def send(method: str, path: str, body: dict) -> dict:
    """POST or PATCH a JSON:API document; a 204 comes back as {}."""
    raw = request(path, method=method, body=body)
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

def utc(stamp: str | None) -> str:
    """App Store Connect's timestamps carry Apple's own offset (US Pacific): shown in UTC."""
    if not stamp:
        return ""
    try:
        return datetime.fromisoformat(stamp.replace("Z", "+00:00")).astimezone(timezone.utc).strftime("%Y-%m-%d %H:%M")
    except ValueError:
        return stamp[:16].replace("T", " ")


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
            "uploaded": utc(attrs.get("uploadedDate")),
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


NOTES = Path(__file__).resolve().parent.parent / "docs" / "release-notes.md"
EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED", "INVALID_BINARY"}


def release_notes(version: str, path: Path = NOTES) -> dict[str, str]:
    """What's New per ASC locale from docs/release-notes.md: each `## <locale>` heading followed by
    a fenced block. The file's title must name the version, so stale notes are never sent."""
    text = path.read_text(encoding="utf-8")
    title = text.splitlines()[0] if text else ""
    if f"Tenra {version}:" not in title:
        sys.exit(f"{path.name} is not the notes of {version} (title: {title!r}).")
    notes = {m.group(1): m.group(2).strip()
             for m in re.finditer(r"^## ([a-z]{2}(?:-[A-Z]{2})?)\n\n```\n(.*?)\n```", text, re.S | re.M)}
    if not notes:
        sys.exit(f"No `## <locale>` blocks in {path.name}.")
    for locale, note in notes.items():
        if len(note) > 4000:
            sys.exit(f"What's New for {locale} is {len(note)} characters; App Store Connect allows 4000.")
    return notes


def prepare_version(app: str, version: str, number: str | None, minutes: int) -> None:
    """Create the App Store version (released after approval) if it is missing, set What's New for
    every locale in docs/release-notes.md and select build `number` once it is processed. It never
    submits for review."""
    notes = release_notes(version)
    found, _ = get_all(f"/v1/apps/{app}/appStoreVersions",
                       {"filter[versionString]": version, "filter[platform]": "IOS"})
    if found:
        record = found[0]
        print(f"Version {version} already exists.")
    else:
        record = send("POST", "/v1/appStoreVersions", {"data": {
            "type": "appStoreVersions",
            "attributes": {"platform": "IOS", "versionString": version, "releaseType": "AFTER_APPROVAL"},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}},
        }})["data"]
        print(f"Version {version} created (released after approval).")
    version_id = record["id"]
    state = record["attributes"].get("appVersionState") or record["attributes"].get("appStoreState")
    if state not in EDITABLE:
        sys.exit(f"Version {version} is {state}: its metadata can't be edited now.")

    existing, _ = get_all(f"/v1/appStoreVersions/{version_id}/appStoreVersionLocalizations", {"limit": 50})
    by_locale = {item["attributes"]["locale"]: item["id"] for item in existing}
    rows = []
    for locale, note in notes.items():
        if locale in by_locale:
            send("PATCH", f"/v1/appStoreVersionLocalizations/{by_locale[locale]}", {"data": {
                "type": "appStoreVersionLocalizations", "id": by_locale[locale], "attributes": {"whatsNew": note},
            }})
            rows.append([locale, "updated", len(note)])
        else:
            send("POST", "/v1/appStoreVersionLocalizations", {"data": {
                "type": "appStoreVersionLocalizations",
                "attributes": {"locale": locale, "whatsNew": note},
                "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}}},
            }})
            rows.append([locale, "created (no description yet)", len(note)])
    rows += [[locale, "not in release-notes.md, left as is", ""] for locale in sorted(set(by_locale) - set(notes))]
    table(f"What's New, {version}", ["Locale", "Result", "Characters"], rows)

    if not number:
        return
    deadline = time.time() + minutes * 60
    while True:
        build = next((b for b in builds(app, 20) if b["number"] == number and b["version"] == version), None)
        if (build and build["processing"] != "PROCESSING") or time.time() > deadline:
            break
        print(f"Build {number}: {build['processing'] if build else 'not visible yet'}, waiting…", flush=True)
        time.sleep(60)
    if not build or build["processing"] != "VALID":
        sys.exit(f"Build {number} of {version}: {build['processing'] if build else 'not in App Store Connect yet'}; "
                 "run prepare-version again once it is processed.")
    send("PATCH", f"/v1/appStoreVersions/{version_id}/relationships/build",
         {"data": {"type": "builds", "id": build["id"]}})
    print(f"Build {number} selected for version {version}. Submitting for review stays with the founder.")


# Product pages: custom product pages and product page optimization ---------------------------------

ROOT = Path(__file__).resolve().parent.parent
PAGES = Path(__file__).resolve().parent / "product-pages.json"
IPHONE = "APP_IPHONE_67"   # the 6.9" set (1320 x 2868), the only size Tenra uploads
CPP_EDITABLE = {"PREPARE_FOR_SUBMISSION", "REJECTED"}


def page_config() -> dict:
    return json.loads(PAGES.read_text(encoding="utf-8"))


def frame_files(config: dict, frames: list[str], locale: str) -> list[Path]:
    """The composed screenshots (screenshots/final/<locale>/<stem>.png) for `frames`, in order."""
    paths = [ROOT / "screenshots" / "final" / locale / f"{config['frames'][frame]}.png" for frame in frames]
    missing = [str(path.relative_to(ROOT)) for path in paths if not path.exists()]
    if missing:
        sys.exit("Missing screenshots: " + ", ".join(missing))
    return paths


def screenshot_set(owner: str, owner_id: str) -> str:
    """The 6.9" screenshot set of a custom page or treatment localization, created when missing.
    `owner` is the relationship name: appCustomProductPageLocalization or
    appStoreVersionExperimentTreatmentLocalization."""
    sets, _ = get_all(f"/v1/{owner}s/{owner_id}/appScreenshotSets", {"limit": 50})
    for item in sets:
        if item["attributes"].get("screenshotDisplayType") == IPHONE:
            return item["id"]
    return send("POST", "/v1/appScreenshotSets", {"data": {
        "type": "appScreenshotSets",
        "attributes": {"screenshotDisplayType": IPHONE},
        "relationships": {owner: {"data": {"type": owner + "s", "id": owner_id}}},
    }})["data"]["id"]


def settled_screenshots(set_id: str) -> list[dict]:
    """The set's screenshots once its contents stop changing. A new treatment or page
    localization gets a copy of the default page's screenshots a few seconds after it is
    created: listing too early saw an empty set, and the copy then overfilled it."""
    previous = None
    for _ in range(10):
        shots, _ = get_all(f"/v1/appScreenshotSets/{set_id}/appScreenshots", {"limit": 50})
        ids = [shot["id"] for shot in shots]
        if ids == previous:
            return shots
        previous = ids
        time.sleep(3)
    return shots


def put_screenshots(set_id: str, files: list[Path]) -> str:
    """Make the set hold exactly `files`, in order. Skips the upload when it already does."""
    wanted = [hashlib.md5(path.read_bytes()).hexdigest() for path in files]
    existing = settled_screenshots(set_id)
    if [shot["attributes"].get("sourceFileChecksum") for shot in existing] == wanted:
        return "unchanged"
    for shot in existing:
        request(f"/v1/appScreenshots/{shot['id']}", method="DELETE")
    ids = []
    for path, checksum in zip(files, wanted):
        data = path.read_bytes()
        body = {"data": {
            "type": "appScreenshots",
            "attributes": {"fileName": path.name, "fileSize": len(data)},
            "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
        }}
        try:
            shot = send("POST", "/v1/appScreenshots", body)["data"]
        except ApiError as error:
            # 409: the default page's copy arrived after all. 5xx: the reservation may or may not
            # exist. Either way keep only this run's uploads, then reserve again.
            if error.code != 409 and error.code < 500:
                raise
            if error.code >= 500:
                print(f"  POST {path.name}: HTTP {error.code}, clearing the set's strays and retrying", flush=True)
                time.sleep(RETRY_DELAYS[0])
            for other in settled_screenshots(set_id):
                if other["id"] not in ids:
                    request(f"/v1/appScreenshots/{other['id']}", method="DELETE")
            shot = send("POST", "/v1/appScreenshots", body)["data"]
        for operation in shot["attributes"]["uploadOperations"]:
            # Presigned upload URLs: no App Store Connect token.
            chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
            headers = {header["name"]: header["value"] for header in operation.get("requestHeaders") or []}
            upload = urllib.request.Request(operation["url"], data=chunk, method=operation["method"], headers=headers)
            try:
                with urllib.request.urlopen(upload, timeout=120):
                    pass
            except urllib.error.HTTPError as error:
                raise ApiError(error.code, f"upload of {path.name} failed") from None
        send("PATCH", f"/v1/appScreenshots/{shot['id']}", {"data": {
            "type": "appScreenshots", "id": shot["id"],
            "attributes": {"uploaded": True, "sourceFileChecksum": checksum},
        }})
        ids.append(shot["id"])
    send("PATCH", f"/v1/appScreenshotSets/{set_id}/relationships/appScreenshots",
         {"data": [{"type": "appScreenshots", "id": shot_id} for shot_id in ids]})
    return f"{len(ids)} uploaded"


def keywords(app: str, locale: str) -> None:
    items, _ = get_all(f"/v1/apps/{app}/searchKeywords",
                       {"filter[platform]": "IOS", "filter[locale]": locale, "limit": 200})
    table(f"App keywords, {locale}", ["Keyword id"], [[item["id"]] for item in items])


def link_keywords(app: str, localization_id: str, locale: str, wanted: list[str]) -> str:
    """Link the custom page localization to the app keywords named in `wanted` (case-insensitive);
    unlink the others. Keywords that are not in the app's keyword list are reported, not added."""
    available, _ = get_all(f"/v1/apps/{app}/searchKeywords",
                           {"filter[platform]": "IOS", "filter[locale]": locale, "limit": 200})
    by_text = {item["id"].casefold(): item["id"] for item in available}
    ids = [by_text[word.casefold()] for word in wanted if word.casefold() in by_text]
    unknown = [word for word in wanted if word.casefold() not in by_text]
    path = f"/v1/appCustomProductPageLocalizations/{localization_id}/relationships/searchKeywords"
    linked, _ = get_all(path, {"limit": 200})
    stale = [{"type": "appKeywords", "id": item["id"]} for item in linked if item["id"] not in ids]
    if stale:
        request(path, method="DELETE", body={"data": stale})
    if ids:
        send("POST", path, {"data": [{"type": "appKeywords", "id": keyword} for keyword in ids]})
    return f"{len(ids)} linked" + (f"; not app keywords: {', '.join(unknown)}" if unknown else "")


def submit_for_review(app: str, items: list[tuple[str, str]], lenient: set[str] = frozenset(),
                      submit: bool = True) -> None:
    """Add (relationship, id) items to the open review submission, or a new one, and submit it.
    An item of a `lenient` relationship that App Store Connect refuses is reported, not fatal.
    With `submit` False the submission stays a draft: the founder sends it from App Store Connect."""
    open_ones, _ = get_all("/v1/reviewSubmissions",
                           {"filter[app]": app, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW"})
    submission = open_ones[0] if open_ones else send("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
    }})["data"]
    types = {"appStoreVersion": "appStoreVersions",
             "appCustomProductPageVersion": "appCustomProductPageVersions",
             "appStoreVersionExperimentV2": "appStoreVersionExperiments",
             "appAssetLibraryImage": "appAssetLibraryImages"}
    added = 0
    for relationship, item_id in items:
        try:
            send("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                relationship: {"data": {"type": types[relationship], "id": item_id}},
            }}})
            added += 1
        except ApiError as error:
            # A 409 is also App Store Connect refusing the item: only "already" means it is in.
            if error.code == 409 and "already" in str(error).lower():
                added += 1
            elif relationship in lenient:
                print(f"  {relationship} {item_id}: not added ({error})", flush=True)
            else:
                raise
    if not added:
        sys.exit("App Store Connect took none of the items: nothing submitted.")
    if not submit:
        print(f"Draft review submission: {added} of {len(items)} item(s) in it, not submitted. "
              "Send it from App Store Connect (Distribution, the draft submission, Submit for Review).")
        return
    send("PATCH", f"/v1/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True},
    }})
    print(f"Submitted for review: {added} of {len(items)} item(s).")


def custom_pages(app: str) -> None:
    pages, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    rows = []
    for page in pages:
        versions, _ = get_all(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions", {"limit": 10})
        states = ", ".join(v["attributes"].get("state", "?") for v in versions)
        rows.append([page["attributes"].get("name"), page["attributes"].get("visible"), states,
                     page["attributes"].get("url") or ""])
    table("Custom product pages", ["Name", "Visible", "Versions", "URL"], rows)


def review_submissions(app: str) -> None:
    """The latest review submissions with their items by kind and state, and our creative
    images in the asset library by state. Read only."""
    found, _ = get_all("/v1/reviewSubmissions", {"filter[app]": app, "filter[platform]": "IOS", "limit": 10}, pages=1)
    found.sort(key=lambda r: r["attributes"].get("submittedDate") or "9999", reverse=True)
    rows = []
    for submission in found[:6]:
        items, _ = get_all(f"/v1/reviewSubmissions/{submission['id']}/items", {
            "limit": 200, "include": "appStoreVersion,appCustomProductPageVersion,appStoreVersionExperimentV2,appAssetLibraryImage"})
        kinds: dict[str, int] = {}
        for item in items:
            kind = next((name for name, value in (item.get("relationships") or {}).items()
                         if (value or {}).get("data")), "item")
            key = f"{kind} {item['attributes'].get('state')}"
            kinds[key] = kinds.get(key, 0) + 1
        rows.append([submission["id"][:8], submission["attributes"].get("state"),
                     utc(submission["attributes"].get("submittedDate")),
                     "; ".join(f"{count} {key}" for key, count in sorted(kinds.items())) or "-"])
    table("Review submissions", ["Id", "State", "Submitted", "Items"], rows)

    library = get(f"/v1/apps/{app}/assetLibrary")["data"]["id"]
    images, _ = get_all(f"/v1/appAssetLibraries/{library}/images", {"limit": 200})
    states: dict[str, int] = {}
    for image in images:
        if (image["attributes"].get("referenceName") or "").startswith("tenra-"):
            state = image["attributes"].get("state")
            states[state] = states.get(state, 0) + 1
    table("Creative images in the asset library", ["State", "Images"], [[k, v] for k, v in sorted(states.items())])


def editable_cpp_version(page_id: str) -> dict:
    versions, _ = get_all(f"/v1/appCustomProductPages/{page_id}/appCustomProductPageVersions", {"limit": 10})
    for version in versions:
        if version["attributes"].get("state") in CPP_EDITABLE:
            return version
    return send("POST", "/v1/appCustomProductPageVersions", {"data": {
        "type": "appCustomProductPageVersions",
        "relationships": {"appCustomProductPage": {"data": {"type": "appCustomProductPages", "id": page_id}}},
    }})["data"]


def push_custom_pages(app: str, submit: bool) -> None:
    """Create or update every custom product page in appstore/product-pages.json: promotional text,
    screenshots and keywords per locale. With submit, sends the edited versions for review.
    A locale that shows another one's frames (en-GB: kk's, `screenshot_source`) is added after
    the page exists, and one App Store Connect refuses (a language the app does not have yet) is
    reported, not fatal."""
    config = page_config()
    files = {(page["name"], locale): frame_files(config, page["frames"], screenshot_source(locale))
             for page in config["customPages"] for locale in page["locales"]}
    existing, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    by_name = {page["attributes"]["name"]: page for page in existing}
    rows, ready = [], []
    for page in config["customPages"]:
        record = by_name.get(page["name"])
        own = [locale for locale in page["locales"] if screenshot_source(locale) == locale]
        if not record:
            record = send("POST", "/v1/appCustomProductPages", {
                "data": {
                    "type": "appCustomProductPages",
                    "attributes": {"name": page["name"]},
                    "relationships": {
                        "app": {"data": {"type": "apps", "id": app}},
                        "appCustomProductPageVersions": {"data": [{"type": "appCustomProductPageVersions", "id": "${version}"}]},
                    },
                },
                "included": [
                    {"type": "appCustomProductPageVersions", "id": "${version}", "relationships": {
                        "appCustomProductPageLocalizations": {"data": [
                            {"type": "appCustomProductPageLocalizations", "id": "${" + locale + "}"}
                            for locale in own]},
                    }},
                    *[{"type": "appCustomProductPageLocalizations", "id": "${" + locale + "}",
                       "attributes": {"locale": locale, "promotionalText": page["locales"][locale]["promotionalText"]}}
                      for locale in own],
                ],
            })["data"]
        version = editable_cpp_version(record["id"])
        localizations, _ = get_all(
            f"/v1/appCustomProductPageVersions/{version['id']}/appCustomProductPageLocalizations", {"limit": 50})
        by_locale = {item["attributes"]["locale"]: item for item in localizations}
        for locale, meta in page["locales"].items():
            localization = by_locale.get(locale)
            if localization:
                send("PATCH", f"/v1/appCustomProductPageLocalizations/{localization['id']}", {"data": {
                    "type": "appCustomProductPageLocalizations", "id": localization["id"],
                    "attributes": {"promotionalText": meta["promotionalText"]},
                }})
            else:
                try:
                    localization = send("POST", "/v1/appCustomProductPageLocalizations", {"data": {
                        "type": "appCustomProductPageLocalizations",
                        "attributes": {"locale": locale, "promotionalText": meta["promotionalText"]},
                        "relationships": {"appCustomProductPageVersion": {
                            "data": {"type": "appCustomProductPageVersions", "id": version["id"]}}},
                    }})["data"]
                except ApiError as error:
                    if locale in own or error.code not in (409, 422):
                        raise
                    rows.append([page["name"], locale, f"not added: {error}", ""])
                    continue
            shots = put_screenshots(screenshot_set("appCustomProductPageLocalization", localization["id"]),
                                    files[(page["name"], locale)])
            words = link_keywords(app, localization["id"], locale, meta.get("keywords", []))
            rows.append([page["name"], locale, shots, words])
        ready.append(("appCustomProductPageVersion", version["id"]))
    table("Custom product pages pushed", ["Page", "Locale", "Screenshots", "Keywords"], rows)
    if submit:
        submit_for_review(app, ready)


def push_experiment(app: str, submit: bool, start: bool, stop: bool = False) -> None:
    """Create or update the product page optimization test in appstore/product-pages.json; with
    submit, send it for review; with start, start it once App Review has approved it; with stop,
    end it (every visitor then sees the default page)."""
    config = page_config()
    test = config["experiment"]
    # Every composed locale but kk, which App Store Connect does not have (`screenshots_only`).
    locales = sorted(path.name for path in (ROOT / "screenshots" / "final").iterdir()
                     if path.is_dir() and path.name not in screenshots_only())
    files = {(treatment["name"], locale): frame_files(config, treatment["frames"], locale)
             for treatment in test["treatments"] for locale in locales}
    existing, _ = get_all(f"/v1/apps/{app}/appStoreVersionExperimentsV2", {"limit": 20})
    record = next((item for item in existing if item["attributes"].get("name") == test["name"]), None)
    if not record:
        record = send("POST", "/v2/appStoreVersionExperiments", {"data": {
            "type": "appStoreVersionExperiments",
            "attributes": {"name": test["name"], "platform": "IOS", "trafficProportion": test["trafficProportion"]},
            "relationships": {"app": {"data": {"type": "apps", "id": app}}},
        }})["data"]
        print(f"Test {test['name']!r} created, {test['trafficProportion']}% of visitors.")
    state = record["attributes"].get("state")
    if stop:
        if not record["attributes"].get("started") and state not in ("APPROVED", "ACCEPTED"):
            sys.exit(f"Test is {state}: not running.")
        updated = send("PATCH", f"/v2/appStoreVersionExperiments/{record['id']}", {"data": {
            "type": "appStoreVersionExperiments", "id": record["id"], "attributes": {"started": False}}})["data"]
        print(f"Test stopped: {updated['attributes'].get('state')}, ends {(updated['attributes'].get('endDate') or '')[:10]}.")
        return
    if start:
        if state not in ("APPROVED", "ACCEPTED"):
            sys.exit(f"Test is {state}: it starts after App Review approves it.")
        try:
            send("PATCH", f"/v2/appStoreVersionExperiments/{record['id']}", {"data": {
                "type": "appStoreVersionExperiments", "id": record["id"], "attributes": {"started": True}}})
        except ApiError as error:
            # An approved test can already be running (started in App Store Connect).
            if error.code == 409 and "already running" in str(error):
                print("Test is already running.")
                return
            raise
        print("Test started.")
        return
    if state not in CPP_EDITABLE:
        sys.exit(f"Test is {state}: its treatments can't be edited now.")
    treatments, _ = get_all(f"/v2/appStoreVersionExperiments/{record['id']}/appStoreVersionExperimentTreatments", {"limit": 10})
    by_name = {item["attributes"].get("name"): item for item in treatments}
    rows = []
    for treatment in test["treatments"]:
        item = by_name.get(treatment["name"]) or send("POST", "/v1/appStoreVersionExperimentTreatments", {"data": {
            "type": "appStoreVersionExperimentTreatments", "attributes": {"name": treatment["name"]},
            "relationships": {"appStoreVersionExperimentV2": {"data": {"type": "appStoreVersionExperiments", "id": record["id"]}}},
        }})["data"]
        localizations, _ = get_all(
            f"/v1/appStoreVersionExperimentTreatments/{item['id']}/appStoreVersionExperimentTreatmentLocalizations", {"limit": 50})
        by_locale = {loc["attributes"]["locale"]: loc for loc in localizations}
        for locale in locales:
            localization = by_locale.get(locale) or send("POST", "/v1/appStoreVersionExperimentTreatmentLocalizations", {"data": {
                "type": "appStoreVersionExperimentTreatmentLocalizations", "attributes": {"locale": locale},
                "relationships": {"appStoreVersionExperimentTreatment": {
                    "data": {"type": "appStoreVersionExperimentTreatments", "id": item["id"]}}},
            }})["data"]
            shots = put_screenshots(screenshot_set("appStoreVersionExperimentTreatmentLocalization", localization["id"]),
                                    files[(treatment["name"], locale)])
            rows.append([treatment["name"], locale, shots])
    table(f"Test {test['name']!r}", ["Treatment", "Locale", "Screenshots"], rows)
    if submit:
        submit_for_review(app, [("appStoreVersionExperimentV2", record["id"])])


# Age rating -------------------------------------------------------------------------------------

# Tenra's answers to the age rating questionnaire (App Information → Age Rating): a money tracker
# whose AI assistant talks to the person only. No chat between people, nothing shared with others,
# no ads, no web browsing, no health or medical topics, no gambling. Apple's App Privacy answers
# are not in the API: they stay in the web form (docs/release-notes.md).
AGE_RATING = {
    "alcoholTobaccoOrDrugUseOrReferences": "NONE", "contests": "NONE", "gamblingSimulated": "NONE",
    "gunsOrOtherWeapons": "NONE", "horrorOrFearThemes": "NONE", "matureOrSuggestiveThemes": "NONE",
    "medicalOrTreatmentInformation": "NONE", "profanityOrCrudeHumor": "NONE",
    "sexualContentGraphicAndNudity": "NONE", "sexualContentOrNudity": "NONE",
    "violenceCartoonOrFantasy": "NONE", "violenceRealistic": "NONE",
    "violenceRealisticProlongedGraphicOrSadistic": "NONE",
    "gambling": False, "lootBox": False, "unrestrictedWebAccess": False,
    "messagingAndChat": False, "userGeneratedContent": False, "advertising": False,
    "healthOrWellnessTopics": False, "parentalControls": False, "ageAssurance": False,
    "socialMedia": False,
}
APP_INFO_EDITABLE = {"PREPARE_FOR_SUBMISSION", "DEVELOPER_REJECTED", "REJECTED", "METADATA_REJECTED"}


def age_rating(app: str, apply: bool) -> None:
    """The age rating declaration of each app info (live and in preparation) against Tenra's
    answers; with `apply`, sets them on the one in preparation."""
    infos, _ = get_all(f"/v1/apps/{app}/appInfos", {"limit": 10})
    editable = None
    for info in infos:
        state = info["attributes"].get("state") or info["attributes"].get("appStoreState")
        rating = info["attributes"].get("appStoreAgeRating")
        declaration = get(f"/v1/appInfos/{info['id']}/ageRatingDeclaration")["data"]
        current = declaration["attributes"]
        rows = [[key, current.get(key), wanted, "" if current.get(key) == wanted else "differs"]
                for key, wanted in AGE_RATING.items()]
        table(f"App info {state} (rating {rating})", ["Question", "Now", "Tenra", ""], rows)
        if state in APP_INFO_EDITABLE:
            editable = declaration["id"]
    if not apply:
        return
    if not editable:
        sys.exit("No app info in preparation: create the version first (prepare-version).")
    send("PATCH", f"/v1/ageRatingDeclarations/{editable}", {"data": {
        "type": "ageRatingDeclarations", "id": editable, "attributes": AGE_RATING,
    }})
    print("Age rating answers set on the version in preparation.")


# Subscription prices ------------------------------------------------------------------------------

def subscriptions(app: str) -> list[dict]:
    """Every subscription of the app's subscription groups."""
    groups, _ = get_all(f"/v1/apps/{app}/subscriptionGroups", {"limit": 50})
    found = []
    for group in groups:
        items, _ = get_all(f"/v1/subscriptionGroups/{group['id']}/subscriptions", {"limit": 50})
        found += items
    return found


def current_prices(subscription_id: str, territory: str) -> list[tuple[str, str]]:
    """(start date, customer price) of a subscription in a territory, scheduled ones included."""
    prices, included = get_all(f"/v1/subscriptions/{subscription_id}/prices", {
        "filter[territory]": territory, "include": "subscriptionPricePoint", "limit": 50})
    points = {item["id"]: item["attributes"].get("customerPrice") for item in included
              if item["type"] == "subscriptionPricePoints"}
    rows = []
    for price in prices:
        point = ((price.get("relationships") or {}).get("subscriptionPricePoint") or {}).get("data") or {}
        rows.append((price["attributes"].get("startDate") or "now", points.get(point.get("id"), "?")))
    return sorted(rows)


def subscription_prices(app: str, territory: str) -> None:
    """Each subscription's price in a territory, with any change already scheduled. Read only."""
    rows = []
    for item in subscriptions(app):
        for start, price in current_prices(item["id"], territory):
            rows.append([item["attributes"].get("productId"), item["attributes"].get("state"), start, price])
    table(f"Subscription prices in {territory}", ["Product", "State", "From", "Price"], rows)


def push_price(app: str, product: str, territory: str, price: str, start: str | None, apply: bool) -> None:
    """A new price for one subscription in one territory, from `start` (YYYY-MM-DD) or at once.
    Current subscribers keep what they pay (`preserveCurrentPrice`), so a rise needs no consent.
    The price must be one of the territory's price points. Without `apply` only shows the change."""
    item = next((s for s in subscriptions(app) if s["attributes"].get("productId") == product), None)
    if not item:
        sys.exit(f"No subscription {product}.")
    points, _ = get_all(f"/v1/subscriptions/{item['id']}/pricePoints",
                        {"filter[territory]": territory, "limit": 200}, pages=20)
    wanted = float(price)
    point = next((p for p in points if float(p["attributes"].get("customerPrice") or -1) == wanted), None)
    if not point:
        near = sorted(points, key=lambda p: abs(float(p["attributes"].get("customerPrice") or 0) - wanted))[:4]
        sys.exit(f"{price} is not a price point in {territory}; the nearest: "
                 + ", ".join(p["attributes"].get("customerPrice") for p in near))
    rows = [[product, territory, start_, now] for start_, now in current_prices(item["id"], territory)]
    rows.append([product, territory, start or "now", f"{point['attributes'].get('customerPrice')} (new)"])
    table("Subscription price" + ("" if apply else " (dry run: --apply sets it)"),
          ["Product", "Territory", "From", "Price"], rows)
    if not apply:
        return
    attributes = {"preserveCurrentPrice": True}
    if start:
        attributes["startDate"] = start
    send("POST", "/v1/subscriptionPrices", {"data": {
        "type": "subscriptionPrices",
        "attributes": attributes,
        "relationships": {
            "subscription": {"data": {"type": "subscriptions", "id": item["id"]}},
            "subscriptionPricePoint": {"data": {"type": "subscriptionPricePoints", "id": point["id"]}},
            "territory": {"data": {"type": "territories", "id": territory}},
        },
    }})
    print(f"{product} in {territory}: {price} from {start or 'now'}; current subscribers keep their price.")


# Review notes and the draft submission ------------------------------------------------------------

def review_notes_text(path: Path = NOTES) -> str:
    """The App Review notes of the submission checklist: the fenced block after its heading."""
    text = path.read_text(encoding="utf-8")
    match = re.search(r"\*\*App Review notes\*\*.*?```\n(.*?)```", text, re.S)
    if not match:
        sys.exit(f"No App Review notes block in {path.name}.")
    return match.group(1).strip()


def review_notes(app: str, version: str, apply: bool) -> None:
    """The version's App Review notes from docs/release-notes.md (contact details are left as
    they are and never printed). Without `apply` only shows them."""
    record = store_version(app, version)
    notes = review_notes_text()
    print(notes)
    if not apply:
        print("\n(dry run: --apply sets these notes)")
        return
    try:
        detail = get(f"/v1/appStoreVersions/{record['id']}/appStoreReviewDetail")["data"]
    except ApiError as error:
        if error.code != 404:
            raise
        detail = None
    if detail:
        send("PATCH", f"/v1/appStoreReviewDetails/{detail['id']}", {"data": {
            "type": "appStoreReviewDetails", "id": detail["id"], "attributes": {"notes": notes}}})
        print(f"App Review notes set on {version}.")
        return
    # A version without review details yet: the contact details of the latest version that has them.
    found, _ = get_all(f"/v1/apps/{app}/appStoreVersions", {"filter[platform]": "IOS", "limit": 20})
    contact = {}
    for other in sorted(found, key=lambda v: v["attributes"].get("createdDate") or "", reverse=True):
        if other["id"] == record["id"]:
            continue
        try:
            attrs = get(f"/v1/appStoreVersions/{other['id']}/appStoreReviewDetail")["data"]["attributes"]
        except ApiError:
            continue
        contact = {k: attrs[k] for k in ("contactFirstName", "contactLastName", "contactPhone", "contactEmail",
                                          "demoAccountRequired") if attrs.get(k) is not None}
        break
    send("POST", "/v1/appStoreReviewDetails", {"data": {
        "type": "appStoreReviewDetails", "attributes": {**contact, "notes": notes},
        "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": record["id"]}}}}})
    print(f"App Review notes set on {version} (contact details from the previous version).")


def prepare_review(app: str, version: str) -> None:
    """A draft review submission with the version and every custom page version in preparation,
    not submitted: App Store Connect checks each item as it is added (a missing build, screenshot
    or text is refused here), and the founder sends the whole release with one button."""
    record = store_version(app, version)
    items = [("appStoreVersion", record["id"])]
    pages, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    for page in pages:
        versions, _ = get_all(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions", {"limit": 10})
        for page_version in versions:
            if page_version["attributes"].get("state") in CPP_EDITABLE:
                items.append(("appCustomProductPageVersion", page_version["id"]))
    submit_for_review(app, items, lenient={"appCustomProductPageVersion"}, submit=False)


# Version screenshots -----------------------------------------------------------------------------

CAPTIONS = ROOT / "scripts" / "screenshot_captions.json"


def push_version_screenshots(app: str, version: str, locales: list[str] | None) -> None:
    """The version's own 6.9" screenshots: per locale, the frames of `defaultOrder` (or the
    locale's own order) from screenshots/final/<locale>/, or from the folder `screenshot_source`
    names (en-GB: kk/). Only a version in preparation. Goes through the version's
    localizations, so kk, which App Store Connect does not have, is reached only through en-GB."""
    captions = json.loads(CAPTIONS.read_text(encoding="utf-8"))
    config = page_config()
    found, _ = get_all(f"/v1/apps/{app}/appStoreVersions",
                       {"filter[versionString]": version, "filter[platform]": "IOS"})
    if not found:
        sys.exit(f"Version {version} does not exist: run prepare-version first.")
    record = found[0]
    state = record["attributes"].get("appVersionState") or record["attributes"].get("appStoreState")
    if state not in EDITABLE:
        sys.exit(f"Version {version} is {state}: its screenshots can't be changed now.")
    existing, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
    rows = []
    for item in existing:
        locale = item["attributes"]["locale"]
        if locales and locale not in locales:
            continue
        source = screenshot_source(locale)
        settings = captions["locales"].get(source, {})
        frames = settings.get("order") or captions["defaultOrder"]
        files = frame_files(config, frames, source)
        print(f"{locale}: {len(files)} frames", flush=True)
        set_id = screenshot_set("appStoreVersionLocalization", item["id"])
        result = put_screenshots(set_id, files)
        print(f"{locale}: {result}", flush=True)
        rows.append([locale, len(files), result])
    table(f"Screenshots, {version}", ["Locale", "Frames", "Result"], rows)


def store_version(app: str, version: str | None) -> dict:
    """The version named, or the latest one on the App Store."""
    params = {"filter[platform]": "IOS", "limit": 20}
    if version:
        params["filter[versionString]"] = version
    found, _ = get_all(f"/v1/apps/{app}/appStoreVersions", params)
    if not version:
        found = [v for v in found if v["attributes"].get("appStoreState") == "READY_FOR_DISTRIBUTION"
                 or v["attributes"].get("appVersionState") == "READY_FOR_DISTRIBUTION"]
        found.sort(key=lambda v: v["attributes"].get("createdDate") or "", reverse=True)
    if not found:
        sys.exit("No such version on the App Store.")
    return found[0]


def metadata(app: str, version: str | None) -> None:
    """The texts each localization shows, read only. Kazakhstan, Belarus, Uzbekistan and most
    storefronts index only English (U.K.) (Apple's "App Store localizations" table): without an
    en-GB localization they fall back to the primary language printed here. The keyword field is
    not public on the store, so in Actions (a public log) only its length shows."""
    primary = get(f"/v1/apps/{app}")["data"]["attributes"].get("primaryLocale")
    print(f"Primary language: {primary}\n")
    infos, _ = get_all(f"/v1/apps/{app}/appInfos", {"limit": 10})
    rows = []
    for info in infos:
        state = info["attributes"].get("appStoreState") or info["attributes"].get("state")
        localizations, _ = get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"limit": 50})
        for item in sorted(localizations, key=lambda i: i["attributes"]["locale"]):
            a = item["attributes"]
            subtitle = a.get("subtitle") or ""
            rows.append([state, a["locale"], a.get("name") or "", subtitle, len(subtitle)])
    table("Name and subtitle (app info)", ["State", "Locale", "Name", "Subtitle", "Chars"], rows)

    record = store_version(app, version)
    in_actions = bool(os.environ.get("GITHUB_ACTIONS"))
    localizations, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
    rows = []
    for item in sorted(localizations, key=lambda i: i["attributes"]["locale"]):
        a = item["attributes"]
        words = a.get("keywords") or ""
        promo = (a.get("promotionalText") or "").replace("\n", " ")
        rows.append([a["locale"], promo, len(promo), len(a.get("description") or ""), len(words),
                     "(hidden in Actions)" if in_actions else words])
    table(f"Version {record['attributes'].get('versionString')}",
          ["Locale", "Promotional text", "Chars", "Description chars", "Keyword chars", "Keywords"], rows)


METADATA = Path(__file__).resolve().parent / "metadata.json"
TEXT_LIMITS = {"name": 30, "subtitle": 30, "promotionalText": 170, "keywords": 100, "description": 4000}


def metadata_config() -> dict:
    config = json.loads(METADATA.read_text(encoding="utf-8"))
    for locale, fields in config["locales"].items():
        for field, limit in TEXT_LIMITS.items():
            text = fields.get(field)
            if text is not None and len(text) > limit:
                sys.exit(f"{locale} {field} is {len(text)} characters; App Store Connect allows {limit}.")
            if text and "\u2014" in text:
                sys.exit(f"{locale} {field} has an em dash (user rule: none in store texts).")
    return config


def screenshot_source(locale: str) -> str:
    """The folder of screenshots/final (and screenshots/art) a locale takes: its own; when it has
    none, its `screenshotsFrom` in metadata.json, else its `copyFrom`. en-GB has the Russian texts
    (copyFrom ru) and the Kazakh frames and art (screenshotsFrom kk), decision D9."""
    if (ROOT / "screenshots" / "final" / locale).is_dir() or not METADATA.exists():
        return locale
    fields = metadata_config()["locales"].get(locale, {})
    return fields.get("screenshotsFrom") or fields.get("copyFrom", locale)


def screenshots_only() -> set[str]:
    """Folders of screenshots/final that are no App Store locale: a language App Store Connect
    lacks (kk), composed only for the locale that shows it through `screenshotsFrom` (en-GB).
    Nothing pushes them as a localization of their own."""
    if not METADATA.exists():
        return set()
    locales = metadata_config()["locales"]
    return {fields["screenshotsFrom"] for fields in locales.values() if fields.get("screenshotsFrom")} - set(locales)


def edited_keywords(current: str, fields: dict) -> tuple[str, list[str]]:
    """The keyword field after `keywords`, or after `keywordsRemove` and `keywordsAdd` applied to
    the field as it is; words that would pass 100 characters are left out and returned."""
    if "keywords" in fields:
        return fields["keywords"], []
    drop = {word.lower() for word in fields.get("keywordsRemove", [])}
    words = [w.strip() for w in current.split(",") if w.strip() and w.strip().lower() not in drop]
    no_room = []
    for word in fields.get("keywordsAdd", []):
        if word.lower() in {w.lower() for w in words}:
            continue
        if len(",".join(words + [word])) > TEXT_LIMITS["keywords"]:
            no_room.append(word)
        else:
            words.append(word)
    return ",".join(words), no_room


def push_metadata(app: str, apply: bool) -> None:
    """The store texts of appstore/metadata.json. Name and subtitle live in the app info and change
    only while a version is in preparation; promotional text changes any time; keywords and
    description belong to the version named in the file. A locale missing in App Store Connect is
    created from its `copyFrom` (description, URLs, What's New, privacy policy). Without `apply`
    nothing is written."""
    config = metadata_config()
    in_actions = bool(os.environ.get("GITHUB_ACTIONS"))
    shown = lambda field, text: f"({len(text)} characters)" if field == "keywords" and in_actions else text

    infos, _ = get_all(f"/v1/apps/{app}/appInfos", {"limit": 10})
    info = next((i for i in infos if (i["attributes"].get("state") or i["attributes"].get("appStoreState")) in EDITABLE), None)
    info_locs = {}
    if info:
        found, _ = get_all(f"/v1/appInfos/{info['id']}/appInfoLocalizations", {"limit": 50})
        info_locs = {item["attributes"]["locale"]: item for item in found}
    else:
        live = infos[0] if infos else None
        if live:
            found, _ = get_all(f"/v1/appInfos/{live['id']}/appInfoLocalizations", {"limit": 50})
            info_locs = {item["attributes"]["locale"]: item for item in found}

    found, _ = get_all(f"/v1/apps/{app}/appStoreVersions",
                       {"filter[versionString]": config["version"], "filter[platform]": "IOS"})
    if not found:
        sys.exit(f"Version {config['version']} does not exist: run prepare-version first.")
    record = found[0]
    editable = (record["attributes"].get("appVersionState") or record["attributes"].get("appStoreState")) in EDITABLE
    existing, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
    version_locs = {item["attributes"]["locale"]: item for item in existing}

    rows = []
    for locale, fields in config["locales"].items():
        source = fields.get("copyFrom")
        # App info: name and subtitle.
        wanted = {k: fields[k] for k in ("name", "subtitle") if k in fields}
        current = info_locs.get(locale)
        if wanted and not info:
            rows.append([locale, "name, subtitle", "", "needs a version in preparation"])
        elif info and (wanted or (current is None and source)):
            attrs = current["attributes"] if current else {}
            changes = {k: v for k, v in wanted.items() if attrs.get(k) != v}
            if current is None:
                base = info_locs.get(source, {}).get("attributes", {}) if source else {}
                changes = {"name": base.get("name"), "privacyPolicyUrl": base.get("privacyPolicyUrl"), **changes}
                changes = {k: v for k, v in changes.items() if v}
            for field, value in changes.items():
                rows.append([locale, field, attrs.get(field) or "", value])
            if apply and changes:
                if current:
                    send("PATCH", f"/v1/appInfoLocalizations/{current['id']}", {"data": {
                        "type": "appInfoLocalizations", "id": current["id"], "attributes": changes}})
                else:
                    send("POST", "/v1/appInfoLocalizations", {"data": {
                        "type": "appInfoLocalizations", "attributes": {"locale": locale, **changes},
                        "relationships": {"appInfo": {"data": {"type": "appInfos", "id": info["id"]}}}}})

        # Version: promotional text, keywords, description.
        current = version_locs.get(locale)
        if current is None and apply and editable:
            # A language added to the app info just now is added to the version in preparation
            # too, empty: update that one (a POST would get HTTP 409).
            found, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
            version_locs = {item["attributes"]["locale"]: item for item in found}
            current = version_locs.get(locale)
        if current is None and not editable:
            rows.append([locale, "version texts", "", f"no {locale} yet: created while a version is in preparation"])
            continue
        attrs = current["attributes"] if current else {}
        changes = {}
        if "promotionalText" in fields:
            changes["promotionalText"] = fields["promotionalText"]
        if editable:
            if any(k in fields for k in ("keywords", "keywordsAdd", "keywordsRemove")):
                words, no_room = edited_keywords(attrs.get("keywords") or "", fields)
                changes["keywords"] = words
                if no_room:
                    rows.append([locale, "keywords", "", "no room for: " + ", ".join(no_room)])
            if "description" in fields:
                changes["description"] = fields["description"]
            if source:
                # A new localization, or the empty one App Store Connect made with the language,
                # takes what it lacks from `copyFrom`.
                base = version_locs.get(source, {}).get("attributes", {})
                for field in ("description", "supportUrl", "marketingUrl", "whatsNew"):
                    if base.get(field) and not attrs.get(field) and field not in changes:
                        changes[field] = base[field]
        elif any(k in fields for k in ("keywords", "keywordsAdd", "keywordsRemove", "description")):
            rows.append([locale, "keywords, description", "", f"version {config['version']} is not in preparation"])
        changes = {k: v for k, v in changes.items() if attrs.get(k) != v}
        for field, value in changes.items():
            rows.append([locale, field, shown(field, attrs.get(field) or ""), shown(field, value)])
        if apply and changes:
            if current:
                send("PATCH", f"/v1/appStoreVersionLocalizations/{current['id']}", {"data": {
                    "type": "appStoreVersionLocalizations", "id": current["id"], "attributes": changes}})
            elif editable:
                send("POST", "/v1/appStoreVersionLocalizations", {"data": {
                    "type": "appStoreVersionLocalizations", "attributes": {"locale": locale, **changes},
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": record["id"]}}}}})
    title = f"Store texts, {config['version']}" + ("" if apply else " (dry run: --apply writes them)")
    table(title, ["Locale", "Field", "Now", "New"], [[r[0], r[1], str(r[2]).replace("|", "/"), str(r[3]).replace("|", "/")] for r in rows])


def store_pages(app: str, version: str | None) -> None:
    """What the store shows, read only: per localization of the version (the latest one on the
    App Store by default), each screenshot set and how many of its screenshots are files in
    screenshots/final/<locale>/ now (en-GB: kk/, `screenshot_source`); the product page tests
    with their state; the languages of each custom page's versions."""
    record = store_version(app, version)
    name = record["attributes"].get("versionString")
    localizations, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
    rows = []
    for item in sorted(localizations, key=lambda i: i["attributes"]["locale"]):
        locale = item["attributes"]["locale"]
        folder = ROOT / "screenshots" / "final" / screenshot_source(locale)
        ours = {hashlib.md5(path.read_bytes()).hexdigest() for path in folder.glob("*.png")} if folder.is_dir() else set()
        sets, _ = get_all(f"/v1/appStoreVersionLocalizations/{item['id']}/appScreenshotSets", {"limit": 50})
        if not sets:
            rows.append([locale, "none", 0, "-"])
        for screenshot_set_record in sets:
            shots, _ = get_all(f"/v1/appScreenshotSets/{screenshot_set_record['id']}/appScreenshots", {"limit": 50})
            current = sum(1 for shot in shots if shot["attributes"].get("sourceFileChecksum") in ours)
            rows.append([locale, screenshot_set_record["attributes"].get("screenshotDisplayType"), len(shots),
                         f"{current}/{len(shots)}" if ours else "no folder"])
    table(f"Screenshots of {name} (current = a file in screenshots/final/<locale>/, en-GB: kk/)",
          ["Locale", "Set", "Shots", "Current"], rows)

    tests, _ = get_all(f"/v1/apps/{app}/appStoreVersionExperimentsV2", {"limit": 20})
    table("Product page tests", ["Name", "State", "Traffic", "Started", "Ends"],
          [[t["attributes"].get("name"), t["attributes"].get("state"), t["attributes"].get("trafficProportion"),
            (t["attributes"].get("startDate") or "")[:10], (t["attributes"].get("endDate") or "")[:10]] for t in tests])

    pages, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    rows = []
    for page in pages:
        versions, _ = get_all(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions", {"limit": 10})
        for page_version in versions:
            locs, _ = get_all(f"/v1/appCustomProductPageVersions/{page_version['id']}/appCustomProductPageLocalizations",
                              {"limit": 50})
            rows.append([page["attributes"].get("name"), page_version["attributes"].get("state"),
                         ", ".join(sorted(loc["attributes"]["locale"] for loc in locs))])
    table("Custom product pages", ["Page", "Version", "Languages"], rows)


# The iOS 27 creative assets (scripts/compose_store_art.py): placement type -> file stem.
CREATIVES = {"PRODUCT_PAGE_HEADER_ASSET": "header", "APP_STORE_SEARCH_RESULTS_ASSET": "search"}
ART = ROOT / "screenshots" / "art"


def page_slug(name: str) -> str:
    return name.lower().replace(" ", "-")


def library_image(library: str, existing: dict[str, dict], path: Path) -> str:
    """The asset library image holding `path`, uploaded unless an image with the same content is
    already there. The library has no checksum for creative assets, so the reference name carries
    one: tenra-<md5>-<file name>."""
    data = path.read_bytes()
    reference = f"tenra-{hashlib.md5(data).hexdigest()[:16]}-{path.parent.name}-{path.name}"
    if reference in existing:
        return existing[reference]["id"]
    image = send("POST", "/v1/appAssetLibraryImages", {"data": {
        "type": "appAssetLibraryImages",
        "attributes": {"category": "CREATIVE_ASSETS", "fileName": path.name, "fileSize": len(data),
                       "referenceName": reference},
        "relationships": {"assetLibrary": {"data": {"type": "appAssetLibraries", "id": library}}},
    }})["data"]
    for operation in image["attributes"].get("uploadOperations") or []:
        # Presigned upload URLs: no App Store Connect token.
        chunk = data[operation["offset"]:operation["offset"] + operation["length"]]
        headers = {header["name"]: header["value"] for header in operation.get("requestHeaders") or []}
        upload = urllib.request.Request(operation["url"], data=chunk, method=operation["method"], headers=headers)
        try:
            with urllib.request.urlopen(upload, timeout=120):
                pass
        except urllib.error.HTTPError as error:
            raise ApiError(error.code, f"upload of {path.name} failed") from None
    # Committed with `uploaded` alone: this resource refuses a checksum.
    send("PATCH", f"/v1/appAssetLibraryImages/{image['id']}", {"data": {
        "type": "appAssetLibraryImages", "id": image["id"], "attributes": {"uploaded": True}}})
    for _ in range(60):
        attributes = get(f"/v1/appAssetLibraryImages/{image['id']}")["data"]["attributes"]
        state = attributes.get("state")
        if state == "FAILED":
            details = "; ".join(d.get("code", "") for d in attributes.get("stateDetails") or [])
            sys.exit(f"{path.relative_to(ROOT)}: App Store Connect refused it ({details or 'FAILED'}).")
        if state not in ("AWAITING_UPLOAD", "UPLOAD_COMPLETE"):
            break
        time.sleep(5)
    existing[reference] = image
    return image["id"]


def place(owner: str, owner_id: str, placement_type: str, image_id: str) -> str:
    """Put the image on a version or custom page localization (`owner`: appStoreVersionLocalization
    or appCustomProductPageLocalization). A placement can't be edited: one of the same type that
    shows another image is deleted first."""
    current, _ = get_all(f"/v1/{owner}s/{owner_id}/placements",
                         {"filter[placementType]": placement_type, "include": "image", "limit": 50})
    for placement in current:
        shown = ((placement.get("relationships") or {}).get("image") or {}).get("data") or {}
        if shown.get("id") == image_id:
            return "unchanged"
    for placement in current:
        request(f"/v1/appAssetLibraryPlacements/{placement['id']}", method="DELETE")
    send("POST", "/v1/appAssetLibraryPlacements", {"data": {
        "type": "appAssetLibraryPlacements",
        "attributes": {"placementType": placement_type},
        "relationships": {
            owner: {"data": {"type": owner + "s", "id": owner_id}},
            "image": {"data": {"type": "appAssetLibraryImages", "id": image_id}},
        },
    }})
    return "placed"


def push_creatives(app: str, version: str | None, locales: list[str] | None, pages: bool, submit: bool) -> None:
    """The header and search art from screenshots/art/<locale>/ on every localization of the
    version (the latest one on the App Store by default: the art can change without a new
    version), and with `pages` on the custom pages' editable versions too (search-<page>.png,
    after push-custom-pages). With submit, sends the images App Review has not taken yet, and
    the page versions with `pages`, for review. A version already on the App Store takes only
    approved images: those show "after review", and running this again once App Review has
    approved them places them."""
    library = get(f"/v1/apps/{app}/assetLibrary")["data"]["id"]
    images, _ = get_all(f"/v1/appAssetLibraries/{library}/images", {"limit": 200})
    for image in images:
        # Our uploads App Store Connect refused: gone, so a fixed file uploads afresh.
        if (image["attributes"].get("referenceName") or "").startswith("tenra-") and image["attributes"].get("state") == "FAILED":
            request(f"/v1/appAssetLibraryImages/{image['id']}", method="DELETE")
    existing = {image["attributes"].get("referenceName"): image for image in images
                if image["attributes"].get("state") not in ("FAILED", "ARCHIVED")}
    used: set[str] = set()

    def art(locale: str, stem: str) -> Path | None:
        # A locale without its own art takes the art of the locale its screenshots come from
        # (en-GB: kk's, `screenshot_source`).
        for folder in dict.fromkeys([locale, screenshot_source(locale)]):
            path = ART / folder / f"{stem}.png"
            if path.exists():
                return path
        return None

    record = store_version(app, version)
    name = record["attributes"].get("versionString")
    localizations, _ = get_all(f"/v1/appStoreVersions/{record['id']}/appStoreVersionLocalizations", {"limit": 50})
    rows = []
    for item in sorted(localizations, key=lambda i: i["attributes"]["locale"]):
        locale = item["attributes"]["locale"]
        if locales and locale not in locales:
            continue
        for placement_type, stem in CREATIVES.items():
            path = art(locale, stem)
            if not path:
                rows.append([name, locale, stem, "no file"])
                continue
            image_id = library_image(library, existing, path)
            used.add(image_id)
            try:
                result = place("appStoreVersionLocalization", item["id"], placement_type, image_id)
            except ApiError as error:
                # A version on the App Store takes only an image App Review has approved: the
                # image goes to review first, and a run after the approval places it.
                if error.code != 409 or "APPROVED" not in str(error):
                    raise
                result = "after review"
            rows.append([name, locale, stem, result])
            print(f"{name} {locale} {stem}: {result}", flush=True)

    ready = []
    if pages:
        config = page_config()
        found, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
        by_name = {page["attributes"]["name"]: page for page in found}
        for page in config["customPages"]:
            record = by_name.get(page["name"])
            if not record:
                rows.append([page["name"], "", "", "no page: run push-custom-pages first"])
                continue
            page_version = editable_cpp_version(record["id"])
            page_locs, _ = get_all(
                f"/v1/appCustomProductPageVersions/{page_version['id']}/appCustomProductPageLocalizations", {"limit": 50})
            for item in page_locs:
                locale = item["attributes"]["locale"]
                if locales and locale not in locales:
                    continue
                for placement_type, stem in (("PRODUCT_PAGE_HEADER_ASSET", "header"),
                                             ("APP_STORE_SEARCH_RESULTS_ASSET", "search-" + page_slug(page["name"]))):
                    path = art(locale, stem)
                    if not path:
                        rows.append([page["name"], locale, stem, "no file"])
                        continue
                    image_id = library_image(library, existing, path)
                    used.add(image_id)
                    result = place("appCustomProductPageLocalization", item["id"], placement_type, image_id)
                    rows.append([page["name"], locale, stem, result])
                    print(f"{page['name']} {locale} {stem}: {result}", flush=True)
            ready.append(("appCustomProductPageVersion", page_version["id"]))
    table("Creative assets", ["Page", "Locale", "Art", "Result"], rows)

    if submit:
        # Every image placed here that App Review has not taken yet, from this run or an earlier one.
        waiting = [("appAssetLibraryImage", image_id) for image_id in sorted(used)
                   if get(f"/v1/appAssetLibraryImages/{image_id}")["data"]["attributes"].get("state")
                   in ("COMPLETE", "PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW", "REJECTED")]
        if not waiting and not ready:
            print("Nothing to submit.")
            return
        submit_for_review(app, waiting + ready, lenient={"appAssetLibraryImage"})


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
    elif command == "prepare-version":
        version = option("--version")
        if not version:
            sys.exit("prepare-version needs --version X.Y")
        prepare_version(app, version, option("--build"), int(option("--wait", 0)))
    elif command == "keywords":
        for locale in option("--locale", "en-US").split(","):
            keywords(app, locale)
    elif command == "metadata":
        metadata(app, option("--version"))
    elif command == "push-metadata":
        push_metadata(app, "--apply" in args)
    elif command == "custom-pages":
        custom_pages(app)
    elif command == "review-submissions":
        review_submissions(app)
    elif command == "push-custom-pages":
        push_custom_pages(app, "--submit" in args)
    elif command == "push-experiment":
        push_experiment(app, "--submit" in args, "--start" in args, "--stop" in args)
    elif command == "age-rating":
        age_rating(app, "--apply" in args)
    elif command == "push-version-screenshots":
        version = option("--version")
        if not version:
            sys.exit("push-version-screenshots needs --version X.Y")
        locales = option("--locale")
        push_version_screenshots(app, version, locales.split(",") if locales else None)
    elif command == "store-pages":
        store_pages(app, option("--version"))
    elif command == "push-creatives":
        locales = option("--locale")
        push_creatives(app, option("--version"), locales.split(",") if locales else None,
                       "--pages" in args, "--submit" in args)
    elif command == "subscription-prices":
        subscription_prices(app, option("--territory", "KAZ"))
    elif command == "push-price":
        product, price = option("--product"), option("--price")
        if not product or not price:
            sys.exit("push-price needs --product ID --price N [--territory KAZ] [--start YYYY-MM-DD]")
        push_price(app, product, option("--territory", "KAZ"), price, option("--start"), "--apply" in args)
    elif command == "review-notes":
        version = option("--version")
        if not version:
            sys.exit("review-notes needs --version X.Y")
        review_notes(app, version, "--apply" in args)
    elif command == "prepare-review":
        version = option("--version")
        if not version:
            sys.exit("prepare-review needs --version X.Y")
        prepare_review(app, version)
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
