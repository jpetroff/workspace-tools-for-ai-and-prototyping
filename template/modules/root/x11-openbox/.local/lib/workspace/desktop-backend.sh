#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE="$HOME/.config/workspace/profile.env"
[[ -r "$PROFILE" ]] && source "$PROFILE"

COMMAND="${1:-start}"
if [[ $# -gt 0 ]]; then shift; fi
RUN_ARGS=()
if [[ "$COMMAND" == run ]]; then RUN_ARGS=("$@"); set --; fi

SCREEN_SIZE="${SCREEN_SIZE:-1440x960}"
SCREEN_DEPTH="${SCREEN_DEPTH:-24}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
NOVNC_BIND="${NOVNC_BIND:-127.0.0.1}"
DISPLAY_VALUE="${DISPLAY:-:0}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.local/run/workspace-desktop}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workspace-desktop"
RUN_DIR="$STATE_DIR/run"
LOG_DIR="$STATE_DIR/log"
ENV_FILE="$STATE_DIR/desktop.env"
DBUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RUNTIME_DIR/dbus-session}"
DBUS_SOCKET="${DBUS_ADDRESS#unix:path=}"
NOVNC_PROXY="${NOVNC_PROXY:-$HOME/.local/bin/novnc_proxy}"
NOVNC_WEB_ROOT="${NOVNC_WEB_ROOT:-$HOME/.local/share/novnc}"
X11VNC_CONFIG="${X11VNC_CONFIG:-$HOME/.config/x11vnc/config}"
X11VNC_ARGS=(-localhost -forever -shared -nopw -xkb -quiet)
[[ -r "$X11VNC_CONFIG" ]] && source "$X11VNC_CONFIG"

usage() {
    cat <<'EOF'
Usage:
  workspace-desktop start [--size WIDTHxHEIGHT]
  workspace-desktop stop
  workspace-desktop restart [--size WIDTHxHEIGHT]
  workspace-desktop status
  workspace-desktop health
  workspace-desktop gpu
  workspace-desktop logs [dbus|xvfb|openbox|x11vnc|novnc]
  workspace-desktop env
  workspace-desktop run APPLICATION [ARGUMENT...]
EOF
}

if [[ "$COMMAND" =~ ^(-h|--help|help)$ ]]; then usage; exit 0; fi

LOG_SERVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size) SCREEN_SIZE="${2:?Missing value for --size}"; shift 2 ;;
        --vnc-port) VNC_PORT="${2:?Missing value for --vnc-port}"; shift 2 ;;
        --novnc-port) NOVNC_PORT="${2:?Missing value for --novnc-port}"; shift 2 ;;
        --novnc-bind) NOVNC_BIND="${2:?Missing value for --novnc-bind}"; shift 2 ;;
        *)
            if [[ "$COMMAND" == logs && -z "$LOG_SERVICE" ]]; then
                LOG_SERVICE="$1"; shift
            else
                echo "Unknown argument: $1" >&2; exit 2
            fi
            ;;
    esac
done

[[ "$SCREEN_SIZE" =~ ^([0-9]+)x([0-9]+)$ ]] || {
    echo "Invalid screen size: $SCREEN_SIZE" >&2; exit 2;
}
WIDTH="${BASH_REMATCH[1]}"; HEIGHT="${BASH_REMATCH[2]}"
[[ "$DISPLAY_VALUE" =~ ^:([0-9]+)$ ]] || {
    echo "Invalid DISPLAY: $DISPLAY_VALUE" >&2; exit 2;
}
DISPLAY_NUM="${BASH_REMATCH[1]}"
for port_name in VNC_PORT NOVNC_PORT; do
    port_value="${!port_name}"
    if [[ ! "$port_value" =~ ^[0-9]+$ ]] ||
       (( port_value < 1 || port_value > 65535 )); then
        echo "Invalid ${port_name}: ${port_value}" >&2
        exit 2
    fi
done
[[ "$VNC_PORT" != "$NOVNC_PORT" ]] || {
    echo "VNC and noVNC ports must differ." >&2
    exit 2
}

mkdir -p "$RUN_DIR" "$LOG_DIR" "$RUNTIME_DIR"
chmod 0700 "$RUNTIME_DIR"

