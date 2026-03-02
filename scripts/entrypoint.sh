#!/bin/bash
set -e

cp -a /opt/preinstall/. /home/ 2>/dev/null || true
mkdir -p /home/go
exec opencode web --port 4096 --hostname 0.0.0.0
