#!/bin/bash
# tests/p10k/golden.sh NAME ZSH_CONFIG BASH_CONFIG DIR [COLS ROWS [KEYS]]
# Capture the first prompt (or the screen after KEYS) of real p10k in zsh and of
# the bash port, in the same terminal size and directory, and compare them cell
# by cell (character, foreground, background, bold). Exit 0 if identical.
set -e
name=$1 zcfg=$2 bcfg=$3 dir=$4 cols=${5:-100} rows=${6:-12} keys=${7-}
out=${B4H_TEST_DIR:-/tmp/b4h-test}/golden/$name; mkdir -p "$out"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
# The capture may reuse the parent terminal number on a different PTY.
unset P9K_SSH _P9K_SSH_TTY P9K_TTY _P9K_TTY
export XDG_RUNTIME_DIR
XDG_RUNTIME_DIR=$(mktemp -d "$out/runtime.XXXXXXXX")
trap 'rm -rf -- "$XDG_RUNTIME_DIR"' EXIT
zdot=$out/zdot; mkdir -p "$zdot"
# VI=1: vi editing mode in both shells. BLE=1: bash runs under ble.sh.
ble=$HOME/.cache/bash4humans/deps/ble.sh/ble.sh
{ [[ -n ${VI-} ]] && echo 'bindkey -v; KEYTIMEOUT=1'
  printf 'source %q\nsource %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme" "$zcfg"
  [[ -z ${GOLDEN_TTY_AGE-} ]] || printf 'POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS=%q\n' "$GOLDEN_TTY_AGE"
} >"$zdot/.zshrc"
{ [[ -n ${BLE-} ]] && printf '. %q --attach=none --norc\n' "$ble"
  [[ -n ${VI-} ]] && echo 'set -o vi'
  printf '. %q\n. %q\n' "$root/lib/p10k/main.bash" "$bcfg"
  [[ -z ${GOLDEN_TTY_AGE-} ]] || printf 'POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS=%q\n' "$GOLDEN_TTY_AGE"
  echo p10k_init
  # typed text is the line editor's business, not the prompt's: no colouring
  # or suggestions from ble.sh (zsh here has neither)
  if [[ -n ${BLE-} ]]; then
    echo 'bleopt highlight_syntax= highlight_filename= highlight_variable= complete_auto_complete='
    echo '[[ ${BLE_VERSION-} ]] && ble-attach'
  fi
} >"$out/bashrc"
steps='[{"wait": 3}'
# KEYS may hold several steps separated by \x1e, each followed by a pause
if [[ -n $keys ]]; then
  IFS=$'\x1e' read -r -d '' -a ksteps <<<"$keys" || :; ksteps[-1]=${ksteps[-1]%$'\n'}
  for k in "${ksteps[@]}"; do steps+=', {"keys": '$(jq -Rn --arg k "$k" '$k')'}, {"wait": 2}'; done
fi
steps+=', {"snap": "screen"}, {"keys": "exit\r"}, {"wait": 1}]'
envj='{"TERM": "xterm-256color", "LANG": "en_GB.UTF-8", "ZDOTDIR": "'$zdot'"}'
# GOLDEN_ENV="VAR=VALUE ...": set for both shells before they start
extra=''; for kv in ${GOLDEN_ENV-}; do extra+=', '$(jq -Rn --arg k "$kv" '$k'); done
if [[ -n ${BLE-} ]]; then
  # Build terminal and keymap caches before taking the editing snapshot.
  # Readiness is confirmed by a command executed by the interactive shell.
  export GITSTATUS_CACHE_DIR=${GITSTATUS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gitstatus}
  export XDG_CACHE_HOME=$XDG_RUNTIME_DIR/cache
  mkdir -p "$XDG_CACHE_HOME"
  { printf '. %q --attach=none --norc\n' "$ble"
    [[ -z ${VI-} ]] || echo 'set -o vi'
    echo 'ble-attach || exit 1'
  } >"$out/warm.bashrc"
  jq -n --arg rc "$out/warm.bashrc" --argjson env "$envj" '{
    cmd:["bash","--rcfile",$rc,"-i"], rows:8, cols:100, env:$env,
    steps:[{wait:3},{keys:": > \"$XDG_RUNTIME_DIR/ready\"\r"},{wait:2},{keys:"exit\r"},{wait:1}]
  }' >"$out/warm.json"
  tui-capture "$out/warm.json" "$out/warm" >"$out/warm.log" 2>&1
  [[ -f $XDG_RUNTIME_DIR/ready ]] || { echo "ble.sh warm-up failed: $out/warm.log" >&2; exit 1; }
fi
for sh in zsh bash; do
  export GS_HOLD_MARKER=$XDG_RUNTIME_DIR/held-$sh
  if [[ $sh == zsh ]]; then cmd='["env", "-u", "SSH_CONNECTION", "-u", "SSH_CLIENT", "-u", "SSH_TTY"'$extra', "zsh", "-i"]'
  else cmd='["env", "-u", "SSH_CONNECTION", "-u", "SSH_CLIENT", "-u", "SSH_TTY"'$extra', "bash", "--rcfile", "'$out/bashrc'", "-i"]'
  fi
  printf '{"cmd": %s, "rows": %s, "cols": %s, "env": %s, "steps": %s}\n' "$cmd" "$rows" "$cols" "$envj" "$steps" >"$out/$sh.json"
  # GOLDEN_PRE="commands": run before each shell starts (fresh fixtures for both)
  [[ -n ${GOLDEN_PRE-} ]] && eval "$GOLDEN_PRE"
  rm -rf "$out/$sh"; (cd "$dir" && tui-capture "$out/$sh.json" "$out/$sh" >"$out/$sh.log" 2>&1)
  if [[ -n ${GOLDEN_REQUIRE_HOLD-} && ! -f $GS_HOLD_MARKER ]]; then
    echo "$sh failed to pause gitstatusd in $name" >&2; exit 1
  fi
done
# rows as text, and a cell-level diff
for sh in zsh bash; do
  jq -r '.grid[] | map(.[0]) | join("")' "$out/$sh/screen.json" >"$out/$sh.txt"
  if [[ -n ${GOLDEN_FIRST_ROW-} ]]; then
    first=$(awk 'NF { print NR; exit }' "$out/$sh.txt")
    [[ $first == "$GOLDEN_FIRST_ROW" ]] || { echo "$sh first prompt row: $first (expected $GOLDEN_FIRST_ROW)"; exit 1; }
  fi
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
