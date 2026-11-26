#!/usr/bin/env python3
"""Offline tests of scripts/threads_video.py: python3 -I scripts/test_threads_video.py"""

import importlib.util
import json
import re
import unittest
from pathlib import Path

spec = importlib.util.spec_from_file_location("threads_video", Path(__file__).resolve().with_name("threads_video.py"))
tv = importlib.util.module_from_spec(spec)
spec.loader.exec_module(tv)

MARKS = {"home": 20.0, "q-month": 35.0, "a-month": 44.0}


class ResolveTests(unittest.TestCase):
    def test_mark_with_offset(self):
        self.assertAlmostEqual(tv.resolve("q-month@-1.5", MARKS), 33.5)
        self.assertAlmostEqual(tv.resolve("q-month@+2", MARKS), 37.0)

    def test_mark_alone_and_seconds(self):
        self.assertEqual(tv.resolve("home", MARKS), 20.0)
        self.assertEqual(tv.resolve(12.5, MARKS), 12.5)

    def test_unknown_mark(self):
        with self.assertRaises(ValueError):
            tv.resolve("q-loan@+1", MARKS)


class TimelineTests(unittest.TestCase):
    def test_captions_follow_segments(self):
        cuts, captions = tv.timeline([
            {"from": "a-month@0", "to": "a-month@+2", "caption": "Первая"},
            {"from": "q-month@-1", "to": "q-month@+5", "speed": 2.0, "caption": "Вторая"},
        ], MARKS)
        self.assertEqual(cuts, [(44.0, 46.0, 1.0), (34.0, 40.0, 2.0)])
        self.assertEqual(captions, [("Первая", 0.0, 2.0), ("Вторая", 2.0, 5.0)])

    def test_null_caption_keeps_the_one_before(self):
        _, captions = tv.timeline([
            {"from": 0, "to": 2, "caption": "Одна"},
            {"from": 5, "to": 6, "caption": None},
        ], MARKS)
        self.assertEqual(captions, [("Одна", 0.0, 3.0)])

    def test_backwards_segment(self):
        with self.assertRaises(ValueError):
            tv.timeline([{"from": "a-month@0", "to": "q-month@0", "caption": "x"}], MARKS)


class WrapTests(unittest.TestCase):
    measure = staticmethod(len)

    def test_one_line_when_it_fits(self):
        self.assertEqual(tv.wrap(self.measure, "А если внести досрочно?", 30), ["А если внести досрочно?"])

    def test_two_even_lines(self):
        self.assertEqual(tv.wrap(self.measure, "Депозит растёт каждый день", 22), ["Депозит растёт", "каждый день"])

    def test_too_long(self):
        with self.assertRaises(ValueError):
            tv.wrap(self.measure, "Очень длинная подпись", 5)


class MarksFromLogTests(unittest.TestCase):
    def test_relative_to_the_recording(self):
        lines = ["noise", "THREADS-MARK home 1000.500", "THREADS-MARK q-month 1010.250 extra"]
        self.assertEqual(tv.marks_from_log(lines, 1000.0), {"home": 0.5, "q-month": 10.25})


class SpecFilesTests(unittest.TestCase):
    """Every cut names a test of ThreadsVideoTests and only marks that test prints."""

    def test_specs_match_the_scenes(self):
        source = (tv.ROOT / "TenraUITests" / "ThreadsVideoTests.swift").read_text(encoding="utf-8")
        bodies = dict(re.findall(r"func (test\w+)\(\) throws \{(.*?)\n    \}\n", source, re.S))
        common = set(re.findall(r'mark\("([\w-]+)"\)', source.split("func testTen")[0]))
        specs = sorted(tv.SPECS.glob("*.json"))
        self.assertTrue(specs)
        for path in specs:
            data = json.loads(path.read_text(encoding="utf-8"))
            self.assertIn(data["test"], bodies, path.name)
            marks = common | set(re.findall(r'mark\("([\w-]+)"\)', bodies[data["test"]]))
            for segment in data["segments"]:
                for point in (segment["from"], segment["to"]):
                    if isinstance(point, str):
                        self.assertIn(point.partition("@")[0], marks, f"{path.name}: {point}")
            for segment in data["segments"]:
                caption = segment.get("caption") or ""
                self.assertNotIn("—", caption, f"{path.name}: no em dashes")
                self.assertLessEqual(len(caption.split()), 6, f"{path.name}: {caption}")


if __name__ == "__main__":
    unittest.main()
