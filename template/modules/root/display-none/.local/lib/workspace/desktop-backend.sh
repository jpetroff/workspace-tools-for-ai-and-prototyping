#!/usr/bin/env bash

set -Eeuo pipefail

command_name="${1:-status}"

case "$command_name" in
    status)
        echo "Desktop backend: none"
        echo "No virtual desktop is configured for this profile."
        ;;
    env)
        printf "export WORKSPACE_DISPLAY_BACKEND='none'\n"
        ;;
    stop)
        echo "No virtual desktop is configured."
        ;;
    start|restart|health|gpu|logs|run)
        echo "No virtual desktop is configured for this profile." >&2
        exit 1
        ;;
    -h|--help|help)
        echo "This profile uses display backend 'none'."
        ;;
    *)
        echo "Unknown workspace-desktop command: $command_name" >&2
        exit 2
        ;;
esac

