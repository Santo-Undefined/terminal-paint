#!/usr/bin/env bash
# ==============================================================================
# Terminal Paint - Pure Bash TUI Drawing Application
#
# Requirements:
#   - Bash 4.0+ (also compatible with macOS Bash 3.2+)
#   - Standard ANSI/xterm-compatible terminal emulator with SGR mouse support
#
# Features:
#   - Extended SGR mouse tracking (\e[?1000h, \e[?1002h, \e[?1006h)
#   - Click & drag drawing with Bresenham line interpolation
#   - Top-row UI toolbar with 8 ANSI colors, Clear, and Quit buttons
#   - Keyboard shortcuts: 1-8 (colors), c/C (clear), q/Q (quit), e/E (eraser)
#   - Right-click eraser functionality
#   - Zero external dependencies (strictly Bash built-ins, read, stty, ANSI escapes)
# ==============================================================================

set -o pipefail

# ------------------------------------------------------------------------------
# Color & Palette Definitions
# ------------------------------------------------------------------------------
COLOR_NAMES=("BLK" "RED" "GRN" "YEL" "BLU" "MAG" "CYA" "WHT")
COLOR_FGS=(30 31 32 33 34 35 36 37)
COLOR_BGS=(40 41 42 43 44 45 46 47)
# Contrasting foreground color for toolbar labels:
TOOLBAR_TEXT_FGS=(97 97 30 30 97 97 30 30)

# State
CURRENT_COLOR_IDX=2          # 1-indexed (default: Red)
CURRENT_FG=${COLOR_FGS[1]}   # ANSI 31 (Red)
IS_ERASER=0                  # 0 = brush, 1 = eraser
GLYPH="█"                    # Solid block glyph for drawing

LAST_X=""
LAST_Y=""

# Save initial terminal settings
ORIG_STTY=""
if [[ -t 0 ]]; then
    ORIG_STTY=$(stty -g 2>/dev/null)
fi

# Detect Bash version for read timeout capability
# Bash 4.0+ supports fractional timeouts (e.g. 0.05s). Bash 3.2 requires integer 1.
READ_TIMEOUT="0.05"
if (( BASH_VERSINFO[0] < 4 )); then
    READ_TIMEOUT="1"
fi

# ------------------------------------------------------------------------------
# Teardown & Cleanup Handler
# ------------------------------------------------------------------------------
cleanup() {
    # Unregister traps to avoid recursion
    trap - EXIT INT TERM

    # Disable mouse tracking:
    #   \e[?1006l: SGR extended mode off
    #   \e[?1002l: button-event tracking off
    #   \e[?1000l: normal mouse tracking off
    # Re-enable auto-wrap:
    #   \e[?7h
    # Re-enable cursor:
    #   \e[?25h
    # Switch back to main screen buffer:
    #   \e[?1049l
    # Reset text formatting:
    #   \e[0m
    printf '\e[?1006l\e[?1002l\e[?1000l\e[?7h\e[?25h\e[?1049l\e[0m'

    # Restore canonical mode and echo
    if [[ -n "$ORIG_STTY" ]]; then
        stty "$ORIG_STTY" 2>/dev/null
    else
        stty sane 2>/dev/null
    fi

    exit 0
}

# ------------------------------------------------------------------------------
# UI Rendering
# ------------------------------------------------------------------------------
draw_toolbar() {
    local bar=""
    local idx=1

    # Move cursor to top-left (1,1)
    bar+=$'\e[1;1H'

    # 1. Render 8 Color Swatches (Cols 1-56, 7 columns each)
    for ((i = 0; i < 8; i++)); do
        local name="${COLOR_NAMES[i]}"
        local bg="${COLOR_BGS[i]}"
        local fg="${TOOLBAR_TEXT_FGS[i]}"
        local num=$((i + 1))

        if (( num == CURRENT_COLOR_IDX && IS_ERASER == 0 )); then
            # Active swatch: bracketed and highlighted with inverted styling
            bar+=$(printf '\e[%d;%d;1;7m[%d:%s]\e[0m' "$bg" "$fg" "$num" "$name")
        else
            # Inactive swatch
            bar+=$(printf '\e[%d;%d;1m %d:%s \e[0m' "$bg" "$fg" "$num" "$name")
        fi
    done

    # 2. Spacing and Action Buttons (Cols 57-75)
    # [C]lear Button: Cols 58-66
    bar+=" "
    bar+=$'\e[100;97;1m [C]lear \e[0m'

    # [Q]uit Button: Cols 68-75
    bar+=" "
    bar+=$'\e[100;97;1m [Q]uit \e[0m'

    # 3. Active Tool Status & Info (Cols 76+)
    bar+=" "
    if (( IS_ERASER == 1 )); then
        bar+=$'\e[90m|\e[0m Active: \e[1;7m Eraser \e[0m \e[90m(R-Click or [E])\e[0m'
    else
        local cur_name="${COLOR_NAMES[CURRENT_COLOR_IDX - 1]}"
        bar+=$(printf '\e[90m|\e[0m Active: \e[%dm%s %s\e[0m' "$CURRENT_FG" "$GLYPH" "$cur_name")
    fi

    # Clear to end of line and reset attributes
    bar+=$'\e[K\e[0m'

    printf '%s' "$bar"
}

