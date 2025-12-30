#!/bin/bash

set -euo pipefail

: "${JSON_DIR:?JSON_DIR not set}"

IMAGES_DIR=${IMAGES_DIR:-}
TMP_DIR=${TMP_DIR:-/tmp/yuri}
DOWNLOAD_CONCURRENCY=${DOWNLOAD_CONCURRENCY:-5}

ATPROTO_DID=${ATPROTO_DID:-did:plc:t3oqokywdpvn3kygygayxchk}

mkdir -p "$TMP_DIR" "$JSON_DIR"

if [ -n "$IMAGES_DIR" ]; then
  mkdir -p "$IMAGES_DIR"
fi

get_feed() {
  local cursor_id=$1

  curl -fsSL "https://public.api.bsky.app/xrpc/app.bsky.feed.getAuthorFeed?actor=$ATPROTO_DID&cursor=$cursor_id"
}

parse_feed() {
  jq -c '.feed[]
    | .post | select(.embed.images | type != "null")
    | {
        id: .cid,
        source: .record.text | match("yuri.4k.pics/([a-zA-Z0-9]{5}|[a-zA-Z0-9]{4})") | .string | trim | "https://\(.)",
        author: null,
        images: [ .embed.images[]
          | {
              src: .fullsize,
              thumbnail: .thumb,
              size: null,
              resolution: .aspectRatio,
            }
        ],
      }
    '
}

field_get() {
  jq -r --arg name "$2" '.[$name]' <<< "$1"
}

field_set() {
  jq --arg field "$2" --arg value "$3" '.[$field] = $value' <<< "$1"
}

iter_images() {
  jq -c -r '.id as $id | .images | to_entries[] | "\($id)=\(.key)=\(.value.src)"'
}

echo "sync: getting feed..."
cursor_id=
while true; do
  body=$(get_feed "$cursor_id")
  mapfile -t items < <(parse_feed <<< "$body")

  for item in "${items[@]}"; do
    name="$(field_get "$item" id).json"

    tmp_path="$TMP_DIR/$name"
    final_path="$JSON_DIR/$name"

    if [ -f "$final_path" ]; then
      break 2
    fi

    source=$(field_get "$item" source)
    finalUrl=$(curl -s -I "$source" | grep -i '^location:' | awk '{print $2}' | tr -d '\r' || true)

    author=
    if [[ "$finalUrl" == *"x.com"* ]]; then
      author=$(echo "$finalUrl" | awk -F/ '{print $4}')
      source="$finalUrl"
    elif [[ "$finalUrl" == *"bsky.app"* ]]; then
      author=$(echo "$finalUrl" | awk -F/ '{print $5}')
      source="$finalUrl"
    fi

    item=$(field_set "$item" source "$source")
    if [ -n "$author" ]; then
      item=$(field_set "$item" author "$author")
    fi

    echo "$item" > "$tmp_path"
  done

  cursor_id=$(field_get "$body" cursor)
  if [ "$cursor_id" = null ]; then
    break
  fi

  echo "sync: at cursor $cursor_id"
  sleep 0.5
done

mv "$TMP_DIR"/*.json "$JSON_DIR/" 2> /dev/null || true

if [ -n "$IMAGES_DIR" ]; then
  echo "sync: checking posts..."

  for json_path in "$JSON_DIR"/*.json; do
    while IFS="=" read -r id index src; do
      name="$id/$index.jpeg"

      tmp_path="$TMP_DIR/$name"
      final_path="$IMAGES_DIR/$name"

      if [ ! -f "$final_path" ]; then
        mkdir -p "$(dirname "$tmp_path")" "$(dirname "$final_path")"

        while [ "$(jobs -rp | wc -l)" -ge "$DOWNLOAD_CONCURRENCY" ]; do
            sleep 0.1
        done

        {
          echo "download: downloading $src"
          curl -fsSL "$src" > "$tmp_path" && mv "$tmp_path" "$final_path"
        } &
      fi
    done < <(iter_images < "$json_path")
  done

  rmdir "$TMP_DIR"/* 2> /dev/null || true
  wait

  echo "sync: updating sizes..."
  for json_path in "$JSON_DIR"/*.json; do
    while IFS="=" read -r id index src; do
      image_path="$IMAGES_DIR/$id/$index.jpeg"
      tmp_json_path="$TMP_DIR/${id}_size.json"

      size=$(stat -c %s "$image_path")
      jq \
        --argjson size "$size" \
        --argjson index "$index" \
        '.images[$index].size = $size' \
        "$json_path" \
      > "$tmp_json_path" && \
      mv "$tmp_json_path" "$json_path"

    done < <(iter_images < "$json_path")
  done
fi

echo "sync: complete"
