#!/bin/bash
set -e

PRELOAD="/opt/preinstall"
TARGET="/home"

if [ -d "$PRELOAD" ]; then
    for item in $PRELOAD/*; do
        if [ -e "$item" ]; then
            basename=$(basename "$item")
            if [ ! -e "$TARGET/$basename" ]; then
                cp -r "$item" "$TARGET/"
            fi
        fi
    done
fi

mkdir -p /home/go

exec opencode web --port 4096 --hostname 0.0.0.0
