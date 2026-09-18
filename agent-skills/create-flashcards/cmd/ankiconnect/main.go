package main

import (
	"bytes"
	"encoding/json"
	"errors"
	"flag"
	"fmt"
	"io"
	"net/http"
	"os"
	"strings"
	"time"
)

type Client struct {
	URL        string
	HTTPClient *http.Client
}

type request struct {
	Action  string      `json:"action"`
	Version int         `json:"version"`
	Params  interface{} `json:"params,omitempty"`
}

type response struct {
	Result json.RawMessage `json:"result"`
	Error  interface{}     `json:"error"`
}

type note struct {
	DeckName  string            `json:"deckName"`
	ModelName string            `json:"modelName"`
	Fields    map[string]string `json:"fields"`
	Tags      []string          `json:"tags,omitempty"`
}

type addNotesParams struct {
	Notes []note `json:"notes"`
}

type notePayload struct {
	Action  string         `json:"action"`
	Version int            `json:"version"`
	Params  addNotesParams `json:"params"`
}

type notesOnly struct {
	Notes []note `json:"notes"`
}

type noteInfo struct {
	NoteID    int64               `json:"noteId"`
	ModelName string              `json:"modelName"`
	Tags      []string            `json:"tags"`
	Fields    map[string]noteField `json:"fields"`
	Cards     []int64             `json:"cards"`
}

type noteField struct {
	Value string `json:"value"`
	Order int    `json:"order"`
}

type updateNote struct {
	ID     int64             `json:"id"`
	Fields map[string]string `json:"fields"`
}

type updatePayload struct {
	Notes []updateNote `json:"notes"`
}

func main() {
	os.Exit(run())
}

func run() int {
	if len(os.Args) < 2 {
		usage()
		return 2
	}

	cmd := os.Args[1]
	switch cmd {
	case "version":
		return cmdVersion(os.Args[2:])
	case "decks":
		return cmdDecks(os.Args[2:])
	case "create-deck":
		return cmdCreateDeck(os.Args[2:])
	case "models":
		return cmdModels(os.Args[2:])
	case "stats":
		return cmdStats(os.Args[2:])
	case "can-add":
		return cmdCanAdd(os.Args[2:])
	case "add":
		return cmdAdd(os.Args[2:])
	case "search":
		return cmdSearch(os.Args[2:])
	case "delete":
		return cmdDelete(os.Args[2:])
	case "update":
		return cmdUpdate(os.Args[2:])
	case "add-tags":
		return cmdAddTags(os.Args[2:])
	case "remove-tags":
		return cmdRemoveTags(os.Args[2:])
	case "snapshot":
		return cmdSnapshot(os.Args[2:])
	case "suspend":
		return cmdCardState("suspend", "suspend", os.Args[2:])
	case "unsuspend":
		return cmdCardState("unsuspend", "unsuspend", os.Args[2:])
	default:
		fmt.Fprintf(os.Stderr, "unknown command: %s\n\n", cmd)
		usage()
		return 2
	}
}

func usage() {
	fmt.Fprintf(os.Stderr, `ankiconnect - small CLI for AnkiConnect

Usage:
  ankiconnect [global flags] version
  ankiconnect [global flags] decks
  ankiconnect [global flags] create-deck -name "LBAI"
  ankiconnect [global flags] models
  ankiconnect [global flags] stats -deck "ML EXAM"
  ankiconnect [global flags] can-add -file cards.json
  ankiconnect [global flags] add -file cards.json [-dry-run] [-allow-duplicates]
  ankiconnect [global flags] search -query 'deck:"ML EXAM" tag:...'
  ankiconnect [global flags] delete -notes 123,456 [-dry-run]
  ankiconnect [global flags] update -file updates.json [-dry-run]
  ankiconnect [global flags] add-tags -notes 123,456 -tags 'tag1 tag2' [-dry-run]
  ankiconnect [global flags] remove-tags -notes 123,456 -tags 'tag1 tag2' [-dry-run]
  ankiconnect [global flags] snapshot -query 'deck:"LBAI"'
  ankiconnect [global flags] suspend -cards 123,456 [-dry-run]
  ankiconnect [global flags] unsuspend -cards 123,456 [-dry-run]

Global flags:
  -url       AnkiConnect URL (default http://127.0.0.1:8765)
  -timeout   Request timeout (default 10s)

Input formats for -file:
  1. Full AnkiConnect payload:
     {"action":"addNotes","version":6,"params":{"notes":[...]}}
  2. Bare notes payload:
     {"notes":[...]}

Behavior:
  add first calls canAddNotes and only adds notes Anki says are new,
  unless -allow-duplicates is set.
`)
}

