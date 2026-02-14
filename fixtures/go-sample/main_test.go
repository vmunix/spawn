package main

import "testing"

func TestGreetDefault(t *testing.T) {
	got := greet("")
	want := "Hello, World!"
	if got != want {
		t.Errorf("greet(\"\") = %q, want %q", got, want)
	}
}

func TestGreetName(t *testing.T) {
	got := greet("Go")
	want := "Hello, Go!"
	if got != want {
		t.Errorf("greet(\"Go\") = %q, want %q", got, want)
	}
}
