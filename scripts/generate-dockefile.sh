#!/bin/bash
# Generate Dockerfile from preinstall.json and template

PREINSTALL_JSON="${1:-preinstall/preinstall.json}"
DOCKERFILE_TEMPLATE="${2:-config/Dockerfile.template}"
OUTPUT_DOCKERFILE="${3:-Dockerfile}"

# Check if template exists
if [ ! -f "$DOCKERFILE_TEMPLATE" ]; then
    echo "Error: Template file $DOCKERFILE_TEMPLATE not found" >&2
    exit 1
fi

# Start with the template
cp "$DOCKERFILE_TEMPLATE" "$OUTPUT_DOCKERFILE"

# Process dockerfile field (commands array)
if jq -e '.dockerfile | length > 0' "$PREINSTALL_JSON" >/dev/null 2>&1; then
    COMMANDS=$(jq -r '.dockerfile[].commands[]?' "$PREINSTALL_JSON" 2>/dev/null)
    if [ -n "$COMMANDS" ]; then
        # Replace placeholder with dockerfile commands
        sed -i "s/# DOCKERFILE_COMMANDS_PLACEHOLDER/$COMMANDS/" "$OUTPUT_DOCKERFILE"
    else
        # Remove placeholder if no commands
        sed -i '/# DOCKERFILE_COMMANDS_PLACEHOLDER/d' "$OUTPUT_DOCKERFILE"
    fi
else
    # Remove placeholder if no dockerfile section
    sed -i '/# DOCKERFILE_COMMANDS_PLACEHOLDER/d' "$OUTPUT_DOCKERFILE"
fi

# Process environment and opencode entries - append after dockerfile commands
jq -r '[.environment[], .opencode[]][] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null | while IFS='|' read -r url install; do
    if [ -n "$install" ]; then
        echo "RUN $install" | sed "s|\$URL|$url|g" >> "$OUTPUT_DOCKERFILE"
    fi
done
