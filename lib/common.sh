# livediag - shared shell library
#
# Sourced by every test module and by the runner.  POSIX shell only so it
# runs on Alpine's BusyBox ash and on dash.  Keep it dependency-light: the
# only hard requirement is a POSIX shell; everything else degrades to a
# text prompt and a SKIP when the tool or hardware is missing.
#
# Environment understood:
#   LIVEDIAG_SESSION       session directory (set by the runner)
#   LIVEDIAG_RESULTS       results TSV path
#   LIVEDIAG_LOG           run log path
#   LIVEDIAG_NONINTERACTIVE=1   never show a GUI; manual steps are skipped
#   LIVEDIAG_OUTDIR        where standalone runs create their session
#   LIVEDIAG_TITLE         window title / branding

LG_VERSION="0.1.0"
: "${LIVEDIAG_TITLE:=livediag}"
: "${LIVEDIAG_NONINTERACTIVE:=0}"
: "${LIVEDIAG_SESSION:=}"
: "${LIVEDIAG_RESULTS:=}"
: "${LIVEDIAG_LOG:=}"

LG_SESSION="$LIVEDIAG_SESSION"
LG_RESULTS="$LIVEDIAG_RESULTS"
LG_LOG="$LIVEDIAG_LOG"
LG_RESULT_SET=0
LG_CLEANUP_FN=""
LG_TEST_ID="unknown"
LG_TEST_NAME="unknown"
LG_TEST_CATEGORY="General"

# The five anycast resolvers used by the connectivity probe.  They are
# deliberately IP literals so the probe works even while DNS is broken, and
# they are operated by five separate outfits, so one outage does not lie.
LG_PROBE_HOSTS="${LIVEDIAG_PROBE_HOSTS:-1.1.1.1 8.8.8.8 9.9.9.9 208.67.222.222 8.8.4.4}"

# --------------------------------------------------------------------------
# tiny utilities
# --------------------------------------------------------------------------

lg_have() { command -v "$1" >/dev/null 2>&1; }

lg_which() { command -v "$1" 2>/dev/null; }

# Print the first path that exists, or nothing.
lg_first() {
    for _p in "$@"; do
        if [ -e "$_p" ]; then
            printf '%s\n' "$_p"
            return 0
        fi
    done
    return 1
}

# Read a file if it is readable, otherwise print nothing.  sysfs/procfs
# reads that fail should never abort a test.
lg_read() {
    [ -n "$1" ] && [ -r "$1" ] && cat "$1" 2>/dev/null
}

# Run a command under a wall-clock timeout when coreutils timeout exists.
lg_try() {
    _lg_secs=$1
    shift
    if lg_have timeout; then
        timeout "$_lg_secs" "$@"
    else
        "$@"
    fi
}

# Run a command capturing stdout+stderr into a file.
lg_capture() {
    _lg_out=$1
    shift
    "$@" >"$_lg_out" 2>&1
}

lg_count() { wc -l 2>/dev/null | tr -d ' '; }

lg_ncpu() {
    if lg_have nproc; then
        nproc 2>/dev/null
    else
        grep -c '^processor' /proc/cpuinfo 2>/dev/null || echo 1
    fi
}

# List non-loopback network interfaces.
lg_net_ifaces() {
    for _d in /sys/class/net/*; do
        [ -e "$_d" ] || continue
        _n=${_d##*/}
        [ "$_n" = "lo" ] && continue
        printf '%s\n' "$_n"
    done
}

lg_is_wireless() { [ -d "/sys/class/net/$1/wireless" ]; }

lg_iface_ip4() {
    ip -4 -o addr show dev "$1" 2>/dev/null | awk '{print $4}' | cut -d/ -f1 | head -n1
}

lg_default_iface() {
    ip route 2>/dev/null | awk '/^default/{print $5; exit}'
}

# --------------------------------------------------------------------------
# session bookkeeping
# --------------------------------------------------------------------------

