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
    python3 appstore/asc.py custom-pages            custom product pages and their review state
    python3 appstore/asc.py push-custom-pages [--submit]
                                                    create/update the pages in product-pages.json
    python3 appstore/asc.py push-experiment [--submit | --start]
                                                    the product page test in product-pages.json
    python3 appstore/asc.py age-rating [--apply]    the age rating answers; --apply sets Tenra's
                                                    (needs a version in preparation)
    python3 appstore/asc.py push-version-screenshots --version 1.6 [--locale ru,en-US]
                                                    the version's own 6.9" screenshots, the frames
                                                    of `defaultOrder` in screenshot_captions.json
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


def submit_for_review(app: str, items: list[tuple[str, str]]) -> None:
    """Add (relationship, id) items to the open review submission, or a new one, and submit it."""
    open_ones, _ = get_all("/v1/reviewSubmissions",
                           {"filter[app]": app, "filter[platform]": "IOS", "filter[state]": "READY_FOR_REVIEW"})
    submission = open_ones[0] if open_ones else send("POST", "/v1/reviewSubmissions", {"data": {
        "type": "reviewSubmissions", "attributes": {"platform": "IOS"},
        "relationships": {"app": {"data": {"type": "apps", "id": app}}},
    }})["data"]
    types = {"appCustomProductPageVersion": "appCustomProductPageVersions",
             "appStoreVersionExperimentV2": "appStoreVersionExperiments"}
    for relationship, item_id in items:
        try:
            send("POST", "/v1/reviewSubmissionItems", {"data": {"type": "reviewSubmissionItems", "relationships": {
                "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission["id"]}},
                relationship: {"data": {"type": types[relationship], "id": item_id}},
            }}})
        except ApiError as error:
            if error.code != 409:   # 409: already in this submission
                raise
    send("PATCH", f"/v1/reviewSubmissions/{submission['id']}", {"data": {
        "type": "reviewSubmissions", "id": submission["id"], "attributes": {"submitted": True},
    }})
    print(f"Submitted for review: {len(items)} item(s).")


def custom_pages(app: str) -> None:
    pages, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    rows = []
    for page in pages:
        versions, _ = get_all(f"/v1/appCustomProductPages/{page['id']}/appCustomProductPageVersions", {"limit": 10})
        states = ", ".join(v["attributes"].get("state", "?") for v in versions)
        rows.append([page["attributes"].get("name"), page["attributes"].get("visible"), states,
                     page["attributes"].get("url") or ""])
    table("Custom product pages", ["Name", "Visible", "Versions", "URL"], rows)


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
    screenshots and keywords per locale. With submit, sends the edited versions for review."""
    config = page_config()
    files = {(page["name"], locale): frame_files(config, page["frames"], locale)
             for page in config["customPages"] for locale in page["locales"]}
    existing, _ = get_all(f"/v1/apps/{app}/appCustomProductPages", {"limit": 50})
    by_name = {page["attributes"]["name"]: page for page in existing}
    rows, ready = [], []
    for page in config["customPages"]:
        record = by_name.get(page["name"])
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
                            for locale in page["locales"]]},
                    }},
                    *[{"type": "appCustomProductPageLocalizations", "id": "${" + locale + "}",
                       "attributes": {"locale": locale, "promotionalText": meta["promotionalText"]}}
                      for locale, meta in page["locales"].items()],
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
                localization = send("POST", "/v1/appCustomProductPageLocalizations", {"data": {
                    "type": "appCustomProductPageLocalizations",
                    "attributes": {"locale": locale, "promotionalText": meta["promotionalText"]},
                    "relationships": {"appCustomProductPageVersion": {
                        "data": {"type": "appCustomProductPageVersions", "id": version["id"]}}},
                }})["data"]
            shots = put_screenshots(screenshot_set("appCustomProductPageLocalization", localization["id"]),
                                    files[(page["name"], locale)])
            words = link_keywords(app, localization["id"], locale, meta.get("keywords", []))
            rows.append([page["name"], locale, shots, words])
        ready.append(("appCustomProductPageVersion", version["id"]))
    table("Custom product pages pushed", ["Page", "Locale", "Screenshots", "Keywords"], rows)
    if submit:
        submit_for_review(app, ready)


def push_experiment(app: str, submit: bool, start: bool) -> None:
    """Create or update the product page optimization test in appstore/product-pages.json; with
    submit, send it for review; with start, start it once App Review has approved it."""
    config = page_config()
    test = config["experiment"]
    locales = sorted(path.name for path in (ROOT / "screenshots" / "final").iterdir() if path.is_dir())
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


# Version screenshots -----------------------------------------------------------------------------

CAPTIONS = ROOT / "scripts" / "screenshot_captions.json"


def push_version_screenshots(app: str, version: str, locales: list[str] | None) -> None:
    """The version's own 6.9" screenshots: per locale, the frames of `defaultOrder` (or the
    locale's own order) from screenshots/final/<locale>/. Only a version in preparation."""
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
        settings = captions["locales"].get(locale, {})
        frames = settings.get("order") or captions["defaultOrder"]
        files = frame_files(config, frames, locale)
        print(f"{locale}: {len(files)} frames", flush=True)
        set_id = screenshot_set("appStoreVersionLocalization", item["id"])
        result = put_screenshots(set_id, files)
        print(f"{locale}: {result}", flush=True)
        rows.append([locale, len(files), result])
    table(f"Screenshots, {version}", ["Locale", "Frames", "Result"], rows)


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
    elif command == "custom-pages":
        custom_pages(app)
    elif command == "push-custom-pages":
        push_custom_pages(app, "--submit" in args)
    elif command == "push-experiment":
        push_experiment(app, "--submit" in args, "--start" in args)
    elif command == "age-rating":
        age_rating(app, "--apply" in args)
    elif command == "push-version-screenshots":
        version = option("--version")
        if not version:
            sys.exit("push-version-screenshots needs --version X.Y")
        locales = option("--locale")
        push_version_screenshots(app, version, locales.split(",") if locales else None)
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
