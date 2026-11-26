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


def reply(rid, approved=True, to="1790000000000000001", text="Мы делаем Tenra, посмотрите."):
    return {"id": rid, "replyToId": to, "text": text, "approved": approved}


class ReplyTests(unittest.TestCase):
    def test_approved_and_unpublished_in_order(self):
        replies = [reply("a"), reply("b", approved=False), reply("c")]
        self.assertEqual([r["id"] for r in threads.waiting_replies(replies, {"a": {}})], ["c"])

    def test_a_few_per_run(self):
        replies = [reply(str(i)) for i in range(10)]
        self.assertEqual(len(threads.waiting_replies(replies, {})), threads.REPLIES_PER_RUN)

    def test_needs_the_post_it_answers(self):
        self.assertTrue(threads.problems([], [reply("a", to="")]))

    def test_ids_unique_across_posts_and_replies(self):
        self.assertTrue(threads.problems([post("a")], [reply("a")]))

    def test_reply_text_rules(self):
        self.assertTrue(threads.problems([], [reply("a", text="Tenra — это")]))


class MediaTests(unittest.TestCase):
    def setUp(self):
        import tempfile
        self.tmp = tempfile.TemporaryDirectory()
        self.root = Path(self.tmp.name)
        (self.root / "docs/public/media/threads").mkdir(parents=True)
        (self.root / "docs/public/media/threads/deposit.mp4").write_bytes(b"0" * 1024)
        (self.root / "social").mkdir()
        (self.root / "social/card.png").write_bytes(b"png")

    def tearDown(self):
        self.tmp.cleanup()

    def test_video_in_the_site(self):
        p = dict(post("v"), video="docs/public/media/threads/deposit.mp4")
        self.assertEqual(threads.media_problems(p, self.root), [])
        self.assertEqual(threads.media_url(p),
                         ("VIDEO", "https://dkicekeeper.github.io/Tenra/media/threads/deposit.mp4"))

    def test_video_outside_the_site_or_missing(self):
        self.assertTrue(threads.media_problems(dict(post("v"), video="social/card.png"), self.root))
        self.assertTrue(threads.media_problems(dict(post("v"), video="docs/public/media/threads/none.mp4"), self.root))

    def test_one_medium(self):
        p = dict(post("v"), video="docs/public/media/threads/deposit.mp4", image="social/card.png")
        self.assertTrue(threads.media_problems(p, self.root))

    def test_image_and_text(self):
        self.assertEqual(threads.media_url(dict(post("i"), image="social/card.png"))[0], "IMAGE")
        self.assertEqual(threads.media_url(post("t")), (None, None))


class OneADayTests(unittest.TestCase):
    def test_a_post_today_stops_the_next(self):
        posts = [post("a"), post("b")]
        # 2026-12-01 19:30 UTC is 02.12 00:30 in Almaty: counts for the 2nd, not the 1st.
        posted = {"a": {"at": "2026-12-01T19:30:00+00:00"}}
        self.assertTrue(threads.posted_today(posts, posted, "2026-12-02"))
        self.assertFalse(threads.posted_today(posts, posted, "2026-12-01"))

    def test_a_reply_today_does_not_count(self):
        posted = {"r-1": {"at": "2026-12-01T10:00:00+00:00"}}
        self.assertFalse(threads.posted_today([post("a")], posted, "2026-12-01"))


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
        self.assertEqual(threads.problems(data["posts"], data.get("replies", [])), [])


if __name__ == "__main__":
    unittest.main()
