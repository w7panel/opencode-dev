#!/bin/bash
set -e

OC_CONFIG_PREINSTALL="/opt/preinstall/.config/opencode/opencode.json"
OC_CONFIG_USER="$HOME/.config/opencode/opencode.json"
OC_DIR="$HOME/.config/opencode"

merge_opencode_config() {
    [ ! -f "$OC_CONFIG_PREINSTALL" ] && return

    mkdir -p "$OC_DIR"

    if [ ! -f "$OC_CONFIG_USER" ]; then
        cp "$OC_CONFIG_PREINSTALL" "$OC_CONFIG_USER"
    else
        for plugin in $(jq -r '.plugin[]?' "$OC_CONFIG_PREINSTALL" 2>/dev/null); do
            if jq -e --arg p "$plugin" '.plugin | index($p) == null' "$OC_CONFIG_USER" >/dev/null 2>&1; then
                TEMP=$(mktemp)
                jq --arg p "$plugin" '.plugin += [$p]' "$OC_CONFIG_USER" > "$TEMP" && mv "$TEMP" "$OC_CONFIG_USER"
            fi
        done
    fi
}

merge_opencode_config
mkdir -p "$HOME/go"
exec opencode web --port 4096 --hostname 0.0.0.0
