#!/bin/bash
# tests/p10k/unit-osc133.sh : POWERLEVEL9K_TERM_SHELL_INTEGRATION. The marks
# (OSC 133 A, B, C, D;status) are invisible on screen, so here the raw
# output of zsh+p10k and bash+port, both driven by the same keys inside
# `script`, is compared: the order of the marks and their parameters.
T=${B4H_TEST_DIR:-/tmp/b4h-test}/osc133; rm -rf "$T"; mkdir -p "$T/zdot"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
tool=$(type -P b4h-tool) || tool=$HOME/.cache/bash4humans/deps/bin/b4h-tool

# CASE|TEMPLATE|EXTRA SETTINGS (both shells, after the config)|ble (bash
# under ble.sh: the transient prompt needs it)
cases=(
  "lean|lean||"
  "pure|pure||"
  "lean-ble|lean||ble"
  "rainbow-transient|rainbow|POWERLEVEL9K_TRANSIENT_PROMPT=always|ble"
)
ble=$HOME/.cache/bash4humans/deps/ble.sh/ble.sh
# keys: a command, an empty line, a failing command, Ctrl-C on a typed line
keys=(true $'\r' '' $'\r' false $'\r' 'echo x' $'\x03' exit $'\r')

drive() {   # CMD OUT : run CMD in script, typing keys with pauses
  { sleep 3
    local k; for k in "${keys[@]}"; do printf '%s' "$k"; sleep 1; done
    sleep 1; } | TERM=xterm-256color COLUMNS=100 LINES=40 script -qfec "$1" "$2" >/dev/null 2>&1
}
# (A B repeated: the line editor drew the prompt again - zle and ble.sh
# redraw at different moments, each time with the marks; counted once)
marks() { grep -aoE $'\e\\]133;[A-Z][^\a]*\a' "$1" | sed 's/\x1b\]133;//; s/\x07$//' | tr '\n' ' ' | sed -E 's/(A B )+/A B /g'; }

pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id tpl extra useble <<<"$c"
  zcfg=$root/p10k/templates/p10k-$tpl.zsh
  "$tool" p10k-config "$zcfg" "$T/$id.bash" >/dev/null || { echo "DIFF  $id (conversion failed)"; (( fail++ )); continue; }
  { printf 'source %q\nsource %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme" "$zcfg"
    printf 'POWERLEVEL9K_TERM_SHELL_INTEGRATION=true\n'
    [[ -n $extra ]] && printf '%s\n' "$extra"; } >"$T/zdot/.zshrc"
  { [[ -n $useble ]] && printf '. %q --attach=none --norc\n' "$ble"
    printf '. %q\n. %q\n' "$root/lib/p10k/main.bash" "$T/$id.bash"
    printf 'POWERLEVEL9K_TERM_SHELL_INTEGRATION=true\n'
    [[ -n $extra ]] && printf '%s\n' "$extra"
    printf 'p10k_init\n'
    [[ -n $useble ]] && printf '%s\n' 'bleopt highlight_syntax= complete_auto_complete=' \
      '[[ ${BLE_VERSION-} ]] && ble-attach'; } >"$T/$id.bashrc"
  drive "ZDOTDIR=$T/zdot zsh -i" "$T/$id.zsh.raw"
  : >"$T/hist"
  drive "HISTFILE=$T/hist bash --rcfile $T/$id.bashrc -i" "$T/$id.bash.raw"
  z=$(marks "$T/$id.zsh.raw") b=$(marks "$T/$id.bash.raw")
  if [[ -n $z && $z == "$b" ]]; then (( pass++ )); echo "SAME  $id   $z"
  else (( fail++ )); echo "DIFF  $id"; echo "   zsh:  $z"; echo "   bash: $b"
  fi
done
echo "same: $pass   different: $fail"
