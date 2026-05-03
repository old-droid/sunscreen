#!/usr/bin/env bash
#
# sunscreen -- Screen-time Pomodoro for Linux
# 2hr daily quota, 5min break every 30min, freezes desktop
#

set -uo pipefail

DATA_DIR="${HOME}/.sunscreen"
QUOTA_SECONDS=7200
SESSION_SECONDS=1800
BREAK_SECONDS=300

RESET='\033[0m'
BOLD='\033[1m'
DIM='\033[2m'
RED='\033[31m'
GREEN='\033[32m'
YELLOW='\033[33m'
BLUE='\033[34m'
CYAN='\033[36m'
WHITE='\033[37m'
BRIGHT_RED='\033[91m'
BRIGHT_GREEN='\033[92m'
BRIGHT_YELLOW='\033[93m'
BRIGHT_CYAN='\033[96m'

BAR_FULL='#'
BAR_EMPTY='-'
V='|'
H='-'

# ─── INIT ─────────────────────────────────────────────────────────────
init_state() {
    mkdir -p "$DATA_DIR"
    local today_epoch
    today_epoch=$(date -u +%Y%m%d)
    local today_file_date
    today_file_date=$(cat "${DATA_DIR}/date" 2>/dev/null || echo "0")
    if [[ "$today_file_date" != "$today_epoch" ]]; then
        echo "$today_epoch" > "${DATA_DIR}/date"
        echo "0" > "${DATA_DIR}/accumulated"
        echo "0" > "${DATA_DIR}/session_start"
        echo "0" > "${DATA_DIR}/break_end"
        echo "0" > "${DATA_DIR}/frozen_today"
    fi
}

get_accumulated()   { cat "${DATA_DIR}/accumulated" 2>/dev/null || echo 0; }
get_session_start() { cat "${DATA_DIR}/session_start" 2>/dev/null || echo 0; }
get_break_end()     { cat "${DATA_DIR}/break_end" 2>/dev/null || echo 0; }
get_frozen_today()  { cat "${DATA_DIR}/frozen_today" 2>/dev/null || echo 0; }

set_accumulated()   { echo "$1" > "${DATA_DIR}/accumulated"; }
set_session_start() { echo "$1" > "${DATA_DIR}/session_start"; }
set_break_end()     { echo "$1" > "${DATA_DIR}/break_end"; }
set_frozen_today()  { echo "$1" > "${DATA_DIR}/frozen_today"; }

get_current_session() {
    local start
    start=$(get_session_start)
    [[ "$start" == "0" ]] && echo 0 || echo $(( $(date +%s) - start ))
}

get_total_today() {
    echo $(( $(get_accumulated) + $(get_current_session) ))
}

is_on_break() {
    local be now
    be=$(get_break_end)
    now=$(date +%s)
    [[ "$be" != "0" && "$now" -lt "$be" ]]
}

start_session() {
    [[ "$(get_session_start)" == "0" ]] && set_session_start "$(date +%s)"
}

commit_session() {
    local cs acc
    cs=$(get_session_start)
    if [[ "$cs" != "0" ]]; then
        acc=$(get_accumulated)
        set_accumulated $(( acc + $(get_current_session) ))
        set_session_start 0
    fi
}

start_break() {
    commit_session
    set_break_end $(( $(date +%s) + BREAK_SECONDS ))
}

# ─── DESKTOP FREEZE ───────────────────────────────────────────────────
do_freeze() {
    local duration=$1
    loginctl lock-session 2>/dev/null || light-locker-command -l 2>/dev/null || xdg-screensaver lock 2>/dev/null || true
}