clear_canvas() {
    # Erase from row 2, col 1 to the end of the screen, leaving toolbar intact
    printf '\e[2;1H\e[J'
    draw_toolbar
    LAST_X=""
    LAST_Y=""
}

set_color() {
    local num=$1
    if (( num >= 1 && num <= 8 )); then
        CURRENT_COLOR_IDX=$num
        CURRENT_FG=${COLOR_FGS[num - 1]}
        IS_ERASER=0
        draw_toolbar
    fi
}

toggle_eraser() {
    if (( IS_ERASER == 1 )); then
        IS_ERASER=0
    else
        IS_ERASER=1
    fi
    draw_toolbar
}

# ------------------------------------------------------------------------------
# Drawing Primitives
# ------------------------------------------------------------------------------
draw_point() {
    local x=$1
    local y=$2
    local erase=${3:-$IS_ERASER}

    # Restrict drawing to canvas area (row 2 and below)
    if (( y >= 2 && x >= 1 )); then
        if (( erase == 1 )); then
            # Erase by printing space with default attributes
            printf '\e[%d;%dH \e[0m' "$y" "$x"
        else
            printf '\e[%d;%dH\e[%dm%s\e[0m' "$y" "$x" "$CURRENT_FG" "$GLYPH"
        fi
    fi
}

# Bresenham's line algorithm for smooth continuous strokes during fast drags
draw_line() {
    local x0=$1 y0=$2 x1=$3 y1=$4
    local erase=${5:-$IS_ERASER}

    local dx=$(( x1 > x0 ? x1 - x0 : x0 - x1 ))
    local sx=$(( x0 < x1 ? 1 : -1 ))
    local dy=$(( y1 > y0 ? y0 - y1 : y1 - y0 ))
    local sy=$(( y0 < y1 ? 1 : -1 ))
    local err=$(( dx + dy ))
    local e2

    while :; do
        draw_point "$x0" "$y0" "$erase"
        (( x0 == x1 && y0 == y1 )) && break
        e2=$(( 2 * err ))
        if (( e2 >= dy )); then
            err=$(( err + dy ))
            x0=$(( x0 + sx ))
        fi
        if (( e2 <= dx )); then
            err=$(( err + dx ))
            y0=$(( y0 + sy ))
        fi
    done
}

# ------------------------------------------------------------------------------
# Mouse & Input Event Handling
# ------------------------------------------------------------------------------
handle_mouse_event() {
    local btn=$1
    local x=$2
    local y=$3
    local action=$4

    # Button release event ('m')
    if [[ "$action" == "m" ]]; then
        LAST_X=""
        LAST_Y=""
        return
    fi

    # Check if click is on Row 1 (UI Toolbar)
    if (( y == 1 )); then
        LAST_X=""
        LAST_Y=""
        # Only trigger toolbar actions on initial press, not continuous drag
        if (( (btn & 32) == 0 )); then
            if (( x >= 1 && x <= 56 )); then
                # 8 swatches of 7 columns each
                local selected_color=$(( (x - 1) / 7 + 1 ))
                set_color "$selected_color"
            elif (( x >= 58 && x <= 66 )); then
                # [C]lear button
                clear_canvas
            elif (( x >= 68 && x <= 75 )); then
                # [Q]uit button
                cleanup
            fi
        fi
        return
    fi

    # Canvas Drawing (Row 2 and below)
    # Check mouse button:
    #   (btn & 64) != 0 : Scroll wheel
    #   (btn & 3) == 0  : Left button
    #   (btn & 3) == 2  : Right button (used as Eraser)
    if (( (btn & 64) == 0 )); then
        local is_right_click=0
        if (( (btn & 3) == 2 )); then
            is_right_click=1
        fi

        # Check if left button or right button
        if (( (btn & 3) == 0 || is_right_click == 1 )); then
            local erase_flag=$IS_ERASER
            (( is_right_click == 1 )) && erase_flag=1

            if [[ -n "$LAST_X" && -n "$LAST_Y" ]]; then
                draw_line "$LAST_X" "$LAST_Y" "$x" "$y" "$erase_flag"
            else
                draw_point "$x" "$y" "$erase_flag"
            fi
            LAST_X=$x
            LAST_Y=$y
        fi
    fi
}

