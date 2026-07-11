package db

import (
	"database/sql"
	"fmt"
	"os"
	"path/filepath"
	"slices"
	"strconv"
	"strings"
	"time"

	_ "modernc.org/sqlite"
)

type Store struct {
	DB *sql.DB
}

type ExerciseTemplateSeed struct {
	ID              int
	Title           string
	DefaultSetCount int
	LateralType     string
	MuscleGroup     string
}

type ExerciseTemplate struct {
	ID              int
	Title           string
	DefaultSetCount sql.NullInt64
	LateralType     string
	MuscleGroup     sql.NullString
}

type TemplateExercise struct {
	LinkID          int
	ExerciseID      int
	ExerciseTitle   string
	MuscleGroup     sql.NullString
	SequenceNo      int
	SetCount        sql.NullInt64
	DefaultSetCount sql.NullInt64
}

type WorkoutRow struct {
	ID                int
	Title             string
	Notes             sql.NullString
	StartedAt         sql.NullString
	CompletedAt       sql.NullString
	CurrentExerciseID sql.NullInt64
}

type WorkoutExerciseRow struct {
	ExerciseID    int
	TemplateID    int
	Title         string
	MuscleGroup   sql.NullString
	SequenceNo    int
	SetCount      int
	CompletedSets int
}

type SetRow struct {
	ID            int
	SequenceNo    int
	WeightInGrams sql.NullInt64
	Reps          sql.NullInt64
	Side          sql.NullString
	RIR           sql.NullString
	IsCompleted   bool
	Notes         sql.NullString
}

type WeightEntry struct {
	ID            int
	WeightInGrams int
	CreatedAt     string
}

type WorkoutProgressSummary struct {
	TotalComparableSets int
	TotalProgressedSets int
	MuscleGroups        []MuscleGroupProgress
	Exercises           []ExerciseProgress
}

type MuscleGroupProgress struct {
	MuscleGroup         string
	TotalComparableSets int
	TotalProgressedSets int
}

type ExerciseProgress struct {
	Exercise            WorkoutExerciseRow
	TotalComparableSets int
	TotalProgressedSets int
	Sets                []SetProgress
}

type SetProgress struct {
	Set        SetRow
	Progressed bool
}

func Open(path string) (*Store, error) {
	if err := os.MkdirAll(filepath.Dir(path), 0o755); err != nil {
		return nil, err
	}
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return nil, err
	}
	if _, err := db.Exec(schema); err != nil {
		_ = db.Close()
		return nil, err
	}
	if _, err := db.Exec(`ALTER TABLE workouts ADD COLUMN current_exercise_id INTEGER REFERENCES exercises(id) ON DELETE SET NULL`); err != nil && !strings.Contains(err.Error(), "duplicate column name") {
		_ = db.Close()
		return nil, err
	}
	return &Store{DB: db}, nil
}

func (s *Store) Close() error { return s.DB.Close() }

func now() string { return time.Now().Format(time.RFC3339) }

func (s *Store) SeedExerciseTemplates(seeds []ExerciseTemplateSeed) error {
	var count int
	if err := s.DB.QueryRow(`SELECT COUNT(*) FROM exercise_templates`).Scan(&count); err != nil {
		return err
	}
	if count > 0 {
		return nil
	}
	for _, item := range seeds {
		if _, err := s.DB.Exec(`
			INSERT INTO exercise_templates (id, title, default_set_count, lateral_type, muscle_group, created_at, updated_at)
			VALUES (?, ?, ?, ?, ?, ?, ?)
		`, item.ID, item.Title, nullableZero(item.DefaultSetCount), strings.ToUpper(item.LateralType), nullableString(item.MuscleGroup), now(), now()); err != nil {
			return err
		}
	}
	return nil
}

func nullableZero(v int) any {
	if v == 0 {
		return nil
	}
	return v
}

func nullableString(v string) any {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	return strings.ToUpper(strings.TrimSpace(v))
}

