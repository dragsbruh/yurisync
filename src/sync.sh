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
            size: .aspectRatio,
          } ],
          id: .cid,
          author: null,
          url: .uri,
          source: .record.text | match("yuri.4k.pics/([a-zA-Z0-9]{5}|[a-zA-Z0-9]{4})") | .string | trim | "https://\(.)",
      }' <<< "$body")

  for item in "${items[@]}"; do
    name="$(jq -r '.id' <<< "$item").json"

    tmp_path="$TMP_DIR/$name"
    final_path="$JSON_DIR/$name"

    if [ -f "$final_path" ]; then
      break 2
    fi

    sourceUrl=$(jq -r '.source' <<< "$item")
    finalUrl=$(curl -s -I "$sourceUrl" | grep -i '^location:' | awk '{print $2}' | tr -d '\r' || true)

    if [[ "$finalUrl" == *"x.com"* ]]; then
        authorName=$(echo "$finalUrl" | awk -F/ '{print $4}')
        item=$(jq --arg a "$authorName" --arg source "$finalUrl" '.author = $a | .source = $source' <<< "$item")
    elif [[ "$finalUrl" == *"bsky.app"* ]]; then
        authorName=$(echo "$finalUrl" | awk -F/ '{print $5}')
        item=$(jq --arg a "$authorName" --arg source "$finalUrl" '.author = $a | .source = $source' <<< "$item")
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
    while IFS="=" read -r id index src; do
      name="$id/$index.jpeg"
      tmp_path="$TMP_DIR/$name"
      final_path="$IMAGES_DIR/$name"

      mkdir -p "$(dirname "$tmp_path")" "$(dirname "$final_path")"

      if [ ! -f "$final_path" ]; then
        while [ "$(jobs -rp | wc -l)" -ge "$DOWNLOAD_CONCURRENCY" ]; do
            sleep 0.1
        done

        {
          echo "download: downloading $src"
          curl -fsSL "$src" -o "$tmp_path" && mv "$tmp_path" "$final_path" && rmdir "$(dirname "$tmp_path")"
        } &
      fi

    done < <(jq -c -r '. as $post | .images | to_entries[] | "\($post.id)=\(.key)=\(.value.src)"' "$json_path")
  done

  wait
fi

echo "sync: complete"
