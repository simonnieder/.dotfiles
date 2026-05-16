package main

import (
	"fmt"
	"os"

	appcmd "github.com/simonnieder/fullstack/app"
)

func main() {
	app, err := appcmd.NewApp()
	if err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
	defer app.Close()

	if err := app.Run(os.Args[1:]); err != nil {
		fmt.Fprintln(os.Stderr, "error:", err)
		os.Exit(1)
	}
}
