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
DB_OVERRIDE: Path | None = None
MEAL_NAME_TO_SLOT = {
    "breakfast": 1,
    "lunch": 2,
    "dinner": 3,
    "snack": 4,
    "snacks": 4,
    "preworkout": 5,
    "postworkout": 6,
}


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
    override = DB_OVERRIDE
    if override is not None:
        path = override.expanduser()
        path.parent.mkdir(parents=True, exist_ok=True)
        return path
    return app_dir() / "calorie_tracker_simple.db"


def connect() -> sqlite3.Connection:
    conn = sqlite3.connect(db_path())
    conn.row_factory = sqlite3.Row
    conn.execute("PRAGMA foreign_keys = ON")
    return conn


def today_str() -> str:
    return dt.date.today().isoformat()


def parse_date(value: str | None) -> str:
    if not value:
        return today_str()
    return dt.date.fromisoformat(value).isoformat()


def date_minus_days(value: str, days: int) -> str:
    return (dt.date.fromisoformat(value) - dt.timedelta(days=days)).isoformat()


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


def table_exists(conn: sqlite3.Connection, name: str) -> bool:
    row = conn.execute(
        "SELECT 1 FROM sqlite_master WHERE type='table' AND name = ?",
        (name,),
    ).fetchone()
    return row is not None


def column_exists(conn: sqlite3.Connection, table: str, column: str) -> bool:
    if not table_exists(conn, table):
        return False
    rows = conn.execute(f"PRAGMA table_info({table})").fetchall()
    return any(row[1] == column for row in rows)


def parse_meal_slot(value: str | int) -> int:
    if isinstance(value, int):
        if value <= 0:
            raise SystemExit("Meal slot must be a positive integer.")
        return value
    raw = str(value).strip()
    if not raw:
        raise SystemExit("Meal slot is required.")
    if raw.isdigit():
        slot = int(raw)
        if slot <= 0:
            raise SystemExit("Meal slot must be a positive integer.")
        return slot
    normalized = normalize_text(raw).replace(" ", "")
    if normalized in MEAL_NAME_TO_SLOT:
        return MEAL_NAME_TO_SLOT[normalized]
    match = re.search(r"(\d+)", normalized)
    if match:
        return int(match.group(1))
    raise SystemExit(f"Could not parse meal slot from: {value}")


def meal_slot_label(slot: int) -> str:
    return f"m{slot}"


def create_foods_schema(conn: sqlite3.Connection) -> None:
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
        CREATE INDEX IF NOT EXISTS idx_foods_search_text ON foods(search_text);
        """
    )
    conn.commit()


def create_log_entries_v2_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS log_entries (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            logged_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            entry_date TEXT NOT NULL,
            meal_slot INTEGER NOT NULL,
            query_text TEXT,
            food_id TEXT REFERENCES foods(id) ON DELETE SET NULL,
            food_name TEXT NOT NULL,
            brand TEXT,
            amount_g REAL NOT NULL,
            calories REAL NOT NULL,
            protein REAL NOT NULL,
            carbs REAL NOT NULL,
            fat REAL NOT NULL,
            note TEXT,
            template_item_id INTEGER,
            template_name_snapshot TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_log_entries_entry_date ON log_entries(entry_date);
        CREATE INDEX IF NOT EXISTS idx_log_entries_meal_slot ON log_entries(meal_slot);
        """
    )
    conn.commit()


def create_goal_phase_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS goal_phases (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT,
            start_date TEXT NOT NULL,
            end_date TEXT,
            calories REAL NOT NULL,
            protein REAL NOT NULL,
            carbs REAL NOT NULL,
            fat REAL NOT NULL,
            note TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            closed_at TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_goal_phases_start_date ON goal_phases(start_date);
        CREATE INDEX IF NOT EXISTS idx_goal_phases_end_date ON goal_phases(end_date);
        """
    )
    conn.commit()


def create_weight_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS weight_logs (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            entry_date TEXT NOT NULL,
            weight_kg REAL NOT NULL,
            note TEXT,
            logged_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );
        CREATE INDEX IF NOT EXISTS idx_weight_logs_entry_date ON weight_logs(entry_date);
        """
    )
    conn.commit()


