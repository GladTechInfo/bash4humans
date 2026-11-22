#!/bin/bash
# tests/p10k/wrap.sh [FILTER] : a prompt line wider than the terminal. It
# wraps; zsh then shows the right prompt beside the part on the last screen
# row, if that fits. A fixed long directory, 80 columns, plain bash and
# ble.sh, against real p10k.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; C=$T/wrapcfg; mkdir -p "$C"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
dir=/tmp/b4h-wrap/aaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa/bbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbbb/cc
mkdir -p "$dir"
mk() {  # mk NAME TEMPLATE LINES...
  local n=$1 tpl=$2 sh src; shift 2
  for sh in zsh bash; do
    src=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh
    [[ $sh == bash ]] && src=$root/p10k/config/p10k-$tpl.bash
    { cat "$src"; printf '%s\n' "$@"; } >"$C/$n.$sh"
  done
}
# (the directory is shortened to fit; a custom segment of fixed width is not)
one='POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(custom_long prompt_char)'
long="POWERLEVEL9K_CUSTOM_LONG='echo $(printf 'x%.0s' {1..95})'"
mk pure pure 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(time)'
mk lean lean "$one" "$long" 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time)'
mk rainbow rainbow "$one" "$long" 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status time)'
pass=0 fail=0
for cfg in pure lean rainbow; do
  for ble in '' 1; do
    id=$cfg${ble:+-ble}
    [[ -n ${1-} && $id != *$1* ]] && continue
    if BLE=$ble MASK_DIGITS=1 "$root/tests/p10k/golden.sh" "wrap-$id" "$C/$cfg.zsh" "$C/$cfg.bash" "$dir" 80 6 \
         >"$T/golden/wrap-$id.log" 2>&1; then
      (( pass++ )); echo "SAME  $id"
    else
      (( fail++ )); echo "DIFF  $id  $(sed -n 1p "$T/golden/wrap-$id.log" | grep -o '([0-9]* cells)')"
    fi
  done
done
echo "same: $pass   different: $fail"
