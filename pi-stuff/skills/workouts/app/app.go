package app

import (
	"errors"
	"flag"
	"fmt"
	"os"
	"path/filepath"
	"strconv"
	"strings"

	"github.com/simonnieder/fullstack/db"
)

type App struct {
	store *db.Store
}

func NewApp() (*App, error) {
	path := os.Getenv("FULLSTACK_DB_PATH")
	if strings.TrimSpace(path) == "" {
		exe, err := os.Executable()
		if err != nil {
			return nil, err
		}
		path = filepath.Join(filepath.Dir(exe), "fullstack.db")
	}
	st, err := db.Open(path)
	if err != nil {
		return nil, err
	}
	if err := st.SeedExerciseTemplates(db.DefaultExerciseTemplates); err != nil {
		_ = st.Close()
		return nil, err
	}
	return &App{store: st}, nil
}

func (a *App) Close() error { return a.store.Close() }

func (a *App) Run(args []string) error {
	if len(args) == 0 {
		a.printHelp()
		return nil
	}
	switch args[0] {
	case "exercise":
		return a.runExercise(args[1:])
	case "template":
		return a.runTemplate(args[1:])
	case "workout":
		return a.runWorkout(args[1:])
	case "weight":
		return a.runWeight(args[1:])
	case "help", "--help", "-h":
		a.printHelp()
		return nil
	default:
		return fmt.Errorf("unknown command %q", args[0])
	}
}

func (a *App) printHelp() {
	fmt.Println(`fullstack - local workout tracker CLI

Commands:
  exercise list
  exercise show <exercise-id>
  exercise create --name <name> [--muscle <group>] [--sets <n>] [--lateral bilateral|unilateral]

  template list
  template create --name <name> [--description <text>] [--type <type>]
  template show <template-id>
  template add-exercise <template-id> --exercise <exercise-id> [--sets <n>]

  workout start [--template <template-id>] [--name <title>]
  workout prompt
  workout next
  workout prev
  workout goto --exercise <exercise-id> | --entry <exercise-entry-id>
  workout log --weight-kg <kg> --reps <n> [--rir <value>] [--side left|right|none] [--exercise-entry <exercise-entry-id>]
  workout note --text <text> [--exercise-entry <exercise-entry-id>]
  workout skip-set [--exercise-entry <exercise-entry-id>]
  workout skip-exercise [--exercise-entry <exercise-entry-id>]
  workout current
  workout list
  workout show <workout-id>
  workout finish [<workout-id>]
  workout add-exercise --exercise <exercise-id>

  weight add --kg <kg> [--at <RFC3339>]
  weight list [--limit <n>]

Env:
  FULLSTACK_DB_PATH=/path/to/fullstack.db
`)
}

func (a *App) runExercise(args []string) error {
	if len(args) == 0 {
		return errors.New("exercise command required")
	}
	switch args[0] {
	case "list":
		items, err := a.store.ListExercises()
		if err != nil {
			return err
		}
		for _, item := range items {
			fmt.Printf("%d\t%s", item.ID, item.Title)
			if item.MuscleGroup.Valid {
				fmt.Printf("\t%s", item.MuscleGroup.String)
			}
			if item.DefaultSetCount.Valid {
				fmt.Printf("\tsets=%d", item.DefaultSetCount.Int64)
			}
			fmt.Println()
		}
		return nil
	case "show":
		if len(args) < 2 {
			return errors.New("usage: fullstack exercise show <exercise-id>")
		}
		id, err := parseIntID("exercise-id", args[1])
		if err != nil {
			return err
		}
		item, err := a.store.GetExercise(id)
		if err != nil {
			return err
		}
		if item == nil {
			return fmt.Errorf("exercise %d not found", id)
		}
		fmt.Printf("id: %d\nname: %s\nlateral: %s\n", item.ID, item.Title, item.LateralType)
		if item.MuscleGroup.Valid {
			fmt.Printf("muscle: %s\n", item.MuscleGroup.String)
		}
		if item.DefaultSetCount.Valid {
			fmt.Printf("default sets: %d\n", item.DefaultSetCount.Int64)
		}
		return nil
	case "create":
		fs := flag.NewFlagSet("exercise create", flag.ContinueOnError)
		name := fs.String("name", "", "exercise name")
		muscle := fs.String("muscle", "", "muscle group")
		sets := fs.Int("sets", 0, "default set count")
		lateral := fs.String("lateral", "bilateral", "bilateral|unilateral")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		if strings.TrimSpace(*name) == "" {
			return errors.New("--name is required")
		}
		id, err := a.store.CreateExercise(*name, strings.ToUpper(*muscle), *sets, strings.ToUpper(*lateral))
		if err != nil {
			return err
		}
		fmt.Println(id)
		return nil
	default:
		return fmt.Errorf("unknown exercise command %q", args[0])
	}
}