func (s *Store) ListExercises() ([]ExerciseTemplate, error) {
	rows, err := s.DB.Query(`SELECT id, title, default_set_count, lateral_type, muscle_group FROM exercise_templates ORDER BY title COLLATE NOCASE ASC, id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []ExerciseTemplate
	for rows.Next() {
		var item ExerciseTemplate
		if err := rows.Scan(&item.ID, &item.Title, &item.DefaultSetCount, &item.LateralType, &item.MuscleGroup); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) CreateExercise(title string, muscleGroup string, defaultSetCount int, lateralType string) (int, error) {
	res, err := s.DB.Exec(`
		INSERT INTO exercise_templates (title, default_set_count, lateral_type, muscle_group, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?)
	`, title, nullableZero(defaultSetCount), strings.ToUpper(lateralType), nullableString(muscleGroup), now(), now())
	if err != nil {
		return 0, err
	}
	return lastInsertID(res)
}

func (s *Store) GetExercise(id int) (*ExerciseTemplate, error) {
	var item ExerciseTemplate
	if err := s.DB.QueryRow(`SELECT id, title, default_set_count, lateral_type, muscle_group FROM exercise_templates WHERE id = ?`, id).Scan(&item.ID, &item.Title, &item.DefaultSetCount, &item.LateralType, &item.MuscleGroup); err != nil {
		if err == sql.ErrNoRows {
			return nil, nil
		}
		return nil, err
	}
	return &item, nil
}

func (s *Store) ListTemplates() ([]WorkoutRow, error) {
	rows, err := s.DB.Query(`SELECT id, title, created_at, updated_at, NULL FROM workout_templates ORDER BY title COLLATE NOCASE ASC, id ASC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WorkoutRow
	for rows.Next() {
		var item WorkoutRow
		if err := rows.Scan(&item.ID, &item.Title, &item.StartedAt, &item.CompletedAt, &item.CurrentExerciseID); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) CreateTemplate(title, description, templateType string) (int, error) {
	res, err := s.DB.Exec(`INSERT INTO workout_templates (title, description, type, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`, title, nullIfBlank(description), defaultIfBlank(templateType, "WORKOUT"), now(), now())
	if err != nil {
		return 0, err
	}
	return lastInsertID(res)
}

func (s *Store) AddExerciseToTemplate(templateID, exerciseID int, setCount int) error {
	var next int
	if err := s.DB.QueryRow(`SELECT COALESCE(MAX(sequence_no), 0) + 1 FROM workout_template_exercises WHERE workout_template_id = ?`, templateID).Scan(&next); err != nil {
		return err
	}
	_, err := s.DB.Exec(`INSERT INTO workout_template_exercises (workout_template_id, exercise_template_id, sequence_no, set_count, created_at, updated_at) VALUES (?, ?, ?, ?, ?, ?)`, templateID, exerciseID, next, nullableZero(setCount), now(), now())
	return err
}

func (s *Store) GetTemplateExercises(templateID int) ([]TemplateExercise, error) {
	rows, err := s.DB.Query(`
		SELECT wte.id, et.id, et.title, et.muscle_group, wte.sequence_no, wte.set_count, et.default_set_count
		FROM workout_template_exercises wte
		JOIN exercise_templates et ON et.id = wte.exercise_template_id
		WHERE wte.workout_template_id = ?
		ORDER BY wte.sequence_no ASC, wte.created_at ASC
	`, templateID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []TemplateExercise
	for rows.Next() {
		var item TemplateExercise
		if err := rows.Scan(&item.LinkID, &item.ExerciseID, &item.ExerciseTitle, &item.MuscleGroup, &item.SequenceNo, &item.SetCount, &item.DefaultSetCount); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) StartWorkout(templateID *int, title string) (int, error) {
	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()

	if strings.TrimSpace(title) == "" {
		if templateID != nil {
			if err := tx.QueryRow(`SELECT title FROM workout_templates WHERE id = ?`, *templateID).Scan(&title); err != nil {
				return 0, err
			}
		} else {
			title = "Workout"
		}
	}

	timestamp := now()
	res, err := tx.Exec(`INSERT INTO workouts (template_id, title, started_at, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`, intPtrValue(templateID), title, timestamp, timestamp, timestamp)
	if err != nil {
		return 0, err
	}
	id, err := lastInsertID(res)
	if err != nil {
		return 0, err
	}

	var firstExerciseID int
	if templateID != nil {
		rows, err := tx.Query(`
			SELECT exercise_template_id, COALESCE(set_count, et.default_set_count, 1), sequence_no
			FROM workout_template_exercises wte
			JOIN exercise_templates et ON et.id = wte.exercise_template_id
			WHERE workout_template_id = ?
			ORDER BY sequence_no ASC
		`, *templateID)
		if err != nil {
			return 0, err
		}
		defer rows.Close()
		for rows.Next() {
			var exerciseTemplateID int
			var setCount int
			var sequenceNo int
			if err := rows.Scan(&exerciseTemplateID, &setCount, &sequenceNo); err != nil {
				return 0, err
			}
			exerciseRes, err := tx.Exec(`INSERT INTO exercises (workout_id, template_id, sequence_no, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`, id, exerciseTemplateID, sequenceNo, timestamp, timestamp)
			if err != nil {
				return 0, err
			}
			exerciseID, err := lastInsertID(exerciseRes)
			if err != nil {
				return 0, err
			}
			if firstExerciseID == 0 {
				firstExerciseID = exerciseID
			}
			for i := 1; i <= max(setCount, 1); i++ {
				if _, err := tx.Exec(`INSERT INTO exercise_sets (exercise_id, sequence_no, is_completed, created_at, updated_at) VALUES (?, ?, 0, ?, ?)`, exerciseID, i, timestamp, timestamp); err != nil {
					return 0, err
				}
			}
		}
		if err := rows.Err(); err != nil {
			return 0, err
		}
	}
	if firstExerciseID != 0 {
		if _, err := tx.Exec(`UPDATE workouts SET current_exercise_id = ?, updated_at = ? WHERE id = ?`, firstExerciseID, timestamp, id); err != nil {
			return 0, err
		}
	}

	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return id, nil
}

func (s *Store) GetCurrentWorkout() (*WorkoutRow, error) {
	var item WorkoutRow
	err := s.DB.QueryRow(`SELECT id, title, notes, started_at, completed_at, current_exercise_id FROM workouts WHERE completed_at IS NULL ORDER BY COALESCE(started_at, created_at) DESC, id DESC LIMIT 1`).Scan(&item.ID, &item.Title, &item.Notes, &item.StartedAt, &item.CompletedAt, &item.CurrentExerciseID)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &item, nil
}

func (s *Store) ListWorkouts() ([]WorkoutRow, error) {
	rows, err := s.DB.Query(`SELECT id, title, notes, started_at, completed_at, current_exercise_id FROM workouts ORDER BY COALESCE(started_at, created_at) DESC, id DESC`)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WorkoutRow
	for rows.Next() {
		var item WorkoutRow
		if err := rows.Scan(&item.ID, &item.Title, &item.Notes, &item.StartedAt, &item.CompletedAt, &item.CurrentExerciseID); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) GetWorkout(id int) (*WorkoutRow, error) {
	var item WorkoutRow
	err := s.DB.QueryRow(`SELECT id, title, notes, started_at, completed_at, current_exercise_id FROM workouts WHERE id = ?`, id).Scan(&item.ID, &item.Title, &item.Notes, &item.StartedAt, &item.CompletedAt, &item.CurrentExerciseID)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}
	return &item, nil
}

func (s *Store) FinishWorkout(id int) error {
	if err := s.cleanupWorkoutEmptyPlaceholderSets(id); err != nil {
		return err
	}
	res, err := s.DB.Exec(`UPDATE workouts SET completed_at = ?, updated_at = ? WHERE id = ? AND completed_at IS NULL`, now(), now(), id)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("workout not found or already completed")
	}
	return nil
}

func (s *Store) AddExerciseToWorkout(workoutID, exerciseTemplateID int) (int, error) {
	var next int
	if err := s.DB.QueryRow(`SELECT COALESCE(MAX(sequence_no), 0) + 1 FROM exercises WHERE workout_id = ?`, workoutID).Scan(&next); err != nil {
		return 0, err
	}
	var defaultSetCount sql.NullInt64
	if err := s.DB.QueryRow(`SELECT default_set_count FROM exercise_templates WHERE id = ?`, exerciseTemplateID).Scan(&defaultSetCount); err != nil {
		return 0, err
	}
	timestamp := now()
	tx, err := s.DB.Begin()
	if err != nil {
		return 0, err
	}
	defer tx.Rollback()
	exerciseRes, err := tx.Exec(`INSERT INTO exercises (workout_id, template_id, sequence_no, created_at, updated_at) VALUES (?, ?, ?, ?, ?)`, workoutID, exerciseTemplateID, next, timestamp, timestamp)
	if err != nil {
		return 0, err
	}
	exerciseID, err := lastInsertID(exerciseRes)
	if err != nil {
		return 0, err
	}
	setCount := 1
	if defaultSetCount.Valid && defaultSetCount.Int64 > 0 {
		setCount = int(defaultSetCount.Int64)
	}
	for i := 1; i <= setCount; i++ {
		if _, err := tx.Exec(`INSERT INTO exercise_sets (exercise_id, sequence_no, is_completed, created_at, updated_at) VALUES (?, ?, 0, ?, ?)`, exerciseID, i, timestamp, timestamp); err != nil {
			return 0, err
		}
	}
	if _, err := tx.Exec(`UPDATE workouts SET current_exercise_id = COALESCE(current_exercise_id, ?), updated_at = ? WHERE id = ?`, exerciseID, timestamp, workoutID); err != nil {
		return 0, err
	}
	if err := tx.Commit(); err != nil {
		return 0, err
	}
	return exerciseID, nil
}

func (s *Store) WorkoutExercises(workoutID int) ([]WorkoutExerciseRow, error) {
	rows, err := s.DB.Query(`
		SELECT e.id, et.id, et.title, et.muscle_group, e.sequence_no,
		       COUNT(es.id) AS set_count,
		       SUM(CASE WHEN es.is_completed = 1 THEN 1 ELSE 0 END) AS completed_sets
		FROM exercises e
		JOIN exercise_templates et ON et.id = e.template_id
		LEFT JOIN exercise_sets es ON es.exercise_id = e.id
		WHERE e.workout_id = ?
		GROUP BY e.id, et.id, et.title, et.muscle_group, e.sequence_no
		ORDER BY e.sequence_no ASC
	`, workoutID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WorkoutExerciseRow
	for rows.Next() {
		var item WorkoutExerciseRow
		if err := rows.Scan(&item.ExerciseID, &item.TemplateID, &item.Title, &item.MuscleGroup, &item.SequenceNo, &item.SetCount, &item.CompletedSets); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) CurrentWorkoutExercise(workoutID int) (*WorkoutExerciseRow, int, int, error) {
	workout, err := s.GetWorkout(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	if workout == nil {
		return nil, 0, 0, fmt.Errorf("workout %d not found", workoutID)
	}
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	if len(exercises) == 0 {
		return nil, 0, 0, nil
	}
	currentID := 0
	if workout.CurrentExerciseID.Valid {
		currentID = int(workout.CurrentExerciseID.Int64)
		for i := range exercises {
			if exercises[i].ExerciseID == currentID {
				return &exercises[i], i + 1, len(exercises), nil
			}
		}
	}
	if err := s.SetCurrentWorkoutExercise(workoutID, exercises[0].ExerciseID); err != nil {
		return nil, 0, 0, err
	}
	return &exercises[0], 1, len(exercises), nil
}

func (s *Store) SetCurrentWorkoutExercise(workoutID, exerciseID int) error {
	res, err := s.DB.Exec(`UPDATE workouts SET current_exercise_id = ?, updated_at = ? WHERE id = ?`, exerciseID, now(), workoutID)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("workout %d not found", workoutID)
	}
	return nil
}

func (s *Store) MoveCurrentWorkoutExercise(workoutID, delta int) (*WorkoutExerciseRow, int, int, error) {
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	if len(exercises) == 0 {
		return nil, 0, 0, nil
	}
	_, pos, total, err := s.CurrentWorkoutExercise(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	index := pos - 1 + delta
	if index < 0 {
		index = 0
	}
	if index >= total {
		index = total - 1
	}
	if err := s.SetCurrentWorkoutExercise(workoutID, exercises[index].ExerciseID); err != nil {
		return nil, 0, 0, err
	}
	return &exercises[index], index + 1, total, nil
}

func (s *Store) GotoWorkoutExerciseByEntry(workoutID, exerciseEntryID int) (*WorkoutExerciseRow, int, int, error) {
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	for i := range exercises {
		if exercises[i].ExerciseID == exerciseEntryID {
			if err := s.SetCurrentWorkoutExercise(workoutID, exerciseEntryID); err != nil {
				return nil, 0, 0, err
			}
			return &exercises[i], i + 1, len(exercises), nil
		}
	}
	return nil, 0, 0, fmt.Errorf("exercise entry %d not found in workout %d", exerciseEntryID, workoutID)
}

func (s *Store) GotoWorkoutExerciseByTemplate(workoutID, templateID int) (*WorkoutExerciseRow, int, int, error) {
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return nil, 0, 0, err
	}
	for i := range exercises {
		if exercises[i].TemplateID == templateID {
			if err := s.SetCurrentWorkoutExercise(workoutID, exercises[i].ExerciseID); err != nil {
				return nil, 0, 0, err
			}
			return &exercises[i], i + 1, len(exercises), nil
		}
	}
	return nil, 0, 0, fmt.Errorf("exercise %d not found in workout %d", templateID, workoutID)
}

func (s *Store) WorkoutNote(workoutID int) (string, error) {
	var note sql.NullString
	err := s.DB.QueryRow(`SELECT notes FROM workouts WHERE id = ?`, workoutID).Scan(&note)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("workout %d not found", workoutID)
	}
	if err != nil {
		return "", err
	}
	if !note.Valid {
		return "", nil
	}
	return note.String, nil
}

func (s *Store) UpdateWorkoutNote(workoutID int, note string) error {
	res, err := s.DB.Exec(`UPDATE workouts SET notes = ?, updated_at = ? WHERE id = ?`, nullIfBlank(note), now(), workoutID)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("workout %d not found", workoutID)
	}
	return nil
}

func (s *Store) ExerciseNote(exerciseID int) (string, error) {
	var note sql.NullString
	err := s.DB.QueryRow(`SELECT notes FROM exercises WHERE id = ?`, exerciseID).Scan(&note)
	if err == sql.ErrNoRows {
		return "", fmt.Errorf("exercise %d not found", exerciseID)
	}
	if err != nil {
		return "", err
	}
	if !note.Valid {
		return "", nil
	}
	return note.String, nil
}

func (s *Store) UpdateExerciseNote(exerciseID int, note string) error {
	res, err := s.DB.Exec(`UPDATE exercises SET notes = ?, updated_at = ? WHERE id = ?`, nullIfBlank(note), now(), exerciseID)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("exercise %d not found", exerciseID)
	}
	return nil
}

func (s *Store) ExerciseSets(exerciseID int) ([]SetRow, error) {
	rows, err := s.DB.Query(`SELECT id, sequence_no, weight_in_grams, reps, side, rir, is_completed, notes FROM exercise_sets WHERE exercise_id = ? ORDER BY sequence_no ASC`, exerciseID)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []SetRow
	for rows.Next() {
		var item SetRow
		var completed int
		if err := rows.Scan(&item.ID, &item.SequenceNo, &item.WeightInGrams, &item.Reps, &item.Side, &item.RIR, &completed, &item.Notes); err != nil {
			return nil, err
		}
		item.IsCompleted = completed == 1
		out = append(out, item)
	}
	return out, rows.Err()
}

func (s *Store) WorkoutProgress(workoutID int) (*WorkoutProgressSummary, error) {
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return nil, err
	}

	summary := &WorkoutProgressSummary{}
	muscleGroups := map[string]*MuscleGroupProgress{}

	for _, exercise := range exercises {
		currentSets, err := s.ExerciseSets(exercise.ExerciseID)
		if err != nil {
			return nil, err
		}
		previousSets, err := s.latestCompletedExerciseSets(exercise.TemplateID, workoutID)
		if err != nil {
			return nil, err
		}

		setProgress := compareExerciseSets(currentSets, previousSets)
		exerciseComparableSets := 0
		exerciseProgressedSets := 0
		for _, item := range setProgress {
			if isComparableCompletedSet(item.Set) {
				summary.TotalComparableSets++
				exerciseComparableSets++
				if exercise.MuscleGroup.Valid {
					group := muscleGroups[exercise.MuscleGroup.String]
					if group == nil {
						group = &MuscleGroupProgress{MuscleGroup: exercise.MuscleGroup.String}
						muscleGroups[exercise.MuscleGroup.String] = group
					}
					group.TotalComparableSets++
				}
			}
			if item.Progressed {
				summary.TotalProgressedSets++
				exerciseProgressedSets++
				if exercise.MuscleGroup.Valid {
					group := muscleGroups[exercise.MuscleGroup.String]
					if group == nil {
						group = &MuscleGroupProgress{MuscleGroup: exercise.MuscleGroup.String}
						muscleGroups[exercise.MuscleGroup.String] = group
					}
					group.TotalProgressedSets++
				}
			}
		}
		summary.Exercises = append(summary.Exercises, ExerciseProgress{
			Exercise:            exercise,
			TotalComparableSets: exerciseComparableSets,
			TotalProgressedSets: exerciseProgressedSets,
			Sets:                setProgress,
		})
	}

	for _, item := range muscleGroups {
		summary.MuscleGroups = append(summary.MuscleGroups, *item)
	}
	slices.SortFunc(summary.MuscleGroups, func(a, b MuscleGroupProgress) int {
		if a.TotalProgressedSets != b.TotalProgressedSets {
			return b.TotalProgressedSets - a.TotalProgressedSets
		}
		if a.TotalComparableSets != b.TotalComparableSets {
			return b.TotalComparableSets - a.TotalComparableSets
		}
		return strings.Compare(a.MuscleGroup, b.MuscleGroup)
	})

	return summary, nil
}

func (s *Store) PreviousExerciseSets(templateID, excludingWorkoutID int) ([]SetRow, error) {
	return s.latestCompletedExerciseSets(templateID, excludingWorkoutID)
}

func (s *Store) PreviousExerciseNote(templateID, excludingWorkoutID int) (string, error) {
	var referenceTime string
	var referenceID int
	err := s.DB.QueryRow(`
		SELECT COALESCE(completed_at, started_at, created_at), id
		FROM workouts
		WHERE id = ?
	`, excludingWorkoutID).Scan(&referenceTime, &referenceID)
	if err != nil {
		return "", err
	}

	var note sql.NullString
	err = s.DB.QueryRow(`
		SELECT e.notes
		FROM exercises e
		JOIN workouts w ON w.id = e.workout_id
		WHERE e.template_id = ?
		  AND e.workout_id <> ?
		  AND w.completed_at IS NOT NULL
		  AND e.notes IS NOT NULL
		  AND TRIM(e.notes) <> ''
		  AND (
			w.completed_at < ?
			OR (w.completed_at = ? AND w.id < ?)
		  )
		ORDER BY w.completed_at DESC, w.id DESC, e.id DESC
		LIMIT 1
	`, templateID, excludingWorkoutID, referenceTime, referenceTime, referenceID).Scan(&note)
	if err == sql.ErrNoRows {
		return "", nil
	}
	if err != nil {
		return "", err
	}
	if !note.Valid {
		return "", nil
	}
	return note.String, nil
}

func (s *Store) latestCompletedExerciseSets(templateID, excludingWorkoutID int) ([]SetRow, error) {
	var referenceTime string
	var referenceID int
	err := s.DB.QueryRow(`
		SELECT COALESCE(completed_at, started_at, created_at), id
		FROM workouts
		WHERE id = ?
	`, excludingWorkoutID).Scan(&referenceTime, &referenceID)
	if err != nil {
		return nil, err
	}

	var exerciseID int
	err = s.DB.QueryRow(`
		SELECT e.id
		FROM exercises e
		JOIN workouts w ON w.id = e.workout_id
		WHERE e.template_id = ?
		  AND e.workout_id <> ?
		  AND w.completed_at IS NOT NULL
		  AND EXISTS (
			SELECT 1
			FROM exercise_sets es
			WHERE es.exercise_id = e.id
			  AND es.is_completed = 1
			  AND es.weight_in_grams IS NOT NULL
			  AND es.reps IS NOT NULL
		  )
		  AND (
			w.completed_at < ?
			OR (w.completed_at = ? AND w.id < ?)
		  )
		ORDER BY w.completed_at DESC, w.id DESC, e.id DESC
		LIMIT 1
	`, templateID, excludingWorkoutID, referenceTime, referenceTime, referenceID).Scan(&exerciseID)
	if err == sql.ErrNoRows {
		return nil, nil
	}
	if err != nil {
		return nil, err
	}

	return s.ExerciseSets(exerciseID)
}

func compareExerciseSets(currentSets, previousSets []SetRow) []SetProgress {
	previousBySequence := map[int]SetRow{}
	for _, previous := range comparableCompletedSets(previousSets) {
		previousBySequence[previous.SequenceNo] = previous
	}
	out := make([]SetProgress, 0, len(currentSets))
	for _, current := range currentSets {
		if isEmptyPlaceholderSet(current) {
			continue
		}
		progressed := false
		if previous, ok := previousBySequence[current.SequenceNo]; ok {
			progressed = isProgressedSetSlot(current, previous)
		}
		out = append(out, SetProgress{Set: current, Progressed: progressed})
	}
	return out
}

func comparableCompletedSets(sets []SetRow) []SetRow {
	out := make([]SetRow, 0, len(sets))
	for _, set := range sets {
		if isComparableCompletedSet(set) {
			out = append(out, set)
		}
	}
	return out
}

func isComparableCompletedSet(set SetRow) bool {
	return set.IsCompleted && set.WeightInGrams.Valid && set.Reps.Valid
}

func isEmptyPlaceholderSet(set SetRow) bool {
	return !set.IsCompleted && !set.WeightInGrams.Valid && !set.Reps.Valid && !set.Side.Valid && !set.RIR.Valid && !set.Notes.Valid
}

func isProgressedSetSlot(current, previous SetRow) bool {
	if !isComparableCompletedSet(current) || !isComparableCompletedSet(previous) {
		return false
	}
	if current.WeightInGrams.Int64 == previous.WeightInGrams.Int64 {
		return current.Reps.Int64 > previous.Reps.Int64 && !hasLowerRIR(current.RIR, previous.RIR)
	}
	if current.WeightInGrams.Int64 > previous.WeightInGrams.Int64 {
		return current.Reps.Int64 >= previous.Reps.Int64 && !hasLowerRIR(current.RIR, previous.RIR)
	}
	return false
}

func isProgressedSet(current SetRow, previousSets []SetRow) (bool, *SetRow) {
	if !isComparableCompletedSet(current) || len(previousSets) == 0 {
		return false, nil
	}
	for i := range previousSets {
		previous := previousSets[i]
		if !isComparableCompletedSet(previous) {
			continue
		}
		if current.WeightInGrams.Int64 == previous.WeightInGrams.Int64 && current.Reps.Int64 > previous.Reps.Int64 && !hasLowerRIR(current.RIR, previous.RIR) {
			return true, &previousSets[i]
		}
		if current.WeightInGrams.Int64 > previous.WeightInGrams.Int64 && current.Reps.Int64 >= previous.Reps.Int64 && !hasLowerRIR(current.RIR, previous.RIR) {
			return true, &previousSets[i]
		}
	}
	return false, nil
}

func hasLowerRIR(current, previous sql.NullString) bool {
	if !current.Valid || !previous.Valid {
		return false
	}
	currentValue, err := strconv.ParseFloat(current.String, 64)
	if err != nil {
		return false
	}
	previousValue, err := strconv.ParseFloat(previous.String, 64)
	if err != nil {
		return false
	}
	return currentValue < previousValue
}

func (s *Store) LogSet(exerciseID int, weightInGrams, reps *int, side, rir, notes string) (int, error) {
	var existingID int
	err := s.DB.QueryRow(`
		SELECT id
		FROM exercise_sets
		WHERE exercise_id = ?
		  AND is_completed = 0
		  AND weight_in_grams IS NULL
		  AND reps IS NULL
		  AND side IS NULL
		  AND rir IS NULL
		  AND notes IS NULL
		ORDER BY sequence_no ASC
		LIMIT 1
	`, exerciseID).Scan(&existingID)
	if err != nil && err != sql.ErrNoRows {
		return 0, err
	}
	if err == nil {
		_, err := s.DB.Exec(`
			UPDATE exercise_sets
			SET weight_in_grams = ?, reps = ?, side = ?, rir = ?, notes = ?, is_completed = 1, updated_at = ?
			WHERE id = ?
		`, intPtrValue(weightInGrams), intPtrValue(reps), nullIfBlank(strings.ToUpper(side)), nullIfBlank(rir), nullIfBlank(notes), now(), existingID)
		return existingID, err
	}
	return s.AddSet(exerciseID, weightInGrams, reps, side, rir, notes, true)
}

func (s *Store) SkipSet(exerciseID int) error {
	return s.deleteFirstEmptyPlaceholderSet(exerciseID)
}

func (s *Store) SkipExercise(exerciseID int) error {
	return s.deleteAllEmptyPlaceholderSets(exerciseID)
}

func (s *Store) AddSet(exerciseID int, weightInGrams, reps *int, side, rir, notes string, done bool) (int, error) {
	var next int
	if err := s.DB.QueryRow(`SELECT COALESCE(MAX(sequence_no), 0) + 1 FROM exercise_sets WHERE exercise_id = ?`, exerciseID).Scan(&next); err != nil {
		return 0, err
	}
	res, err := s.DB.Exec(`
		INSERT INTO exercise_sets (exercise_id, weight_in_grams, reps, side, rir, is_completed, sequence_no, notes, created_at, updated_at)
		VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
	`, exerciseID, intPtrValue(weightInGrams), intPtrValue(reps), nullIfBlank(strings.ToUpper(side)), nullIfBlank(rir), boolToInt(done), next, nullIfBlank(notes), now(), now())
	if err != nil {
		return 0, err
	}
	return lastInsertID(res)
}

func (s *Store) cleanupWorkoutEmptyPlaceholderSets(workoutID int) error {
	rows, err := s.DB.Query(`SELECT id FROM exercises WHERE workout_id = ? ORDER BY sequence_no ASC, id ASC`, workoutID)
	if err != nil {
		return err
	}
	defer rows.Close()
	var exerciseIDs []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return err
		}
		exerciseIDs = append(exerciseIDs, id)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	for _, exerciseID := range exerciseIDs {
		if err := s.deleteAllEmptyPlaceholderSetsIfAny(exerciseID); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) deleteFirstEmptyPlaceholderSet(exerciseID int) error {
	var setID int
	err := s.DB.QueryRow(`
		SELECT id
		FROM exercise_sets
		WHERE exercise_id = ?
		  AND is_completed = 0
		  AND weight_in_grams IS NULL
		  AND reps IS NULL
		  AND side IS NULL
		  AND rir IS NULL
		  AND notes IS NULL
		ORDER BY sequence_no ASC
		LIMIT 1
	`, exerciseID).Scan(&setID)
	if err == sql.ErrNoRows {
		return fmt.Errorf("no skipped set available")
	}
	if err != nil {
		return err
	}
	return s.deleteSetAndResequence(exerciseID, setID)
}

func (s *Store) deleteAllEmptyPlaceholderSets(exerciseID int) error {
	deleted, err := s.deleteEmptyPlaceholderSets(exerciseID)
	if err != nil {
		return err
	}
	if deleted == 0 {
		return fmt.Errorf("no skipped sets available")
	}
	return nil
}

func (s *Store) deleteAllEmptyPlaceholderSetsIfAny(exerciseID int) error {
	_, err := s.deleteEmptyPlaceholderSets(exerciseID)
	return err
}

func (s *Store) deleteEmptyPlaceholderSets(exerciseID int) (int, error) {
	rows, err := s.DB.Query(`
		SELECT id
		FROM exercise_sets
		WHERE exercise_id = ?
		  AND is_completed = 0
		  AND weight_in_grams IS NULL
		  AND reps IS NULL
		  AND side IS NULL
		  AND rir IS NULL
		  AND notes IS NULL
		ORDER BY sequence_no ASC
	`, exerciseID)
	if err != nil {
		return 0, err
	}
	defer rows.Close()
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return 0, err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return 0, err
	}
	if len(ids) == 0 {
		return 0, nil
	}
	for _, id := range ids {
		if _, err := s.DB.Exec(`DELETE FROM exercise_sets WHERE id = ?`, id); err != nil {
			return 0, err
		}
	}
	if err := s.resequenceExerciseSets(exerciseID); err != nil {
		return 0, err
	}
	return len(ids), nil
}