lg_new_session() {
    _lg_base="${LIVEDIAG_OUTDIR:-${HOME:-/tmp}/livediag-results}"
    _lg_dir="$_lg_base/$(date +%Y%m%d-%H%M%S)"
    if ! mkdir -p "$_lg_dir" 2>/dev/null; then
        _lg_dir=$(mktemp -d "${TMPDIR:-/tmp}/livediag.XXXXXX")
    fi
    printf '%s\n' "$_lg_dir"
}

# Called by every test module.  Reuses the runner's session when present,
# otherwise creates one so a test can also be run by hand.
lg_init() {
    if [ -z "$LG_SESSION" ]; then
        LG_SESSION=$(lg_new_session)
        LIVEDIAG_SESSION=$LG_SESSION
    fi
    [ -n "$LG_RESULTS" ] || LG_RESULTS="$LG_SESSION/results.tsv"
    [ -n "$LG_LOG" ] || LG_LOG="$LG_SESSION/run.log"
    [ -f "$LG_RESULTS" ] || : >"$LG_RESULTS"
    [ -f "$LG_LOG" ] || : >"$LG_LOG"
    LIVEDIAG_SESSION=$LG_SESSION
    LIVEDIAG_RESULTS=$LG_RESULTS
    LIVEDIAG_LOG=$LG_LOG
    export LIVEDIAG_SESSION LIVEDIAG_RESULTS LIVEDIAG_LOG
}

lg_write_environment() {
    _lg_f="$LG_SESSION/environment.txt"
    {
        printf 'livediag %s\n' "$LG_VERSION"
        printf 'generated: %s\n' "$(date 2>/dev/null)"
        printf 'kernel: %s\n' "$(uname -srm 2>/dev/null)"
        printf 'hostname: %s\n' "$(hostname 2>/dev/null)"
        printf 'session: %s\n' "$LG_SESSION"
        if [ -r /etc/os-release ]; then
            printf 'os-release:\n'
            sed 's/^/  /' /etc/os-release 2>/dev/null
        fi
    } >"$_lg_f" 2>/dev/null
}

# --------------------------------------------------------------------------
# GUI layer (zenity)
# --------------------------------------------------------------------------

lg_ui_available() {
    [ "$LIVEDIAG_NONINTERACTIVE" = "1" ] && return 1
    [ "${LIVEDIAG_NO_UI:-0}" = "1" ] && return 1
    lg_have zenity || return 1
    [ -n "${DISPLAY:-}${WAYLAND_DISPLAY:-}" ] || return 1
    return 0
}

lg_ui_info() {
    if lg_ui_available; then
        zenity --info --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
            --text="$1" >/dev/null 2>&1
    else
        printf 'livediag: %s\n' "$1" >&2
    fi
}

lg_ui_warn() {
    if lg_ui_available; then
        zenity --warning --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
            --text="$1" >/dev/null 2>&1
    else
        printf 'livediag: WARNING: %s\n' "$1" >&2
    fi
}

lg_ui_error() {
    if lg_ui_available; then
        zenity --error --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
            --text="$1" >/dev/null 2>&1
    else
        printf 'livediag: ERROR: %s\n' "$1" >&2
    fi
}

# Return 0 for yes, 1 for no/cancel.
lg_ui_yesno() {
    if lg_ui_available; then
        zenity --question --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
            --text="$1" >/dev/null 2>&1
        return $?
    fi
    printf 'livediag: %s [y/N] ' "$1" >&2
    if [ "$LIVEDIAG_NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
        read -r _lg_a || return 1
        case "$_lg_a" in y | Y | yes | YES) return 0 ;; esac
    fi
    return 1
}

