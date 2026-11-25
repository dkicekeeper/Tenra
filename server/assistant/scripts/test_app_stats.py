"""The arithmetic of app_stats.py over counted rows (no SQL API): python3 -m unittest scripts/test_app_stats.py"""

import os
import sys
import unittest

sys.path.insert(0, os.path.dirname(__file__))

from app_stats import drop_off, funnel, retention  # noqa: E402


def m(cohort, name, value, count):
    return {"cohort": cohort, "name": name, "value": value, "count": count}


class FunnelTests(unittest.TestCase):
    def test_funnel_counts_each_milestone_once_per_cohort(self):
        rows = [
            m("2026-W49", "installed", "", 100),
            m("2026-W49", "onboarding_done", "finished", 40),
            m("2026-W49", "onboarding_done", "skipped", 20),
            m("2026-W49", "entries", "1", 30),
        ]
        steps = {row["step"]: row for row in funnel(rows) if row["cohort"] == "2026-W49"}
        self.assertEqual(steps["installed"]["count"], 100)
        self.assertEqual(steps["onboarding_done"]["count"], 60)
        self.assertEqual(steps["onboarding_done"]["of_previous"], "60%")
        self.assertEqual(steps["entries:1"]["of_previous"], "50%")
        self.assertEqual(steps["entries:1"]["of_installs"], "30%")
        # A step nobody reached or that has no row is left out, not shown as a drop to zero.
        self.assertNotIn("trial_started", steps)

    def test_cohort_with_no_installs_is_skipped(self):
        rows = [m("2026-W48", "entries", "1", 3), m("2026-W49", "installed", "", 10)]
        self.assertEqual({row["cohort"] for row in funnel(rows)}, {"2026-W49"})
        self.assertEqual({row["cohort"] for row in retention([], rows)}, {"2026-W49"})


class DropOffTests(unittest.TestCase):
    def test_drop_off_names_the_step_that_loses_most(self):
        day0 = [
            m("2026-W49", "installed", "", 100),
            m("2026-W49", "onboarding", "welcome", 95),
            m("2026-W49", "onboarding", "currency", 90),
            m("2026-W49", "onboarding", "account", 60),
            m("2026-W49", "onboarding", "categories", 58),
            m("2026-W49", "onboarding", "capture", 55),
            m("2026-W49", "onboarding_done", "finished", 50),
            m("2026-W49", "entries", "1", 15),
            m("2026-W49", "reminder_on", "", 5),
        ]
        rows = [row for row in drop_off(day0) if row["cohort"] == "2026-W49"]
        # From onboarding done to a first entry, 35 of 100 are lost: the biggest step.
        self.assertEqual(rows[0]["step"], "onboarding_done")
        self.assertEqual(rows[0]["lost"], 35)
        self.assertEqual(rows[0]["of_installs"], "35%")
        # From currency to account, 30.
        self.assertEqual(rows[1]["step"], "currency")
        self.assertEqual(rows[1]["lost"], 30)
        # Before the first screen of onboarding.
        self.assertIn("installed", [row["step"] for row in rows])


class RetentionTests(unittest.TestCase):
    def test_retention_by_furthest0(self):
        day0 = [
            m("2026-W49", "installed", "", 100),
            m("2026-W49", "onboarding_done", "finished", 60),
            m("2026-W49", "entries", "1", 40),
            m("2026-W49", "reminder_on", "", 10),
        ]
        returned = [
            {"cohort": "2026-W49", "value": "1", "furthest0": "entry", "count": 12},
            {"cohort": "2026-W49", "value": "1", "furthest0": "reminder", "count": 6},
            {"cohort": "2026-W49", "value": "7", "furthest0": "reminder", "count": 4},
        ]
        rows = {row["furthest0"]: row for row in retention(returned, day0) if row["cohort"] == "2026-W49"}
        # Installs whose furthest day-0 milestone is the first entry: 40 reached it, 10 went on to
        # the reminder, so 30; 12 of them came back on day 1.
        self.assertEqual(rows["entry"]["installs"], 30)
        self.assertEqual(rows["entry"]["d1"], "40%")
        self.assertEqual(rows["reminder"]["installs"], 10)
        self.assertEqual(rows["reminder"]["d1"], "60%")
        self.assertEqual(rows["reminder"]["d7"], "40%")
        self.assertEqual(rows["all"]["installs"], 100)
        self.assertEqual(rows["all"]["d1"], "18%")


if __name__ == "__main__":
    unittest.main()