func newClient(fs *flag.FlagSet) (*Client, error) {
	url := fs.Lookup("url").Value.String()
	timeoutText := fs.Lookup("timeout").Value.String()
	timeout, err := time.ParseDuration(timeoutText)
	if err != nil {
		return nil, fmt.Errorf("invalid timeout: %w", err)
	}
	return &Client{
		URL: url,
		HTTPClient: &http.Client{Timeout: timeout},
	}, nil
}

func addGlobalFlags(fs *flag.FlagSet) {
	fs.String("url", envOr("ANKI_CONNECT_URL", "http://127.0.0.1:8765"), "AnkiConnect URL")
	fs.String("timeout", envOr("ANKI_CONNECT_TIMEOUT", "10s"), "request timeout")
}

func cmdVersion(args []string) int {
	fs := flag.NewFlagSet("version", flag.ContinueOnError)
	addGlobalFlags(fs)
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var v int
	if err := client.call("version", nil, &v); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	fmt.Println(v)
	return 0
}

func cmdDecks(args []string) int {
	fs := flag.NewFlagSet("decks", flag.ContinueOnError)
	addGlobalFlags(fs)
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var decks []string
	if err := client.call("deckNames", nil, &decks); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	for _, deck := range decks {
		fmt.Println(deck)
	}
	return 0
}