# Echo the entered string; return 1 on cancel.
lg_ui_input() {
    if lg_ui_available; then
        if [ -n "${2:-}" ]; then
            zenity --entry --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
                --text="$1" --entry-text="$2" 2>/dev/null
        else
            zenity --entry --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
                --text="$1" 2>/dev/null
        fi
        return $?
    fi
    printf 'livediag: %s ' "$1" >&2
    [ -n "${2:-}" ] && printf '[%s] ' "$2" >&2
    if [ "$LIVEDIAG_NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
        read -r _lg_a || return 1
        printf '%s\n' "${_lg_a:-${2:-}}"
        return 0
    fi
    return 1
}

# Echo the entered secret; return 1 on cancel.
lg_ui_password() {
    if lg_ui_available; then
        zenity --password --no-markup --title="$LIVEDIAG_TITLE" --width=480 \
            --text="$1" 2>/dev/null
        return $?
    fi
    printf 'livediag: %s ' "$1" >&2
    if [ "$LIVEDIAG_NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
        read -r _lg_a || return 1
        printf '%s\n' "$_lg_a"
        return 0
    fi
    return 1
}

# lg_ui_menu TITLE TEXT id label description [id label description ...]
# Echoes the selected id.  Rows are grouped in threes.
lg_ui_menu() {
    _lg_t=$1
    _lg_x=$2
    shift 2
    [ "$#" -ge 3 ] || return 1
    if lg_ui_available; then
        _lg_out=$(zenity --list --no-markup --title="$_lg_t" --text="$_lg_x" \
            --width=640 --height=440 \
            --column=Id --column=Item --column=Details "$@" 2>/dev/null) || return 1
        printf '%s\n' "$_lg_out" | cut -d'|' -f1 | head -n1
        return 0
    fi
    _lg_tmp=$(mktemp "${TMPDIR:-/tmp}/livediag.menu.XXXXXX")
    _lg_i=0
    while [ "$#" -ge 3 ]; do
        _lg_i=$((_lg_i + 1))
        printf '%s\t%s\t%s\n' "$1" "$2" "$3" >>"$_lg_tmp"
        shift 3
    done
    awk -F'\t' '{printf "  %2d) %s - %s\n", NR, $2, $3}' "$_lg_tmp" >&2
    printf 'livediag: select [1-%d]: ' "$_lg_i" >&2
    if [ "$LIVEDIAG_NONINTERACTIVE" != "1" ] && [ -t 0 ]; then
        read -r _lg_n || { rm -f "$_lg_tmp"; return 1; }
        awk -F'\t' -v n="$_lg_n" 'NR==n{print $1}' "$_lg_tmp"
        _lg_rc=$?
    else
        _lg_rc=1
    fi
    rm -f "$_lg_tmp"
    return $_lg_rc
}

# lg_ui_checklist TITLE TEXT < list-of "id<TAB>label<TAB>description"
# Echoes selected ids, one per line.  In non-interactive mode everything is
# selected so a headless run still exercises every module.
lg_ui_checklist() {
    _lg_t=$1
    _lg_x=$2
    _lg_tmp=$(mktemp "${TMPDIR:-/tmp}/livediag.list.XXXXXX")
    cat >"$_lg_tmp"
    if lg_ui_available; then
        set --
        while IFS="$(printf '\t')" read -r _id _label _desc; do
            [ -z "$_id" ] && continue
            set -- "$@" TRUE "$_id" "$_label" "$_desc"
        done <"$_lg_tmp"
        _lg_out=$(zenity --list --checklist --no-markup --title="$_lg_t" \
            --text="$_lg_x" --width=780 --height=580 \
            --column='' --column=Id --column=Test --column=Description "$@" 2>/dev/null) || {
            rm -f "$_lg_tmp"
            return 1
        }
        _lg_ids=$(mktemp "${TMPDIR:-/tmp}/livediag.ids.XXXXXX")
        cut -f1 "$_lg_tmp" >"$_lg_ids"
        printf '%s\n' "$_lg_out" | tr '|' '\n' | while IFS= read -r _tok; do
            [ -n "$_tok" ] || continue
            if grep -qxF -- "$_tok" "$_lg_ids"; then
                printf '%s\n' "$_tok"
            fi
        done
        rm -f "$_lg_tmp" "$_lg_ids"
        return 0
    fi
    cut -f1 "$_lg_tmp"
    rm -f "$_lg_tmp"
    return 0
}

# Show a text file in a scrollable window.
lg_ui_text() {
    if lg_ui_available && [ -r "$2" ]; then
        zenity --text-info --no-markup --title="$1" --width=780 --height=580 \
            --filename="$2" >/dev/null 2>&1
    else
        printf '\n----- %s -----\n' "$1" >&2
        [ -r "$2" ] && cat "$2" >&2
        printf '\n' >&2
    fi
}

# lg_ui_table TITLE TEXT status check note [status check note ...]
# A plain table window: one row per check, with its note.
lg_ui_table() {
    _lg_t=$1
    _lg_x=$2
    shift 2
    if lg_ui_available; then
        zenity --list --no-markup --title="$_lg_t" --text="$_lg_x" \
            --width=880 --height=580 \
            --column=Status --column=Check --column=Notes "$@" >/dev/null 2>&1
        return 0
    fi
    [ -n "$_lg_x" ] && printf '\n%s\n' "$_lg_x" >&2
    while [ "$#" -ge 3 ]; do
        printf '  %-8s %-22s %s\n' "$1" "$2" "$3" >&2
        shift 3
    done
    return 0
}

# lg_busy TITLE COMMAND OUTFILE
# Runs COMMAND (a shell string) behind a pulsating progress dialog.
lg_busy() {
    _lg_t=$1
    _lg_cmd=$2
    _lg_out=$3
    if lg_ui_available; then
        (eval "$_lg_cmd") >"$_lg_out" 2>&1 &
        _lg_pid=$!
        (
            while kill -0 "$_lg_pid" 2>/dev/null; do
                sleep 0.3
            done
        ) | zenity --progress --pulsate --auto-close --no-cancel --no-markup \
            --title="$LIVEDIAG_TITLE" --text="$_lg_t" --width=480 >/dev/null 2>&1
        wait "$_lg_pid"
        return $?
    fi
    eval "$_lg_cmd" >"$_lg_out" 2>&1
}

# --------------------------------------------------------------------------
# live progress window
# --------------------------------------------------------------------------

LG_PROGRESS_FIFO=""
LG_PROGRESS_PID=""
LG_PROGRESS_TOTAL=0

# lg_progress_start TITLE TOTAL
lg_progress_start() {
    LG_PROGRESS_TITLE=${1:-livediag}
    LG_PROGRESS_TOTAL=${2:-0}
    LG_PROGRESS_FIFO=""
    LG_PROGRESS_PID=""
    if lg_ui_available; then
        _lg_fifo="${TMPDIR:-/tmp}/livediag-progress.$$"
        rm -f "$_lg_fifo"
        if mkfifo "$_lg_fifo" 2>/dev/null; then
            LG_PROGRESS_FIFO=$_lg_fifo
            (
                zenity --progress --no-markup --no-cancel --auto-close \
                    --title="$LG_PROGRESS_TITLE" \
                    --text="Preparing the checks..." \
                    --percentage=0 --width=540 <"$_lg_fifo" >/dev/null 2>&1
            ) &
            LG_PROGRESS_PID=$!
            # Read-write so this never blocks waiting for a reader and never
            # raises SIGPIPE if zenity goes away early.
            exec 9<>"$_lg_fifo"
            return 0
        fi
    fi
    printf 'livediag: %s check(s) queued\n' "$LG_PROGRESS_TOTAL" >&2
}

# lg_progress_set DONE MESSAGE
lg_progress_set() {
    _lg_done=$1
    shift
    _lg_msg=$*
    _lg_pct=0
    if [ "${LG_PROGRESS_TOTAL:-0}" -gt 0 ] 2>/dev/null; then
        _lg_pct=$((_lg_done * 100 / LG_PROGRESS_TOTAL))
    fi
    [ "$_lg_pct" -gt 100 ] && _lg_pct=100
    if [ -n "$LG_PROGRESS_FIFO" ]; then
        printf '%s\n# %s\n' "$_lg_pct" "$_lg_msg" >&9 2>/dev/null || true
    else
        printf 'livediag: [%s/%s] %s\n' "$_lg_done" "$LG_PROGRESS_TOTAL" "$_lg_msg" >&2
    fi
}

lg_progress_finish() {
    if [ -n "$LG_PROGRESS_FIFO" ]; then
        printf '100\n# All checks finished\n' >&9 2>/dev/null || true
        exec 9>&- 2>/dev/null || true
        wait "$LG_PROGRESS_PID" 2>/dev/null || true
        rm -f "$LG_PROGRESS_FIFO"
        LG_PROGRESS_FIFO=""
    fi
}

# True when this looks like a portable machine.
lg_is_laptop() {
    case "$(cat /sys/class/dmi/id/chassis_type 2>/dev/null)" in
    8 | 9 | 10 | 11 | 14) return 0 ;;
    esac
    for _lg_b in /sys/class/power_supply/*; do
        [ -r "$_lg_b/type" ] || continue
        [ "$(cat "$_lg_b/type" 2>/dev/null)" = "Battery" ] && return 0
    done
    return 1
}

# --------------------------------------------------------------------------
# results
# --------------------------------------------------------------------------

lg_begin() {
    LG_TEST_ID=$1
    LG_TEST_NAME=$2
    LG_TEST_CATEGORY=${3:-General}
    LG_RESULT_SET=0
    trap lg__exit_trap EXIT
    trap 'exit 130' INT
    trap 'exit 143' TERM
    printf '\n=== %s [%s] (%s) ===\n' "$LG_TEST_NAME" "$LG_TEST_ID" "$LG_TEST_CATEGORY" >>"$LG_LOG"
}

lg__exit_trap() {
    if [ -n "$LG_CLEANUP_FN" ]; then
        $LG_CLEANUP_FN
    fi
    if [ "$LG_RESULT_SET" != "1" ]; then
        lg_record WARN "test ended without reporting a result"
    fi
}

lg_record() {
    _lg_st=$1
    shift
    _lg_msg=$(printf '%s' "$*" | tr '\t\n' '  ')
    [ "$LG_RESULT_SET" = "1" ] && return 0
    LG_RESULT_SET=1
    printf '%s\t%s\t%s\t%s\t%s\t%s\n' \
        "$(date '+%Y-%m-%d %H:%M:%S' 2>/dev/null)" \
        "$LG_TEST_ID" "$_lg_st" "$LG_TEST_NAME" "$_lg_msg" "$LG_TEST_CATEGORY" >>"$LG_RESULTS"
    printf '[%s] %s: %s\n' "$_lg_st" "$LG_TEST_NAME" "$_lg_msg" | tee -a "$LG_LOG" >&2
}

lg_pass() {
    lg_record PASS "$@"
    exit 0
}
lg_fail() {
    lg_record FAIL "$@"
    exit 1
}
lg_warn() {
    lg_record WARN "$@"
    exit 0
}
lg_skip() {
    lg_record SKIP "$@"
    exit 0
}

# --------------------------------------------------------------------------
# network probes
# --------------------------------------------------------------------------

# lg_ping HOST [COUNT]
lg_ping() {
    _lg_host=$1
    _lg_c=${2:-1}
    lg_have ping || return 1
    ping -c "$_lg_c" -W 3 "$_lg_host" >/dev/null 2>&1 && return 0
    # BusyBox / older iputils use -w as a deadline in seconds.
    ping -c "$_lg_c" -w $((_lg_c * 3 + 3)) "$_lg_host" >/dev/null 2>&1 && return 0
    return 1
}

# lg_tcp HOST PORT - check a TCP port without trusting ICMP.
lg_tcp() {
    _lg_host=$1
    _lg_port=$2
    if lg_have nc; then
        nc -z -w 3 "$_lg_host" "$_lg_port" >/dev/null 2>&1 && return 0
    fi
    if lg_have curl; then
        # -k because this is a reachability check, not a security check: a
        # captive portal or a self-signed interceptor still proves the port
        # answers, which is all we are asking.
        curl -ksS --max-time 5 -o /dev/null "https://$_lg_host:$_lg_port" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# lg_http URL - fetch URL and discard the body.
lg_http() {
    if lg_have curl; then
        curl -fsS --max-time 8 -o /dev/null "$1" >/dev/null 2>&1 && return 0
    fi
    if lg_have wget; then
        wget -q -T 8 -O /dev/null "$1" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Probe the five resolvers; sets LG_PROBE_OK and LG_PROBE_TOTAL.
lg_net_probe() {
    LG_PROBE_OK=0
    LG_PROBE_TOTAL=0
    for _lg_h in $LG_PROBE_HOSTS; do
        LG_PROBE_TOTAL=$((LG_PROBE_TOTAL + 1))
        if lg_ping "$_lg_h" 1; then
            printf '  %-16s ping ok\n' "$_lg_h"
            LG_PROBE_OK=$((LG_PROBE_OK + 1))
        elif lg_tcp "$_lg_h" 443; then
            printf '  %-16s tcp/443 ok\n' "$_lg_h"
            LG_PROBE_OK=$((LG_PROBE_OK + 1))
        else
            printf '  %-16s unreachable\n' "$_lg_h"
        fi
    done
}

# --------------------------------------------------------------------------
# audio helpers (shared by the speaker and Bluetooth-audio tests)
# --------------------------------------------------------------------------

# Generate a stereo sine WAV.  Returns non-zero if no generator is available.
lg_make_tone() {
    _lg_o=$1
    _lg_d=${2:-1.5}
    _lg_hz=${3:-440}
    if lg_have ffmpeg; then
        ffmpeg -y -loglevel error -f lavfi -i "sine=frequency=$_lg_hz:duration=$_lg_d" \
            -ar 48000 -ac 2 "$_lg_o" >/dev/null 2>&1 && return 0
    fi
    if lg_have sox; then
        sox -n -r 48000 -c 2 "$_lg_o" synth "$_lg_d" sine "$_lg_hz" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Play a WAV through whichever sound server is present.
lg_play_wav() {
    _lg_f=$1
    [ -n "$_lg_f" ] && [ -r "$_lg_f" ] || return 1
    if lg_have paplay; then
        paplay "$_lg_f" >/dev/null 2>&1 && return 0
    fi
    if lg_have pw-play; then
        pw-play "$_lg_f" >/dev/null 2>&1 && return 0
    fi
    if lg_have aplay; then
        aplay -q "$_lg_f" >/dev/null 2>&1 && return 0
    fi
    if lg_have ffplay; then
        ffplay -nodisp -autoexit -loglevel quiet "$_lg_f" >/dev/null 2>&1 && return 0
    fi
    if lg_have play; then
        play -q "$_lg_f" >/dev/null 2>&1 && return 0
    fi
    return 1
}

# Play a generated tone, falling back to speaker-test.
lg_play_tone() {
    _lg_o=$(mktemp "${TMPDIR:-/tmp}/livediag.tone.XXXXXX") || _lg_o="${TMPDIR:-/tmp}/livediag.tone.$$"
    if lg_make_tone "$_lg_o"; then
        lg_play_wav "$_lg_o"
        _lg_rc=$?
        rm -f "$_lg_o"
        return $_lg_rc
    fi
    rm -f "$_lg_o"
    if lg_have speaker-test; then
        lg_try 15 speaker-test -q -t sine -f 440 -c 2 -l 1 >/dev/null 2>&1 && return 0
    fi
    return 1
}
