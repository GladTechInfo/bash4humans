#!/bin/bash
# tests/p10k/golden.sh NAME ZSH_CONFIG BASH_CONFIG DIR [COLS ROWS [KEYS]]
# Capture the first prompt (or the screen after KEYS) of real p10k in zsh and of
# the bash port, in the same terminal size and directory, and compare them cell
# by cell (character, foreground, background, bold). Exit 0 if identical.
name=$1 zcfg=$2 bcfg=$3 dir=$4 cols=${5:-100} rows=${6:-12} keys=${7-}
out=${B4H_TEST_DIR:-/tmp/b4h-test}/golden/$name; mkdir -p "$out"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
zdot=$out/zdot; mkdir -p "$zdot"
# VI=1: vi editing mode in both shells. BLE=1: bash runs under ble.sh.
ble=$HOME/.cache/bash4humans/deps/ble.sh/ble.sh
{ [[ -n ${VI-} ]] && echo 'bindkey -v; KEYTIMEOUT=1'
  printf 'source %q\nsource %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme" "$zcfg"; } >"$zdot/.zshrc"
{ [[ -n ${BLE-} ]] && printf '. %q --attach=none --norc\n' "$ble"
  [[ -n ${VI-} ]] && echo 'set -o vi'
  printf '. %q\n. %q\np10k_init\n' "$root/lib/p10k/main.bash" "$bcfg"
  # typed text is the line editor's business, not the prompt's: no colouring
  # or suggestions from ble.sh (zsh here has neither)
  [[ -n ${BLE-} ]] && echo 'bleopt highlight_syntax= highlight_filename= highlight_variable= complete_auto_complete=' \
    && echo '[[ ${BLE_VERSION-} ]] && ble-attach'; } >"$out/bashrc"
steps='[{"wait": 3}'
# KEYS may hold several steps separated by \x1e, each followed by a pause
if [[ -n $keys ]]; then
  IFS=$'\x1e' read -r -d '' -a ksteps <<<"$keys"; ksteps[-1]=${ksteps[-1]%$'\n'}
  for k in "${ksteps[@]}"; do steps+=', {"keys": '$(jq -Rn --arg k "$k" '$k')'}, {"wait": 2}'; done
fi
steps+=', {"snap": "screen"}, {"keys": "exit\r"}, {"wait": 1}]'
envj='{"TERM": "xterm-256color", "LANG": "en_GB.UTF-8", "ZDOTDIR": "'$zdot'"}'
# GOLDEN_ENV="VAR=VALUE ...": set for both shells before they start
extra=''; for kv in ${GOLDEN_ENV-}; do extra+=', '$(jq -Rn --arg k "$kv" '$k'); done
for sh in zsh bash; do
  if [[ $sh == zsh ]]; then cmd='["env", "-u", "SSH_CONNECTION", "-u", "SSH_CLIENT", "-u", "SSH_TTY"'$extra', "zsh", "-i"]'
  else cmd='["env", "-u", "SSH_CONNECTION", "-u", "SSH_CLIENT", "-u", "SSH_TTY"'$extra', "bash", "--rcfile", "'$out/bashrc'", "-i"]'
  fi
  printf '{"cmd": %s, "rows": %s, "cols": %s, "env": %s, "steps": %s}\n' "$cmd" "$rows" "$cols" "$envj" "$steps" >"$out/$sh.json"
  # GOLDEN_PRE="commands": run before each shell starts (fresh fixtures for both)
  [[ -n ${GOLDEN_PRE-} ]] && eval "$GOLDEN_PRE"
  rm -rf "$out/$sh"; (cd "$dir" && tui-capture "$out/$sh.json" "$out/$sh" >/dev/null 2>&1)
done
# rows as text, and a cell-level diff
for sh in zsh bash; do
  jq -r '.grid[] | map(.[0]) | join("")' "$out/$sh/screen.json" >"$out/$sh.txt"
  jq -c '.grid | to_entries[] | .key as $r | .value | to_entries[] | [$r, .key, .value[0], .value[1], .value[2], .value[3]]' \
    "$out/$sh/screen.json" >"$out/$sh.cells"
  # MASK_DIGITS=1: the clock differs between the two captures; compare digits as "#".
  [[ -n ${MASK_DIGITS-} ]] && sed -i 's/^\(\[[0-9]*,[0-9]*,"\)[0-9]"/\1#"/' "$out/$sh.cells"
done
if diff -q "$out/zsh.cells" "$out/bash.cells" >/dev/null; then
  echo "SAME   $name"
  exit 0
fi
echo "DIFF   $name   ($(diff "$out/zsh.cells" "$out/bash.cells" | grep -c '^<') cells)"
echo "--- zsh";  sed -n '1,8p' "$out/zsh.txt"
echo "--- bash"; sed -n '1,8p' "$out/bash.txt"
diff "$out/zsh.cells" "$out/bash.cells" | head -${DIFF_LINES:-20}
exit 1
