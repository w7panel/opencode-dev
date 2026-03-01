#!/bin/bash
set -e

cp -r /opt/preinstall/* /home/
mkdir -p /home/go
exec opencode web --port 4096 --hostname 0.0.0.0
