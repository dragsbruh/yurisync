#!/bin/bash

set -euo pipefail

: "${SYNC_INTERVAL:?SYNC_INTERVAL not set}"

while true; do
  echo "run: triggering sync"
  ./sync.sh
  sleep "$SYNC_INTERVAL"
done
