#!/bin/bash
# Generate Dockerfile from preinstall.json

PREINSTALL_JSON="${1:-preinstall/preinstall.json}"
OUTPUT_DOCKERFILE="${2:-Dockerfile}"

# Process environment and opencode entries
jq -r '[.environment[], .opencode[]][] | select(.install != null) | "\(.url)|\(.install)"' "$PREINSTALL_JSON" 2>/dev/null | while IFS='|' read -r url install; do
    if [ -n "$install" ]; then
        echo "RUN $install" | sed "s|\$URL|$url|g" >> "$OUTPUT_DOCKERFILE"
    fi
done
