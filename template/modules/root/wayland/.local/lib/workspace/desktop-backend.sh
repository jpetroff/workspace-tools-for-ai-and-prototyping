#!/usr/bin/env bash

set -Eeuo pipefail

PROFILE="$HOME/.config/workspace/profile.env"
[[ -r "$PROFILE" ]] && source "$PROFILE"

COMMAND="${1:-start}"
if [[ $# -gt 0 ]]; then shift; fi

RUN_ARGS=()
if [[ "$COMMAND" == "run" ]]; then
    RUN_ARGS=("$@")
    set --
fi

SCREEN_SIZE="${SCREEN_SIZE:-1440x960}"
VNC_PORT="${VNC_PORT:-5900}"
NOVNC_PORT="${NOVNC_PORT:-6080}"
NOVNC_BIND="${NOVNC_BIND:-127.0.0.1}"
DISPLAY_VALUE="${DISPLAY:-:0}"
WAYLAND_NAME="${WAYLAND_DISPLAY:-wayland-1}"
RENDER_MODE="${WORKSPACE_RENDER_MODE:-software}"
GPU_DEVICE="${WLR_RENDER_DRM_DEVICE:-${GPU_RENDER_DEVICE:-/dev/dri/renderD128}}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-$HOME/.local/run/workspace-desktop}"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/workspace-desktop"
RUN_DIR="$STATE_DIR/run"
LOG_DIR="$STATE_DIR/log"
ENV_FILE="$STATE_DIR/desktop.env"
DBUS_ADDRESS="${DBUS_SESSION_BUS_ADDRESS:-unix:path=$RUNTIME_DIR/dbus-session}"
DBUS_SOCKET="${DBUS_ADDRESS#unix:path=}"
WAYLAND_SOCKET="$RUNTIME_DIR/$WAYLAND_NAME"
SWAY_CONFIG="${SWAY_CONFIG:-$HOME/.config/sway/config}"
SWAY_SOCKET_FILE="$RUN_DIR/sway.socket"
OUTPUT_FILE="$RUN_DIR/output.name"
NOVNC_PROXY="${NOVNC_PROXY:-$HOME/.local/bin/novnc_proxy}"
NOVNC_WEB_ROOT="${NOVNC_WEB_ROOT:-$HOME/.local/share/novnc}"

usage() {
    cat <<'EOF'
Usage:
  workspace-desktop start [--size WIDTHxHEIGHT]
  workspace-desktop stop
  workspace-desktop restart [--size WIDTHxHEIGHT]
  workspace-desktop status
  workspace-desktop health
  workspace-desktop gpu
  workspace-desktop logs [dbus|sway|wayvnc|novnc]
  workspace-desktop env
  workspace-desktop run APPLICATION [ARGUMENT...]
EOF
}

if [[ "$COMMAND" == "-h" || "$COMMAND" == "--help" || "$COMMAND" == "help" ]]; then
    usage
    exit 0
fi

LOG_SERVICE=""
while [[ $# -gt 0 ]]; do
    case "$1" in
        --size) SCREEN_SIZE="${2:?Missing value for --size}"; shift 2 ;;
        --vnc-port) VNC_PORT="${2:?Missing value for --vnc-port}"; shift 2 ;;
        --novnc-port) NOVNC_PORT="${2:?Missing value for --novnc-port}"; shift 2 ;;
        --novnc-bind) NOVNC_BIND="${2:?Missing value for --novnc-bind}"; shift 2 ;;
        *)
            if [[ "$COMMAND" == "logs" && -z "$LOG_SERVICE" ]]; then
                LOG_SERVICE="$1"
                shift
            else
                echo "Unknown argument: $1" >&2
                exit 2
            fi
            ;;
    esac
done

if [[ ! "$SCREEN_SIZE" =~ ^([0-9]+)x([0-9]+)$ ]]; then
    echo "Invalid screen size: $SCREEN_SIZE" >&2
    exit 2
fi
WIDTH="${BASH_REMATCH[1]}"
HEIGHT="${BASH_REMATCH[2]}"
if [[ ! "$DISPLAY_VALUE" =~ ^:([0-9]+)$ ]]; then
    echo "Invalid DISPLAY: $DISPLAY_VALUE" >&2
    exit 2
fi
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
        sway) printf sway ;;
        wayvnc) printf wayvnc ;;
        novnc) printf novnc_proxy ;;
        *) return 1 ;;
    esac
}