handle_winch() {
    draw_toolbar
}

# ------------------------------------------------------------------------------
# Main Entry Point
# ------------------------------------------------------------------------------
main() {
    # Verify execution in interactive terminal
    if [[ ! -t 0 || ! -t 1 ]]; then
        echo "Error: terminal-paint requires an interactive terminal (TTY)." >&2
        exit 1
    fi

    # Register signal traps for robust cleanup
    trap cleanup EXIT INT TERM
    trap handle_winch WINCH

    # Configure terminal I/O:
    #   -echo:   Disable local character echo
    #   -icanon: Disable line buffering (read character-by-character immediately)
    #   min 1:   Block until at least 1 character is received
    #   time 0:  No inter-character timer
    stty -echo -icanon min 1 time 0 2>/dev/null

    # Switch to alternate screen, hide cursor, disable auto-wrap, enable SGR mouse tracking:
    #   \e[?1049h: Alternate screen buffer
    #   \e[?25l:   Hide cursor
    #   \e[?7l:    Disable auto-wrap (prevents scrolling at bottom-right corner)
    #   \e[?1000h: Normal mouse tracking
    #   \e[?1002h: Button-event mouse tracking (drag/motion while button down)
    #   \e[?1006h: SGR extended coordinates mode (\e[<btn;x;y[Mm])
    #   \e[2J:     Clear entire canvas
    printf '\e[?1049h\e[?25l\e[?7l\e[?1000h\e[?1002h\e[?1006h\e[2J'

    # Render initial toolbar
    draw_toolbar

    # Event Loop
    local char c2 c3 ch seq action btn tmp x y

    while :; do
        # Read next input character
        IFS= read -r -n 1 char || break

        if [[ "$char" == $'\e' ]]; then
            # Potential ANSI / Mouse Escape Sequence
            # Use non-blocking read to check if more characters follow immediately
            if IFS= read -r -n 1 -t "$READ_TIMEOUT" c2; then
                if [[ "$c2" == "[" ]]; then
                    if IFS= read -r -n 1 -t "$READ_TIMEOUT" c3; then
                        if [[ "$c3" == "<" ]]; then
                            # SGR Mouse Sequence: \e[<btn;x;y[Mm]
                            seq=""
                            action=""
                            while IFS= read -r -n 1 ch; do
                                if [[ "$ch" == "M" || "$ch" == "m" ]]; then
                                    action="$ch"
                                    break
                                fi
                                seq+="$ch"
                                # Safety limit against malformed sequences
                                (( ${#seq} > 24 )) && break
                            done

                            # Fast parameter expansion parsing: seq is "btn;x;y"
                            btn="${seq%%;*}"
                            tmp="${seq#*;}"
                            x="${tmp%%;*}"
                            y="${tmp#*;}"

                            if [[ -n "$btn" && -n "$x" && -n "$y" && -n "$action" ]]; then
                                handle_mouse_event "$btn" "$x" "$y" "$action"
                            fi
                        else
                            # Consume any remaining bytes of other CSI escape sequences
                            if [[ "$c3" =~ [0-9\;\?] ]]; then
                                while IFS= read -r -n 1 -t "$READ_TIMEOUT" ch; do
                                    [[ "$ch" =~ [@-~] ]] && break
                                done
                            fi
                        fi
                    fi
                fi
            else
                # Bare Escape key pressed: reset line interpolation state
                LAST_X=""
                LAST_Y=""
            fi
        else
            # Keyboard character processing
            case "$char" in
                [1-8])
                    set_color "$char"
                    ;;
                [cC])
                    clear_canvas
                    ;;
                [qQ])
                    cleanup
                    ;;
                [eE])
                    toggle_eraser
                    ;;
                *)
                    # Ignore other keys
                    ;;
            esac
        fi
    done

    cleanup
}

main "$@"
