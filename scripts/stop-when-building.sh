#!/usr/bin/env bash
# Stop a `nix build` client once it starts building a given derivation, e.g. a
# wasm GHC derivation that is already known to fail. Whatever it built before
# that point (shared dependencies) stays in the store.
#
#   scripts/stop-when-building.sh <pid> <log-file> <drv-hash-prefix>
set -euo pipefail

pid=$1
log=$2
drv=$3

until grep -q "building '/nix/store/$drv" "$log" 2>/dev/null; do
  if ! kill -0 "$pid" 2>/dev/null; then
    echo "pid $pid exited before building $drv"
    exit 0
  fi
  sleep 15
done

echo "pid $pid ($log) started building doomed $drv, stopping it"
kill -INT "$pid" 2>/dev/null || true
for _ in $(seq 1 12); do
  kill -0 "$pid" 2>/dev/null || { echo "stopped"; exit 0; }
  sleep 5
done
kill -TERM "$pid" 2>/dev/null || true
sleep 10
kill -0 "$pid" 2>/dev/null && kill -KILL "$pid" 2>/dev/null || true
echo "stopped (forced)"
