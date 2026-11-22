#!/bin/bash
# tests/drive.sh RCFILE KEYS... : type KEYS (printf %b; "@N" = wait N/10 s) into an
# interactive bash started with RCFILE in a pseudo-terminal. History goes to
# $B4H_TEST_DIR/hist, the screen to $B4H_TEST_DIR/typescript.
B4H_TEST_DIR=${B4H_TEST_DIR:-/tmp/b4h-test}; mkdir -p "$B4H_TEST_DIR"
rc=$1; shift
{
  sleep 3
  for k in "$@"; do
    if [[ $k == @* ]]; then sleep "$(( ${k#@} / 10 )).$(( ${k#@} % 10 ))"
    else printf '%b' "$k"; sleep 0.5
    fi
  done
  sleep 1; printf 'exit\r'; sleep 1
} | COLUMNS=110 LINES=40 TERM=xterm-256color LANG=en_GB.UTF-8 HISTFILE=$B4H_TEST_DIR/hist \
    script -qfec "stty cols 110 rows 40; bash --rcfile $rc -i" "$B4H_TEST_DIR/typescript" >/dev/null 2>&1
