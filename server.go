package main

import (
	"context"
	"encoding/json"
	"errors"
	"fmt"
	"io"
	"io/fs"
	"log"
	"math/rand"
	"net/http"
	"os"
	"os/signal"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"syscall"
	"time"
)

func main() {
	ctx, cancel := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer cancel()

	addr, ok := os.LookupEnv("ADDR")
	if !ok {
		log.Fatal("ADDR not set")
	}

	jsonDir, ok := os.LookupEnv("JSON_DIR")
	if !ok {
		log.Fatal("JSON_DIR not set")
	}

	cacheIntervalStr, ok := os.LookupEnv("CACHE_INTERVAL")
	if !ok {
		cacheIntervalStr = "6h"
	}

	imagesDir, ok := os.LookupEnv("IMAGES_DIR")
	var imageFs fs.FS = nil
	if ok {
		imageFs = os.DirFS(imagesDir)
	}

	cacheInterval, err := time.ParseDuration(cacheIntervalStr)
	if err != nil {
		log.Fatalf("error parsing CACHE_INTERVAL: %v", err)
	}

	yc := YuCache{
		Mu:     sync.RWMutex{},
		Cache:  map[string]Yuri{},
		JsonFS: os.DirFS(jsonDir),
	}

	routes := Routes{
		YC:      &yc,
		ImageFS: imageFs,
	}

	log.Print("seeding yuri")
	if err := yc.Update(); err != nil {
		log.Fatalf("error seeding yuri: %v", err)
	}

	server := http.Server{
		Addr:    addr,
		Handler: routes.Router(),
	}

	wg := sync.WaitGroup{}

	wg.Go(func() {
		log.Printf("listening on %s", addr)
		if err := server.ListenAndServe(); err != nil && !errors.Is(err, http.ErrServerClosed) {
			log.Fatalf("error listening: %v", err)
		}
	})

	wg.Go(func() {
		ticker := time.NewTicker(cacheInterval)
		defer ticker.Stop()

		for {
			select {
			case <-ctx.Done():
				return
			case <-ticker.C:
				if err := yc.Update(); err != nil {
					log.Printf("error updating yuri cache: %v", err)
				}
			}
		}
	})

	<-ctx.Done()

	sctx, scancel := context.WithTimeout(context.Background(), time.Second*15)
	defer scancel()

	log.Print("shutting down server")
	if err := server.Shutdown(sctx); err != nil {
		log.Fatalf("shutdown error: %v", err)
	}

	go func() {
		wg.Wait()
		scancel()
	}()

	<-sctx.Done()
}

type Yuri struct {
	CID    string `json:"cid"`
	URL    string `json:"url"`
	Source string `json:"source"`

	Images []struct {
		Source string `json:"src"`
		Thumb  string `json:"thumb"`
		Size   struct {
			Width  int `json:"width"`
			Height int `json:"height"`
		} `json:"size"`
	} `json:"images"`
}

type YuCache struct {
	Mu     sync.RWMutex
	JsonFS fs.FS
	Cache  map[string]Yuri
	Arr    []Yuri
}

func (yc *YuCache) Select(n int) []Yuri {
	if n <= 0 {
		return nil
	}

	yc.Mu.RLock()
	arr := make([]Yuri, len(yc.Arr))
	copy(arr, yc.Arr)
	yc.Mu.RUnlock()

	if n >= len(arr) {
		return arr
	}

	rand.Shuffle(len(arr), func(i, j int) {
		arr[i], arr[j] = arr[j], arr[i]
	})

	if n >= len(arr) {
		return arr
	}

	return arr[:n]
}

func (yc *YuCache) Update() error {
	yc.Mu.Lock()
	defer yc.Mu.Unlock()

	entries, err := fs.ReadDir(yc.JsonFS, ".")
	if err != nil {
		return fmt.Errorf("read dir: %w", err)
	}

	for _, ent := range entries {
		if ent.IsDir() {
			continue
		}

		fname := ent.Name()
		if !strings.HasSuffix(fname, ".json") {
			continue
		}

		f, err := yc.JsonFS.Open(fname)
		if err != nil {
			log.Printf("error opening file: %v", err)
			continue
		}

		var yuri Yuri
		if err := json.NewDecoder(f).Decode(&yuri); err != nil {
			log.Printf("json decode error in yuri: %v", err)
			f.Close()
			continue
		}
		f.Close()

		yc.Cache[fname] = yuri
	}

	yc.Arr = []Yuri{}
	for _, yuri := range yc.Cache {
		yc.Arr = append(yc.Arr, yuri)
	}

	return nil
}

func (c *Routes) Router() http.Handler {
	api := http.NewServeMux()

	api.HandleFunc("/yuri", c.Yuri)

	api.HandleFunc("/yuri/{cid}/{index}", func(w http.ResponseWriter, r *http.Request) {
		cid := r.PathValue("cid")
		indexStr := r.PathValue("index")

		index, err := strconv.ParseInt(indexStr, 10, 64)
		if err != nil {
			writeErr(w, http.StatusBadRequest, "invalid number for index")
			return
		}

		c.YuriImage(w, cid, index)
	})

	api.HandleFunc("/yuri/{cid}", func(w http.ResponseWriter, r *http.Request) {
		c.YuriImage(w, r.PathValue("cid"), 0)
	})

	r := http.NewServeMux()

	r.Handle("/v1/", http.StripPrefix("/v1", api))

	r.HandleFunc("/", func(w http.ResponseWriter, r *http.Request) {
		http.Redirect(w, r, "https://github.com/dragsbruh/yuriapi", http.StatusFound)
	})

	return r
}

func writeErr(w http.ResponseWriter, status int, msg string) error {
	w.Header().Set("Content-Type", "application/json")
	w.WriteHeader(status)
	return json.NewEncoder(w).Encode(map[string]string{
		"error": msg,
	})
}

type Routes struct {
	YC      *YuCache
	ImageFS fs.FS
}

func (c *Routes) Yuri(w http.ResponseWriter, r *http.Request) {
	countStr := r.URL.Query().Get("n")
	if countStr == "" {
		countStr = "10"
	}

	count, err := strconv.ParseInt(countStr, 10, 64)
	if err != nil {
		writeErr(w, http.StatusBadRequest, "invalid numeric value for `n`")
		return
	}

	if count < 1 || count > 50 {
		writeErr(w, http.StatusBadRequest, "count must be in range (0, 50]")
		return
	}

	w.Header().Set("Content-Type", "application/json")
	json.NewEncoder(w).Encode(c.YC.Select(int(count)))
}

func (c *Routes) YuriImage(w http.ResponseWriter, cid string, index int64) {
	f, err := c.ImageFS.Open(filepath.Join(cid, fmt.Sprintf("%d.jpeg", index)))
	if err != nil {
		if os.IsNotExist(err) {
			writeErr(w, http.StatusNotFound, "no such yuri")
		} else {
			log.Printf("error opening image %s/%d: %v", cid, index, err)
			writeErr(w, http.StatusInternalServerError, "couldnt read image")
		}
		return
	}
	defer f.Close()

	w.Header().Set("Content-Type", "image/jpeg")
	io.Copy(w, f)
}
