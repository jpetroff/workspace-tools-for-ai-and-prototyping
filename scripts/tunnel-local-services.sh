#!/usr/bin/env bash

# Expose local-only Chrome DevTools and Figma Desktop MCP services inside a
# Coder workspace. The tunnel exists only while this SSH session is open.

set -Eeuo pipefail

readonly DEFAULT_CHROME_PORT=9222
readonly DEFAULT_FIGMA_PORT=3845
readonly LOCAL_SERVICE_HOST=127.0.0.1

usage() {
  cat <<'EOF'
Usage: tunnel-local-services.sh WORKSPACE [options]

Create reverse SSH forwards from a Coder workspace to services on this
computer. By default, the same port is used at both ends:

  workspace 127.0.0.1:9222 -> local 127.0.0.1:9222 (Chrome DevTools)
  workspace 127.0.0.1:3845 -> local 127.0.0.1:3845 (Figma Desktop MCP)

Options:
  --chrome LOCAL[:REMOTE]  Override Chrome's local and optional workspace port
  --figma LOCAL[:REMOTE]   Override Figma's local and optional workspace port
  --no-chrome              Do not forward Chrome
  --no-figma               Do not forward Figma
  -h, --help               Show this help

Examples:
  ./scripts/tunnel-local-services.sh my-workspace
  ./scripts/tunnel-local-services.sh my-workspace --no-chrome
  ./scripts/tunnel-local-services.sh my-workspace --chrome 9223:19222

Exit the workspace shell (or press Ctrl-D) to close the tunnel.
EOF
}

fail() {
  printf 'error: %s\n' "$*" >&2
  exit 1
}

validate_port() {
  local port=$1
  local label=$2

  [[ $port =~ ^[1-9][0-9]{0,4}$ ]] || fail "$label must be a port from 1 to 65535"
  (( 10#$port <= 65535 )) || fail "$label must be a port from 1 to 65535"
}

parse_port_pair() {
  local value=$1
  local label=$2
  local local_port remote_port

  [[ $value != *:*:* ]] || fail "$label must use LOCAL or LOCAL:REMOTE"

  if [[ $value == *:* ]]; then
    local_port=${value%%:*}
    remote_port=${value#*:}
  else
    local_port=$value
    remote_port=$value
  fi

  validate_port "$local_port" "$label local port"
  validate_port "$remote_port" "$label workspace port"
  printf '%s %s\n' "$local_port" "$remote_port"
}

port_is_open() {
  local host=$1
  local port=$2

  (exec 3<>"/dev/tcp/${host}/${port}") 2>/dev/null
}

[[ ${1:-} != "" ]] || {
  usage >&2
  exit 2
}

case $1 in
  -h|--help)
    usage
    exit 0
    ;;
  -* )
    fail "the workspace name must be the first argument"
    ;;
esac

workspace=$1
shift

chrome_enabled=true
figma_enabled=true
chrome_local_port=$DEFAULT_CHROME_PORT
chrome_remote_port=$DEFAULT_CHROME_PORT
figma_local_port=$DEFAULT_FIGMA_PORT
figma_remote_port=$DEFAULT_FIGMA_PORT

while (($#)); do
  case $1 in
    --chrome)
      (($# >= 2)) || fail "--chrome requires LOCAL or LOCAL:REMOTE"
      read -r chrome_local_port chrome_remote_port < <(parse_port_pair "$2" "Chrome")
      chrome_enabled=true
      shift 2
      ;;
    --figma)
      (($# >= 2)) || fail "--figma requires LOCAL or LOCAL:REMOTE"
      read -r figma_local_port figma_remote_port < <(parse_port_pair "$2" "Figma")
      figma_enabled=true
      shift 2
      ;;
    --no-chrome)
      chrome_enabled=false
      shift
      ;;
    --no-figma)
      figma_enabled=false
      shift
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      fail "unknown option: $1"
      ;;
  esac
done

[[ $chrome_enabled == true || $figma_enabled == true ]] || fail "nothing to forward"

if [[ $chrome_enabled == true && $figma_enabled == true && $chrome_remote_port == "$figma_remote_port" ]]; then
  fail "Chrome and Figma cannot use the same workspace port"
fi

command -v coder >/dev/null 2>&1 || fail "Coder CLI is not installed or not in PATH"

if ! coder_ssh_help=$(coder ssh --help 2>&1) || [[ $coder_ssh_help != *"--remote-forward"* ]]; then
  fail "this Coder CLI does not support 'coder ssh --remote-forward'; update the CLI"
fi

coder_args=(ssh)

if [[ $chrome_enabled == true ]]; then
  if port_is_open "$LOCAL_SERVICE_HOST" "$chrome_local_port"; then
    printf 'Chrome: local port %s is ready.\n' "$chrome_local_port"
  else
    printf 'warning: Chrome is not listening on local port %s yet.\n' "$chrome_local_port" >&2
  fi
  coder_args+=(--remote-forward "${chrome_remote_port}:${LOCAL_SERVICE_HOST}:${chrome_local_port}")
fi

if [[ $figma_enabled == true ]]; then
  if port_is_open "$LOCAL_SERVICE_HOST" "$figma_local_port"; then
    printf 'Figma: local port %s is ready.\n' "$figma_local_port"
  else
    printf 'warning: Figma is not listening on local port %s yet.\n' "$figma_local_port" >&2
  fi
  coder_args+=(--remote-forward "${figma_remote_port}:${LOCAL_SERVICE_HOST}:${figma_local_port}")
fi

coder_args+=("$workspace")

printf 'Opening the tunnel to Coder workspace %s. Exit the shell to close it.\n' "$workspace"
exec coder "${coder_args[@]}"