def create_template_schema(conn: sqlite3.Connection) -> None:
    conn.executescript(
        """
        CREATE TABLE IF NOT EXISTS meal_templates (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            name TEXT NOT NULL UNIQUE,
            default_meal_slot INTEGER,
            active INTEGER NOT NULL DEFAULT 1,
            note TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            updated_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP
        );

        CREATE TABLE IF NOT EXISTS meal_template_items (
            id INTEGER PRIMARY KEY AUTOINCREMENT,
            template_id INTEGER NOT NULL REFERENCES meal_templates(id) ON DELETE CASCADE,
            position INTEGER NOT NULL,
            food_id TEXT REFERENCES foods(id) ON DELETE SET NULL,
            food_name_snapshot TEXT NOT NULL,
            brand_snapshot TEXT,
            amount_g REAL NOT NULL,
            note TEXT
        );
        CREATE INDEX IF NOT EXISTS idx_meal_template_items_template_id ON meal_template_items(template_id);
        """
    )
    conn.commit()


def ensure_fts(conn: sqlite3.Connection) -> None:
    fts_exists = table_exists(conn, "foods_fts")
    if not fts_exists:
        conn.execute("CREATE VIRTUAL TABLE foods_fts USING fts5(id UNINDEXED, search_text)")
        conn.execute("INSERT INTO foods_fts(id, search_text) SELECT id, search_text FROM foods")
        conn.commit()


def migrate_log_entries_to_v2(conn: sqlite3.Connection) -> None:
    if not table_exists(conn, "log_entries") or column_exists(conn, "log_entries", "meal_slot"):
        return
    if table_exists(conn, "log_entries_legacy"):
        return

    conn.execute("ALTER TABLE log_entries RENAME TO log_entries_legacy")
    create_log_entries_v2_schema(conn)

    legacy_rows = conn.execute(
        "SELECT * FROM log_entries_legacy ORDER BY id"
    ).fetchall()
    unknown_map: dict[str, int] = {}
    next_unknown_slot = 10

    for row in legacy_rows:
        meal_text = row["meal"]
        normalized = normalize_text(meal_text or "")
        if normalized in MEAL_NAME_TO_SLOT:
            meal_slot = MEAL_NAME_TO_SLOT[normalized]
        else:
            match = re.search(r"(\d+)", normalized)
            if match:
                meal_slot = int(match.group(1))
            else:
                if normalized not in unknown_map:
                    unknown_map[normalized] = next_unknown_slot
                    next_unknown_slot += 1
                meal_slot = unknown_map[normalized]

        conn.execute(
            """
            INSERT INTO log_entries (
                id, logged_at, entry_date, meal_slot, query_text, food_id, food_name, brand,
                amount_g, calories, protein, carbs, fat, note
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
            """,
            (
                row["id"],
                row["logged_at"],
                row["entry_date"],
                meal_slot,
                row["query_text"],
                row["food_id"],
                row["food_name"],
                row["brand"],
                row["amount_g"],
                row["calories"],
                row["protein"],
                row["carbs"],
                row["fat"],
                row["note"],
            ),
        )

    conn.commit()


def migrate_daily_goals_to_phases(conn: sqlite3.Connection) -> None:
    if not table_exists(conn, "daily_goals") or table_exists(conn, "daily_goals_legacy"):
        return

    create_goal_phase_schema(conn)
    existing = conn.execute("SELECT COUNT(*) FROM goal_phases").fetchone()[0]
    if existing > 0:
        return

    rows = conn.execute(
        "SELECT * FROM daily_goals ORDER BY entry_date"
    ).fetchall()
    conn.execute("ALTER TABLE daily_goals RENAME TO daily_goals_legacy")
    if not rows:
        conn.commit()
        return

    for index, row in enumerate(rows):
        next_start = rows[index + 1]["entry_date"] if index + 1 < len(rows) else None
        end_date = date_minus_days(next_start, 1) if next_start else None
        conn.execute(
            """
            INSERT INTO goal_phases (
                name, start_date, end_date, calories, protein, carbs, fat, note, created_at, closed_at
            ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, CURRENT_TIMESTAMP, ?)
            """,
            (
                f"migrated-{row['entry_date']}",
                row["entry_date"],
                end_date,
                row["calories"],
                row["protein"],
                row["carbs"],
                row["fat"],
                "Migrated from legacy daily_goals",
                row["updated_at"] if end_date else None,
            ),
        )
    conn.commit()