func (a *App) runTemplate(args []string) error {
	if len(args) == 0 {
		return errors.New("template command required")
	}
	switch args[0] {
	case "list":
		items, err := a.store.ListTemplates()
		if err != nil {
			return err
		}
		for _, item := range items {
			fmt.Printf("%d\t%s\n", item.ID, item.Title)
		}
		return nil
	case "create":
		fs := flag.NewFlagSet("template create", flag.ContinueOnError)
		name := fs.String("name", "", "template name")
		description := fs.String("description", "", "description")
		typeValue := fs.String("type", "WORKOUT", "template type")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		if strings.TrimSpace(*name) == "" {
			return errors.New("--name is required")
		}
		id, err := a.store.CreateTemplate(*name, *description, *typeValue)
		if err != nil {
			return err
		}
		fmt.Println(id)
		return nil
	case "show":
		if len(args) < 2 {
			return errors.New("usage: fullstack template show <template-id>")
		}
		id, err := parseIntID("template-id", args[1])
		if err != nil {
			return err
		}
		exercises, err := a.store.GetTemplateExercises(id)
		if err != nil {
			return err
		}
		fmt.Printf("template: %d\n", id)
		for _, item := range exercises {
			setCount := item.SetCount
			if !setCount.Valid {
				setCount = item.DefaultSetCount
			}
			fmt.Printf("%d. %s (%s) [exercise=%d]", item.SequenceNo, item.ExerciseTitle, nullString(item.MuscleGroup.String, item.MuscleGroup.Valid), item.ExerciseID)
			if setCount.Valid {
				fmt.Printf(" sets=%d", setCount.Int64)
			}
			fmt.Println()
		}
		return nil
	case "add-exercise":
		if len(args) < 2 {
			return errors.New("usage: fullstack template add-exercise <template-id> --exercise <exercise-id> [--sets <n>]")
		}
		templateID, err := parseIntID("template-id", args[1])
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("template add-exercise", flag.ContinueOnError)
		exerciseID := fs.Int("exercise", 0, "exercise template id")
		sets := fs.Int("sets", 0, "override set count")
		if err := fs.Parse(args[2:]); err != nil {
			return err
		}
		if *exerciseID <= 0 {
			return errors.New("--exercise is required")
		}
		if err := a.store.AddExerciseToTemplate(templateID, *exerciseID, *sets); err != nil {
			return err
		}
		fmt.Println("ok")
		return nil
	default:
		return fmt.Errorf("unknown template command %q", args[0])
	}
}

