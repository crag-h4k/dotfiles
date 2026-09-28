// tools/pbvar/main.go
//
// pbvar reads the system clipboard and prints a shell `export NAME='value'`
// statement to stdout, for a wrapping shell function to eval. A child process
// cannot set its parent shell's environment, so the zsh wrapper
// (~/.zsh/custom/functions/pbvar.zsh) evals this output into the interactive
// shell.
//
// Clipboard read: on macOS it shells out to /usr/bin/pbpaste (an OS built-in);
// elsewhere, and as a macOS fallback, it queries the controlling terminal over
// OSC 52. The OSC 52 path needs no system packages and works over SSH into a
// headless host, because the terminal that answers the query is the local one.
package main

import (
	"encoding/base64"
	"errors"
	"fmt"
	"io"
	"os"
	"os/exec"
	"regexp"
	"runtime"
	"strings"
	"time"

	"golang.org/x/term"
)

const usage = `usage: pbvar [--raw] NAME

Read the clipboard and print a shell statement that exports NAME with its
contents. Meant to be evaluated by the pbvar shell function:

    pbvar TOKEN     # exports $TOKEN from the clipboard

Options:
  --raw    keep the clipboard bytes exactly (default: strip one trailing newline)
  -h       show this help
`

// osc52ReadTimeout bounds how long we wait for a terminal to answer the OSC 52
// query. A terminal that refuses the read must not hang the shell.
const osc52ReadTimeout = 750 * time.Millisecond

var nameRe = regexp.MustCompile(`^[A-Za-z_][A-Za-z0-9_]*$`)

// OSC 52 clipboard response: ESC ] 52 ; <selection> ; <base64> (BEL | ST).
var osc52Re = regexp.MustCompile(`\x1b\]52;[^;]*;([A-Za-z0-9+/=]*)(?:\x07|\x1b\\)`)

var (
	errHelp                 = errors.New("help")
	errClipboardTimeout     = errors.New("clipboard read timed out (terminal did not answer OSC 52; allow clipboard read and, under tmux, set allow-passthrough on)")
	errClipboardUnsupported = errors.New("terminal did not return an OSC 52 clipboard response")
)

func main() {
	name, raw, err := parseArgs(os.Args[1:])
	if err != nil {
		if errors.Is(err, errHelp) {
			fmt.Fprint(os.Stderr, usage)
			os.Exit(0)
		}
		fmt.Fprintf(os.Stderr, "pbvar: %v\n", err)
		fmt.Fprint(os.Stderr, usage)
		os.Exit(2)
	}

	data, err := readClipboard()
	if err != nil {
		fmt.Fprintf(os.Stderr, "pbvar: %v\n", err)
		os.Exit(1)
	}

	value := string(data)
	if !raw {
		value = stripTrailingNewline(value)
	}

	// stdout carries only the eval-able statement; the confirmation and every
	// error go to stderr, so the wrapper never evals anything but the export and
	// the clipboard value never lands on stdout.
	fmt.Fprintf(os.Stdout, "export %s=%s\n", name, shellSingleQuote(value))
	fmt.Fprintf(os.Stderr, "pbvar: exported %s (%d bytes)\n", name, len(value))
}

func parseArgs(args []string) (name string, raw bool, err error) {
	for _, a := range args {
		switch {
		case a == "-h" || a == "--help":
			return "", false, errHelp
		case a == "--raw":
			raw = true
		case a != "-" && strings.HasPrefix(a, "-"):
			return "", false, fmt.Errorf("unknown option: %s", a)
		default:
			if name != "" {
				return "", false, fmt.Errorf("unexpected extra argument: %s", a)
			}
			name = a
		}
	}
	if name == "" {
		return "", false, errors.New("missing variable name")
	}
	if !nameRe.MatchString(name) {
		return "", false, fmt.Errorf("invalid variable name: %q (must match [A-Za-z_][A-Za-z0-9_]*)", name)
	}
	return name, raw, nil
}