func cmdCreateDeck(args []string) int {
	fs := flag.NewFlagSet("create-deck", flag.ContinueOnError)
	addGlobalFlags(fs)
	name := fs.String("name", "", "deck name")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if strings.TrimSpace(*name) == "" {
		fmt.Fprintln(os.Stderr, "-name is required")
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var created int64
	if err := client.call("createDeck", map[string]string{"deck": *name}, &created); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printJSON(map[string]interface{}{"deck": *name, "id": created})
	return 0
}

func cmdModels(args []string) int {
	fs := flag.NewFlagSet("models", flag.ContinueOnError)
	addGlobalFlags(fs)
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var models []string
	if err := client.call("modelNames", nil, &models); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	for _, model := range models {
		fmt.Println(model)
	}
	return 0
}

func cmdStats(args []string) int {
	fs := flag.NewFlagSet("stats", flag.ContinueOnError)
	addGlobalFlags(fs)
	deck := fs.String("deck", "", "deck name")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *deck == "" {
		fmt.Fprintln(os.Stderr, "-deck is required")
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var stats map[string]interface{}
	if err := client.call("getDeckStats", map[string][]string{"decks": []string{*deck}}, &stats); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printJSON(stats)
	return 0
}

func cmdCanAdd(args []string) int {
	fs := flag.NewFlagSet("can-add", flag.ContinueOnError)
	addGlobalFlags(fs)
	file := fs.String("file", "", "path to JSON payload")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *file == "" {
		fmt.Fprintln(os.Stderr, "-file is required")
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	notes, err := loadNotes(*file)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	allowed, err := canAdd(client, notes)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	out := struct {
		Notes []struct {
			Front  string `json:"front,omitempty"`
			Allowed bool   `json:"allowed"`
		} `json:"notes"`
	}{Notes: make([]struct {
		Front  string `json:"front,omitempty"`
		Allowed bool   `json:"allowed"`
	}, len(notes))}
	for i, n := range notes {
		out.Notes[i].Front = firstNonEmpty(n.Fields["Front"], n.Fields["Text"])
		out.Notes[i].Allowed = allowed[i]
	}
	printJSON(out)
	return 0
}

func cmdSearch(args []string) int {
	fs := flag.NewFlagSet("search", flag.ContinueOnError)
	addGlobalFlags(fs)
	query := fs.String("query", "", "Anki search query")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *query == "" {
		fmt.Fprintln(os.Stderr, "-query is required")
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	var ids []int64
	if err := client.call("findNotes", map[string]string{"query": *query}, &ids); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	var infos []noteInfo
	if len(ids) > 0 {
		if err := client.call("notesInfo", map[string][]int64{"notes": ids}, &infos); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	printJSON(infos)
	return 0
}

func cmdDelete(args []string) int {
	fs := flag.NewFlagSet("delete", flag.ContinueOnError)
	addGlobalFlags(fs)
	notesText := fs.String("notes", "", "comma-separated note IDs")
	dryRun := fs.Bool("dry-run", false, "print note IDs without deleting")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *notesText == "" {
		fmt.Fprintln(os.Stderr, "-notes is required")
		return 2
	}
	var ids []int64
	for _, part := range strings.Split(*notesText, ",") {
		part = strings.TrimSpace(part)
		if part == "" { continue }
		var id int64
		if _, err := fmt.Sscan(part, &id); err != nil {
			fmt.Fprintf(os.Stderr, "invalid note id %q: %v\n", part, err)
			return 2
		}
		ids = append(ids, id)
	}
	if *dryRun {
		printJSON(map[string]interface{}{"delete": ids, "dryRun": true})
		return 0
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if err := client.call("deleteNotes", map[string][]int64{"notes": ids}, nil); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printJSON(map[string]interface{}{"deleted": ids})
	return 0
}

func cmdUpdate(args []string) int {
	fs := flag.NewFlagSet("update", flag.ContinueOnError)
	addGlobalFlags(fs)
	file := fs.String("file", "", "path to JSON update payload")
	dryRun := fs.Bool("dry-run", false, "print note updates without applying")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *file == "" {
		fmt.Fprintln(os.Stderr, "-file is required")
		return 2
	}
	data, err := os.ReadFile(*file)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	var payload updatePayload
	if err := json.Unmarshal(data, &payload); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	if len(payload.Notes) == 0 {
		fmt.Fprintln(os.Stderr, "update file must contain a non-empty notes array")
		return 1
	}
	ids := make([]int64, 0, len(payload.Notes))
	for _, note := range payload.Notes {
		ids = append(ids, note.ID)
	}
	if *dryRun {
		printJSON(map[string]interface{}{"update": payload.Notes, "dryRun": true})
		return 0
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	for _, note := range payload.Notes {
		if note.ID == 0 || len(note.Fields) == 0 {
			fmt.Fprintf(os.Stderr, "invalid update note: %+v\n", note)
			return 2
		}
		if err := client.call("updateNoteFields", map[string]updateNote{"note": note}, nil); err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
	}
	printJSON(map[string]interface{}{"updated": ids})
	return 0
}

func cmdAddTags(args []string) int {
	return cmdTags("add-tags", "addTags", args)
}

func cmdRemoveTags(args []string) int {
	return cmdTags("remove-tags", "removeTags", args)
}

func cmdSnapshot(args []string) int {
	fs := flag.NewFlagSet("snapshot", flag.ContinueOnError)
	addGlobalFlags(fs)
	query := fs.String("query", "", "Anki search query")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil { fmt.Fprintln(os.Stderr, err); return 2 }
	if *query == "" { fmt.Fprintln(os.Stderr, "-query is required"); return 2 }
	client, err := newClient(fs)
	if err != nil { fmt.Fprintln(os.Stderr, err); return 2 }
	var ids []int64
	if err := client.call("findNotes", map[string]string{"query": *query}, &ids); err != nil { fmt.Fprintln(os.Stderr, err); return 1 }
	var notes []noteInfo
	if len(ids) > 0 {
		if err := client.call("notesInfo", map[string][]int64{"notes": ids}, &notes); err != nil { fmt.Fprintln(os.Stderr, err); return 1 }
	}
	var cards []json.RawMessage
	var cardIDs []int64
	for _, n := range notes { cardIDs = append(cardIDs, n.Cards...) }
	if len(cardIDs) > 0 {
		if err := client.call("cardsInfo", map[string][]int64{"cards": cardIDs}, &cards); err != nil { fmt.Fprintln(os.Stderr, err); return 1 }
	}
	printJSON(map[string]interface{}{"query": *query, "notes": notes, "cards": cards})
	return 0
}

func cmdCardState(name, action string, args []string) int {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	addGlobalFlags(fs)
	cardsText := fs.String("cards", "", "comma-separated card IDs")
	dryRun := fs.Bool("dry-run", false, "print card IDs without changing state")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil { fmt.Fprintln(os.Stderr, err); return 2 }
	if *cardsText == "" { fmt.Fprintln(os.Stderr, "-cards is required"); return 2 }
	ids, err := parseNoteIDs(*cardsText)
	if err != nil { fmt.Fprintln(os.Stderr, err); return 2 }
	if *dryRun { printJSON(map[string]interface{}{name: ids, "dryRun": true}); return 0 }
	client, err := newClient(fs)
	if err != nil { fmt.Fprintln(os.Stderr, err); return 2 }
	if err := client.call(action, map[string][]int64{"cards": ids}, nil); err != nil { fmt.Fprintln(os.Stderr, err); return 1 }
	printJSON(map[string]interface{}{name: ids})
	return 0
}

func cmdTags(name, action string, args []string) int {
	fs := flag.NewFlagSet(name, flag.ContinueOnError)
	addGlobalFlags(fs)
	notesText := fs.String("notes", "", "comma-separated note IDs")
	tags := fs.String("tags", "", "space-separated tags")
	dryRun := fs.Bool("dry-run", false, "print tag change without applying")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *notesText == "" {
		fmt.Fprintln(os.Stderr, "-notes is required")
		return 2
	}
	if strings.TrimSpace(*tags) == "" {
		fmt.Fprintln(os.Stderr, "-tags is required")
		return 2
	}
	ids, err := parseNoteIDs(*notesText)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *dryRun {
		printJSON(map[string]interface{}{name: ids, "tags": *tags, "dryRun": true})
		return 0
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if err := client.call(action, map[string]interface{}{"notes": ids, "tags": *tags}, nil); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	printJSON(map[string]interface{}{name: ids, "tags": *tags})
	return 0
}

func parseNoteIDs(text string) ([]int64, error) {
	var ids []int64
	for _, part := range strings.Split(text, ",") {
		part = strings.TrimSpace(part)
		if part == "" {
			continue
		}
		var id int64
		if _, err := fmt.Sscan(part, &id); err != nil {
			return nil, fmt.Errorf("invalid note id %q: %w", part, err)
		}
		ids = append(ids, id)
	}
	if len(ids) == 0 {
		return nil, errors.New("no note IDs provided")
	}
	return ids, nil
}

func cmdAdd(args []string) int {
	fs := flag.NewFlagSet("add", flag.ContinueOnError)
	addGlobalFlags(fs)
	file := fs.String("file", "", "path to JSON payload")
	dryRun := fs.Bool("dry-run", false, "show what would be added")
	allowDuplicates := fs.Bool("allow-duplicates", false, "skip canAddNotes duplicate filtering")
	fs.SetOutput(io.Discard)
	if err := fs.Parse(args); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	if *file == "" {
		fmt.Fprintln(os.Stderr, "-file is required")
		return 2
	}
	client, err := newClient(fs)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 2
	}
	notes, err := loadNotes(*file)
	if err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}

	toAdd := notes
	blocked := []note{}
	if !*allowDuplicates {
		allowed, err := canAdd(client, notes)
		if err != nil {
			fmt.Fprintln(os.Stderr, err)
			return 1
		}
		toAdd = nil
		for i, ok := range allowed {
			if ok {
				toAdd = append(toAdd, notes[i])
			} else {
				blocked = append(blocked, notes[i])
			}
		}
	}

	summary := struct {
		Requested int      `json:"requested"`
		Addable   int      `json:"addable"`
		Skipped   int      `json:"skipped"`
		SkippedQA []string `json:"skippedQuestions,omitempty"`
		AddedIDs  []int64  `json:"addedIds,omitempty"`
	}{
		Requested: len(notes),
		Addable:   len(toAdd),
		Skipped:   len(blocked),
	}
	for _, n := range blocked {
		summary.SkippedQA = append(summary.SkippedQA, firstNonEmpty(n.Fields["Front"], n.Fields["Text"]))
	}

	if *dryRun {
		printJSON(summary)
		return 0
	}
	if len(toAdd) == 0 {
		printJSON(summary)
		return 0
	}
	var ids []int64
	if err := client.call("addNotes", addNotesParams{Notes: toAdd}, &ids); err != nil {
		fmt.Fprintln(os.Stderr, err)
		return 1
	}
	summary.AddedIDs = ids
	printJSON(summary)
	return 0
}

func canAdd(client *Client, notes []note) ([]bool, error) {
	var allowed []bool
	if err := client.call("canAddNotes", addNotesParams{Notes: notes}, &allowed); err != nil {
		return nil, err
	}
	return allowed, nil
}

func loadNotes(path string) ([]note, error) {
	data, err := os.ReadFile(path)
	if err != nil {
		return nil, err
	}

	var payload notePayload
	if err := json.Unmarshal(data, &payload); err == nil && strings.EqualFold(payload.Action, "addNotes") && len(payload.Params.Notes) > 0 {
		return payload.Params.Notes, nil
	}

	var bare notesOnly
	if err := json.Unmarshal(data, &bare); err == nil && len(bare.Notes) > 0 {
		return bare.Notes, nil
	}

	return nil, errors.New("file must contain either a full addNotes payload or a JSON object with a notes array")
}

func (c *Client) call(action string, params interface{}, out interface{}) error {
	body, err := json.Marshal(request{Action: action, Version: 6, Params: params})
	if err != nil {
		return err
	}
	resp, err := c.HTTPClient.Post(c.URL, "application/json", bytes.NewReader(body))
	if err != nil {
		return err
	}
	defer resp.Body.Close()
	if resp.StatusCode < 200 || resp.StatusCode >= 300 {
		b, _ := io.ReadAll(resp.Body)
		return fmt.Errorf("ankiconnect returned %s: %s", resp.Status, strings.TrimSpace(string(b)))
	}
	var decoded response
	if err := json.NewDecoder(resp.Body).Decode(&decoded); err != nil {
		return err
	}
	if decoded.Error != nil {
		return fmt.Errorf("ankiconnect error: %v", decoded.Error)
	}
	if out == nil {
		return nil
	}
	return json.Unmarshal(decoded.Result, out)
}

func printJSON(v interface{}) {
	enc := json.NewEncoder(os.Stdout)
	enc.SetIndent("", "  ")
	_ = enc.Encode(v)
}

func envOr(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func firstNonEmpty(values ...string) string {
	for _, value := range values {
		if strings.TrimSpace(value) != "" {
			return value
		}
	}
	return ""
}