func (s *Store) deleteSetAndResequence(exerciseID, setID int) error {
	if _, err := s.DB.Exec(`DELETE FROM exercise_sets WHERE id = ?`, setID); err != nil {
		return err
	}
	return s.resequenceExerciseSets(exerciseID)
}

func (s *Store) resequenceExerciseSets(exerciseID int) error {
	rows, err := s.DB.Query(`SELECT id FROM exercise_sets WHERE exercise_id = ? ORDER BY sequence_no ASC, id ASC`, exerciseID)
	if err != nil {
		return err
	}
	defer rows.Close()
	var ids []int
	for rows.Next() {
		var id int
		if err := rows.Scan(&id); err != nil {
			return err
		}
		ids = append(ids, id)
	}
	if err := rows.Err(); err != nil {
		return err
	}
	timestamp := now()
	for i, id := range ids {
		if _, err := s.DB.Exec(`UPDATE exercise_sets SET sequence_no = ?, updated_at = ? WHERE id = ?`, i+1, timestamp, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) UpdateSet(setID int, weightInGrams *int, reps *int, side, rir string) (int, error) {
	var exerciseID int
	if err := s.DB.QueryRow(`SELECT exercise_id FROM exercise_sets WHERE id = ?`, setID).Scan(&exerciseID); err != nil {
		if err == sql.ErrNoRows {
			return 0, fmt.Errorf("set %d not found", setID)
		}
		return 0, err
	}
	res, err := s.DB.Exec(`
		UPDATE exercise_sets
		SET weight_in_grams = ?, reps = ?, side = ?, rir = ?, is_completed = 1, updated_at = ?
		WHERE id = ?
	`, intPtrValue(weightInGrams), intPtrValue(reps), nullIfBlank(strings.ToUpper(side)), nullIfBlank(rir), now(), setID)
	if err != nil {
		return 0, err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return 0, err
	}
	if count == 0 {
		return 0, fmt.Errorf("set %d not found", setID)
	}
	return exerciseID, nil
}

func (s *Store) UndoLastSet(exerciseID int) error {
	var setID int
	err := s.DB.QueryRow(`
		SELECT id
		FROM exercise_sets
		WHERE exercise_id = ? AND is_completed = 1
		ORDER BY sequence_no DESC, id DESC
		LIMIT 1
	`, exerciseID).Scan(&setID)
	if err == sql.ErrNoRows {
		return fmt.Errorf("no completed set to undo")
	}
	if err != nil {
		return err
	}
	return s.deleteSetAndResequence(exerciseID, setID)
}

func (s *Store) SetWorkoutExerciseSetCount(exerciseID, setCount int) error {
	if setCount < 0 {
		return fmt.Errorf("set count must be >= 0")
	}
	var completed int
	if err := s.DB.QueryRow(`SELECT COUNT(*) FROM exercise_sets WHERE exercise_id = ? AND is_completed = 1`, exerciseID).Scan(&completed); err != nil {
		return err
	}
	if completed > setCount {
		return fmt.Errorf("exercise has %d completed sets; cannot reduce to %d", completed, setCount)
	}
	for {
		var count int
		if err := s.DB.QueryRow(`SELECT COUNT(*) FROM exercise_sets WHERE exercise_id = ?`, exerciseID).Scan(&count); err != nil {
			return err
		}
		if count == setCount {
			return nil
		}
		if count < setCount {
			if _, err := s.AddSet(exerciseID, nil, nil, "", "", "", false); err != nil {
				return err
			}
			continue
		}
		if err := s.deleteFirstEmptyPlaceholderSet(exerciseID); err != nil {
			return err
		}
	}
}

func (s *Store) MoveWorkoutExercise(workoutID, exerciseID, beforeExerciseID int) error {
	exercises, err := s.WorkoutExercises(workoutID)
	if err != nil {
		return err
	}
	ids := make([]int, 0, len(exercises))
	foundMove := false
	foundBefore := beforeExerciseID == 0
	for _, ex := range exercises {
		if ex.ExerciseID == exerciseID {
			foundMove = true
			continue
		}
		if ex.ExerciseID == beforeExerciseID {
			ids = append(ids, exerciseID)
			foundBefore = true
		}
		ids = append(ids, ex.ExerciseID)
	}
	if !foundMove {
		return fmt.Errorf("exercise entry %d not found in workout %d", exerciseID, workoutID)
	}
	if !foundBefore {
		return fmt.Errorf("before entry %d not found in workout %d", beforeExerciseID, workoutID)
	}
	if beforeExerciseID == 0 {
		ids = append(ids, exerciseID)
	}
	timestamp := now()
	for i, id := range ids {
		if _, err := s.DB.Exec(`UPDATE exercises SET sequence_no = ?, updated_at = ? WHERE id = ?`, i+1, timestamp, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) ResolveWorkoutExerciseEntry(workoutID, exerciseTemplateID int) (int, error) {
	var entryID int
	err := s.DB.QueryRow(`SELECT id FROM exercises WHERE workout_id = ? AND template_id = ? ORDER BY sequence_no ASC, id ASC LIMIT 1`, workoutID, exerciseTemplateID).Scan(&entryID)
	if err == sql.ErrNoRows {
		return 0, fmt.Errorf("exercise %d not found in workout %d", exerciseTemplateID, workoutID)
	}
	return entryID, err
}

func (s *Store) SetTemplateExerciseSetCount(templateID, exerciseTemplateID, setCount int) error {
	if setCount < 0 {
		return fmt.Errorf("set count must be >= 0")
	}
	res, err := s.DB.Exec(`UPDATE workout_template_exercises SET set_count = ?, updated_at = ? WHERE workout_template_id = ? AND exercise_template_id = ?`, nullableZero(setCount), now(), templateID, exerciseTemplateID)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("exercise %d not found in template %d", exerciseTemplateID, templateID)
	}
	return nil
}

func (s *Store) ReplaceTemplateExercise(templateID, fromExerciseTemplateID, toExerciseTemplateID int) error {
	res, err := s.DB.Exec(`
		UPDATE workout_template_exercises
		SET exercise_template_id = ?, updated_at = ?
		WHERE workout_template_id = ? AND exercise_template_id = ?
	`, toExerciseTemplateID, now(), templateID, fromExerciseTemplateID)
	if err != nil {
		return err
	}
	count, err := res.RowsAffected()
	if err != nil {
		return err
	}
	if count == 0 {
		return fmt.Errorf("exercise %d not found in template %d", fromExerciseTemplateID, templateID)
	}
	return nil
}

func (s *Store) MoveTemplateExercise(templateID, exerciseTemplateID, beforeExerciseTemplateID int) error {
	exercises, err := s.GetTemplateExercises(templateID)
	if err != nil {
		return err
	}
	moveLinkID := 0
	for _, ex := range exercises {
		if ex.ExerciseID == exerciseTemplateID {
			moveLinkID = ex.LinkID
			break
		}
	}
	if moveLinkID == 0 {
		return fmt.Errorf("exercise %d not found in template %d", exerciseTemplateID, templateID)
	}
	ids := make([]int, 0, len(exercises))
	foundBefore := beforeExerciseTemplateID == 0
	for _, ex := range exercises {
		if ex.ExerciseID == exerciseTemplateID {
			continue
		}
		if ex.ExerciseID == beforeExerciseTemplateID {
			ids = append(ids, moveLinkID)
			foundBefore = true
		}
		ids = append(ids, ex.LinkID)
	}
	if !foundBefore {
		return fmt.Errorf("before exercise %d not found in template %d", beforeExerciseTemplateID, templateID)
	}
	if beforeExerciseTemplateID == 0 {
		ids = append(ids, moveLinkID)
	}
	timestamp := now()
	for i, id := range ids {
		if _, err := s.DB.Exec(`UPDATE workout_template_exercises SET sequence_no = ?, updated_at = ? WHERE id = ?`, i+1, timestamp, id); err != nil {
			return err
		}
	}
	return nil
}

func (s *Store) AddWeight(kg float64, at string) (int, error) {
	grams := int(kg * 1000)
	if strings.TrimSpace(at) == "" {
		at = now()
	}
	res, err := s.DB.Exec(`INSERT INTO weight_entries (weight_in_grams, created_at, updated_at) VALUES (?, ?, ?)`, grams, at, now())
	if err != nil {
		return 0, err
	}
	return lastInsertID(res)
}

func (s *Store) ListWeights(limit int) ([]WeightEntry, error) {
	rows, err := s.DB.Query(`SELECT id, weight_in_grams, created_at FROM weight_entries ORDER BY created_at DESC LIMIT ?`, limit)
	if err != nil {
		return nil, err
	}
	defer rows.Close()
	var out []WeightEntry
	for rows.Next() {
		var item WeightEntry
		if err := rows.Scan(&item.ID, &item.WeightInGrams, &item.CreatedAt); err != nil {
			return nil, err
		}
		out = append(out, item)
	}
	return out, rows.Err()
}

func intPtrValue(v *int) any {
	if v == nil {
		return nil
	}
	return *v
}

func boolToInt(v bool) int {
	if v {
		return 1
	}
	return 0
}

func nullIfBlank(v string) any {
	if strings.TrimSpace(v) == "" {
		return nil
	}
	return v
}

func defaultIfBlank(v, fallback string) string {
	if strings.TrimSpace(v) == "" {
		return fallback
	}
	return v
}

func max(a, b int) int {
	if a > b {
		return a
	}
	return b
}

func lastInsertID(res sql.Result) (int, error) {
	id, err := res.LastInsertId()
	if err != nil {
		return 0, err
	}
	return int(id), nil
}
