#!/bin/bash
set -e

OC_DIR="$HOME/.config/opencode"
OC_PREINSTALL_DIR="/opt/preinstall/.config/opencode"
PREINSTALL_OPENCODE="/opt/preinstall/preinstall-opencode.json"

mkdir -p "$OC_DIR"
cp -rn "$OC_PREINSTALL_DIR"/* "$OC_DIR/" 2>/dev/null || true

if [ -f "$PREINSTALL_OPENCODE" ]; then
    if [ -f "$OC_DIR/opencode.json" ]; then
        tmp=$(mktemp)
        for key in $(jq -r 'keys[]' "$PREINSTALL_OPENCODE" 2>/dev/null); do
            base_type=$(jq -r ".$key | type" "$OC_DIR/opencode.json" 2>/dev/null)
            patch_type=$(jq -r ".$key | type" "$PREINSTALL_OPENCODE" 2>/dev/null)
            
            if [ "$base_type" = "array" ] && [ "$patch_type" = "array" ]; then
                jq --argjson a "$(jq ".$key" "$OC_DIR/opencode.json")" --argjson b "$(jq ".$key" "$PREINSTALL_OPENCODE")" \
                    '($a + $b | unique_by(tostring))' > "$tmp" && mv "$tmp" "$OC_DIR/opencode.json"
            elif [ "$base_type" = "null" ]; then
                jq --argjson v "$(jq ".$key" "$PREINSTALL_OPENCODE")" '. * { "'"$key"'": $v }' "$OC_DIR/opencode.json" > "$tmp" && mv "$tmp" "$OC_DIR/opencode.json"
            fi
        done
        rm -f "$tmp"
    else
        cp "$PREINSTALL_OPENCODE" "$OC_DIR/opencode.json"
    fi
fi

mkdir -p "$HOME/go"
exec opencode web --port 4096 --hostname 0.0.0.0
