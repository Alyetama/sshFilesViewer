#!/usr/bin/env bash
#
# Build (release) and (re)launch SSHFilesViewer.
#
set -euo pipefail
cd "$(dirname "$0")"

./build.sh release

echo "▸ Relaunching…"
killall SSHFilesViewer >/dev/null 2>&1 || true
open ./SSHFilesViewer.app

echo "✓ SSHFilesViewer is running."
