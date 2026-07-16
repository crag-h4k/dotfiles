# ~/.config/statusline/gud-palette.sh
# shellcheck shell=bash
# The Dracula "gud" extras that ANSI 16 cannot carry.
#
# Sourced once by ~/.claude/statusline-command.sh. Everything else the statusline
# prints is pure SGR (\e[NNm) so ~/.config/ghostty/themes/gud-theme.conf stays the
# single source of color truth: recolor the terminal, recolor the statusline. The
# only exception is orange (#FFB86C): gud has no ANSI slot for it (ANSI 4 is purple
# and bright-red maps to red), so it is defined here as a 24-bit truecolor SGR
# escape. Keep this list to genuine "no ANSI slot exists" shades only.
# shellcheck disable=SC2034  # sourced by statusline-command.sh; used there
GUD_ORANGE=$'\e[38;2;255;184;108m'
