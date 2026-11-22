#!/bin/bash
# tests/p10k/wizard-real.sh OUT.zsh KEY=VALUE...
# Run the real `p10k configure` (it starts by itself when there is no config)
# with answers given as KEY=VALUE (see wizard-keys.sh), and keep the config
# it writes. It is not asked to edit .zshrc (zshrc=n).
out=$1; shift
. "${BASH_SOURCE[0]%/*}/wizard-keys.sh"
# Pure: Original / Snazzy is asked only in a true-colour terminal (COLORTERM)
[[ ${COLORTERM-} == @(24bit|truecolor) ]] && TRUECOLOR=1
wizard_keys "$@" zshrc=n; k=$REPLY
T=${B4H_TEST_DIR:-/tmp/b4h-test}/wizard-real; mkdir -p "$T"
z=$T/zdot.$$; rm -rf "$z"; mkdir -p "$z"
printf 'source %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme" >"$z/.zshrc"
keys=$(printf '%s' "$k" | sed 's/./&\n/g' | jq -R . | jq -s 'map({"keys": .}, {"wait": 0.4})')
printf '{"cmd": ["zsh", "-i"], "rows": 50, "cols": 100, "env": {"ZDOTDIR": "%s", "TERM": "xterm-256color", "LANG": "en_GB.UTF-8"}, "steps": [{"wait": 3}] + %s + [{"wait": 2}, {"keys": "exit\\r"}, {"wait": 1}]}\n' "$z" "$keys" \
  | jq -c '.steps = (.steps | flatten)' >"$T/spec.$$.json" 2>/dev/null || {
  # jq cannot add in a printf string: build the steps array explicitly
  jq -n --arg z "$z" --argjson ks "$keys" '{cmd: ["zsh","-i"], rows: 50, cols: 100,
     env: {ZDOTDIR: $z, TERM: "xterm-256color", LANG: "en_GB.UTF-8"},
     steps: ([{wait: 3}] + $ks + [{wait: 2}, {keys: "exit\r"}, {wait: 1}])}' >"$T/spec.$$.json"; }
(cd /tmp && tui-capture "$T/spec.$$.json" "$T/cap.$$" >/dev/null 2>&1)
if [[ -s $z/.p10k.zsh ]]; then cp "$z/.p10k.zsh" "$out"; echo "keys=$k -> $(sed -n 3,4p "$out" | tr -d '#' | tr -s ' ' | tr '\n' ' ')"
else echo "keys=$k -> NO CONFIG WRITTEN" >&2; rm -rf "$z" "$T/spec.$$.json" "$T/cap.$$"; exit 1
fi
rm -rf "$z" "$T/spec.$$.json" "$T/cap.$$"
