# Complete Bash configuration for the Coder workspace.

case $- in
    *i*) ;;
    *) return ;;
esac

HISTCONTROL=ignoreboth
shopt -s histappend
HISTSIZE=1000
HISTFILESIZE=2000
shopt -s checkwinsize

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
[ ! -r "$HOME/.local/state/workspace-desktop/desktop.env" ] || \
    . "$HOME/.local/state/workspace-desktop/desktop.env"

# Ordered feature aliases, functions and prompt integration are assembled here.
[ ! -r "$HOME/.config/bash_config" ] || . "$HOME/.config/bash_config"

COLOR_L_MAGENTA="\e[95m"
COLOR_GREY="\e[2m"
COLOR_END="\e[0m"

echo -e "${COLOR_GREY}${WORKSPACE_DESCRIPTION:-Development workspace}${COLOR_END}"
if [ -s "$HOME/.config/workspace/scripts" ]; then
    workspace_script_list=""
    while IFS= read -r workspace_script; do
        [ -n "$workspace_script" ] || continue
        if [ -n "$workspace_script_list" ]; then
            workspace_script_list+="${COLOR_GREY}, ${COLOR_END}"
        fi
        workspace_script_list+="${COLOR_L_MAGENTA}${workspace_script}${COLOR_END}"
    done < "$HOME/.config/workspace/scripts"
    echo -e "${COLOR_GREY}Available scripts:${COLOR_END} ${workspace_script_list}"
    unset workspace_script workspace_script_list
fi

workspace_function_list=""
while read -r workspace_declare workspace_flag workspace_function; do
    [ -n "$workspace_function" ] || continue
    if [ -n "$workspace_function_list" ]; then
        workspace_function_list+="${COLOR_GREY}, ${COLOR_END}"
    fi
    workspace_function_list+="${COLOR_L_MAGENTA}${workspace_function}${COLOR_END}"
done < <(declare -F)
if [ -n "$workspace_function_list" ]; then
    echo -e "${COLOR_GREY}Available functions:${COLOR_END} ${workspace_function_list}"
fi
unset workspace_declare workspace_flag workspace_function workspace_function_list

unset COLOR_L_MAGENTA COLOR_GREY COLOR_END