func (a *App) runWorkout(args []string) error {
	if len(args) == 0 {
		return errors.New("workout command required")
	}
	switch args[0] {
	case "start":
		fs := flag.NewFlagSet("workout start", flag.ContinueOnError)
		templateIDValue := fs.Int("template", 0, "template id")
		name := fs.String("name", "", "title")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		var templateID *int
		if *templateIDValue > 0 {
			templateID = templateIDValue
		}
		id, err := a.store.StartWorkout(templateID, *name)
		if err != nil {
			return err
		}
		fmt.Printf("started workout %d\n\n", id)
		return a.printWorkoutPrompt(id)
	case "prompt":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "next":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		if _, _, _, err := a.store.MoveCurrentWorkoutExercise(id, 1); err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "prev":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		if _, _, _, err := a.store.MoveCurrentWorkoutExercise(id, -1); err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "goto":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("workout goto", flag.ContinueOnError)
		exerciseID := fs.Int("exercise", 0, "exercise template id")
		entryID := fs.Int("entry", 0, "workout exercise entry id")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		if *exerciseID > 0 {
			if _, _, _, err := a.store.GotoWorkoutExerciseByTemplate(id, *exerciseID); err != nil {
				return err
			}
		} else if *entryID > 0 {
			if _, _, _, err := a.store.GotoWorkoutExerciseByEntry(id, *entryID); err != nil {
				return err
			}
		} else {
			return errors.New("usage: fullstack workout goto --exercise <exercise-id> | --entry <exercise-entry-id>")
		}
		return a.printWorkoutPrompt(id)
	case "log":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("workout log", flag.ContinueOnError)
		exerciseEntry := fs.Int("exercise-entry", 0, "workout exercise entry id")
		weightKg := fs.String("weight-kg", "", "weight in kg")
		reps := fs.Int("reps", 0, "reps")
		rir := fs.String("rir", "", "rir value like 0, 0.5, 1, 2")
		side := fs.String("side", "", "left|right|none")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		entryID := *exerciseEntry
		if entryID <= 0 {
			currentExercise, _, _, err := a.store.CurrentWorkoutExercise(id)
			if err != nil {
				return err
			}
			if currentExercise == nil {
				return errors.New("current workout has no exercises")
			}
			entryID = currentExercise.ExerciseID
		}
		if strings.TrimSpace(*weightKg) == "" {
			return errors.New("--weight-kg is required")
		}
		if *reps <= 0 {
			return errors.New("--reps must be > 0")
		}
		grams, repsPtr, err := parseLoggedSet(*weightKg, *reps)
		if err != nil {
			return err
		}
		if _, err := a.store.LogSet(entryID, grams, repsPtr, strings.ToUpper(*side), *rir, ""); err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "note":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("workout note", flag.ContinueOnError)
		exerciseEntry := fs.Int("exercise-entry", 0, "workout exercise entry id")
		text := fs.String("text", "", "exercise note")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		entryID := *exerciseEntry
		if entryID <= 0 {
			currentExercise, _, _, err := a.store.CurrentWorkoutExercise(id)
			if err != nil {
				return err
			}
			if currentExercise == nil {
				return errors.New("current workout has no exercises")
			}
			entryID = currentExercise.ExerciseID
		}
		if err := a.store.UpdateExerciseNote(entryID, *text); err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "skip-set":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("workout skip-set", flag.ContinueOnError)
		exerciseEntry := fs.Int("exercise-entry", 0, "workout exercise entry id")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		entryID := *exerciseEntry
		if entryID <= 0 {
			currentExercise, _, _, err := a.store.CurrentWorkoutExercise(id)
			if err != nil {
				return err
			}
			if currentExercise == nil {
				return errors.New("current workout has no exercises")
			}
			entryID = currentExercise.ExerciseID
		}
		if err := a.store.SkipSet(entryID); err != nil {
			return err
		}
		return a.printWorkoutPrompt(id)
	case "skip-exercise":
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		fs := flag.NewFlagSet("workout skip-exercise", flag.ContinueOnError)
		exerciseEntry := fs.Int("exercise-entry", 0, "workout exercise entry id")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		entryID := *exerciseEntry
		if entryID <= 0 {
			currentExercise, _, _, err := a.store.CurrentWorkoutExercise(id)
			if err != nil {
				return err
			}
			if currentExercise == nil {
				return errors.New("current workout has no exercises")
			}
			entryID = currentExercise.ExerciseID
		}
		if err := a.store.SkipExercise(entryID); err != nil {
			return err
		}
		workout, err := a.store.GetWorkout(id)
		if err != nil {
			return err
		}
		if workout != nil && workout.CurrentExerciseID.Valid && int(workout.CurrentExerciseID.Int64) == entryID {
			if _, _, _, err := a.store.MoveCurrentWorkoutExercise(id, 1); err != nil {
				return err
			}
		}
		return a.printWorkoutPrompt(id)
	case "current":
		item, err := a.store.GetCurrentWorkout()
		if err != nil {
			return err
		}
		if item == nil {
			fmt.Println("no active workout")
			return nil
		}
		return a.printWorkout(item.ID)
	case "list":
		items, err := a.store.ListWorkouts()
		if err != nil {
			return err
		}
		for _, item := range items {
			status := "active"
			if item.CompletedAt.Valid {
				status = "completed"
			}
			fmt.Printf("%d\t%s\t%s\n", item.ID, item.Title, status)
		}
		return nil
	case "show":
		if len(args) < 2 {
			return errors.New("usage: fullstack workout show <workout-id>")
		}
		id, err := parseIntID("workout-id", args[1])
		if err != nil {
			return err
		}
		return a.printWorkout(id)
	case "finish":
		if len(args) >= 2 {
			id, err := parseIntID("workout-id", args[1])
			if err != nil {
				return err
			}
			if err := a.store.FinishWorkout(id); err != nil {
				return err
			}
			fmt.Println("ok")
			return nil
		}
		id, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		if err := a.store.FinishWorkout(id); err != nil {
			return err
		}
		fmt.Println("ok")
		return nil
	case "add-exercise":
		fs := flag.NewFlagSet("workout add-exercise", flag.ContinueOnError)
		exerciseID := fs.Int("exercise", 0, "exercise template id")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		if *exerciseID <= 0 {
			return errors.New("--exercise is required")
		}
		workoutID, err := a.resolveCurrentWorkoutID()
		if err != nil {
			return err
		}
		id, err := a.store.AddExerciseToWorkout(workoutID, *exerciseID)
		if err != nil {
			return err
		}
		fmt.Println(id)
		return nil
	default:
		return fmt.Errorf("unknown workout command %q", args[0])
	}
}

