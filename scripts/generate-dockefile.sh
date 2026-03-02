#!/bin/bash
# Generate Dockerfile from preinstall.json and template
# Replace placeholder "# DOCKERFILE_COMMANDS_PLACEHOLDER" with generated RUN commands

PREINSTALL_JSON="${1:-preinstall/preinstall.json}"
DOCKERFILE_TEMPLATE="${2:-config/Dockerfile.template}"
OUTPUT_DOCKERFILE="${3:-Dockerfile}"
COMMANDS_FILE="/tmp/commands_$$"

# Check if template exists
if [ ! -f "$DOCKERFILE_TEMPLATE" ]; then
    echo "Error: Template file $DOCKERFILE_TEMPLATE not found" >&2
    exit 1
fi

# Generate RUN commands from preinstall.json
> "$COMMANDS_FILE"

# 1. Process dockerfile field - direct commands
if jq -e '.dockerfile | length > 0' "$PREINSTALL_JSON" >/dev/null 2>&1; then
    DF_COMMANDS=$(jq -r '.dockerfile[].commands[]?' "$PREINSTALL_JSON" 2>/dev/null)
    if [ -n "$DF_COMMANDS" ]; then
        echo "$DF_COMMANDS" >> "$COMMANDS_FILE"
    fi
fi

# 2. Process environment field - install commands with $URL replacement
ENV_COMMANDS=$(jq -r '.environment[]? // [] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null)
while IFS='|' read -r url install; do
    if [ -n "$install" ]; then
        RUN_CMD=$(echo "$install" | sed "s|\$URL|$url|g")
        echo "RUN $RUN_CMD" >> "$COMMANDS_FILE"
    fi
done <<< "$ENV_COMMANDS"

# 3. Process opencode field - install commands with $URL replacement
OC_COMMANDS=$(jq -r '.opencode[]? // [] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null)
while IFS='|' read -r url install; do
    if [ -n "$install" ]; then
        RUN_CMD=$(echo "$install" | sed "s|\$URL|$url|g")
        echo "RUN $RUN_CMD" >> "$COMMANDS_FILE"
    fi
done <<< "$OC_COMMANDS"

# Replace placeholder in template with generated commands
if [ -s "$COMMANDS_FILE" ]; then
    # Read template, find placeholder, and insert commands
    while IFS= read -r line || [ -n "$line" ]; do
        if [ "$line" = "# DOCKERFILE_COMMANDS_PLACEHOLDER" ]; then
            cat "$COMMANDS_FILE"
        else
            echo "$line"
        fi
    done < "$DOCKERFILE_TEMPLATE" > "$OUTPUT_DOCKERFILE"
else
    # Remove placeholder if no commands
    sed '/# DOCKERFILE_COMMANDS_PLACEHOLDER/d' "$DOCKERFILE_TEMPLATE" > "$OUTPUT_DOCKERFILE"
fi

rm -f "$COMMANDS_FILE"
