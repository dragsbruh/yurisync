#!/bin/bash

set -euo pipefail

cursor_id=
while true; do
  body=$(curl -fsSL "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=$ATPROTO_DID&cursor=$cursor_id")

  mapfile -t items < <(jq -c '.feed[]
    | .post | select(.embed.images | type != "null")
    | {
          images: [ .embed.images[] | {
            src: .fullsize,
            thumb: .thumb,
            size: .aspectRatio,
          } ],
          cid: .cid,
          url: .uri,
          source: .record.text | match("yuri.4k.pics/([a-zA-Z0-9]{5}|[a-zA-Z0-9]{4})") | .string | trim | "https://\(.)",
      }' <<< "$body")

  for item in "${items[@]}"; do
    name=$(jq -r '"\(.cid).json"' <<< "$item")
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
  echo "sync: checking posts..."

  for json_path in "$JSON_DIR"/*.json; do
    while IFS="=" read -r cid index src; do
      name="$cid/$index.jpeg"
      tmp_path="$TMP_DIR/$name"
      final_path="$IMAGES_DIR/$name"

      mkdir -p "$(dirname "$tmp_path")" "$(dirname "$final_path")"

      if [ ! -f "$final_path" ]; then
        while [ "$(jobs -rp | wc -l)" -ge "$DOWNLOAD_CONCURRENCY" ]; do
            sleep 0.1
        done

        {
          echo "download: downloading $src"
          curl -fsSL "$src" -o "$tmp_path" && mv "$tmp_path" "$final_path"
        } &
      fi

    done < <(jq -c -r '. as $post | .images | to_entries[] | "\($post.cid)=\(.key)=\(.value.src)"' "$json_path")
  done

  wait
fi

echo "sync: complete"