# ─── DAEMON MODE ──────────────────────────────────────────────────────
run_daemon() {
    init_state
    start_session

    while true; do
        local total frozen
        total=$(get_total_today)
        frozen=$(get_frozen_today)

        # If already frozen (quota reached earlier), keep locking until midnight
        if [[ "$frozen" == "1" ]]; then
            loginctl lock-session 2>/dev/null || light-locker-command -l 2>/dev/null || true
            sleep 10
            continue
        fi

        # Check if quota (2 hours) is reached
        if [[ "$total" -ge "$QUOTA_SECONDS" ]]; then
            set_frozen_today 1
            commit_session
            loginctl lock-session 2>/dev/null || light-locker-command -l 2>/dev/null || true
            # Loop will now hit frozen==1 case above and keep locking
            continue
        fi

        # Check if 30 min session is up - trigger 5 min break
        # Only trigger based on CURRENT session time (not accumulated)
        local current_session
        current_session=$(get_current_session)
        if [[ "$current_session" -ge "$SESSION_SECONDS" ]] && ! is_on_break; then
            start_break
            loginctl lock-session 2>/dev/null || light-locker-command -l 2>/dev/null || true
            
            # Wait through full break duration
            while is_on_break; do
                loginctl lock-session 2>/dev/null || true
                sleep 5
            done
            
            # Break done - reset for new session
            commit_session
            set_break_end 0
            start_session
            continue
        fi

        sleep 1
    done
}

# ─── TUI MODE ─────────────────────────────────────────────────────────
format_time() {
    local s=$1
    printf "%02d:%02d:%02d" "$((s/3600))" "$(((s%3600)/60))" "$((s%60))"
}

get_bar_color() {
    local p=$1
    if [[ $p -lt 50 ]]; then echo "$GREEN"
    elif [[ $p -lt 75 ]]; then echo "$YELLOW"
    elif [[ $p -lt 90 ]]; then echo "$BRIGHT_YELLOW"
    else echo "$RED"
    fi
}

build_bar() {
    local current=$1 max=$2 w=$3
    local filled=$(( (current * w) / max ))
    [[ $filled -gt $w ]] && filled=$w
    local empty=$(( w - filled ))
    local bar="" i
    for ((i=0; i<filled; i++)); do bar+="${BAR_FULL}"; done
    for ((i=0; i<empty; i++)); do bar+="${BAR_EMPTY}"; done
    echo "$bar"
}

