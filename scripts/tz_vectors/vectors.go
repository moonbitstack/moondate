// Copyright 2026 Leo Cheng
// SPDX-License-Identifier: Apache-2.0
//
// What Go's time package reads at each instant instants.py asked about:
//
//	go run scripts/tz_vectors/vectors.go /path/to/tzif instants.txt
//
// The TZif tree is built by the release's own zic and ZONEINFO points Go at it,
// so Go and Python are reading the same bytes. Go reports no daylight flag, so the
// last column is always zero and the comparison leaves it out.

package main

import (
	"bufio"
	"fmt"
	"os"
	"sort"
	"time"
)

func main() {
	root, list := os.Args[1], os.Args[2]
	if err := os.Setenv("ZONEINFO", root); err != nil {
		panic(err)
	}
	wanted := map[string][]int64{}
	handle, err := os.Open(list)
	if err != nil {
		panic(err)
	}
	scan := bufio.NewScanner(handle)
	for scan.Scan() {
		fields := fields(scan.Text())
		if len(fields) != 2 {
			continue
		}
		wanted[fields[0]] = append(wanted[fields[0]], number(fields[1]))
	}
	names := make([]string, 0, len(wanted))
	for name := range wanted {
		names = append(names, name)
	}
	sort.Strings(names)
	for _, name := range names {
		loc, err := time.LoadLocation(name)
		if err != nil {
			fmt.Fprintf(os.Stderr, "%s: %v\n", name, err)
			continue
		}
		instants := wanted[name]
		sort.Slice(instants, func(i, j int) bool { return instants[i] < instants[j] })
		for _, when := range instants {
			report(name, when, loc)
		}
	}
}

func report(name string, when int64, loc *time.Location) {
	abbrev, offset := time.Unix(when, 0).In(loc).Zone()
	fmt.Printf("%s %d %d %s 0\n", name, when, offset, abbrev)
}

func fields(line string) []string {
	var out []string
	start := -1
	for i := 0; i <= len(line); i++ {
		if i == len(line) || line[i] == ' ' || line[i] == '\t' {
			if start >= 0 {
				out = append(out, line[start:i])
				start = -1
			}
		} else if start < 0 {
			start = i
		}
	}
	return out
}

func number(text string) int64 {
	var out int64
	negative := false
	for i := 0; i < len(text); i++ {
		if text[i] == '-' && i == 0 {
			negative = true
			continue
		}
		out = out*10 + int64(text[i]-'0')
	}
	if negative {
		return -out
	}
	return out
}
