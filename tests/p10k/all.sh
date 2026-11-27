#!/bin/bash
# tests/p10k/all.sh : every comparison with real p10k, one after the other
# (they share the terminal capture tool; do not edit the tested files while
# this runs). Full output in $B4H_TEST_DIR/all-<suite>.txt; a summary at the end.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; mkdir -p "$T"
# golden.sh writes its logs here; the matrix suites run before segments.sh,
# which used to be the only one to create it (a clean /tmp failed them all)
mkdir -p "$T/golden" || exit 1
here=$(cd "${BASH_SOURCE[0]%/*}" && pwd)
suites=(unit-parser unit-battery unit-wifi unit-colors unit-osc133 matrix matrix-git matrix-wizard segments ble display async instant wrap)
results=()
failed=0
for s in "${suites[@]}"; do
  [[ -n ${1-} && $s != *$1* ]] && continue
  echo "== $s"
  log=$T/all-$s.txt
  status=0
  ( cd /tmp && "$here/$s.sh" </dev/null ) >"$log" 2>&1 || status=$?
  grep -v '^SAME' "$log" | tail -40
  summary=$(tail -n 1 "$log")
  if [[ $status != 0 ]]; then
    summary="FAIL (exit $status)  $summary"
    failed=1
  elif [[ ! $summary =~ ^same:[[:space:]]+[0-9]+[[:space:]]+different:[[:space:]]+0$ ]]; then
    summary="FAIL (differences or missing summary)  $summary"
    failed=1
  fi
  results+=("$(printf '%-14s %s' "$s" "$summary")")
done
if (( ${#results[@]} == 0 )); then
  echo "No suites match '$1'" >&2
  exit 1
fi
echo "== summary"
printf '%s\n' "${results[@]}"
exit "$failed"
