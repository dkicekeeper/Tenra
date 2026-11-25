#!/usr/bin/env python3
"""Offline tests of scripts/threads.py: python3 -I scripts/test_threads.py"""

import importlib.util
import json
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("threads", Path(__file__).resolve().with_name("threads.py"))
threads = importlib.util.module_from_spec(spec)
spec.loader.exec_module(threads)


def post(pid, approved=True, not_before=None, text="Текст поста."):
    item = {"id": pid, "text": text, "approved": approved}
    if not_before:
        item["notBefore"] = not_before
    return item


class NextPostTests(unittest.TestCase):
    def test_first_approved_in_order(self):
        posts = [post("a", approved=False), post("b"), post("c")]
        self.assertEqual(threads.next_post(posts, {}, "2026-12-01")["id"], "b")

    def test_skips_published(self):
        posts = [post("a"), post("b")]
        self.assertEqual(threads.next_post(posts, {"a": {}}, "2026-12-01")["id"], "b")

    def test_waits_for_its_date(self):
        posts = [post("a", not_before="2026-12-05"), post("b")]
        self.assertEqual(threads.next_post(posts, {}, "2026-12-01")["id"], "b")
        self.assertEqual(threads.next_post(posts, {}, "2026-12-05")["id"], "a")

    def test_nothing_waiting(self):
        self.assertIsNone(threads.next_post([post("a", approved=False)], {}, "2026-12-01"))


class ProblemTests(unittest.TestCase):
    def test_clean_post(self):
        self.assertEqual(threads.problems([post("a")]), [])

    def test_too_long(self):
        self.assertTrue(threads.problems([post("a", text="я" * 501)]))

    def test_em_dash_and_emoji(self):
        found = threads.problems([post("a", text="Деньги — это"), post("b", text="Привет \U0001F600")])
        self.assertEqual(len(found), 2)

    def test_twice_the_same_id(self):
        self.assertTrue(threads.problems([post("a"), post("a")]))

    def test_bad_date(self):
        self.assertTrue(threads.problems([post("a", not_before="1 декабря")]))

    def test_the_posts_file(self):
        data = json.loads((threads.ROOT / "social" / "threads.json").read_text(encoding="utf-8"))
        self.assertEqual(threads.problems(data["posts"]), [])


if __name__ == "__main__":
    unittest.main()
