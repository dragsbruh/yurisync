#!/bin/bash

set -euo pipefail

: "${IMAGES_DIR:?IMAGES_DIR not set}"
: "${JSON_DIR:?JSON_DIR not set}"
: "${ADDR:?ADDR not set}"

export TMP_DIR=${TMP_DIR:-/tmp/yuri}

export SYNC_SCRIPT=${SYNC_SCRIPT:-./sync.sh}
export SERVER_BIN=${SERVER_BIN:-./server}
export ATPROTO_DID=${ATPROTO_DID:-did:plc:t3oqokywdpvn3kygygayxchk}

export SYNC_INTERVAL=${SYNC_INTERVAL:-6h}
export CACHE_INTERVAL=${CACHE_INTERVAL:-30m}
export DOWNLOAD_CONCURRENCY=${DOWNLOAD_CONCURRENCY:-5}

if [ ! -x "$SYNC_SCRIPT" ]; then
  echo "error: SYNC_SCRIPT does not exist or is not executable"
  exit 1
fi

if [ ! -x "$SERVER_BIN" ]; then
  echo "error: SERVER_BIN does not exist or is not executable"
  exit 1
fi

mkdir -p "$IMAGES_DIR" "$TMP_DIR" "$JSON_DIR"

echo "info: triggering initial sync"
"$SYNC_SCRIPT"

trap 'kill $(jobs -p) 2>/dev/null || true' EXIT

while true; do
  sleep "$SYNC_INTERVAL"
  echo "info: triggering sync"
  "$SYNC_SCRIPT"
done &

"$SERVER_BIN" &
echo "server: started with pid $!"

wait "$!"
