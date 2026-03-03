#!/bin/bash
set -e

# 复制预装内容到 /home（首次启动时）
if [ -z "$(ls -A /home 2>/dev/null)" ]; then
    cp -a /opt/preinstall/. /home/ 2>/dev/null || true
fi

mkdir -p /home/go
exec opencode web --port 4096 --hostname 0.0.0.0
