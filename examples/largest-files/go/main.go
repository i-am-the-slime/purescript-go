// The same program in plain Go, for comparison: one goroutine per directory,
// at most 64 directories open at once, a 2 second deadline.
package main

import (
	"context"
	"errors"
	"fmt"
	"os"
	"path/filepath"
	"sort"
	"sync"
	"time"
)

type sizedFile struct {
	path string
	size int64
}

func main() {
	root := "."
	if len(os.Args) > 1 {
		root = os.Args[1]
	}
	ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
	defer cancel()

	found := make(chan sizedFile, 256)
	openDirectories := make(chan struct{}, 64)
	var wg sync.WaitGroup

	var walk func(dir string)
	walk = func(dir string) {
		defer wg.Done()
		if ctx.Err() != nil {
			return
		}
		openDirectories <- struct{}{}
		entries, _ := os.ReadDir(dir)
		<-openDirectories
		for _, entry := range entries {
			path := filepath.Join(dir, entry.Name())
			if entry.IsDir() {
				wg.Add(1)
				go walk(path)
				continue
			}
			info, err := os.Lstat(path)
			if err != nil || !info.Mode().IsRegular() {
				continue
			}
			select {
			case found <- sizedFile{path, info.Size()}:
			case <-ctx.Done():
				return
			}
		}
	}

	wg.Add(1)
	go walk(root)
	go func() {
		wg.Wait()
		close(found)
	}()

	filesSeen := 0
	var largest []sizedFile
collect:
	for {
		select {
		case file, ok := <-found:
			if !ok {
				break collect
			}
			filesSeen++
			largest = append(largest, file)
			sort.Slice(largest, func(i, j int) bool { return largest[i].size > largest[j].size })
			if len(largest) > 10 {
				largest = largest[:10]
			}
		case <-ctx.Done():
			break collect
		}
	}

	fmt.Printf("The largest of %d files under %s:\n", filesSeen, root)
	for _, file := range largest {
		fmt.Printf("%s  %s\n", readable(file.size), file.path)
	}
	if errors.Is(ctx.Err(), context.DeadlineExceeded) {
		fmt.Println("Stopped at the 2 second deadline, so that's the largest so far.")
	} else {
		fmt.Println("That's the whole tree.")
	}
}

func readable(bytes int64) string {
	if bytes >= 1e9 {
		return fmt.Sprintf("%7.1f GB", float64(bytes)/1e9)
	}
	return fmt.Sprintf("%7.1f MB", float64(bytes)/1e6)
}