def ensure_schema(conn: sqlite3.Connection) -> None:
    create_foods_schema(conn)
    migrate_log_entries_to_v2(conn)
    create_log_entries_v2_schema(conn)
    create_goal_phase_schema(conn)
    migrate_daily_goals_to_phases(conn)
    create_weight_schema(conn)
    create_template_schema(conn)
    ensure_fts(conn)
    conn.execute("PRAGMA user_version = 2")
    conn.commit()


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
    conn.execute("DELETE FROM foods_fts")
    conn.execute("INSERT INTO foods_fts(id, search_text) SELECT id, search_text FROM foods")
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
    conn.execute(
        "INSERT INTO foods_fts(id, search_text) VALUES (?, ?)",
        (food_id, food_search_text(name, brand=brand)),
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
    conn.execute("DELETE FROM foods_fts WHERE id = ?", (food_id,))
    cur = conn.execute("DELETE FROM foods WHERE id = ?", (food_id,))
    conn.commit()
    return cur.rowcount


def search_foods(conn: sqlite3.Connection, query: str, limit: int = 10) -> list[sqlite3.Row]:
    normalized = normalize_text(query)
    tokens = normalized.split()
    if not tokens:
        return []

    rows = conn.execute(
        """SELECT f.* FROM foods f
           JOIN foods_fts ON f.id = foods_fts.id
           WHERE foods_fts MATCH ?
           LIMIT ?""",
        (normalized, limit * 10),
    ).fetchall()

    if not rows:
        like_pat = f"%{normalized}%"
        rows = conn.execute(
            "SELECT * FROM foods WHERE search_text LIKE ? LIMIT ?",
            (like_pat, limit * 10),
        ).fetchall()

    def score(row: sqlite3.Row) -> tuple[int, int, int, int, str]:
        haystack = row["search_text"]
        exact_name = 1 if normalized == normalize_text(row["name"]) else 0
        prefix_name = 1 if normalize_text(row["name"]).startswith(normalized) else 0
        token_hits = sum(1 for token in tokens if token in haystack)
        all_tokens = 1 if all(token in haystack for token in tokens) else 0
        source_rank = 1 if row["source"] == "custom" else 0
        return (exact_name, prefix_name, all_tokens, token_hits + source_rank, row["name"].lower())

    rows.sort(key=score, reverse=True)
    return rows[:limit]


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


def compute_macros_for_amount(food: sqlite3.Row, amount_g: float) -> dict[str, float]:
    factor = amount_g / 100.0
    return {
        "amount_g": amount_g,
        "calories": food["kcal_per_100g"] * factor,
        "protein": food["protein_per_100g"] * factor,
        "carbs": food["carbs_per_100g"] * factor,
        "fat": food["fat_per_100g"] * factor,
    }


def insert_log_entry(
    conn: sqlite3.Connection,
    *,
    entry_date: str,
    meal_slot: int,
    food: sqlite3.Row,
    amount: float,
    unit: str,
    query_text: str | None = None,
    note: str | None = None,
    template_item_id: int | None = None,
    template_name_snapshot: str | None = None,
) -> sqlite3.Row:
    amount_g = amount_to_grams(food, amount, unit)
    macros = compute_macros_for_amount(food, amount_g)
    cur = conn.execute(
        """
        INSERT INTO log_entries (
            entry_date, meal_slot, query_text, food_id, food_name, brand, amount_g,
            calories, protein, carbs, fat, note, template_item_id, template_name_snapshot
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (
            entry_date,
            meal_slot,
            query_text,
            food["id"],
            food["name"],
            food["brand"],
            macros["amount_g"],
            macros["calories"],
            macros["protein"],
            macros["carbs"],
            macros["fat"],
            note,
            template_item_id,
            template_name_snapshot,
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
    note = f" | note: {row['note']}" if row["note"] else ""
    print(
        f"#{row['id']} {row['entry_date']} {meal_slot_label(row['meal_slot'])}: {row['food_name']}{brand} | "
        f"{row['amount_g']:.0f}g | {row['calories']:.0f} kcal "
        f"P{row['protein']:.1f} C{row['carbs']:.1f} F{row['fat']:.1f}{note}"
    )


def get_goal_phase_for_date(conn: sqlite3.Connection, entry_date: str) -> sqlite3.Row | None:
    return conn.execute(
        """
        SELECT * FROM goal_phases
        WHERE start_date <= ? AND (end_date IS NULL OR end_date >= ?)
        ORDER BY start_date DESC, id DESC
        LIMIT 1
        """,
        (entry_date, entry_date),
    ).fetchone()


def start_goal_phase(
    conn: sqlite3.Connection,
    *,
    name: str | None,
    start_date: str,
    calories: float,
    protein: float,
    carbs: float,
    fat: float,
    note: str | None,
) -> sqlite3.Row:
    active = get_goal_phase_for_date(conn, start_date)
    if active and active["start_date"] == start_date:
        conn.execute(
            """
            UPDATE goal_phases
            SET name = ?, calories = ?, protein = ?, carbs = ?, fat = ?, note = ?
            WHERE id = ?
            """,
            (name, calories, protein, carbs, fat, note, active["id"]),
        )
        conn.commit()
        return conn.execute("SELECT * FROM goal_phases WHERE id = ?", (active["id"],)).fetchone()

    if active:
        conn.execute(
            "UPDATE goal_phases SET end_date = ?, closed_at = CURRENT_TIMESTAMP WHERE id = ?",
            (date_minus_days(start_date, 1), active["id"]),
        )

    next_phase = conn.execute(
        "SELECT * FROM goal_phases WHERE start_date > ? ORDER BY start_date ASC LIMIT 1",
        (start_date,),
    ).fetchone()
    end_date = date_minus_days(next_phase["start_date"], 1) if next_phase else None

    cur = conn.execute(
        """
        INSERT INTO goal_phases (name, start_date, end_date, calories, protein, carbs, fat, note)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
        """,
        (name, start_date, end_date, calories, protein, carbs, fat, note),
    )
    conn.commit()
    return conn.execute("SELECT * FROM goal_phases WHERE id = ?", (cur.lastrowid,)).fetchone()


def close_goal_phase(conn: sqlite3.Connection, close_date: str) -> sqlite3.Row:
    active = get_goal_phase_for_date(conn, close_date)
    if not active:
        raise SystemExit(f"No active goal phase found for {close_date}")
    conn.execute(
        "UPDATE goal_phases SET end_date = ?, closed_at = CURRENT_TIMESTAMP WHERE id = ?",
        (close_date, active["id"]),
    )
    conn.commit()
    return conn.execute("SELECT * FROM goal_phases WHERE id = ?", (active["id"],)).fetchone()


def print_goal_phase(row: sqlite3.Row) -> None:
    name = f" [{row['name']}]" if row['name'] else ""
    end = row['end_date'] or "open"
    print(
        f"#{row['id']}{name} {row['start_date']} -> {end} | "
        f"{row['calories']:.0f} kcal | P{row['protein']:.1f} | C{row['carbs']:.1f} | F{row['fat']:.1f}"
    )


def resolve_template(conn: sqlite3.Connection, ref: str) -> sqlite3.Row:
    if ref.isdigit():
        row = conn.execute("SELECT * FROM meal_templates WHERE id = ?", (int(ref),)).fetchone()
    else:
        row = conn.execute("SELECT * FROM meal_templates WHERE lower(name) = lower(?)", (ref,)).fetchone()
    if not row:
        raise SystemExit(f"Template not found: {ref}")
    return row


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
        meal_slot=parse_meal_slot(args.meal_slot),
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
    if not rows:
        print(f"No entries for {parse_date(args.date)}")
        return
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


def cmd_meals(args) -> None:
    conn = connect()
    ensure_schema(conn)
    date = parse_date(args.date)
    rows = conn.execute(
        "SELECT * FROM log_entries WHERE entry_date = ? ORDER BY meal_slot, id",
        (date,),
    ).fetchall()
    if not rows:
        print(f"No entries for {date}")
        return

    meals: dict[int, list[sqlite3.Row]] = {}
    for row in rows:
        meals.setdefault(row["meal_slot"], []).append(row)

    for meal_slot in sorted(meals):
        entries = meals[meal_slot]
        print(f"\n## {meal_slot_label(meal_slot)}")
        for entry in entries:
            brand = f" [{entry['brand']}]" if entry["brand"] else ""
            note = f" | note: {entry['note']}" if entry["note"] else ""
            print(
                f"  #{entry['id']} {entry['food_name']}{brand} | "
                f"{entry['amount_g']:.0f}g | {entry['calories']:.0f} kcal "
                f"P{entry['protein']:.1f} C{entry['carbs']:.1f} F{entry['fat']:.1f}{note}"
            )
        mcal = sum(e["calories"] for e in entries)
        mp = sum(e["protein"] for e in entries)
        mc = sum(e["carbs"] for e in entries)
        mf = sum(e["fat"] for e in entries)
        print(f"  **{meal_slot_label(meal_slot)} total:** {mcal:.0f} kcal | P{mp:.1f} | C{mc:.1f} | F{mf:.1f}")

    totals = daily_totals(conn, date)
    print(f"\n**day total:** {totals['calories']:.0f} kcal | P{totals['protein']:.1f} | C{totals['carbs']:.1f} | F{totals['fat']:.1f}")


def cmd_goals(args) -> None:
    conn = connect()
    ensure_schema(conn)
    date = parse_date(args.date)

    if args.list:
        rows = conn.execute("SELECT * FROM goal_phases ORDER BY start_date, id").fetchall()
        if not rows:
            print("No goal phases configured.")
            return
        for row in rows:
            print_goal_phase(row)
        return

    if args.close:
        row = close_goal_phase(conn, date)
        print(f"Closed goal phase #{row['id']} on {date}")
        return

    starting = any(v is not None for v in [args.calories, args.protein, args.carbs, args.fat])
    if starting:
        if None in (args.calories, args.protein, args.carbs, args.fat):
            raise SystemExit("Starting a phase requires --calories, --protein, --carbs, and --fat")
        row = start_goal_phase(
            conn,
            name=args.name,
            start_date=date,
            calories=args.calories,
            protein=args.protein,
            carbs=args.carbs,
            fat=args.fat,
            note=args.note,
        )
        print(f"Started goal phase #{row['id']} on {date}")
        print_goal_phase(row)
        return

    row = get_goal_phase_for_date(conn, date)
    if row:
        print_goal_phase(row)
    else:
        print(f"No goal phase active for {date}")


def cmd_remaining(args) -> None:
    conn = connect()
    ensure_schema(conn)
    date = parse_date(args.date)
    totals = daily_totals(conn, date)
    goals = get_goal_phase_for_date(conn, date)
    if not goals:
        print(f"No goal phase active for {date}. Use 'goals' to start one.")
        return

    print(f"{date}")
    print(f"  consumed:  {totals['calories']:.0f} kcal | P{totals['protein']:.1f} | C{totals['carbs']:.1f} | F{totals['fat']:.1f}")
    print(f"  goals:     {goals['calories']:.0f} kcal | P{goals['protein']:.1f} | C{goals['carbs']:.1f} | F{goals['fat']:.1f}")
    print(f"  remaining: {goals['calories'] - totals['calories']:.0f} kcal | P{goals['protein'] - totals['protein']:.1f} | C{goals['carbs'] - totals['carbs']:.1f} | F{goals['fat'] - totals['fat']:.1f}")


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
    rows = conn.execute("SELECT * FROM foods WHERE source = 'custom' ORDER BY lower(name)").fetchall()
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


def cmd_entry_edit(args) -> None:
    conn = connect()
    ensure_schema(conn)
    row = conn.execute("SELECT * FROM log_entries WHERE id = ?", (args.entry_id,)).fetchone()
    if not row:
        raise SystemExit(f"Entry #{args.entry_id} not found.")

    update_fields: dict[str, object] = {}
    current_food_id = args.food_id or row["food_id"]
    food_changed = args.food_id is not None or args.query is not None
    amount_changed = args.amount is not None

    if args.meal_slot is not None:
        update_fields["meal_slot"] = parse_meal_slot(args.meal_slot)
    if args.date is not None:
        update_fields["entry_date"] = parse_date(args.date)
    if args.note is not None:
        update_fields["note"] = args.note

    if food_changed or amount_changed:
        if not current_food_id and not args.query:
            raise SystemExit("Cannot recalculate entry without a linked food. Provide --food-id or --query.")
        food = resolve_food(conn, query=args.query, food_id=current_food_id)
        amount_g = amount_to_grams(food, args.amount, args.unit) if amount_changed else row["amount_g"]
        macros = compute_macros_for_amount(food, amount_g)
        update_fields.update(
            {
                "food_id": food["id"],
                "food_name": food["name"],
                "brand": food["brand"],
                "query_text": args.query if args.query is not None else row["query_text"],
                "amount_g": macros["amount_g"],
                "calories": macros["calories"],
                "protein": macros["protein"],
                "carbs": macros["carbs"],
                "fat": macros["fat"],
            }
        )

    if not update_fields:
        raise SystemExit("No changes requested.")

    assignments = ", ".join(f"{key} = ?" for key in update_fields)
    values = list(update_fields.values()) + [args.entry_id]
    conn.execute(f"UPDATE log_entries SET {assignments} WHERE id = ?", values)
    conn.commit()
    updated = conn.execute("SELECT * FROM log_entries WHERE id = ?", (args.entry_id,)).fetchone()
    print_log_entry(updated)


def cmd_weight_log(args) -> None:
    conn = connect()
    ensure_schema(conn)
    cur = conn.execute(
        "INSERT INTO weight_logs (entry_date, weight_kg, note) VALUES (?, ?, ?)",
        (parse_date(args.date), args.weight_kg, args.note),
    )
    conn.commit()
    row = conn.execute("SELECT * FROM weight_logs WHERE id = ?", (cur.lastrowid,)).fetchone()
    print(f"#{row['id']} {row['entry_date']} | {row['weight_kg']:.1f} kg")


def cmd_weight_list(args) -> None:
    conn = connect()
    ensure_schema(conn)
    sql = "SELECT * FROM weight_logs"
    params: list[object] = []
    if args.days is not None:
        start_date = date_minus_days(today_str(), args.days - 1)
        sql += " WHERE entry_date >= ?"
        params.append(start_date)
    sql += " ORDER BY entry_date DESC, id DESC"
    rows = conn.execute(sql, params).fetchall()
    if not rows:
        print("No weight entries.")
        return
    for row in rows:
        note = f" | note: {row['note']}" if row['note'] else ""
        print(f"#{row['id']} {row['entry_date']} | {row['weight_kg']:.1f} kg{note}")


def cmd_template_add(args) -> None:
    conn = connect()
    ensure_schema(conn)
    meal_slot = parse_meal_slot(args.meal_slot) if args.meal_slot is not None else None
    cur = conn.execute(
        "INSERT INTO meal_templates (name, default_meal_slot, note) VALUES (?, ?, ?)",
        (args.name, meal_slot, args.note),
    )
    conn.commit()
    print(f"template #{cur.lastrowid}: {args.name}")


def cmd_template_list(args) -> None:
    conn = connect()
    ensure_schema(conn)
    rows = conn.execute("SELECT * FROM meal_templates ORDER BY lower(name)").fetchall()
    if not rows:
        print("No templates.")
        return
    for row in rows:
        slot = f" | default {meal_slot_label(row['default_meal_slot'])}" if row['default_meal_slot'] else ""
        active = "active" if row['active'] else "inactive"
        print(f"#{row['id']} {row['name']} | {active}{slot}")


def cmd_template_show(args) -> None:
    conn = connect()
    ensure_schema(conn)
    template = resolve_template(conn, args.template)
    slot = f" | default {meal_slot_label(template['default_meal_slot'])}" if template['default_meal_slot'] else ""
    print(f"#{template['id']} {template['name']}{slot}")
    items = conn.execute(
        "SELECT * FROM meal_template_items WHERE template_id = ? ORDER BY position, id",
        (template['id'],),
    ).fetchall()
    for item in items:
        note = f" | note: {item['note']}" if item['note'] else ""
        brand = f" [{item['brand_snapshot']}]" if item['brand_snapshot'] else ""
        print(f"  item #{item['id']} pos {item['position']} | {item['food_name_snapshot']}{brand} | {item['amount_g']:.0f}g{note}")


def cmd_template_rm(args) -> None:
    conn = connect()
    ensure_schema(conn)
    template = resolve_template(conn, args.template)
    conn.execute("DELETE FROM meal_templates WHERE id = ?", (template['id'],))
    conn.commit()
    print(f"Removed template #{template['id']}: {template['name']}")


def cmd_template_item_add(args) -> None:
    conn = connect()
    ensure_schema(conn)
    template = resolve_template(conn, args.template)
    food = resolve_food(conn, query=args.query, food_id=args.food_id)
    amount_g = amount_to_grams(food, args.amount, args.unit)
    next_pos = conn.execute(
        "SELECT COALESCE(MAX(position), 0) + 1 FROM meal_template_items WHERE template_id = ?",
        (template['id'],),
    ).fetchone()[0]
    cur = conn.execute(
        """
        INSERT INTO meal_template_items (
            template_id, position, food_id, food_name_snapshot, brand_snapshot, amount_g, note
        ) VALUES (?, ?, ?, ?, ?, ?, ?)
        """,
        (template['id'], next_pos, food['id'], food['name'], food['brand'], amount_g, args.note),
    )
    conn.execute("UPDATE meal_templates SET updated_at = CURRENT_TIMESTAMP WHERE id = ?", (template['id'],))
    conn.commit()
    print(f"template item #{cur.lastrowid} added to {template['name']}")


def cmd_template_item_edit(args) -> None:
    conn = connect()
    ensure_schema(conn)
    item = conn.execute("SELECT * FROM meal_template_items WHERE id = ?", (args.item_id,)).fetchone()
    if not item:
        raise SystemExit(f"Template item #{args.item_id} not found.")

    update_fields: dict[str, object] = {}
    current_food_id = args.food_id or item["food_id"]
    food_changed = args.food_id is not None or args.query is not None
    if food_changed or args.amount is not None:
        food = resolve_food(conn, query=args.query, food_id=current_food_id)
        amount_g = amount_to_grams(food, args.amount, args.unit) if args.amount is not None else item['amount_g']
        update_fields.update(
            {
                "food_id": food['id'],
                "food_name_snapshot": food['name'],
                "brand_snapshot": food['brand'],
                "amount_g": amount_g,
            }
        )
    if args.position is not None:
        update_fields['position'] = args.position
    if args.note is not None:
        update_fields['note'] = args.note

    if not update_fields:
        raise SystemExit("No changes requested.")

    assignments = ", ".join(f"{key} = ?" for key in update_fields)
    values = list(update_fields.values()) + [args.item_id]
    conn.execute(f"UPDATE meal_template_items SET {assignments} WHERE id = ?", values)
    conn.execute(
        "UPDATE meal_templates SET updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (item['template_id'],),
    )
    conn.commit()
    print(f"Updated template item #{args.item_id}")


def cmd_template_item_rm(args) -> None:
    conn = connect()
    ensure_schema(conn)
    item = conn.execute("SELECT * FROM meal_template_items WHERE id = ?", (args.item_id,)).fetchone()
    if not item:
        raise SystemExit(f"Template item #{args.item_id} not found.")
    conn.execute("DELETE FROM meal_template_items WHERE id = ?", (args.item_id,))
    conn.execute(
        "UPDATE meal_templates SET updated_at = CURRENT_TIMESTAMP WHERE id = ?",
        (item['template_id'],),
    )
    conn.commit()
    print(f"Removed template item #{args.item_id}")


def cmd_template_apply(args) -> None:
    conn = connect()
    ensure_schema(conn)
    template = resolve_template(conn, args.template)
    items = conn.execute(
        "SELECT * FROM meal_template_items WHERE template_id = ? ORDER BY position, id",
        (template['id'],),
    ).fetchall()
    if not items:
        raise SystemExit(f"Template '{template['name']}' has no items.")
    meal_slot = parse_meal_slot(args.meal_slot) if args.meal_slot is not None else template['default_meal_slot']
    if meal_slot is None:
        raise SystemExit("Template has no default meal slot. Provide --meal-slot.")

    created = []
    for item in items:
        if not item['food_id']:
            raise SystemExit(f"Template item #{item['id']} has no linked food_id.")
        food = resolve_food(conn, food_id=item['food_id'])
        entry = insert_log_entry(
            conn,
            entry_date=parse_date(args.date),
            meal_slot=meal_slot,
            food=food,
            amount=item['amount_g'],
            unit='g',
            note=item['note'],
            template_item_id=item['id'],
            template_name_snapshot=template['name'],
        )
        created.append(entry)
    for entry in created:
        print_log_entry(entry)


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Simple local calorie tracker.")
    parser.add_argument("--db", help="Path to an alternative SQLite database file")
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
    p.add_argument("meal_slot")
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

    p = sub.add_parser("meals")
    p.add_argument("--date")
    p.set_defaults(func=cmd_meals)

    p = sub.add_parser("goals")
    p.add_argument("--date")
    p.add_argument("--name")
    p.add_argument("--calories", type=float)
    p.add_argument("--protein", type=float)
    p.add_argument("--carbs", type=float)
    p.add_argument("--fat", type=float)
    p.add_argument("--note")
    p.add_argument("--list", action="store_true")
    p.add_argument("--close", action="store_true")
    p.set_defaults(func=cmd_goals)

    p = sub.add_parser("remaining")
    p.add_argument("--date")
    p.set_defaults(func=cmd_remaining)

    p = sub.add_parser("rm")
    p.add_argument("entry_id", type=int)
    p.set_defaults(func=cmd_rm)

    p = sub.add_parser("entry")
    entry_sub = p.add_subparsers(dest="entry_command", required=True)
    edit = entry_sub.add_parser("edit")
    edit.add_argument("entry_id", type=int)
    edit.add_argument("--amount", type=float)
    edit.add_argument("--unit", choices=["g", "unit"], default="g")
    edit.add_argument("--food-id")
    edit.add_argument("--query")
    edit.add_argument("--meal-slot")
    edit.add_argument("--date")
    edit.add_argument("--note")
    edit.set_defaults(func=cmd_entry_edit)

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
    rm_cmd = custom_sub.add_parser("rm")
    rm_cmd.add_argument("food_id")
    rm_cmd.set_defaults(func=cmd_custom_rm)

    p = sub.add_parser("weight")
    weight_sub = p.add_subparsers(dest="weight_command", required=True)
    weight_log = weight_sub.add_parser("log")
    weight_log.add_argument("weight_kg", type=float)
    weight_log.add_argument("--date")
    weight_log.add_argument("--note")
    weight_log.set_defaults(func=cmd_weight_log)
    weight_list = weight_sub.add_parser("list")
    weight_list.add_argument("--days", type=int)
    weight_list.set_defaults(func=cmd_weight_list)

    p = sub.add_parser("template")
    template_sub = p.add_subparsers(dest="template_command", required=True)
    t_add = template_sub.add_parser("add")
    t_add.add_argument("name")
    t_add.add_argument("--meal-slot")
    t_add.add_argument("--note")
    t_add.set_defaults(func=cmd_template_add)
    t_list = template_sub.add_parser("list")
    t_list.set_defaults(func=cmd_template_list)
    t_show = template_sub.add_parser("show")
    t_show.add_argument("template")
    t_show.set_defaults(func=cmd_template_show)
    t_rm = template_sub.add_parser("rm")
    t_rm.add_argument("template")
    t_rm.set_defaults(func=cmd_template_rm)
    t_apply = template_sub.add_parser("apply")
    t_apply.add_argument("template")
    t_apply.add_argument("--date")
    t_apply.add_argument("--meal-slot")
    t_apply.set_defaults(func=cmd_template_apply)

    p = template_sub.add_parser("item-add")
    p.add_argument("template")
    p.add_argument("amount", type=float)
    p.add_argument("--query")
    p.add_argument("--food-id")
    p.add_argument("--unit", choices=["g", "unit"], default="g")
    p.add_argument("--note")
    p.set_defaults(func=cmd_template_item_add)

    p = template_sub.add_parser("item-edit")
    p.add_argument("item_id", type=int)
    p.add_argument("--amount", type=float)
    p.add_argument("--query")
    p.add_argument("--food-id")
    p.add_argument("--unit", choices=["g", "unit"], default="g")
    p.add_argument("--position", type=int)
    p.add_argument("--note")
    p.set_defaults(func=cmd_template_item_edit)

    p = template_sub.add_parser("item-rm")
    p.add_argument("item_id", type=int)
    p.set_defaults(func=cmd_template_item_rm)

    return parser


def main(argv: list[str] | None = None) -> None:
    global DB_OVERRIDE
    parser = build_parser()
    args = parser.parse_args(argv)
    if args.db:
        DB_OVERRIDE = Path(args.db)
    args.func(args)


if __name__ == "__main__":
    try:
        main()
    except BrokenPipeError:
        sys.exit(1)