is_running() {
    local name="$1" file pid command expected
    file="$(pid_file "$name")"
    [[ -r "$file" ]] || return 1
    pid="$(<"$file")"
    [[ "$pid" =~ ^[0-9]+$ ]] || return 1
    kill -0 "$pid" 2>/dev/null || return 1
    command="$(ps -p "$pid" -o args= 2>/dev/null || true)"
    expected="$(expected_command "$name")"
    [[ "$command" == *"$expected"* ]]
}

spawn() {
    local name="$1"; shift
    nohup "$@" >>"$LOG_DIR/$name.log" 2>&1 </dev/null &
    echo "$!" > "$(pid_file "$name")"
}

wait_socket() {
    local socket="$1" label="$2" attempt
    for attempt in $(seq 1 150); do
        [[ -S "$socket" ]] && return 0
        sleep 0.1
    done
    echo "$label socket did not become ready: $socket" >&2
    return 1
}

wait_port() {
    local host="$1" port="$2" label="$3" attempt
    for attempt in $(seq 1 150); do
        if timeout 1 bash -c 'exec 3<>"/dev/tcp/${1}/${2}"' _ "$host" "$port" \
            >/dev/null 2>&1; then
            return 0
        fi
        sleep 0.1
    done
    echo "$label did not listen on $host:$port" >&2
    return 1
}

wait_xwayland() {
    local attempt
    for attempt in $(seq 1 150); do
        xdpyinfo -display "$DISPLAY_VALUE" >/dev/null 2>&1 && return 0
        sleep 0.1
    done
    echo "XWayland did not become ready on $DISPLAY_VALUE" >&2
    return 1
}

find_sway_socket() {
    local attempt socket
    for attempt in $(seq 1 150); do
        socket="$(find "$RUNTIME_DIR" -maxdepth 1 -type s \
            -name 'sway-ipc.*.sock' -print -quit 2>/dev/null || true)"
        [[ -n "$socket" ]] && { printf '%s' "$socket"; return 0; }
        sleep 0.1
    done
    return 1
}

find_output() {
    local socket="$1" attempt output
    for attempt in $(seq 1 100); do
        output="$(swaymsg -s "$socket" -t get_outputs -r 2>/dev/null |
            jq -r '.[] | select(.name | startswith("HEADLESS-")) | .name' |
            head -n 1 || true)"
        [[ -n "$output" && "$output" != null ]] && { printf '%s' "$output"; return 0; }
        sleep 0.1
    done
    return 1
}

write_env() {
    local sway_socket="${1:-}"
    {
        printf "export WORKSPACE_DISPLAY_BACKEND='%s'\n" "$WORKSPACE_DISPLAY_BACKEND"
        printf "export DISPLAY='%s'\n" "$DISPLAY_VALUE"
        printf "export WAYLAND_DISPLAY='%s'\n" "$WAYLAND_NAME"
        printf "export XDG_RUNTIME_DIR='%s'\n" "$RUNTIME_DIR"
        printf "export XDG_CONFIG_HOME='%s'\n" "${XDG_CONFIG_HOME:-$HOME/.config}"
        printf "export XDG_DATA_HOME='%s'\n" "${XDG_DATA_HOME:-$HOME/.local/share}"
        printf "export XDG_STATE_HOME='%s'\n" "${XDG_STATE_HOME:-$HOME/.local/state}"
        printf "export DBUS_SESSION_BUS_ADDRESS='%s'\n" "$DBUS_ADDRESS"
        printf "export XDG_SESSION_TYPE='wayland'\n"
        printf "export XDG_CURRENT_DESKTOP='sway'\n"
        printf "export GDK_BACKEND='wayland,x11'\n"
        printf "export QT_QPA_PLATFORM='wayland;xcb'\n"
        printf "export WLR_BACKENDS='headless'\n"
        printf "export WLR_HEADLESS_OUTPUTS='1'\n"
        printf "export WLR_LIBINPUT_NO_DEVICES='1'\n"
        printf "export SWAYSOCK='%s'\n" "$sway_socket"
        if [[ "$RENDER_MODE" == gpu ]]; then
            printf "export WLR_RENDERER='gles2'\n"
            printf "export WLR_RENDER_DRM_DEVICE='%s'\n" "$GPU_DEVICE"
            printf "unset LIBGL_ALWAYS_SOFTWARE GALLIUM_DRIVER\n"
        else
            printf "export WLR_RENDERER='pixman'\n"
            printf "export LIBGL_ALWAYS_SOFTWARE='1'\n"
            printf "export GALLIUM_DRIVER='llvmpipe'\n"
        fi
    } > "$ENV_FILE"
}

