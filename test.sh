#!/usr/bin/env bash
# Compiles the specs of every package to Go with Iris and runs them.
#
#   ./test.sh
#
# Environment: IRIS (the iris binary), IRIS_GO (a local iris-go checkout to build against).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IRIS="${IRIS:-iris}"

go_module() {
  echo "module example.com/$1"
  echo
  echo "go 1.27.0"
  echo
  echo "require github.com/i-am-the-slime/iris-go v0.3.0"
  if [ -n "${IRIS_GO:-}" ]; then
    echo
    echo "replace github.com/i-am-the-slime/iris-go => $IRIS_GO"
  fi
}

OUT="$HERE/out"
mkdir -p "$OUT"
go_module go-specs >"$OUT/go.mod"
(cd "$HERE" && "$IRIS" go --package go-specs --entry Test.Main.main "$OUT")
(cd "$OUT" && go mod tidy && go build -o spec-runner .)
"$OUT/spec-runner"

PARALLEL="$HERE/out-parallel"
mkdir -p "$PARALLEL"
go_module go-parallel >"$PARALLEL/go.mod"
(cd "$HERE" && "$IRIS" go --package go-specs --entry Test.Parallel.Main.main "$PARALLEL")
(cd "$PARALLEL" && go mod tidy && go build -race -o parallel .)
"$PARALLEL/parallel"