render_tui() {
    local w
    w=$(tput cols 2>/dev/null || echo 80)

    local total acc cur
    total=$(get_total_today)
    acc=$(get_accumulated)
    cur=$(get_current_session)

    local rem sess_rem
    rem=$(( QUOTA_SECONDS - total ))
    [[ $rem -lt 0 ]] && rem=0
    sess_rem=$(( SESSION_SECONDS - cur ))
    [[ $sess_rem -lt 0 ]] && sess_rem=0

    local tnow dnow frozen
    tnow=$(date '+%H:%M:%S')
    dnow=$(date '+%A, %B %d, %Y')
    frozen=$(get_frozen_today)

    local stext scolor
    if [[ "$frozen" == "1" ]]; then
        stext="QUOTA REACHED - LOCKED UNTIL TOMORROW"
        scolor="$BRIGHT_RED"
    elif is_on_break; then
        stext="ON BREAK"
        scolor="$BRIGHT_YELLOW"
    else
        stext="SCREEN TIME ACTIVE"
        scolor="$BRIGHT_GREEN"
    fi

    local spct=$(( (cur * 100) / SESSION_SECONDS ))
    [[ $spct -gt 100 ]] && spct=100
    local dpct=$(( (total * 100) / QUOTA_SECONDS ))
    [[ $dpct -gt 100 ]] && dpct=100

    local sbar dbar sbc dbc
    sbar=$(build_bar "$cur" "$SESSION_SECONDS" 40)
    dbar=$(build_bar "$total" "$QUOTA_SECONDS" 40)
    sbc=$(get_bar_color $spct)
    dbc=$(get_bar_color $dpct)

    local hline="" i
    for ((i=0; i<w; i++)); do hline+="${H}"; done

    printf '\e[H\e[2J'
    echo -e "${DIM}${hline}${RESET}"

    local hd=" SUNSCREEN"
    local hr="$tnow | $dnow"
    local pad=$(( w - ${#hd} - ${#hr} - 4 ))
    [[ $pad -lt 1 ]] && pad=1
    local ps=""
    for ((i=0; i<pad; i++)); do ps+=" "; done
    echo -e "${BOLD}${BRIGHT_CYAN}${V}${hd}${RESET}${ps}${DIM}${hr}${RESET} ${V}"

    echo -e "${DIM}${hline}${RESET}"

    local sl="${scolor}${BOLD} ${stext} ${RESET}"
    local spd=$(( (w - ${#sl} + 9) / 2 ))
    [[ $spd -lt 2 ]] && spd=2
    local ss=""
    for ((i=0; i<spd; i++)); do ss+=" "; done
    echo -e "${V}${ss}${sl}"
    echo "${V}"

    echo -e "${V}${BOLD}${WHITE} SESSION TIMER: $(format_time $sess_rem) / $(format_time $SESSION_SECONDS)${RESET}"
    echo -e "${V} [${sbc}${sbar}${RESET}] ${DIM}${spct}%${RESET}"
    echo "${V}"

    echo -e "${V}${BOLD}${WHITE} DAILY QUOTA (2 HOURS): $(format_time $total) / $(format_time $QUOTA_SECONDS)${RESET}"
    echo -e "${V} [${dbc}${dbar}${RESET}] ${DIM}${dpct}%${RESET}"
    echo "${V}"

    if is_on_break; then
        local br=$(( $(get_break_end) - $(date +%s) ))
        [[ $br -lt 0 ]] && br=0
        local break_pct=$(( (br * 100) / BREAK_SECONDS ))
        [[ $break_pct -gt 100 ]] && break_pct=100
        local bbar=""
        local bf=$(( (br * 20) / BREAK_SECONDS ))
        [[ $bf -gt 20 ]] && bf=20
        local be=$(( 20 - bf ))
        local bi
        for ((bi=0; bi<bf; bi++)); do bbar+="${BAR_FULL}"; done
        for ((bi=0; bi<be; bi++)); do bbar+="${BAR_EMPTY}"; done
        echo "${V}"
        echo -e "${V}${BRIGHT_YELLOW}${BOLD} ================= BREAK TIME =================${RESET}"
        echo -e "${V}${BRIGHT_YELLOW}${BOLD}  Screen locked - $(format_time $br) until unlock${RESET}"
        echo -e "${V}${BRIGHT_YELLOW}  [${bbar}] ${break_pct}%${RESET}"
        echo -e "${V}${BRIGHT_YELLOW}${BOLD} ==============================================${RESET}"
        echo "${V}"
    fi

    echo -e "${V}${DIM} Accumulated: ${BOLD}$(format_time $acc)${RESET}${DIM} | Remaining: ${BOLD}$(format_time $rem)${RESET}"
    echo -e "${DIM}${hline}${RESET}"
    local qp=$(( w - 12 ))
    [[ $qp -lt 1 ]] && qp=1
    local qs=""
    for ((i=0; i<qp; i++)); do qs+=" "; done
    echo -e "${DIM}${qs}[q] Quit${RESET} ${V}"
    echo -e "${DIM}${hline}${RESET}"

    tput civis 2>/dev/null || true
}

run_tui() {
    init_state
    trap 'tput cnorm 2>/dev/null' EXIT

    while true; do
        render_tui
        local key=""
        read -rsn1 -t 1 key 2>/dev/null || true
        case "$key" in
            q|Q) echo -e "\n${DIM}Bye.${RESET}\n"; exit 0 ;;
        esac
    done
}

# ─── MAIN ─────────────────────────────────────────────────────────────
case "${1:-}" in
    --daemon) run_daemon ;;
    *)        run_tui ;;
esac
