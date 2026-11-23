#!/usr/bin/env bash
# Compiles the specs of every package to Go with Iris and runs them.
#
#   ./test.sh
#
# Environment: IRIS (the iris binary), IRIS_GO (a local iris-go checkout to build against).
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
IRIS="${IRIS:-iris}"
OUT="$HERE/out"
mkdir -p "$OUT"
{
  echo "module example.com/go-specs"
  echo
  echo "go 1.27.0"
  echo
  echo "require github.com/i-am-the-slime/iris-go v0.2.0"
  if [ -n "${IRIS_GO:-}" ]; then
    echo
    echo "replace github.com/i-am-the-slime/iris-go => $IRIS_GO"
  fi
} >"$OUT/go.mod"
(cd "$HERE" && "$IRIS" go --package go-specs --entry Test.Main.main "$OUT")
(cd "$OUT" && go build -o spec-runner .)
"$OUT/spec-runner"
