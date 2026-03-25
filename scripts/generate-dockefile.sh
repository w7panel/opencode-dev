#!/bin/bash

PREINSTALL_JSON="${1:-preinstall/preinstall.json}"
DOCKERFILE_TEMPLATE="${2:-config/Dockerfile.template}"
OUTPUT_DOCKERFILE="${3:-Dockerfile}"
COMMANDS_FILE="/tmp/commands_$$"

if [ ! -f "$DOCKERFILE_TEMPLATE" ]; then
    echo "Error: Template file $DOCKERFILE_TEMPLATE not found" >&2
    exit 1
fi

> "$COMMANDS_FILE"

if jq -e '.dockerfile | length > 0' "$PREINSTALL_JSON" >/dev/null 2>&1; then
    jq -r '.dockerfile[].commands[]?' "$PREINSTALL_JSON" 2>/dev/null >> "$COMMANDS_FILE"
fi

ENV_COMMANDS=$(jq -r '.environment[]? // [] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null)
while IFS='|' read -r url install; do
    [ -n "$install" ] && echo "RUN $(echo "$install" | sed "s|\$URL|$url|g")" >> "$COMMANDS_FILE"
done <<< "$ENV_COMMANDS"

OC_COMMANDS=$(jq -r '.opencode[]? // [] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null)
while IFS='|' read -r url install; do
    [ -n "$install" ] && echo "RUN $(echo "$install" | sed "s|\$URL|$url|g")" >> "$COMMANDS_FILE"
done <<< "$OC_COMMANDS"

if [ -s "$COMMANDS_FILE" ]; then
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = "# DOCKERFILE_COMMANDS_PLACEHOLDER" ]; then
            cat "$COMMANDS_FILE"
        else
            echo "$line"
        fi
    done < "$DOCKERFILE_TEMPLATE" > "$OUTPUT_DOCKERFILE"
else
    sed '/# DOCKERFILE_COMMANDS_PLACEHOLDER/d' "$DOCKERFILE_TEMPLATE" > "$OUTPUT_DOCKERFILE"
fi

rm -f "$COMMANDS_FILE"
