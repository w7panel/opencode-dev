#!/bin/bash
set -e

OC_DIR="$HOME/.config/opencode"
OC_PREINSTALL_DIR="/opt/preinstall/.config/opencode"

copy_config_files() {
    [ ! -d "$OC_PREINSTALL_DIR" ] && return
    mkdir -p "$OC_DIR"

    for file in "$OC_PREINSTALL_DIR"/*.json; do
        [ -f "$file" ] || continue
        filename=$(basename "$file")

        if [ "$filename" = "opencode.json" ]; then
            if [ ! -f "$OC_DIR/$filename" ]; then
                cp "$file" "$OC_DIR/$filename"
            else
                for plugin in $(jq -r '.plugin[]?' "$file" 2>/dev/null); do
                    if jq -e --arg p "$plugin" '.plugin | index($p) == null' "$OC_DIR/$filename" >/dev/null 2>&1; then
                        TEMP=$(mktemp)
                        jq --arg p "$plugin" '.plugin += [$p]' "$OC_DIR/$filename" > "$TEMP" && mv "$TEMP" "$OC_DIR/$filename"
                    fi
                done
            fi
        else
            [ ! -f "$OC_DIR/$filename" ] && cp "$file" "$OC_DIR/$filename"
        fi
    done

    for dir in "$OC_PREINSTALL_DIR"/*/; do
        [ -d "$dir" ] || continue
        dirname=$(basename "$dir")
        [ ! -d "$OC_DIR/$dirname" ] && cp -r "$dir" "$OC_DIR/$dirname"
    done
}

copy_config_files
mkdir -p "$HOME/go"
exec opencode web --port 4096 --hostname 0.0.0.0
