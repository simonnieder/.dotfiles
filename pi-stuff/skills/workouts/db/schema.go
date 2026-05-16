package db

const schema = `
PRAGMA foreign_keys = ON;

CREATE TABLE IF NOT EXISTS exercise_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  default_set_count INTEGER,
  default_starting_side TEXT,
  lateral_type TEXT NOT NULL DEFAULT 'BILATERAL',
  muscle_group TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workout_templates (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  title TEXT NOT NULL,
  description TEXT,
  type TEXT NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE TABLE IF NOT EXISTS workout_template_exercises (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workout_template_id INTEGER NOT NULL,
  exercise_template_id INTEGER NOT NULL,
  sequence_no INTEGER NOT NULL,
  set_count INTEGER,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(workout_template_id) REFERENCES workout_templates(id) ON DELETE CASCADE,
  FOREIGN KEY(exercise_template_id) REFERENCES exercise_templates(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS workouts (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  template_id INTEGER,
  current_exercise_id INTEGER,
  title TEXT NOT NULL,
  notes TEXT,
  started_at TEXT,
  completed_at TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(template_id) REFERENCES workout_templates(id) ON DELETE SET NULL,
  FOREIGN KEY(current_exercise_id) REFERENCES exercises(id) ON DELETE SET NULL
);

CREATE TABLE IF NOT EXISTS exercises (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  workout_id INTEGER NOT NULL,
  template_id INTEGER NOT NULL,
  sequence_no INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(workout_id) REFERENCES workouts(id) ON DELETE CASCADE,
  FOREIGN KEY(template_id) REFERENCES exercise_templates(id) ON DELETE RESTRICT
);

CREATE TABLE IF NOT EXISTS exercise_sets (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  exercise_id INTEGER NOT NULL,
  weight_in_grams INTEGER,
  reps INTEGER,
  side TEXT,
  rir TEXT,
  is_completed INTEGER NOT NULL DEFAULT 0,
  sequence_no INTEGER NOT NULL,
  notes TEXT,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL,
  FOREIGN KEY(exercise_id) REFERENCES exercises(id) ON DELETE CASCADE
);

CREATE TABLE IF NOT EXISTS weight_entries (
  id INTEGER PRIMARY KEY AUTOINCREMENT,
  weight_in_grams INTEGER NOT NULL,
  created_at TEXT NOT NULL,
  updated_at TEXT NOT NULL
);

CREATE INDEX IF NOT EXISTS idx_template_exercises_template ON workout_template_exercises(workout_template_id, sequence_no);
CREATE INDEX IF NOT EXISTS idx_exercises_workout ON exercises(workout_id, sequence_no);
CREATE INDEX IF NOT EXISTS idx_sets_exercise ON exercise_sets(exercise_id, sequence_no);
CREATE INDEX IF NOT EXISTS idx_weight_created_at ON weight_entries(created_at DESC);
`