func (a *App) runWeight(args []string) error {
	if len(args) == 0 {
		return errors.New("weight command required")
	}
	switch args[0] {
	case "add":
		fs := flag.NewFlagSet("weight add", flag.ContinueOnError)
		kg := fs.Float64("kg", 0, "weight in kg")
		at := fs.String("at", "", "RFC3339 timestamp")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		if *kg <= 0 {
			return errors.New("--kg must be > 0")
		}
		id, err := a.store.AddWeight(*kg, *at)
		if err != nil {
			return err
		}
		fmt.Println(id)
		return nil
	case "list":
		fs := flag.NewFlagSet("weight list", flag.ContinueOnError)
		limit := fs.Int("limit", 20, "result limit")
		if err := fs.Parse(args[1:]); err != nil {
			return err
		}
		items, err := a.store.ListWeights(*limit)
		if err != nil {
			return err
		}
		for _, item := range items {
			fmt.Printf("%d\t%.1fkg\t%s\n", item.ID, float64(item.WeightInGrams)/1000.0, item.CreatedAt)
		}
		return nil
	default:
		return fmt.Errorf("unknown weight command %q", args[0])
	}
}

func (a *App) resolveCurrentWorkoutID() (int, error) {
	item, err := a.store.GetCurrentWorkout()
	if err != nil {
		return 0, err
	}
	if item == nil {
		return 0, errors.New("no active workout")
	}
	return item.ID, nil
}

func (a *App) printWorkout(id int) error {
	workout, err := a.store.GetWorkout(id)
	if err != nil {
		return err
	}
	if workout == nil {
		return fmt.Errorf("workout %d not found", id)
	}
	status := "active"
	if workout.CompletedAt.Valid {
		status = "completed"
	}
	fmt.Printf("id: %d\ntitle: %s\nstatus: %s\n", workout.ID, workout.Title, status)
	if workout.StartedAt.Valid {
		fmt.Printf("started: %s\n", workout.StartedAt.String)
	}
	if workout.CompletedAt.Valid {
		fmt.Printf("completed: %s\n", workout.CompletedAt.String)
	}
	exercises, err := a.store.WorkoutExercises(id)
	if err != nil {
		return err
	}
	progress, err := a.store.WorkoutProgress(id)
	if err != nil {
		return err
	}
	fmt.Printf("progress: %d/%d exercises progressed\n", progress.TotalProgressedExercises, progress.TotalExercises)
	if len(progress.MuscleGroups) > 0 {
		fmt.Println("muscle groups:")
		for _, item := range progress.MuscleGroups {
			fmt.Printf("  - %s: %d/%d progressed\n", item.MuscleGroup, item.ProgressedExercises, item.TotalExercises)
		}
	}
	progressByExerciseID := map[int]db.ExerciseProgress{}
	for _, item := range progress.Exercises {
		progressByExerciseID[item.Exercise.ExerciseID] = item
	}
	currentExercise, _, _, err := a.store.CurrentWorkoutExercise(id)
	if err != nil {
		return err
	}
	for _, ex := range exercises {
		exProgress := progressByExerciseID[ex.ExerciseID]
		progressLabel := "not progressed"
		if exProgress.Progressed {
			progressLabel = "progressed"
		}
		currentMarker := ""
		if currentExercise != nil && currentExercise.ExerciseID == ex.ExerciseID {
			currentMarker = " <- current"
		}
		fmt.Printf("\n%d. %s [%s] entry=%d %d/%d complete %s%s\n", ex.SequenceNo, ex.Title, nullString(ex.MuscleGroup.String, ex.MuscleGroup.Valid), ex.ExerciseID, ex.CompletedSets, ex.SetCount, progressLabel, currentMarker)
		sets, err := a.store.ExerciseSets(ex.ExerciseID)
		if err != nil {
			return err
		}
		for _, set := range sets {
			fmt.Printf("  - set %d id=%d", set.SequenceNo, set.ID)
			if set.WeightInGrams.Valid {
				fmt.Printf(" %.1fkg", float64(set.WeightInGrams.Int64)/1000.0)
			}
			if set.Reps.Valid {
				fmt.Printf(" x %d", set.Reps.Int64)
			}
			if set.RIR.Valid {
				fmt.Printf(" @ %s rir", set.RIR.String)
			}
			if set.Side.Valid {
				fmt.Printf(" side=%s", set.Side.String)
			}
			if set.IsCompleted {
				fmt.Printf(" [done]")
			}
			fmt.Println()
		}
	}
	return nil
}

