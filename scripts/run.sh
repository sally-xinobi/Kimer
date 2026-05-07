#!/usr/bin/env bash
set -euo pipefail

cd "$(dirname "$0")/.."

./scripts/build.sh

APP=".build/Kimer.app"
BIN="${APP}/Contents/MacOS/Kimer"
LOG_DIR="${HOME}/Library/Logs/Kimer"
LOG="${LOG_DIR}/kimer.log"

mkdir -p "${LOG_DIR}"

# kill any previous instance so position/permission reload cleanly
pkill -x Kimer 2>/dev/null || true
sleep 0.3

# Launching the binary directly from the shell (rather than `open`) makes
# Kimer inherit the shell's Input Monitoring grant. With ad-hoc signing
# every rebuild produces a fresh code hash, so a permission granted to a
# previous build does not transfer — using the shell's inherited grant
# sidesteps the re-prompt loop during development.
echo "==> launching ${BIN}"
echo "    log: ${LOG}"
nohup "${BIN}" > "${LOG}" 2>&1 &
disown

sleep 0.6
if pgrep -x Kimer > /dev/null; then
    echo "==> Kimer started (pid $(pgrep -x Kimer))"
else
    echo "ERROR: Kimer did not start. Tail of log:" >&2
    tail -n 20 "${LOG}" >&2 || true
    exit 1
fi
