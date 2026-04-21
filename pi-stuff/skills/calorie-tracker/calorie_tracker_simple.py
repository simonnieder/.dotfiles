#!/usr/bin/env python3
import argparse
import csv
import datetime as dt
import json
import os
import re
import sqlite3
import sys
import uuid
from pathlib import Path

APP_NAME = "calorie-tracker-simple"
SKILL_DIR = Path(__file__).resolve().parent
DEFAULT_OPENNUTRITION_PATH = str(SKILL_DIR / "opennutrition_foods.tsv")


def app_dir() -> Path:
    override = os.environ.get("CALORIE_TRACKER_SIMPLE_HOME")
    if override:
        path = Path(override).expanduser()
    else:
        base = Path(os.environ.get("XDG_DATA_HOME", Path.home() / ".local" / "share"))
        path = base / APP_NAME
    path.mkdir(parents=True, exist_ok=True)
    return path


def db_path() -> Path:
    return app_dir() / "calorie_tracker_simple.db"


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def ensure_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS foods (
            id TEXT PRIMARY KEY,
            name TEXT NOT NULL,
            brand TEXT,
            source TEXT NOT NULL,
            source_ref TEXT,
            serving_g REAL,
            kcal_per_100g REAL NOT NULL,
            protein_per_100g REAL NOT NULL,
            carbs_per_100g REAL NOT NULL,
            fat_per_100g REAL NOT NULL,
            search_text TEXT NOT NULL,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_foods_name ON foods(name);
        CREATE INDEX IF NOT EXISTS idx_foods_source ON foods(source);

        CREATE TABLE IF NOT EXISTS log_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            logged_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            entry_date TEXT NOT NULL,
            meal TEXT NOT NULL,
            query_text TEXT,
            food_id TEXT REFERENCES foods(id) ON DELETE SET NULL,
            food_name TEXT NOT NULL,
            brand TEXT,
            amount_g REAL NOT NULL,
            calories REAL NOT NULL,
            protein REAL NOT NULL,
            carbs REAL NOT NULL,
            fat REAL NOT NULL,
            note TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_log_entries_date ON log_entries(entry_date);
        """
    )
    conn.commit()


def today_str() -> str:
    return dt.date.today().isoformat()


def parse_date(value: str | None) -> str:
    if not value:
        return today_str()
    return dt.date.fromisoformat(value).isoformat()


def normalize_text(text: str) -> str:
    cleaned = re.sub(r"[^\w\s]", " ", (text or "").lower())
    return " ".join(cleaned.split())


def json_loads_safe(value: str | None, default):
    if not value:
        return default
    try:
        return json.loads(value)
    except Exception:
        return default


def food_search_text(name: str, aliases: list[str] | None = None, brand: str | None = None) -> str:
    parts = [name]
    if brand:
        parts.append(brand)
    parts.extend(aliases or [])
    return normalize_text(" ".join(parts))


def import_open_nutrition(conn: sqlite3.Connection, path: str) -> int:
    path = os.path.expanduser(path)
    if not os.path.exists(path):
        raise SystemExit(f"OpenNutrition file not found: {path}")

    rows = []
    with open(path, "r", encoding="utf-8", newline="") as handle:
        reader = csv.DictReader(handle, delimiter="\t")
        for row in reader:
            nutrition = json_loads_safe(row.get("nutrition_100g"), {})
            calories = nutrition.get("calories")
            protein = nutrition.get("protein")
            carbs = nutrition.get("carbohydrates")
            fat = nutrition.get("total_fat")
            if any(value is None for value in [calories, protein, carbs, fat]):
                continue
            name = (row.get("name") or "").strip()
            if not name:
                continue
            aliases = json_loads_safe(row.get("alternate_names"), [])
            serving = json_loads_safe(row.get("serving"), {})
            metric = serving.get("metric") or {}
            serving_g = metric.get("quantity") if metric.get("unit") in {"g", "ml"} else None
            rows.append(
                (
                    row["id"],
                    name,
                    None,
                    "opennutrition",
                    row["id"],
                    float(serving_g) if serving_g else None,
                    float(calories),
                    float(protein),
                    float(carbs),
                    float(fat),
                    food_search_text(name, aliases=aliases),
                )
            )

    conn.executemany(
        """
        INSERT INTO foods (
            id, name, brand, source, source_ref, serving_g,
            kcal_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, search_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        ON CONFLICT(id) DO UPDATE SET
            name = excluded.name,
            brand = excluded.brand,
            source = excluded.source,
            source_ref = excluded.source_ref,
            serving_g = excluded.serving_g,
            kcal_per_100g = excluded.kcal_per_100g,
            protein_per_100g = excluded.protein_per_100g,
            carbs_per_100g = excluded.carbs_per_100g,
            fat_per_100g = excluded.fat_per_100g,
            search_text = excluded.search_text
        """,
        rows,
    )
    conn.commit()
    return len(rows)


def create_custom_food(
    conn: sqlite3.Connection,
    name: str,
    kcal_per_100g: float,
    protein_per_100g: float,
    carbs_per_100g: float,
    fat_per_100g: float,
    serving_g: float | None = None,
    brand: str | None = None,
) -> str:
    food_id = f"custom_{uuid.uuid4().hex[:12]}"
    conn.execute(
        """
        INSERT INTO foods (
            id, name, brand, source, source_ref, serving_g,
            kcal_per_100g, protein_per_100g, carbs_per_100g, fat_per_100g, search_text
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            food_id,
            name.strip(),
            brand.strip() if brand else None,
            "custom",
            None,
            serving_g,
            kcal_per_100g,
            protein_per_100g,
            carbs_per_100g,
            fat_per_100g,
            food_search_text(name, brand=brand),
        ),
    )
    conn.commit()
    return food_id


def delete_custom_food(conn: sqlite3.Connection, food_id: str) -> int:
    row = conn.execute(
        "SELECT id FROM foods WHERE id = ? AND source = 'custom'",
        (food_id,),
    ).fetchone()
    if not row:
        raise SystemExit(f"Custom food not found: {food_id}")
    cur = conn.execute("DELETE FROM foods WHERE id = ?", (food_id,))
    conn.commit()
    return cur.rowcount


def search_foods(conn: sqlite3.Connection, query: str, limit: int = 10) -> list[sqlite3.Row]:
    normalized = normalize_text(query)
    tokens = normalized.split()
    if not tokens:
        return []

    rows = conn.execute("SELECT * FROM foods").fetchall()

    def score(row: sqlite3.Row) -> tuple[int, int, int, int, str]:
        haystack = row["search_text"]
        exact_name = 1 if normalized == normalize_text(row["name"]) else 0
        prefix_name = 1 if normalize_text(row["name"]).startswith(normalized) else 0
        token_hits = sum(1 for token in tokens if token in haystack)
        all_tokens = 1 if all(token in haystack for token in tokens) else 0
        source_rank = 1 if row["source"] == "custom" else 0
        return (exact_name, prefix_name, all_tokens, token_hits + source_rank, row["name"].lower())

    matches = [row for row in rows if any(token in row["search_text"] for token in tokens)]
    matches.sort(key=score, reverse=True)
    return matches[:limit]


def resolve_food(conn: sqlite3.Connection, query: str | None = None, food_id: str | None = None) -> sqlite3.Row:
    if food_id:
        row = conn.execute("SELECT * FROM foods WHERE id = ?", (food_id,)).fetchone()
        if not row:
            raise SystemExit(f"Unknown food id: {food_id}")
        return row
    if not query:
        raise SystemExit("Provide either a query or --food-id")
    exact = conn.execute(
        "SELECT * FROM foods WHERE lower(name) = lower(?) ORDER BY source = 'custom' DESC LIMIT 1",
        (query.strip(),),
    ).fetchone()
    if exact:
        return exact
    matches = search_foods(conn, query, limit=5)
    if not matches:
        raise SystemExit(f"No food matches found for: {query}")
    return matches[0]


def amount_to_grams(food: sqlite3.Row, amount: float, unit: str) -> float:
    if unit == "g":
        return amount
    if unit == "unit":
        if not food["serving_g"]:
            raise SystemExit(f"Food '{food['name']}' does not define a unit serving size.")
        return amount * float(food["serving_g"])
    raise SystemExit(f"Unsupported unit: {unit}")


def insert_log_entry(
    conn: sqlite3.Connection,
    *,
    entry_date: str,
    meal: str,
    food: sqlite3.Row,
    amount: float,
    unit: str,
    query_text: str | None = None,
    note: str | None = None,
) -> sqlite3.Row:
    amount_g = amount_to_grams(food, amount, unit)
    factor = amount_g / 100.0
    cur = conn.execute(
        """
        INSERT INTO log_entries (
            entry_date, meal, query_text, food_id, food_name, brand, amount_g,
            calories, protein, carbs, fat, note
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            entry_date,
            meal,
            query_text,
            food["id"],
            food["name"],
            food["brand"],
            amount_g,
            food["kcal_per_100g"] * factor,
            food["protein_per_100g"] * factor,
            food["carbs_per_100g"] * factor,
            food["fat_per_100g"] * factor,
            note,
        ),
    )
    conn.commit()
    return conn.execute("SELECT * FROM log_entries WHERE id = ?", (cur.lastrowid,)).fetchone()


def daily_totals(conn: sqlite3.Connection, entry_date: str) -> sqlite3.Row:
    return conn.execute(
        """
        SELECT
            COALESCE(SUM(calories), 0) AS calories,
            COALESCE(SUM(protein), 0) AS protein,
            COALESCE(SUM(carbs), 0) AS carbs,
            COALESCE(SUM(fat), 0) AS fat
        FROM log_entries
        WHERE entry_date = ?
        """,
        (entry_date,),
    ).fetchone()


def print_food_row(row: sqlite3.Row) -> None:
    brand = f" [{row['brand']}]" if row["brand"] else ""
    serving = f", serving {row['serving_g']:.0f}g" if row["serving_g"] else ""
    print(
        f"{row['id']}: {row['name']}{brand} | {row['kcal_per_100g']:.0f} kcal "
        f"P{row['protein_per_100g']:.1f} C{row['carbs_per_100g']:.1f} F{row['fat_per_100g']:.1f} per 100g{serving}"
    )


def print_log_entry(row: sqlite3.Row) -> None:
    brand = f" [{row['brand']}]" if row["brand"] else ""
    print(
        f"#{row['id']} {row['entry_date']} {row['meal']}: {row['food_name']}{brand} | "
        f"{row['amount_g']:.0f}g | {row['calories']:.0f} kcal "
        f"P{row['protein']:.1f} C{row['carbs']:.1f} F{row['fat']:.1f}"
    )


def cmd_init(args) -> None:
    conn = connect()
    ensure_schema(conn)
    if args.import_path:
        imported = import_open_nutrition(conn, args.import_path)
        print(f"Initialized {db_path()} and imported {imported} foods.")
    else:
        print(f"Initialized {db_path()}.")


def cmd_import(args) -> None:
    conn = connect()
    ensure_schema(conn)
    imported = import_open_nutrition(conn, args.path)
    print(f"Imported {imported} foods from {args.path}.")


def cmd_search(args) -> None:
    conn = connect()
    ensure_schema(conn)
    rows = search_foods(conn, args.query, limit=args.limit)
    if not rows:
        raise SystemExit(f"No matches found for: {args.query}")
    for row in rows:
        print_food_row(row)


def cmd_log(args) -> None:
    conn = connect()
    ensure_schema(conn)
    food = resolve_food(conn, query=args.query, food_id=args.food_id)
    entry = insert_log_entry(
        conn,
        entry_date=parse_date(args.date),
        meal=args.meal,
        food=food,
        amount=args.amount,
        unit=args.unit,
        query_text=args.query,
        note=args.note,
    )
    print_log_entry(entry)


def cmd_entries(args) -> None:
    conn = connect()
    ensure_schema(conn)
    rows = conn.execute(
        "SELECT * FROM log_entries WHERE entry_date = ? ORDER BY id",
        (parse_date(args.date),),
    ).fetchall()
    for row in rows:
        print_log_entry(row)


def cmd_totals(args) -> None:
    conn = connect()
    ensure_schema(conn)
    totals = daily_totals(conn, parse_date(args.date))
    print(
        f"{parse_date(args.date)} | {totals['calories']:.0f} kcal "
        f"P{totals['protein']:.1f} C{totals['carbs']:.1f} F{totals['fat']:.1f}"
    )


def cmd_custom_add(args) -> None:
    conn = connect()
    ensure_schema(conn)
    food_id = create_custom_food(
        conn,
        args.name,
        args.calories,
        args.protein,
        args.carbs,
        args.fat,
        serving_g=args.serving_g,
        brand=args.brand,
    )
    print(food_id)


def cmd_custom_list(args) -> None:
    conn = connect()
    ensure_schema(conn)
    rows = conn.execute(
        "SELECT * FROM foods WHERE source = 'custom' ORDER BY lower(name)"
    ).fetchall()
    for row in rows:
        print_food_row(row)


def cmd_custom_rm(args) -> None:
    conn = connect()
    ensure_schema(conn)
    deleted = delete_custom_food(conn, args.food_id)
    print(f"Removed {deleted} custom food.")


def cmd_rm(args) -> None:
    conn = connect()
    ensure_schema(conn)
    row = conn.execute("SELECT id FROM log_entries WHERE id = ?", (args.entry_id,)).fetchone()
    if not row:
        raise SystemExit(f"Entry #{args.entry_id} not found.")
    conn.execute("DELETE FROM log_entries WHERE id = ?", (args.entry_id,))
    conn.commit()
    print(f"Deleted entry #{args.entry_id}")


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Simple local calorie tracker.")
    sub = parser.add_subparsers(dest="command", required=True)

    p = sub.add_parser("init")
    p.add_argument("--import-path", default=DEFAULT_OPENNUTRITION_PATH)
    p.set_defaults(func=cmd_init)

    p = sub.add_parser("import-opennutrition")
    p.add_argument("path", nargs="?", default=DEFAULT_OPENNUTRITION_PATH)
    p.set_defaults(func=cmd_import)

    p = sub.add_parser("search")
    p.add_argument("query")
    p.add_argument("--limit", type=int, default=10)
    p.set_defaults(func=cmd_search)

    p = sub.add_parser("log")
    p.add_argument("meal")
    p.add_argument("amount", type=float)
    p.add_argument("--query")
    p.add_argument("--food-id")
    p.add_argument("--unit", choices=["g", "unit"], default="g")
    p.add_argument("--date")
    p.add_argument("--note")
    p.set_defaults(func=cmd_log)

    p = sub.add_parser("entries")
    p.add_argument("--date")
    p.set_defaults(func=cmd_entries)

    p = sub.add_parser("totals")
    p.add_argument("--date")
    p.set_defaults(func=cmd_totals)

    p = sub.add_parser("rm")
    p.add_argument("entry_id", type=int)
    p.set_defaults(func=cmd_rm)

    p = sub.add_parser("custom")
    custom_sub = p.add_subparsers(dest="custom_command", required=True)

    add = custom_sub.add_parser("add")
    add.add_argument("name")
    add.add_argument("calories", type=float)
    add.add_argument("protein", type=float)
    add.add_argument("carbs", type=float)
    add.add_argument("fat", type=float)
    add.add_argument("--serving-g", type=float)
    add.add_argument("--brand")
    add.set_defaults(func=cmd_custom_add)

    list_cmd = custom_sub.add_parser("list")
    list_cmd.set_defaults(func=cmd_custom_list)

    rm = custom_sub.add_parser("rm")
    rm.add_argument("food_id")
    rm.set_defaults(func=cmd_custom_rm)

    return parser


def main(argv: list[str] | None = None) -> None:
    parser = build_parser()
    args = parser.parse_args(argv)
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(1)