// stripTrailingNewline removes exactly one trailing line ending (\r\n or \n),
// the common case of a value copied with a stray newline.
func stripTrailingNewline(s string) string {
	if strings.HasSuffix(s, "\r\n") {
		return s[:len(s)-2]
	}
	if strings.HasSuffix(s, "\n") {
		return s[:len(s)-1]
	}
	return s
}

// shellSingleQuote wraps s in single quotes so any bytes (newlines, $, backticks,
// quotes) are inert under eval. A literal ' becomes '\” (close, escaped, reopen).
func shellSingleQuote(s string) string {
	return "'" + strings.ReplaceAll(s, "'", `'\''`) + "'"
}

func readClipboard() ([]byte, error) {
	if runtime.GOOS == "darwin" {
		if out, err := exec.Command("/usr/bin/pbpaste").Output(); err == nil {
			return out, nil
		}
		// pbpaste missing or failed (unusual): fall through to OSC 52.
	}
	return readOSC52(osc52ReadTimeout)
}

// readOSC52 asks the controlling terminal for its clipboard over OSC 52. It puts
// /dev/tty in raw mode for the exchange and always restores it.
func readOSC52(timeout time.Duration) ([]byte, error) {
	tty, err := os.OpenFile("/dev/tty", os.O_RDWR, 0)
	if err != nil {
		return nil, fmt.Errorf("cannot open /dev/tty: %w", err)
	}
	defer tty.Close()

	fd := int(tty.Fd())
	if !term.IsTerminal(fd) {
		return nil, errors.New("not a terminal; cannot read clipboard over OSC 52")
	}
	state, err := term.MakeRaw(fd)
	if err != nil {
		return nil, fmt.Errorf("cannot set raw mode: %w", err)
	}
	defer term.Restore(fd, state)

	return osc52Exchange(tty, os.Getenv("TMUX") != "", timeout)
}

// osc52Exchange writes the OSC 52 clipboard query to rw and reads the reply. It is
// split from the tty setup so the protocol can be tested against an in-memory pipe.
func osc52Exchange(rw io.ReadWriter, tmux bool, timeout time.Duration) ([]byte, error) {
	query := "\x1b]52;c;?\x07"
	if tmux {
		// tmux passthrough: wrap in DCS and double the inner ESCs so tmux forwards
		// the query to the outer terminal instead of consuming it.
		query = "\x1bPtmux;" + strings.ReplaceAll(query, "\x1b", "\x1b\x1b") + "\x1b\\"
	}
	if _, err := io.WriteString(rw, query); err != nil {
		return nil, fmt.Errorf("cannot write OSC 52 query: %w", err)
	}
	resp, err := readUntilOSC52(rw, timeout)
	if err != nil {
		return nil, err
	}
	return parseOSC52(resp)
}

// readUntilOSC52 accumulates bytes from r until a complete OSC 52 reply is seen or
// the timeout elapses. The read runs in a goroutine so a terminal that never
// answers cannot block; the buffered channel keeps that goroutine from leaking,
// and the caller's deferred tty.Close unblocks a stuck Read.
func readUntilOSC52(r io.Reader, timeout time.Duration) ([]byte, error) {
	type result struct {
		data []byte
		err  error
	}
	ch := make(chan result, 1)
	go func() {
		var buf []byte
		tmp := make([]byte, 256)
		for {
			n, err := r.Read(tmp)
			if n > 0 {
				buf = append(buf, tmp[:n]...)
				if osc52Re.Match(buf) {
					ch <- result{buf, nil}
					return
				}
			}
			if err != nil {
				ch <- result{buf, err}
				return
			}
		}
	}()

	select {
	case res := <-ch:
		if osc52Re.Match(res.data) {
			return res.data, nil
		}
		if res.err != nil {
			return nil, res.err
		}
		return nil, errClipboardUnsupported
	case <-time.After(timeout):
		return nil, errClipboardTimeout
	}
}

func parseOSC52(buf []byte) ([]byte, error) {
	m := osc52Re.FindSubmatch(buf)
	if m == nil {
		return nil, errClipboardUnsupported
	}
	decoded, err := base64.StdEncoding.DecodeString(string(m[1]))
	if err != nil {
		return nil, fmt.Errorf("bad base64 in clipboard response: %w", err)
	}
	return decoded, nil
}