func (a *App) printWorkoutPrompt(workoutID int) error {
	workout, err := a.store.GetWorkout(workoutID)
	if err != nil {
		return err
	}
	if workout == nil {
		return fmt.Errorf("workout %d not found", workoutID)
	}
	currentExercise, position, total, err := a.store.CurrentWorkoutExercise(workoutID)
	if err != nil {
		return err
	}
	fmt.Printf("workout: %s\n", workout.Title)
	if currentExercise == nil {
		fmt.Println("exercise: none")
		fmt.Println("next: add an exercise or finish workout")
		return nil
	}
	fmt.Printf("exercise: %s\n", currentExercise.Title)
	fmt.Printf("entry: %d\n", currentExercise.ExerciseID)
	fmt.Printf("position: %d/%d\n", position, total)
	if currentExercise.MuscleGroup.Valid {
		fmt.Printf("muscle: %s\n", currentExercise.MuscleGroup.String)
	}
	fmt.Printf("sets: %d/%d\n", currentExercise.CompletedSets, currentExercise.SetCount)
	previousSets, err := a.store.PreviousExerciseSets(currentExercise.TemplateID, workoutID)
	if err != nil {
		return err
	}
	fmt.Println()
	fmt.Println("last time:")
	if len(previousSets) == 0 {
		fmt.Println("  - none")
	} else {
		for _, set := range previousSets {
			fmt.Printf("  - %s\n", formatPromptSet(set))
		}
	}
	note, err := a.store.ExerciseNote(currentExercise.ExerciseID)
	if err != nil {
		return err
	}
	if strings.TrimSpace(note) != "" {
		fmt.Printf("note: %s\n", note)
	}
	currentSets, err := a.store.ExerciseSets(currentExercise.ExerciseID)
	if err != nil {
		return err
	}
	fmt.Println("today:")
	logged := 0
	for _, set := range currentSets {
		if !set.IsCompleted && !set.WeightInGrams.Valid && !set.Reps.Valid && !set.RIR.Valid && !set.Side.Valid && !set.Notes.Valid {
			continue
		}
		logged++
		fmt.Printf("  - %s\n", formatPromptSet(set))
	}
	if logged == 0 {
		fmt.Println("  - no sets logged")
	}
	fmt.Println("next:")
	fmt.Println("  log a set, say next/prev, jump to another exercise, or finish workout")
	return nil
}

func formatPromptSet(set db.SetRow) string {
	parts := []string{fmt.Sprintf("set %d", set.SequenceNo)}
	if set.WeightInGrams.Valid {
		parts = append(parts, fmt.Sprintf("%.1fkg", float64(set.WeightInGrams.Int64)/1000.0))
	}
	if set.Reps.Valid {
		parts = append(parts, fmt.Sprintf("x %d", set.Reps.Int64))
	}
	if set.RIR.Valid {
		parts = append(parts, fmt.Sprintf("@ %s rir", set.RIR.String))
	}
	if set.Side.Valid {
		parts = append(parts, fmt.Sprintf("side=%s", set.Side.String))
	}
	if set.IsCompleted {
		parts = append(parts, "[done]")
	}
	return strings.Join(parts, " ")
}

func parseLoggedSet(weightKg string, reps int) (*int, *int, error) {
	var grams *int
	if strings.TrimSpace(weightKg) != "" {
		parsed, err := strconv.ParseFloat(weightKg, 64)
		if err != nil {
			return nil, nil, fmt.Errorf("invalid --weight-kg: %w", err)
		}
		v := int(parsed * 1000)
		grams = &v
	}
	var repsPtr *int
	if reps > 0 {
		repsPtr = &reps
	}
	return grams, repsPtr, nil
}

func parseIntID(name, value string) (int, error) {
	id, err := strconv.Atoi(value)
	if err != nil || id <= 0 {
		return 0, fmt.Errorf("invalid %s %q", name, value)
	}
	return id, nil
}

func nullString(value string, valid bool) string {
	if !valid || strings.TrimSpace(value) == "" {
		return "-"
	}
	return value
}