check_assets() {
    [[ -r "$SWAY_CONFIG" ]] || { echo "Missing Sway config: $SWAY_CONFIG" >&2; return 1; }
    [[ -x "$NOVNC_PROXY" ]] || { echo "Missing noVNC proxy: $NOVNC_PROXY" >&2; return 1; }
    [[ -r "$NOVNC_WEB_ROOT/vnc.html" ]] || { echo "Missing noVNC web assets" >&2; return 1; }
}

check_gpu() {
    [[ "$RENDER_MODE" == gpu ]] || return 0
    [[ -c "$GPU_DEVICE" ]] || { echo "Missing GPU render node: $GPU_DEVICE" >&2; return 1; }
    local gid
    gid="$(stat -c '%g' "$GPU_DEVICE")"
    id -G | tr ' ' '\n' | grep -qx "$gid" || {
        echo "Current process lacks render-node GID $gid" >&2
        return 1
    }
    if ! getent group "$gid" >/dev/null; then
        sudo groupadd --gid "$gid" "host-render-$gid"
    fi
    [[ -r "$GPU_DEVICE" && -w "$GPU_DEVICE" ]] || {
        echo "Cannot read and write $GPU_DEVICE" >&2
        return 1
    }
}

stop_one() {
    local name="$1" file pid
    file="$(pid_file "$name")"
    if is_running "$name"; then
        pid="$(<"$file")"
        kill "$pid" 2>/dev/null || true
        for _ in $(seq 1 30); do
            kill -0 "$pid" 2>/dev/null || break
            sleep 0.1
        done
        kill -KILL "$pid" 2>/dev/null || true
    fi
    rm -f "$file"
}

stop_desktop() {
    local quiet="${1:-false}"
    stop_one novnc
    stop_one wayvnc
    stop_one sway
    stop_one dbus
    rm -f "$ENV_FILE" "$DBUS_SOCKET" "$WAYLAND_SOCKET" "${WAYLAND_SOCKET}.lock" \
        "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}" \
        "$SWAY_SOCKET_FILE" "$OUTPUT_FILE"
    find "$RUNTIME_DIR" -maxdepth 1 -type s -name 'sway-ipc.*.sock' -delete \
        2>/dev/null || true
    [[ "$quiet" == true ]] || echo "Workspace desktop stopped."
}

all_running() {
    local name
    for name in dbus sway wayvnc novnc; do is_running "$name" || return 1; done
}

start_desktop() {
    local sway_socket output renderer_args=()
    if all_running; then
        echo "Workspace desktop is already running."
        status_desktop
        return
    fi
    check_assets
    check_gpu
    stop_desktop true
    rm -f "$DBUS_SOCKET" "$WAYLAND_SOCKET" "${WAYLAND_SOCKET}.lock" \
        "/tmp/.X${DISPLAY_NUM}-lock" "/tmp/.X11-unix/X${DISPLAY_NUM}"
    write_env

    spawn dbus dbus-daemon --session --nofork --address="$DBUS_ADDRESS"
    wait_socket "$DBUS_SOCKET" D-Bus || { stop_desktop true; return 1; }

    if [[ "$RENDER_MODE" == gpu ]]; then
        renderer_args=(WLR_RENDERER=gles2 WLR_RENDER_DRM_DEVICE="$GPU_DEVICE")
    else
        renderer_args=(WLR_RENDERER=pixman LIBGL_ALWAYS_SOFTWARE=1 GALLIUM_DRIVER=llvmpipe)
    fi
    spawn sway env \
        XDG_RUNTIME_DIR="$RUNTIME_DIR" \
        DBUS_SESSION_BUS_ADDRESS="$DBUS_ADDRESS" \
        WLR_BACKENDS=headless \
        WLR_HEADLESS_OUTPUTS=1 \
        WLR_LIBINPUT_NO_DEVICES=1 \
        "${renderer_args[@]}" \
        sway --config "$SWAY_CONFIG"

    wait_socket "$WAYLAND_SOCKET" Wayland || { stop_desktop true; return 1; }
    wait_xwayland || { stop_desktop true; return 1; }
    sway_socket="$(find_sway_socket)" || { echo "Sway IPC unavailable" >&2; stop_desktop true; return 1; }
    printf '%s' "$sway_socket" > "$SWAY_SOCKET_FILE"
    output="$(find_output "$sway_socket")" || { echo "No headless output" >&2; stop_desktop true; return 1; }
    printf '%s' "$output" > "$OUTPUT_FILE"
    swaymsg -s "$sway_socket" output "$output" mode "${WIDTH}x${HEIGHT}@60Hz" scale 1 >/dev/null
    write_env "$sway_socket"

    spawn wayvnc env XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY="$WAYLAND_NAME" \
        wayvnc --output "$output" 127.0.0.1 "$VNC_PORT"
    wait_port 127.0.0.1 "$VNC_PORT" WayVNC || { stop_desktop true; return 1; }
    spawn novnc "$NOVNC_PROXY" --listen "$NOVNC_BIND:$NOVNC_PORT" \
        --vnc "127.0.0.1:$VNC_PORT" --web "$NOVNC_WEB_ROOT"
    wait_port 127.0.0.1 "$NOVNC_PORT" noVNC || { stop_desktop true; return 1; }

    echo "Workspace desktop started: $WORKSPACE_DISPLAY_BACKEND"
    echo "Wayland=$WAYLAND_NAME DISPLAY=$DISPLAY_VALUE size=$SCREEN_SIZE"
    echo "noVNC=http://127.0.0.1:$NOVNC_PORT/"
}

