# Complete login-shell configuration for the Coder workspace.

export HOME="${HOME:-/home/coder}"
export XDG_CONFIG_HOME="${XDG_CONFIG_HOME:-$HOME/.config}"
export XDG_DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
export XDG_STATE_HOME="${XDG_STATE_HOME:-$HOME/.local/state}"
case ":${PATH:-}:" in
    *":$HOME/.local/bin:"*) ;;
    *) export PATH="$HOME/.local/bin${PATH:+:$PATH}" ;;
esac

[ ! -r "$HOME/.config/workspace/profile.env" ] || \
    . "$HOME/.config/workspace/profile.env"

if [ -n "${BASH_VERSION:-}" ] && [ -r "$HOME/.bashrc" ]; then
    . "$HOME/.bashrc"
fi
