#!/bin/bash
set -e

OC_DIR="$HOME/.config/opencode"
OC_PREINSTALL_DIR="/opt/preinstall/.config/opencode"
PREINSTALL_OPENCODE="/opt/preinstall/preinstall-opencode.json"

mkdir -p "$OC_DIR"

if [ -d "$OC_PREINSTALL_DIR" ]; then
    for entry in "$OC_PREINSTALL_DIR"/*; do
        [ -e "$entry" ] || continue
        target="$OC_DIR/$(basename "$entry")"
        [ -e "$target" ] && continue
        cp -r "$entry" "$OC_DIR/" 2>/dev/null || true
    done
fi

if [ -f "$PREINSTALL_OPENCODE" ]; then
    if [ -f "$OC_DIR/opencode.json" ]; then
        tmp=$(mktemp)
        jq -s '
            def merge($base; $patch):
                if ($base | type) == "object" and ($patch | type) == "object" then
                    reduce ($patch | keys_unsorted[]) as $key ($base;
                        if has($key) then
                            .[$key] = merge(.[$key]; $patch[$key])
                        else
                            . + {($key): $patch[$key]}
                        end
                    )
                elif ($base | type) == "array" and ($patch | type) == "array" then
                    reduce ($patch[]) as $item ($base;
                        if index($item) == null then . + [$item] else . end
                    )
                else
                    $base
                end;
            merge(.[0]; .[1])
        ' "$OC_DIR/opencode.json" "$PREINSTALL_OPENCODE" > "$tmp"
        mv "$tmp" "$OC_DIR/opencode.json"
    else
        cp "$PREINSTALL_OPENCODE" "$OC_DIR/opencode.json"
    fi
fi

mkdir -p "$HOME/go"
exec opencode web --port 4096 --hostname 0.0.0.0