status_desktop() {
    local name healthy=true
    echo "Backend=$WORKSPACE_DISPLAY_BACKEND"
    echo "Renderer=$RENDER_MODE"
    echo "WAYLAND_DISPLAY=$WAYLAND_NAME"
    echo "DISPLAY=$DISPLAY_VALUE"
    for name in dbus sway wayvnc novnc; do
        if is_running "$name"; then
            printf '%-8s running PID %s\n' "$name" "$(<"$(pid_file "$name")")"
        else
            printf '%-8s stopped\n' "$name"
            healthy=false
        fi
    done
    [[ "$healthy" == true ]]
}

health_desktop() {
    local socket
    all_running || return 1
    check_gpu >/dev/null || return 1
    [[ -S "$WAYLAND_SOCKET" ]] || return 1
    xdpyinfo -display "$DISPLAY_VALUE" >/dev/null 2>&1 || return 1
    socket="$(<"$SWAY_SOCKET_FILE")"
    swaymsg -s "$socket" -t get_outputs >/dev/null 2>&1 || return 1
    timeout 1 bash -c 'exec 3<>"/dev/tcp/${1}/${2}"' _ 127.0.0.1 "$NOVNC_PORT" \
        >/dev/null 2>&1
}

renderer_status() {
    [[ -S "$WAYLAND_SOCKET" ]] || { echo "Desktop is not running" >&2; return 1; }
    local details
    details="$(env XDG_RUNTIME_DIR="$RUNTIME_DIR" WAYLAND_DISPLAY="$WAYLAND_NAME" \
        wflinfo --platform wayland --api gles2 --verbose 2>&1)" || {
        printf '%s\n' "$details"
        return 1
    }
    printf '%s\n' "$details"
    if [[ "$RENDER_MODE" == gpu ]]; then
        check_gpu
        grep -Eqi 'AMD|Radeon|radeonsi' <<<"$details" || {
            echo "AMD hardware renderer was not detected." >&2
            return 1
        }
        grep -Eqi 'llvmpipe|softpipe|swrast' <<<"$details" && {
            echo "Unexpected software renderer." >&2
            return 1
        }
        echo "Hardware rendering detected: AMD/radeonsi."
    else
        grep -Eqi 'llvmpipe|softpipe|swrast|software' <<<"$details" || {
            echo "Software renderer was not detected." >&2
            return 1
        }
        echo "Software rendering detected as configured."
    fi
}

show_logs() {
    if [[ -n "$LOG_SERVICE" ]]; then
        [[ "$LOG_SERVICE" =~ ^(dbus|sway|wayvnc|novnc)$ ]] || { echo "Unknown service" >&2; return 2; }
        tail -n 200 "$LOG_DIR/$LOG_SERVICE.log"
    else
        local log
        for log in "$LOG_DIR"/*.log; do
            [[ -e "$log" ]] || continue
            printf '\n==> %s <==\n' "$(basename "$log")"
            tail -n 80 "$log"
        done
    fi
}

run_app() {
    [[ ${#RUN_ARGS[@]} -gt 0 ]] || { echo "Missing application" >&2; return 2; }
    [[ -r "$ENV_FILE" ]] || { echo "Desktop is not running" >&2; return 1; }
    source "$ENV_FILE"
    exec "${RUN_ARGS[@]}"
}

case "$COMMAND" in
    start) start_desktop ;;
    stop) stop_desktop ;;
    restart) stop_desktop true; start_desktop ;;
    status) status_desktop ;;
    health) health_desktop ;;
    gpu) renderer_status ;;
    logs) show_logs ;;
    env)
        if [[ -r "$ENV_FILE" ]]; then
            cat "$ENV_FILE"
        else
            write_env
            cat "$ENV_FILE"
        fi
        ;;
    run) run_app ;;
    *) echo "Unknown command: $COMMAND" >&2; usage >&2; exit 2 ;;
esac