pid_file() { printf '%s/%s.pid' "$RUN_DIR" "$1"; }
expected_command() {
    case "$1" in
        dbus) printf dbus-daemon ;;
        xvfb) printf Xvfb ;;
        openbox) printf openbox ;;
        x11vnc) printf x11vnc ;;
        novnc) printf novnc_proxy ;;
        *) return 1 ;;
    esac
}
is_running() {
    local name="$1" file pid args expected
    file="$(pid_file "$name")"; [[ -r "$file" ]] || return 1
    pid="$(<"$file")"; [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    args="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    expected="$(expected_command "$name")"
    [[ "$args" == *"$expected"* ]]
}
spawn() {
    local name="$1"; shift
    nohup "$@" >>"$LOG_DIR/$name.log" 2>&1 </dev/null &
    echo "$!" > "$(pid_file "$name")"
}
wait_socket() {
    local socket="$1" label="$2" attempt
    for attempt in $(seq 1 100); do [[ -S "$socket" ]] && return 0; sleep 0.1; done
    echo "$label socket did not become ready" >&2; return 1
}
wait_display() {
    local attempt
    for attempt in $(seq 1 100); do
        xdpyinfo -display "$DISPLAY_VALUE" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    echo "Xvfb did not become ready on $DISPLAY_VALUE" >&2; return 1
}
wait_port() {
    local host="$1" port="$2" label="$3" attempt
    for attempt in $(seq 1 100); do
        if timeout 1 bash -c 'exec 3<>"/dev/tcp/${1}/${2}"' _ "$host" "$port" \
            >/dev/null 2>&1; then return 0; fi
        sleep 0.1
    done
    echo "$label did not listen on $host:$port" >&2; return 1
}
write_env() {
    cat > "$ENV_FILE" <<EOF
export WORKSPACE_DISPLAY_BACKEND='x11-openbox'
export DISPLAY='${DISPLAY_VALUE}'
export XDG_RUNTIME_DIR='${RUNTIME_DIR}'
export XDG_CONFIG_HOME='${XDG_CONFIG_HOME:-$HOME/.config}'
export XDG_DATA_HOME='${XDG_DATA_HOME:-$HOME/.local/share}'
export XDG_STATE_HOME='${XDG_STATE_HOME:-$HOME/.local/state}'
export DBUS_SESSION_BUS_ADDRESS='${DBUS_ADDRESS}'
export XDG_SESSION_TYPE='x11'
export XDG_CURRENT_DESKTOP='Openbox'
export GDK_BACKEND='x11'
export QT_QPA_PLATFORM='xcb'
unset WAYLAND_DISPLAY
export LIBGL_ALWAYS_SOFTWARE='1'
export GALLIUM_DRIVER='llvmpipe'
EOF
}
check_assets() {
    [[ -x "$NOVNC_PROXY" ]] || { echo "Missing noVNC proxy" >&2; return 1; }
    [[ -r "$NOVNC_WEB_ROOT/vnc.html" ]] || { echo "Missing noVNC assets" >&2; return 1; }
}
stop_one() {
    local name="$1" file pid
    file="$(pid_file "$name")"
    if is_running "$name"; then
        pid="$(<"$file")"; kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.1; done
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$file"
}
stop_desktop() {
    local quiet="${1:-false}"
    stop_one novnc; stop_one x11vnc; stop_one openbox; stop_one xvfb; stop_one dbus
    rm -f "$ENV_FILE" "$DBUS_SOCKET" "/tmp/.X${DISPLAY_NUM}-lock" \
        "/tmp/.X11-unix/X${DISPLAY_NUM}"
    [[ "$quiet" == true ]] || echo "Workspace desktop stopped."
}
all_running() {
    local name
    for name in dbus xvfb openbox x11vnc novnc; do is_running "$name" || return 1; done
}
start_desktop() {
    if all_running; then echo "Workspace desktop is already running."; status_desktop; return; fi
    check_assets
    stop_desktop true
    rm -f "$DBUS_SOCKET" "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
    write_env
    spawn dbus dbus-daemon --session --nofork --address="$DBUS_ADDRESS"
    wait_socket "$DBUS_SOCKET" D-Bus || { stop_desktop true; return 1; }
    spawn xvfb env LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe \
        Xvfb "$DISPLAY_VALUE" -screen 0 "${WIDTH}x${HEIGHT}x${SCREEN_DEPTH}" \
        -dpi 96 -nolisten tcp
    wait_display || { stop_desktop true; return 1; }
    spawn openbox env DISPLAY="$DISPLAY_VALUE" DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" \
        openbox
    sleep 0.3
    spawn x11vnc x11vnc -display "$DISPLAY_VALUE" -rfbport "$VNC_PORT" \
        "${X11VNC_ARGS[@]}"
    wait_port 127.0.0.1 "$VNC_PORT" x11vnc || { stop_desktop true; return 1; }
    spawn novnc "$NOVNC_PROXY" --listen "$NOVNC_BIND:$NOVNC_PORT" \
        --vnc "127.0.0.1:$VNC_PORT" --web "$NOVNC_WEB_ROOT"
    wait_port 127.0.0.1 "$NOVNC_PORT" noVNC || { stop_desktop true; return 1; }
    echo "Workspace desktop started: x11-openbox"
    echo "DISPLAY=$DISPLAY_VALUE size=${SCREEN_SIZE}x${SCREEN_DEPTH}"
    echo "noVNC=http://127.0.0.1:$NOVNC_PORT/"
}
status_desktop() {
    local name healthy=true
    echo "Backend=x11-openbox"; echo "Renderer=software"; echo "DISPLAY=$DISPLAY_VALUE"
    for name in dbus xvfb openbox x11vnc novnc; do
        if is_running "$name"; then
            printf '%-8s running PID %s\n' "$name" "$(<"$(pid_file "$name")")"
        else
            printf '%-8s stopped\n' "$name"; healthy=false
        fi
    done
    [[ "$healthy" == true ]]
}
health_desktop() {
    all_running && xdpyinfo -display "$DISPLAY_VALUE" >/dev/null 2>&1 &&
        timeout 1 bash -c 'exec 3<>"/dev/tcp/${1}/${2}"' _ 127.0.0.1 "$NOVNC_PORT" \
            >/dev/null 2>&1
}
renderer_status() {
    xdpyinfo -display "$DISPLAY_VALUE" >/dev/null 2>&1 || {
        echo "Desktop is not running" >&2; return 1;
    }
    local details
    details="$(env DISPLAY="$DISPLAY_VALUE" LIBGL_ALWAYS_SOFTWARE=1 \
        GALLIUM_DRIVER=llvmpipe glxinfo -B 2>&1)" || { printf '%s\n' "$details"; return 1; }
    printf '%s\n' "$details"
    grep -Eqi 'llvmpipe|softpipe|swrast|software' <<<"$details" || {
        echo "Software renderer was not detected." >&2; return 1;
    }
    echo "Software rendering detected as configured."
}
show_logs() {
    if [[ -n "$LOG_SERVICE" ]]; then
        [[ "$LOG_SERVICE" =~ ^(dbus|xvfb|openbox|x11vnc|novnc)$ ]] || return 2
        tail -n 200 "$LOG_DIR/$LOG_SERVICE.log"
    else
        local log
        for log in "$LOG_DIR"/*.log; do
            [[ -e "$log" ]] || continue
            printf '\n==> %s <==\n' "$(basename "$log")"; tail -n 80 "$log"
        done
    fi
}
run_app() {
    [[ ${#RUN_ARGS[@]} -gt 0 ]] || { echo "Missing application" >&2; return 2; }
    [[ -r "$ENV_FILE" ]] || { echo "Desktop is not running" >&2; return 1; }
    source "$ENV_FILE"; exec "${RUN_ARGS[@]}"
}

case "$COMMAND" in
    start) start_desktop ;;
    stop) stop_desktop ;;
    restart) stop_desktop true; start_desktop ;;
    status) status_desktop ;;
    health) health_desktop ;;
    gpu) renderer_status ;;
    logs) show_logs ;;
    env) if [[ -r "$ENV_FILE" ]]; then cat "$ENV_FILE"; else write_env; cat "$ENV_FILE"; fi ;;
    run) run_app ;;
    *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 2 ;;
esac
