// tools/pbvar/main_test.go
package main

import (
	"bytes"
	"errors"
	"io"
	"testing"
	"time"
)

func TestParseArgs(t *testing.T) {
	cases := []struct {
		name     string
		args     []string
		wantName string
		wantRaw  bool
		wantErr  error // errHelp, or a non-nil sentinel meaning "some error"
		errAny   bool
	}{
		{name: "simple", args: []string{"FOO"}, wantName: "FOO"},
		{name: "underscore lead", args: []string{"_x"}, wantName: "_x"},
		{name: "raw before name", args: []string{"--raw", "FOO"}, wantName: "FOO", wantRaw: true},
		{name: "raw after name", args: []string{"FOO", "--raw"}, wantName: "FOO", wantRaw: true},
		{name: "help short", args: []string{"-h"}, wantErr: errHelp},
		{name: "help long", args: []string{"--help"}, wantErr: errHelp},
		{name: "missing name", args: nil, errAny: true},
		{name: "leading digit", args: []string{"1BAD"}, errAny: true},
		{name: "hyphen in name", args: []string{"BAD-NAME"}, errAny: true},
		{name: "injection attempt", args: []string{"x;rm -rf /"}, errAny: true},
		{name: "unknown flag", args: []string{"--nope", "FOO"}, errAny: true},
		{name: "extra arg", args: []string{"FOO", "BAR"}, errAny: true},
	}
	for _, tc := range cases {
		t.Run(tc.name, func(t *testing.T) {
			name, raw, err := parseArgs(tc.args)
			switch {
			case tc.wantErr != nil:
				if !errors.Is(err, tc.wantErr) {
					t.Fatalf("want err %v, got %v", tc.wantErr, err)
				}
			case tc.errAny:
				if err == nil {
					t.Fatalf("want an error, got name=%q", name)
				}
			default:
				if err != nil {
					t.Fatalf("unexpected error: %v", err)
				}
				if name != tc.wantName || raw != tc.wantRaw {
					t.Fatalf("got name=%q raw=%v, want name=%q raw=%v", name, raw, tc.wantName, tc.wantRaw)
				}
			}
		})
	}
}

func TestShellSingleQuote(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"", "''"},
		{"plain", "'plain'"},
		{"with space", "'with space'"},
		{"has'quote", `'has'\''quote'`},
		{"$(rm -rf /)", "'$(rm -rf /)'"},
		{"back`tick`", "'back`tick`'"},
		{"line1\nline2", "'line1\nline2'"},
	}
	for _, tc := range cases {
		if got := shellSingleQuote(tc.in); got != tc.want {
			t.Errorf("shellSingleQuote(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestStripTrailingNewline(t *testing.T) {
	cases := []struct {
		in, want string
	}{
		{"token", "token"},
		{"token\n", "token"},
		{"token\r\n", "token"},
		{"token\n\n", "token\n"}, // strips exactly one
		{"a\nb\n", "a\nb"},
		{"", ""},
		{"\n", ""},
	}
	for _, tc := range cases {
		if got := stripTrailingNewline(tc.in); got != tc.want {
			t.Errorf("stripTrailingNewline(%q) = %q, want %q", tc.in, got, tc.want)
		}
	}
}

func TestParseOSC52(t *testing.T) {
	// "secret" base64 -> c2VjcmV0
	bel := []byte("\x1b]52;c;c2VjcmV0\x07")
	if got, err := parseOSC52(bel); err != nil || string(got) != "secret" {
		t.Fatalf("BEL-terminated: got %q err %v", got, err)
	}
	st := []byte("\x1b]52;c;c2VjcmV0\x1b\\")
	if got, err := parseOSC52(st); err != nil || string(got) != "secret" {
		t.Fatalf("ST-terminated: got %q err %v", got, err)
	}
	// leading noise (e.g. keystrokes echoed before the reply) is tolerated
	noisy := []byte("junk\x1b]52;c;c2VjcmV0\x07")
	if got, err := parseOSC52(noisy); err != nil || string(got) != "secret" {
		t.Fatalf("noisy: got %q err %v", got, err)
	}
	if _, err := parseOSC52([]byte("no response here")); !errors.Is(err, errClipboardUnsupported) {
		t.Fatalf("want errClipboardUnsupported, got %v", err)
	}
}

// fakeTTY stands in for /dev/tty: it captures the query written to it and returns
// preloaded chunks to the reader. Write happens before the reader goroutine
// starts, so the buffer is never touched concurrently.
type fakeTTY struct {
	writes bytes.Buffer
	reads  chan []byte
}

func (f *fakeTTY) Write(p []byte) (int, error) { return f.writes.Write(p) }

func (f *fakeTTY) Read(p []byte) (int, error) {
	chunk, ok := <-f.reads
	if !ok {
		return 0, io.EOF
	}
	return copy(p, chunk), nil
}

func TestOSC52ExchangeSuccess(t *testing.T) {
	f := &fakeTTY{reads: make(chan []byte, 1)}
	f.reads <- []byte("\x1b]52;c;c2VjcmV0\x07") // base64("secret")
	close(f.reads)

	got, err := osc52Exchange(f, false, time.Second)
	if err != nil || string(got) != "secret" {
		t.Fatalf("got %q err %v", got, err)
	}
	if f.writes.String() != "\x1b]52;c;?\x07" {
		t.Fatalf("query = %q", f.writes.String())
	}
}

func TestOSC52ExchangeTmuxPassthrough(t *testing.T) {
	f := &fakeTTY{reads: make(chan []byte, 1)}
	f.reads <- []byte("\x1b]52;c;c2VjcmV0\x07")
	close(f.reads)

	if _, err := osc52Exchange(f, true, time.Second); err != nil {
		t.Fatalf("err %v", err)
	}
	want := "\x1bPtmux;\x1b\x1b]52;c;?\x07\x1b\\"
	if f.writes.String() != want {
		t.Fatalf("tmux query = %q, want %q", f.writes.String(), want)
	}
}

func TestOSC52ExchangeTimeout(t *testing.T) {
	f := &fakeTTY{reads: make(chan []byte)} // never answers
	_, err := osc52Exchange(f, false, 50*time.Millisecond)
	if !errors.Is(err, errClipboardTimeout) {
		t.Fatalf("want errClipboardTimeout, got %v", err)
	}
	close(f.reads) // release the blocked reader goroutine
}
