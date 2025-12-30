<!--markdownlint-disable md013-->

# yurisync

> see live version at [yuri.hearth.is-a.dev](https://hearth.is-a.dev/api/v1/yuri)

server for metadata (and images) for yuri sourced from [yuri.4k.pics](https://yuri.4k.pics/)

## usage

this is a sync tool only, see [serber](https://github.com/dragsbruh/serber) for a complete server.
this produces compatible data for serber to serbe from.

```sh
JSON_DIR=./yuri/metadata
IMAGES_DIR=./yuri/images
TMP_DIR=./yuri/.tmp
SYNC_INTERVAL=3h
DOWNLOAD_CONCURRENCY=5
```

with these env vars call `run.sh` (or manually call `sync.sh` whenever you want to update)

## license

under [BSD-2-Clause](./LICENSE)
