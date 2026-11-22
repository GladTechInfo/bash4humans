#!/bin/bash
# tests/remote-session.sh HOST : start an interactive bash4humans shell on HOST
# over an ssh pseudo-terminal and run checks; results in HOST:/tmp/b4h-check.
host=$1
B4H_TEST_DIR=${B4H_TEST_DIR:-/tmp/b4h-test}; mkdir -p "$B4H_TEST_DIR"
keys() {
  sleep 5
  printf 'echo "ble=$BLE_VERSION attached=${_ble_attached-} jobs=[$(jobs -l)]" > /tmp/b4h-check\r'; sleep 2
  printf 'rm -rf /tmp/b4h-repo; mkdir /tmp/b4h-repo && cd /tmp/b4h-repo && git init -q 2>/dev/null; touch a b\r'; sleep 3
  printf 'echo "gs=$GITSTATUS_DAEMON_PID" >> /tmp/b4h-check\r'; sleep 2
  printf 'sleep 4; (exit 130)\r'; sleep 6
  # the prompt as text (codes and readline markers removed)
  printf 'printf "%%s\\n" "$_p9k_ps1" | tr -d "\\001\\002" | sed "s/\\x1b\\[[0-9;]*m//g; s/\\x1b\\][^\\x07]*\\x07//g" >> /tmp/b4h-check\r'; sleep 2
  printf 'abbr -a gco git checkout\r'; sleep 1
  printf 'gco -h >/dev/null 2>&1; history 1 >> /tmp/b4h-check\r'; sleep 2
  printf 'zmv -n "(*)" "x-\\$1" >> /tmp/b4h-check 2>&1\r'; sleep 2
  printf 'b4h doctor >> /tmp/b4h-check 2>&1; cd; rm -rf /tmp/b4h-repo\r'; sleep 3
  printf 'exit\r'; sleep 2
}
keys | ssh -tt "$host" 'stty cols 110 rows 40; bash -i' >"$B4H_TEST_DIR/$host.session" 2>&1
