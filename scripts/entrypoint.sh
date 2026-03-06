#!/bin/bash
set -e

# 复制预装内容到 /home
cp -a /opt/preinstall/. /home/ 2>/dev/null || true

mkdir -p /home/go
exec opencode web --port 4096 --hostname 0.0.0.0
