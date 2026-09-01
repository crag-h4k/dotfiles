# ~/.zsh/custom/functions/dns-sniff.zsh
# Interactive front end for the dns-sniff capture engine (~/.zsh/bin/dns-sniff).
# Runs the wrapped command via `eval` in THIS shell, so aliases (including
# oh-my-zsh plugin aliases like `gl`), shell functions, and env are exactly what
# you'd get by typing the command yourself. A zsh function outranks a PATH
# command, so interactive `dns-sniff ...` lands here; scripts hit the binary.
#
# Why not let the binary run the command? An external process can't see this
# shell's aliases/functions, and reconstructing them by launching `zsh -i`
# reloads the iTerm2 shell integration, which leaks OSC 133 marks to the shared
# terminal and breaks autosuggestions/highlighting. Running in-shell sidesteps
# both: nothing is reconstructed, nothing is re-sourced.
#
# Capture flags (--no-log, --pcap, --flush, --log-dir PATH, --iface IFACE) must
# come before the command, mirroring the binary. See `dns-sniff --help`.

dns-sniff() {
    emulate -L zsh

    # Snapshot terminal modes up front so we can always hand the tty back exactly
    # as we found it. sudo runs commands in a pseudo-terminal by default
    # (use_pty, on since sudo 1.9.14), and the backgrounded `sudo tcpdump`
    # retaining the terminal races the teardown-time `sudo kill`, which can leave
    # the real tty in a raw / no-OPOST state (LF-without-CR "staircase" output).
    # The capture engine restores the tty itself; this is the outer belt.
    local _dns_stty
    _dns_stty="$(stty -g 2>/dev/null)"

    local bin="$HOME/.zsh/bin/dns-sniff"
    if [[ ! -x "$bin" ]]; then
        print -u2 "dns-sniff: capture engine not found at $bin"
        return 127
    fi

    # Split our own flags from the wrapped command (everything at/after the
    # first non-flag word, or after a literal --).
    local -a sniff_flags
    while (( $# )); do
        case "$1" in
            --no-log|--pcap|--flush)  sniff_flags+=("$1"); shift ;;
            --log-dir|--iface)      sniff_flags+=("$1" "$2"); shift 2 ;;
            --log-dir=*|--iface=*)  sniff_flags+=("$1"); shift ;;
            -h|--help)              "$bin" --help; return $? ;;
            --)                     shift; break ;;
            -*)                     print -u2 "dns-sniff: unknown option: $1"; return 2 ;;
            *)                      break ;;
        esac
    done

    if (( ! $# )); then
        print -u2 "dns-sniff: no command given"
        return 2
    fi
    local -a cmd=("$@")

    local statefile
    statefile="$(mktemp "${TMPDIR:-/tmp}/dns-sniff-state.XXXXXX")" || return 1

    # Bring capture up. _start warms sudo, launches tcpdump per interface, and
    # writes the state file; the sudo tcpdumps outlive it and _finish reaps them.
    if ! "$bin" _start --state "$statefile" "${sniff_flags[@]}" -- "${cmd[@]}"; then
        command rm -f "$statefile"
        return 1
    fi

    # Run in THIS shell so aliases/functions/plugins all apply, then ALWAYS tear
    # capture down - the `always` block runs even on Ctrl-C, so tcpdump is
    # stopped, the log is written, and temp pcaps are cleaned up regardless.
    # Reconstruct the command line for eval: (q) quotes each element so args
    # with spaces/globs/metacharacters stay literal, and the explicit [@]
    # subscript keeps it an array through the nested join so word boundaries
    # survive (without [@], zsh joins to a scalar first and eval sees one giant
    # command name). eval re-parses it, expanding the leading alias/function.
    local st
    {
        eval "${(j: :)${(q)cmd[@]}}"
        st=$?
    } always {
        "$bin" _finish --state "$statefile" --status "${st:-1}"
        command rm -f "$statefile"
        # Final guard: even though _finish restores the tty, re-assert the modes
        # we captured before anything ran, in case a future teardown path slips.
        [[ -n "$_dns_stty" ]] && stty "$_dns_stty" 2>/dev/null
    }
    return ${st:-1}
}
