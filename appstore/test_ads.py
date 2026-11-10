#!/usr/bin/env python3
"""Offline tests of appstore/ads.py: python3 -I appstore/test_ads.py

No network: a throwaway EC key is made at run time, and urlopen is replaced by a fake Apple Ads
whose answers follow the examples in Apple's Platform API documentation.
"""

import base64
import contextlib
import importlib.util
import io
import json
import os
import unittest
import urllib.error
import urllib.parse
from datetime import date
from email.message import Message
from pathlib import Path
from unittest import mock

import jwt
from cryptography.hazmat.primitives import serialization
from cryptography.hazmat.primitives.asymmetric import ec

spec = importlib.util.spec_from_file_location("ads", Path(__file__).resolve().with_name("ads.py"))
ads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(ads)

KEY = ec.generate_private_key(ec.SECP256R1())
SEC1 = KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.TraditionalOpenSSL,
                         serialization.NoEncryption()).decode()
PKCS8 = KEY.private_bytes(serialization.Encoding.PEM, serialization.PrivateFormat.PKCS8,
                          serialization.NoEncryption()).decode()
ENV = {
    "ADS_CLIENT_ID": "SEARCHADS.11111111-2222-3333-4444-555555555555",
    "ADS_TEAM_ID": "SEARCHADS.66666666-7777-8888-9999-000000000000",
    "ADS_KEY_ID": "aaaaaaaa-bbbb-cccc-dddd-eeeeeeeeeeee",
    "ADS_PRIVATE_KEY": SEC1,
}
TOKEN = "fake-access-token-0123456789"
ACCOUNT = 123456789
CATEGORY, DISCOVERY = 444555666, 444555777
GENERAL, SUBSCRIPTIONS, SEARCH_MATCH, BROAD = 555666001, 555666002, 555666003, 555666004


def usd(amount: str) -> dict:
    return {"amount": amount, "currency": "USD"}


def campaign(id_: int, name: str, budget: str) -> dict:
    return {"id": id_, "name": name, "adAccountId": ACCOUNT, "promotedObjectType": "APPSTORE_APP",
            "promotedObjectId": "6761530361", "status": "ENABLED", "displayStatus": "RUNNING",
            "dailyBudget": {"value": usd(budget)}, "systemStatusReasons": [],
            "targeting": {"countryOrRegion": {"include": ["KZ"]}, "supplyPlacement": {"include": ["APPSTORE_SEARCH_RESULTS"]}},
            "bidStrategy": {"bidStrategyType": "MANUAL_CPT", "bidStrategyGoal": "TAP"}}


def group(id_: int, campaign_id: int, name: str, bid: str, search_match: bool = False) -> dict:
    return {"id": id_, "campaignId": campaign_id, "name": name, "status": "ENABLED", "displayStatus": "RUNNING",
            "automatedKeywordsOptIn": search_match,
            "bidStrategy": {"bidStrategyType": "MANUAL_CPT", "bidStrategyGoal": "TAP", "bid": usd(bid)}}


def row(metadata: dict, impressions: int, taps: int, tap_installs: int, view_installs: int, spend: str) -> dict:
    return {"metadata": metadata, "totalMetrics": {
        "localSpend": usd(spend), "impressions": impressions, "taps": taps, "tapInstalls": tap_installs,
        "viewInstalls": view_installs, "totalInstalls": tap_installs + view_installs}}


def filters_of(body: dict) -> dict:
    return {f["field"]: (f["operator"], f.get("value")) for f in body.get("filters") or []}


