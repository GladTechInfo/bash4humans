#!/bin/bash
# tests/p10k/all.sh : every comparison with real p10k, one after the other
# (they share the terminal capture tool; do not edit the tested files while
# this runs). Full output in $B4H_TEST_DIR/all-<suite>.txt; a summary at the end.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; mkdir -p "$T"
# golden.sh writes its logs here; the matrix suites run before segments.sh,
# which used to be the only one to create it (a clean /tmp failed them all)
mkdir -p "$T/golden"
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
suites=(unit-parser unit-battery unit-wifi unit-colors unit-osc133 matrix matrix-git matrix-wizard segments ble display async instant wrap)
for s in "${suites[@]}"; do
  [[ -n ${1-} && $s != *$1* ]] && continue
  echo "== $s"
  ( cd /tmp && "$here/$s.sh" </dev/null ) >"$T/all-$s.txt" 2>&1
  grep -v '^SAME' "$T/all-$s.txt" | tail -40
done
echo "== summary"
for s in "${suites[@]}"; do
  [[ -f $T/all-$s.txt ]] && printf '%-14s %s\n' "$s" "$(grep -E '^same:' "$T/all-$s.txt" | tail -1)"
done
