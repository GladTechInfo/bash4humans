#!/bin/bash
# tests/remote-install.sh HOST : run install.sh on HOST (source already copied to
# /tmp/bash4humans) over an ssh pseudo-terminal, answering its questions, then
# use the new shell for a few checks. Output: $B4H_TEST_DIR/HOST.typescript and
# HOST:/tmp/b4h-check.
# The first start offers to convert ~/.p10k.zsh (the lab VMs have one): y.
# Without one, p10k's wizard would start with the first prompt instead.
host=$1
B4H_TEST_DIR=${B4H_TEST_DIR:-/tmp/b4h-test}; mkdir -p "$B4H_TEST_DIR"
keys() {
  sleep 3
  for k in 1 1 n 1 n; do printf '%s' "$k"; sleep 1; done   # keys, line editor, tmux, replace .bashrc, no chsh
  sleep 90                                                  # downloads and builds
  printf y; sleep 8                                         # first start: convert ~/.p10k.zsh
  printf 'cd /tmp/bash4humans\r'; sleep 2
  printf 'echo "ble=$BLE_VERSION gs=$GITSTATUS_DAEMON_PID mode=$POWERLEVEL9K_MODE osc133=$_p9k__si colours=$_p9k__tc_colors" > /tmp/b4h-check\r'; sleep 2
  printf 'b4h doctor >> /tmp/b4h-check 2>&1\r'; sleep 3
  printf 'gti --version >> /tmp/b4h-check 2>&1\r'; sleep 3
  printf 'sleep 4; false\r'; sleep 6
  # the prompt as text (codes and readline markers removed; ESC[K ends each
  # line of a multi-line prompt under ble.sh)
  printf 'printf "%%s\\n" "$_p9k_ps1" | tr -d "\\001\\002" | sed "s/\\x1b\\[[0-9;]*[mK]//g; s/\\x1b\\][^\\x07]*\\x07//g" >> /tmp/b4h-check\r'; sleep 2
  printf 'exit\r'; sleep 2
}
keys | ssh -tt "$host" 'B4H_SOURCE=/tmp/bash4humans bash /tmp/bash4humans/install.sh' >"$B4H_TEST_DIR/$host.typescript" 2>&1