class FakeAds:
    """Answers like api.ads.apple.com and appleid.apple.com, and records every request."""

    def __init__(self, throttle_first_query: bool = False, fail: dict | None = None):
        self.requests = []
        self.throttle = throttle_first_query
        self.fail = fail or {}  # path → (status, body)
        self.negatives = [
            {"id": 1, "campaignId": DISCOVERY, "text": "tenra", "matchType": "EXACT", "status": "ENABLED"},
            {"id": 2, "campaignId": DISCOVERY, "adGroupId": BROAD, "text": "free", "matchType": "BROAD", "status": "ENABLED"},
        ]

    def __call__(self, req, timeout=None):
        body = req.data
        record = {"method": req.get_method(), "url": req.full_url,
                  "headers": {k.lower(): v for k, v in req.header_items()},
                  "body": json.loads(body) if body and req.full_url.startswith(ads.API) else body}
        self.requests.append(record)
        if req.full_url == ads.TOKEN_URL:
            return self.answer({"access_token": TOKEN, "token_type": "Bearer", "expires_in": 3600, "scope": "searchadsorg"})
        path = req.full_url[len(ads.API):]
        if self.throttle and path.endswith("/query"):
            self.throttle = False
            headers = Message()
            headers["Retry-After"] = "0"
            raise urllib.error.HTTPError(req.full_url, 429, "Too Many Requests", headers,
                                         io.BytesIO(b'{"error": {"code": "rate_limit_exceeded"}}'))
        if path in self.fail:
            status, payload = self.fail[path]
            raise urllib.error.HTTPError(req.full_url, status, "Error", Message(), io.BytesIO(json.dumps(payload).encode()))
        return self.answer(self.route(record["method"], path, record["body"] or {}))

    @staticmethod
    def answer(payload: dict):
        return contextlib.closing(io.BytesIO(json.dumps(payload).encode()))

    def route(self, method: str, path: str, body: dict) -> dict:
        where = filters_of(body)
        campaign_id = int((where.get("campaignId") or (None, 0))[1] or 0)
        if (method, path) == ("GET", "/acls"):
            return {"result": {"acls": [{"adAccount": {"id": ACCOUNT, "name": "Tenra", "orgId": 1}, "roles": ["API Account Manager"]}]}}
        if path == "/campaigns/query":
            return {"result": [campaign(CATEGORY, "KZ-Category", "4.00"), campaign(DISCOVERY, "KZ-Discovery", "2.50")],
                    "pagination": {"totalCount": 2, "offset": 0, "pageSize": 1000}}
        if path == "/adgroups/query":
            groups = [group(GENERAL, CATEGORY, "Общие", "0.40"), group(SUBSCRIPTIONS, CATEGORY, "Подписки", "0.30"),
                      group(SEARCH_MATCH, DISCOVERY, "Search Match", "0.20", True), group(BROAD, DISCOVERY, "Broad", "0.20")]
            return {"result": [g for g in groups if not campaign_id or g["campaignId"] == campaign_id]}
        if path == "/reports/apps/campaigns/query":
            return {"result": {"rows": [row({"id": CATEGORY, "name": "KZ-Category"}, 1000, 50, 10, 2, "12.50"),
                                        row({"id": DISCOVERY, "name": "KZ-Discovery"}, 400, 20, 0, 1, "4.00")]}}
        if path == "/reports/apps/adgroups/query":
            rows = {CATEGORY: [row({"id": GENERAL, "campaignId": CATEGORY}, 900, 45, 10, 2, "11.00")],
                    DISCOVERY: [row({"id": SEARCH_MATCH, "campaignId": DISCOVERY}, 400, 20, 0, 1, "4.00")]}
            return {"result": {"rows": rows[campaign_id]}}
        if path == "/reports/apps/searchterms/query":
            return {"result": {"rows": [
                row({"searchTermText": "учет денег", "searchTermSource": "AUTO", "adGroup": {"name": "Search Match"}}, 100, 8, 3, 0, "1.60"),
                row({"searchTermText": "калькулятор", "searchTermSource": "AUTO", "adGroup": {"name": "Search Match"}}, 300, 12, 0, 0, "2.40"),
                row({"searchTermText": None, "searchTermSource": "AUTO", "adGroup": {"name": "Search Match"}}, 5, 0, 0, 0, "0"),
            ]}}
        if path == "/keywords/query":
            return {"result": [{"id": 7, "adGroupId": GENERAL, "text": "бюджет", "matchType": "EXACT", "status": "ENABLED", "bid": usd("0.45")},
                               {"id": 8, "adGroupId": GENERAL, "text": "расходы", "matchType": "EXACT", "status": "ENABLED"}]}
        if path == "/reports/apps/keywords/query":
            return {"result": {"rows": [row({"id": 7}, 3000, 120, 0, 0, "50.00")]}}
        if path == "/negative-keywords/query":
            null = where["adGroupId"][0] == "IS_NULL"
            return {"result": [n for n in self.negatives if n["campaignId"] == campaign_id and ("adGroupId" not in n) == null]}
        if path in ("/negative-keywords/bulk-create", "/keywords/bulk-create"):
            return {"result": [{"correlationId": item["correlationId"], "operation": "CREATE", "success": True,
                                "result": {"id": 900 + item["correlationId"], **item["data"]}} for item in body["items"]]}
        if (method, path) == ("GET", f"/ad-accounts/{ACCOUNT}"):
            return {"result": {"id": ACCOUNT, "currency": "USD", "timezone": "Asia/Almaty"}}
        raise AssertionError(f"unexpected {method} {path}")


