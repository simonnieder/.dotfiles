#!/usr/bin/env python3
import csv
import importlib.util
import json
import os
import tempfile
import unittest
from pathlib import Path

SKILL_DIR = Path(__file__).resolve().parent
MODULE_PATH = SKILL_DIR / "calorie_tracker_simple.py"

spec = importlib.util.spec_from_file_location("calorie_tracker_simple", MODULE_PATH)
mod = importlib.util.module_from_spec(spec)
spec.loader.exec_module(mod)


class CalorieTrackerSimpleTests(unittest.TestCase):
    def setUp(self):
        self.tmp = tempfile.TemporaryDirectory()
        self.addCleanup(self.tmp.cleanup)
        self.home = Path(self.tmp.name)
        os.environ["CALORIE_TRACKER_SIMPLE_HOME"] = str(self.home)
        self.addCleanup(lambda: os.environ.pop("CALORIE_TRACKER_SIMPLE_HOME", None))

    def connect(self):
        conn = mod.connect()
        mod.ensure_schema(conn)
        return conn

    def write_tsv(self, path: Path):
        fieldnames = [
            "id", "name", "alternate_names", "description", "type", "source", "serving",
            "nutrition_100g", "ean_13", "labels", "package_size", "ingredients", "ingredient_analysis",
        ]
        rows = [
            {
                "id": "fd_test_banana",
                "name": "Banana",
                "alternate_names": json.dumps(["Banane"]),
                "description": "",
                "type": "everyday",
                "source": "[]",
                "serving": json.dumps({"metric": {"unit": "g", "quantity": 118}}),
                "nutrition_100g": json.dumps({"calories": 89, "protein": 1.1, "carbohydrates": 22.8, "total_fat": 0.3}),
                "ean_13": "",
                "labels": "[]",
                "package_size": "{}",
                "ingredients": "",
                "ingredient_analysis": "{}",
            },
            {
                "id": "fd_test_oats",
                "name": "Rolled Oats",
                "alternate_names": json.dumps(["Haferflocken"]),
                "description": "",
                "type": "everyday",
                "source": "[]",
                "serving": json.dumps({"metric": {"unit": "g", "quantity": 40}}),
                "nutrition_100g": json.dumps({"calories": 370, "protein": 13, "carbohydrates": 68, "total_fat": 7}),
                "ean_13": "",
                "labels": "[]",
                "package_size": "{}",
                "ingredients": "",
                "ingredient_analysis": "{}",
            },
        ]
        with path.open("w", encoding="utf-8", newline="") as handle:
            writer = csv.DictWriter(handle, fieldnames=fieldnames, delimiter="\t")
            writer.writeheader()
            writer.writerows(rows)

    def test_import_and_search_single_word(self):
        conn = self.connect()
        tsv = self.home / "foods.tsv"
        self.write_tsv(tsv)
        imported = mod.import_open_nutrition(conn, str(tsv))
        self.assertEqual(imported, 2)
        rows = mod.search_foods(conn, "banana", limit=5)
        self.assertEqual(rows[0]["name"], "Banana")

    def test_log_entry_stores_snapshot_values(self):
        conn = self.connect()
        food_id = mod.create_custom_food(conn, "Protein Yogurt", 60, 10, 4, 1, serving_g=500)
        food = mod.resolve_food(conn, food_id=food_id)
        entry = mod.insert_log_entry(
            conn,
            entry_date="2026-04-20",
            meal="meal-2",
            food=food,
            amount=1,
            unit="unit",
            query_text="protein yogurt",
        )
        self.assertAlmostEqual(entry["amount_g"], 500.0)
        self.assertAlmostEqual(entry["calories"], 300.0)
        self.assertEqual(entry["food_name"], "Protein Yogurt")

    def test_delete_custom_food_preserves_history(self):
        conn = self.connect()
        food_id = mod.create_custom_food(conn, "Restaurant Ramen", 155, 8, 18, 6, serving_g=500)
        food = mod.resolve_food(conn, food_id=food_id)
        mod.insert_log_entry(
            conn,
            entry_date="2026-04-20",
            meal="meal-3",
            food=food,
            amount=1,
            unit="unit",
        )
        deleted = mod.delete_custom_food(conn, food_id)
        self.assertEqual(deleted, 1)
        entry = conn.execute("SELECT * FROM log_entries").fetchone()
        self.assertIsNone(entry["food_id"])
        self.assertEqual(entry["food_name"], "Restaurant Ramen")

    def test_daily_totals_add_up(self):
        conn = self.connect()
        food_id = mod.create_custom_food(conn, "Rice", 130, 2.5, 28, 0.3)
        food = mod.resolve_food(conn, food_id=food_id)
        mod.insert_log_entry(conn, entry_date="2026-04-20", meal="meal-1", food=food, amount=200, unit="g")
        totals = mod.daily_totals(conn, "2026-04-20")
        self.assertAlmostEqual(totals["calories"], 260.0)
        self.assertAlmostEqual(totals["carbs"], 56.0)


if __name__ == "__main__":
    unittest.main()
