#!/bin/bash

set -euo pipefail

ATPROTO_DID=${ATPROTO_DID:-"did:plc:t3oqokywdpvn3kygygayxchk"}
DOWNLOAD_CONCURRENCY=${DOWNLOAD_CONCURRENCY:-5}
IMAGES_DIR=${IMAGES_DIR:-""}

mkdir -p "$JSON_DIR" "$TMP_DIR"

cursor_id=
while true; do
  body=$(curl -fsSL "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=$ATPROTO_DID&cursor=$cursor_id")

  mapfile -t items < <(jq -c '.feed[]
    | .post | select(type != "null")
    | . as $post
    | .embed | select(type != "null")
    | .images | select(type != "null") | to_entries[]
    | .key as $index | .value
    | {
        sky: {
          cid: $post.cid,
          index: $index,
          uri: $post.uri,
          createdAt: $post.record.createdAt,
          alt: .alt
        },
        src: .fullsize,
        size: .aspectRatio,
        thumb: .thumb,
        source: $post.record.text | match("yuri.4k.pics/([a-zA-Z0-9]{5}|[a-zA-Z0-9]{4})") | .string | trim | "https://\(.)",
      }' <<< "$body")

  for item in "${items[@]}"; do
    name=$(jq -r '"\(.sky.cid).\(.sky.index).json"' <<< "$item")
    tmp_path="$TMP_DIR/$name"
    final_path="$JSON_DIR/$name"

    if [ -f "$final_path" ]; then
      break 2
    fi

    echo "$item" > "$tmp_path"
  done

  cursor_id=$(jq -r '.cursor' <<< "$body")
  if [ "$cursor_id" = null ]; then
    break
  fi
  echo "sync: at cursor $cursor_id"

  sleep 0.5
done

mv "$TMP_DIR"/*.json "$JSON_DIR/" 2>/dev/null || true

if [ -n "$IMAGES_DIR" ]; then
  mkdir -p "$IMAGES_DIR"

  echo "sync: checking posts..."

  for json_path in "$JSON_DIR"/*.json; do
    img_src=$(jq -r '.src' "$json_path")
    name="$(basename "${json_path%.json}.jpeg")"
    tmp_path="$TMP_DIR/$name"
    final_path="$IMAGES_DIR/$name"

    if [ ! -f "$final_path" ]; then
      while [ "$(jobs -rp | wc -l)" -ge "$DOWNLOAD_CONCURRENCY" ]; do
          sleep 0.1
      done

      {
        echo "download: downloading $img_src"
        curl -fsSL "$img_src" -o "$tmp_path" && mv "$tmp_path" "$final_path"
      } &
    fi
  done

  wait
fi

echo "sync: complete"
