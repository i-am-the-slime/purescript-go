package ffi

import (
	"cmp"
	"maps"
	"slices"
)

// GoMap is Go's own map. Every read and write is an effect.
type GoMap[K cmp.Ordered, V any] = map[K]V

func NewImpl[K cmp.Ordered, V any](capacity int) map[K]V { return make(map[K]V, capacity) }

func LookupImpl[K cmp.Ordered, V, M any](just func(V) M, nothing M, key K, entries map[K]V) M {
	if value, found := entries[key]; found {
		return just(value)
	}
	return nothing
}

func MemberImpl[K cmp.Ordered, V any](key K, entries map[K]V) bool {
	_, found := entries[key]
	return found
}

func InsertImpl[K cmp.Ordered, V any](key K, value V, entries map[K]V) { entries[key] = value }

func DeleteImpl[K cmp.Ordered, V any](key K, entries map[K]V) { delete(entries, key) }

func SizeImpl[K cmp.Ordered, V any](entries map[K]V) int { return len(entries) }

func EntriesImpl[K cmp.Ordered, V, T any](pair func(K) func(V) T, entries map[K]V) []T {
	sorted := make([]T, 0, len(entries))
	for _, key := range slices.Sorted(maps.Keys(entries)) {
		sorted = append(sorted, pair(key)(entries[key]))
	}
	return sorted
}

func KeysImpl[K cmp.Ordered, V any](entries map[K]V) []K {
	return slices.Sorted(maps.Keys(entries))
}

func ValuesImpl[K cmp.Ordered, V any](entries map[K]V) []V {
	sorted := make([]V, 0, len(entries))
	for _, key := range slices.Sorted(maps.Keys(entries)) {
		sorted = append(sorted, entries[key])
	}
	return sorted
}
