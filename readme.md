<!--markdownlint-disable md013-->

# yuriapi

> see live version at [yuri.hearth.is-a.dev](https://yuri.hearth.is-a.dev/v1/yuri)

server for metadata (and images) for yuri sourced from [yuri.4k.pics](https://yuri.4k.pics/)

## usage

### api

1. `GET /v1/yuri?n={N}`

   **where:**
   - `N` is number of random posts to fetch, `0` < `N` < `50`

   **returns:** array of `post` object

   ```jsonc
   [
     {
       "cid": "string", // bsky cid of post
       "url": "string", // bsky atproto uri of post
       "source": "string", // source image extracted from `yuri.4k.pics`
       "images": [
         {
           "src": "string", // full resolution image url
           "thumb": "string", // image thumbnail url
           "size": {
             "width": "number", // image width
             "height": "number", // image height
           },
         },
       ],
     },
   ]
   ```

2. `GET /v1/yuri/{CID}`

   **where:**
   - `CID` is the bluesky cid (`post.cid` returned from `/v1/yuri?n={N}`)

   **returns:** a jpeg full resolution image

   if post contains multiple images, this returns the first image only.

3. `GET /v1/yuri/{CID}/{index}`

   **where:**
   - `CID` is the bluesky cid (`post.cid` returned from `/v1/yuri?n={N}`)
   - `index` is index of image in `post.images` of post matching `CID`

   **returns:** a jpeg full resolution image

any endpoint on error status code returns `error` object

```jsonc
{
  "error": "string",
}
```

note that endpoints `/yuri/{CID}/....` wont work

### docker

image is at `ghcr.io/dragsbruh/yuriapi:latest`

docker compose is recommended, adapt for docker

```yaml
services:
  yuriapi:
    image: ghcr.io/dragsbruh/yuriapi:latest
    restart: unless-stopped

    volumes:
      - ./yuri:/data
      # - ./yuri/.tmp:/tmp/yuri # this is where temporary download files will be stored.

    environment:
      # essential config
      - ADDR=:80
      - JSON_DIR=/data/metadata
      - IMAGES_DIR=/data/images # if not set, images will neither be downloaded nor served.


      # # non essential config
      # - TMP_DIR=/tmp/yuri
      # - DOWNLOAD_CONCURRENCY=5 # for images
      # - SYNC_INTERVAL=6h       # check for new posts at this interval
      # - CACHE_INTERVAL=30m     # server updates cache at this interval. low is recommended.

      # # do not change unless you know what youre doing
      # - ATPROTO_DID=did:plc:t3oqokywdpvn3kygygayxchk # overrides default `yuri.4k.pics` bluesky did
      # - SYNC_SCRIPT=/app/sync.sh                     # executable to run at `SYNC_INTERVAL`
      # - SERVER_BIN=/app/server                       # executable to run to serve the files
```

## todo

- [ ] configure `N` in [api](#api)
- [ ] serve thumbnails for images
- [ ] resolve source url

## license

under [BSD-2-Clause](./LICENSE)