class AdsTest(unittest.TestCase):
    def setUp(self):
        ads._token.update(value="", exp=0)
        ads._account.clear()

    def run_ads(self, argv: list[str], actions: bool = False, env: dict | None = None, fake: FakeAds | None = None):
        fake = fake or FakeAds()
        environment = dict(ENV if env is None else env)
        if actions:
            environment["GITHUB_ACTIONS"] = "true"
        out = io.StringIO()
        with mock.patch.dict(os.environ, environment, clear=True), \
                mock.patch.object(ads.urllib.request, "urlopen", fake), \
                mock.patch.object(ads.time, "sleep", lambda seconds: None), \
                contextlib.redirect_stdout(out):
            ads.main(argv)
        text = out.getvalue()
        for secret in (TOKEN, "".join(SEC1.split("\n")[1:2])):
            self.assertNotIn(secret, text)
        secrets = [urllib.parse.parse_qs(r["body"].decode())["client_secret"][0] for r in fake.requests if r["url"] == ads.TOKEN_URL]
        for secret in secrets:
            self.assertNotIn(secret, text)
        return text, fake

    def api_calls(self, fake: FakeAds) -> list[dict]:
        return [r for r in fake.requests if r["url"].startswith(ads.API)]

    # Credentials

    def test_private_key_forms(self):
        lines = SEC1.strip().split("\n")
        forms = {
            "pem": SEC1,
            "escaped newlines": SEC1.replace("\n", "\\n"),
            "one line with spaces": " ".join(lines),
            "base64 of the file": base64.b64encode(SEC1.encode()).decode(),
            "pkcs8": PKCS8,
            "with EC PARAMETERS": "-----BEGIN EC PARAMETERS-----\nBggqhkjOPQMBBw==\n-----END EC PARAMETERS-----\n" + SEC1,
        }
        for name, value in forms.items():
            with self.subTest(name), mock.patch.dict(os.environ, {"ADS_PRIVATE_KEY": value}):
                pem = ads.private_key()
                loaded = serialization.load_pem_private_key(pem.encode(), password=None)
                self.assertEqual(loaded.private_numbers(), KEY.private_numbers())
        with mock.patch.dict(os.environ, {"ADS_PRIVATE_KEY": "not a key"}), self.assertRaises(SystemExit) as stop:
            ads.private_key()
        self.assertIn("paste all of private-key.pem", str(stop.exception))

    def test_client_secret_claims(self):
        now = 1_800_000_000
        with mock.patch.dict(os.environ, ENV):
            secret = ads.client_secret(now)
        header = jwt.get_unverified_header(secret)
        self.assertEqual(header["alg"], "ES256")
        self.assertEqual(header["kid"], ENV["ADS_KEY_ID"])
        claims = jwt.decode(secret, KEY.public_key(), algorithms=["ES256"], audience="https://appleid.apple.com",
                            options={"verify_exp": False, "verify_iat": False})
        self.assertEqual(claims["sub"], ENV["ADS_CLIENT_ID"])
        self.assertEqual(claims["iss"], ENV["ADS_TEAM_ID"])
        self.assertEqual(claims["iat"], now)
        self.assertTrue(0 < claims["exp"] - claims["iat"] <= 180 * 86400)

    def test_token_request(self):
        with mock.patch.dict(os.environ, ENV):
            req = ads.token_request(1_800_000_000)
        self.assertEqual(req.full_url, "https://appleid.apple.com/auth/oauth2/token")
        self.assertEqual(req.get_method(), "POST")
        self.assertEqual(req.get_header("Content-type"), "application/x-www-form-urlencoded")
        form = urllib.parse.parse_qs(req.data.decode())
        self.assertEqual(form["grant_type"], ["client_credentials"])
        self.assertEqual(form["client_id"], [ENV["ADS_CLIENT_ID"]])
        self.assertEqual(form["scope"], ["searchadsorg"])
        self.assertEqual(len(form["client_secret"][0].split(".")), 3)

    def test_missing_credentials(self):
        for argv in (["campaigns"], ["report"], ["search-terms", "--campaign", "x"], ["negatives", "--campaign", "x", "--add", "a"]):
            with self.subTest(argv), self.assertRaises(SystemExit) as stop:
                self.run_ads(argv, env={"ADS_CLIENT_ID": "x"})
            self.assertIn("ADS_TEAM_ID, ADS_KEY_ID, ADS_PRIVATE_KEY not set", str(stop.exception))
        with self.assertRaises(SystemExit) as stop:
            self.run_ads(["search-terms"], env={})
        self.assertIn("needs --campaign", str(stop.exception))

    # Requests

    def test_request_headers(self):
        req = ads.build_request("POST", "/campaigns/query", {"pagination": {"offset": 0}}, "tok", ACCOUNT)
        self.assertEqual(req.full_url, "https://api.ads.apple.com/v1/campaigns/query")
        self.assertEqual(req.get_header("Authorization"), "Bearer tok")
        self.assertEqual(req.get_header("X-ap-context"), f"adAccountId={ACCOUNT}")
        self.assertEqual(req.get_header("Content-type"), "application/json")
        self.assertIsNone(ads.build_request("GET", "/acls", None, "tok", None).get_header("X-ap-context"))

    def test_report_time_range(self):
        today = date(2026, 11, 9)
        week = ads.report_body(7, [ads.eq("campaignId", "1")], today=today)
        self.assertEqual(week["timeRange"], {"start": "2026-11-02", "end": "2026-11-08", "timeZone": "ORTZ", "granularity": "DAILY"})
        self.assertEqual(week["filters"], [{"field": "campaignId", "operator": "EQUALS", "value": "1"}])
        self.assertNotIn("granularity", ads.report_body(1, None, today=today)["timeRange"])
        self.assertEqual(ads.report_body(120, None, today=today)["timeRange"]["granularity"], "WEEKLY")

    def test_find_and_terms(self):
        items = [{"id": 1, "name": "KZ-Category"}, {"id": 2, "name": "KZ-Discovery"}, {"id": 3, "name": "KZ-Brand"}]
        self.assertEqual(ads.find(items, "2", "campaign")["id"], 2)
        self.assertEqual(ads.find(items, "kz-brand", "campaign")["id"], 3)
        self.assertEqual(ads.find(items, "discovery", "campaign")["id"], 2)
        with self.assertRaises(SystemExit):
            ads.find(items, "KZ", "campaign")
        self.assertEqual(ads.split_terms("учет  расходов, бюджет,,Бюджет\nqalta "), ["учет расходов", "бюджет", "qalta"])

    # Commands against the fake API

    def test_campaigns(self):
        text, fake = self.run_ads(["campaigns"])
        calls = self.api_calls(fake)
        self.assertEqual((calls[0]["method"], calls[0]["url"]), ("GET", ads.API + "/acls"))
        self.assertNotIn("x-ap-context", calls[0]["headers"])
        self.assertTrue(all(c["headers"]["x-ap-context"] == f"adAccountId={ACCOUNT}" for c in calls[1:]))
        self.assertEqual(calls[1]["body"]["pagination"]["pageSize"], 1000)
        self.assertIn("| 444555777 | KZ-Discovery | RUNNING | KZ | search_results | MANUAL_CPT | 2.50 USD |", text)
        self.assertIn("| KZ-Discovery | 555666003 | Search Match | RUNNING | on | 0.20 USD |", text)
        hidden, _ = self.run_ads(["campaigns"], actions=True)
        self.assertNotIn("USD", hidden)
        self.assertIn("| MANUAL_CPT | hidden |", hidden)

    def test_report(self):
        text, fake = self.run_ads(["report", "--days", "7"])
        paths = [c["url"][len(ads.API):] for c in self.api_calls(fake)]
        self.assertEqual(paths.count("/reports/apps/adgroups/query"), 2)
        for c in self.api_calls(fake):
            if c["url"].endswith("/reports/apps/adgroups/query"):
                self.assertIn(filters_of(c["body"])["campaignId"][1], (str(CATEGORY), str(DISCOVERY)))
        # KZ-Category: 1000 impressions, 50 taps (5.0%), 10 + 2 installs, 20.0% conversion, 12.50 spent.
        self.assertIn("| **KZ-Category** | all | 1000 | 50 | 5.0% | 10 | 2 | 20.0% | 12.50 USD | 0.25 USD | 1.25 USD | 1.04 USD |", text)
        self.assertIn("|  | Подписки | 0 | 0 | - | 0 | 0 | - | 0.00 | - | - | - |", text)
        self.assertIn("| **Total** |  | 1400 | 70 | 5.0% | 10 | 3 | 14.3% | 16.50 USD |", text)
        hidden, _ = self.run_ads(["report", "--days", "7"], actions=True)
        self.assertNotIn("USD", hidden)
        self.assertNotIn("12.50", hidden)
        self.assertIn("money hidden in Actions", hidden)

    def test_search_terms(self):
        text, fake = self.run_ads(["search-terms", "--campaign", "discovery", "--days", "7"])
        call = next(c for c in self.api_calls(fake) if c["url"].endswith("/reports/apps/searchterms/query"))
        self.assertEqual(call["body"]["timeRange"]["timeZone"], "ORTZ")
        self.assertEqual(filters_of(call["body"])["campaignId"], ("EQUALS", str(DISCOVERY)))
        lines = text.splitlines()
        first = next(i for i, line in enumerate(lines) if "калькулятор" in line)
        self.assertLess(first, next(i for i, line in enumerate(lines) if "учет денег" in line))
        self.assertIn("| калькулятор | Search Match | Search Match | 300 | 12 | 0 | 0 | 2.40 USD | taps, no installs |", text)
        self.assertIn("(low volume, withheld by Apple)", text)
        self.assertIn("candidates for negative keywords: калькулятор", text)
        self.assertIn("candidates for exact keywords: учет денег", text)

    def test_keywords(self):
        text, _ = self.run_ads(["keywords", "--campaign", "KZ-Category"])
        self.assertIn("| Общие | бюджет | EXACT | ENABLED | 0.45 USD | 3000 | 120 | 0 | 0 | 100+ taps, no installs: pause? |", text)
        self.assertIn("| Общие | расходы | EXACT | ENABLED | - | 0 | 0 | 0 | 0 |  |", text)
        hidden, _ = self.run_ads(["keywords", "--campaign", "KZ-Category"], actions=True)
        self.assertNotIn("0.45", hidden)

    def test_negatives_dry_run(self):
        text, fake = self.run_ads(["negatives", "--campaign", "discovery", "--add", "Tenra, новое слово"])
        self.assertFalse(any(c["url"].endswith("bulk-create") for c in fake.requests))
        self.assertIn("| campaign | tenra | EXACT | ENABLED |", text)
        self.assertIn("| ad group Broad | free | BROAD | ENABLED |", text)
        self.assertIn("| Tenra | EXACT | already there |", text)
        self.assertIn("| новое слово | EXACT | add |", text)
        self.assertIn("Dry run: nothing written. With --apply 1 would be added.", text)

    def test_negatives_apply(self):
        text, fake = self.run_ads(["negatives", "--campaign", "discovery", "--add", "tenra, новое слово, free", "--match", "exact", "--apply"])
        created = [c for c in fake.requests if c["url"].endswith("/negative-keywords/bulk-create")]
        self.assertEqual(len(created), 1)
        self.assertEqual(created[0]["body"], {"allowPartialSuccess": True, "items": [
            {"correlationId": 0, "data": {"campaignId": DISCOVERY, "text": "новое слово", "matchType": "EXACT", "status": "ENABLED"}},
            {"correlationId": 1, "data": {"campaignId": DISCOVERY, "text": "free", "matchType": "EXACT", "status": "ENABLED"}},
        ]})
        self.assertIn("| новое слово | EXACT | added |", text)

    def test_negatives_ad_group_level(self):
        _, fake = self.run_ads(["negatives", "--campaign", "discovery", "--adgroup", "broad", "--add", "free, cheap", "--match", "BROAD", "--apply"])
        created = next(c for c in fake.requests if c["url"].endswith("/negative-keywords/bulk-create"))
        self.assertEqual([i["data"] for i in created["body"]["items"]],
                         [{"adGroupId": BROAD, "text": "cheap", "matchType": "BROAD", "status": "ENABLED"}])

    def test_add_keywords(self):
        text, fake = self.run_ads(["add-keywords", "--campaign", "category", "--adgroup", "Общие",
                                   "--add", "учет денег, бюджет", "--bid", "0.4", "--apply"])
        created = next(c for c in fake.requests if c["url"].endswith("/keywords/bulk-create"))
        self.assertEqual(created["body"]["items"], [{"correlationId": 0, "data": {
            "adGroupId": GENERAL, "text": "учет денег", "matchType": "EXACT", "status": "ENABLED", "bid": usd("0.40")}}])
        self.assertIn('negatives --campaign KZ-Discovery --add "учет денег" --apply', text)
        hidden, fake = self.run_ads(["add-keywords", "--campaign", "category", "--adgroup", "Общие",
                                     "--add", "учет денег", "--bid", "0.4"], actions=True)
        self.assertNotIn("0.40", hidden)
        self.assertFalse(any(c["url"].endswith("bulk-create") for c in fake.requests))

    def test_errors(self):
        documented = {"error": {"code": "VALIDATION_ERROR", "message": "Validation errors found", "details": [
            {"code": "DUPLICATE_NAME", "message": "bid 0.45 too low", "info": {"field": "bid"}}]}}
        gateway = {"data": None, "error": {"errors": [{"messageCode": "UNAUTHORIZED", "message": "No authentication header provided", "field": ""}]}}
        with mock.patch.dict(os.environ, {}, clear=True):
            self.assertEqual(ads.error_text(json.dumps(documented)),
                             "VALIDATION_ERROR: Validation errors found; DUPLICATE_NAME: bid 0.45 too low (bid)")
            self.assertEqual(ads.error_text(json.dumps(gateway).encode()), "UNAUTHORIZED: No authentication header provided")
        with mock.patch.dict(os.environ, {"GITHUB_ACTIONS": "true"}):
            self.assertNotIn("0.45", ads.error_text(json.dumps(documented)))
        # A failed create is not sent twice: it may have landed.
        fake = FakeAds(fail={"/negative-keywords/bulk-create": (500, documented)})
        with self.assertRaises(ads.ApiError) as stop:
            self.run_ads(["negatives", "--campaign", "discovery", "--add", "x", "--apply"], fake=fake)
        self.assertEqual(stop.exception.code, 500)
        self.assertEqual(sum(r["url"].endswith("bulk-create") for r in fake.requests), 1)

    def test_rate_limit_is_retried(self):
        text, fake = self.run_ads(["campaigns"], fake=FakeAds(throttle_first_query=True))
        queries = [c for c in fake.requests if c["url"].endswith("/campaigns/query")]
        self.assertEqual(len(queries), 2)
        self.assertIn("HTTP 429, retrying", text)


if __name__ == "__main__":
    unittest.main(verbosity=2)
