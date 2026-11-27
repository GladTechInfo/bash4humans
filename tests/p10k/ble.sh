#!/bin/bash
# tests/p10k/ble.sh [FILTER] : behaviour under ble.sh against real p10k:
#   vi editing modes (vi_mode, prompt_char), transient prompt (always,
#   same-dir), SHOW_ON_COMMAND while typing, right prompt on a 2-line frame.
# Configurations are templates plus a few settings; keys are typed into both
# shells (steps separated by \x1e, golden.sh waits after each).
T=${B4H_TEST_DIR:-/tmp/b4h-test}; C=$T/blecfg; mkdir -p "$C"
mkdir -p "$T/golden"
export GOLDEN_TTY_AGE=-1
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
"$root/tests/p10k/make-lang-fixtures.sh" "$T/lang" >/dev/null   # kubectl fixture
mk() {  # mk NAME TEMPLATE LINES...  -> $C/NAME.zsh and $C/NAME.bash
  local n=$1 tpl=$2 sh src; shift 2
  for sh in zsh bash; do
    src=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh
    [[ $sh == bash ]] && src=$root/p10k/config/p10k-$tpl.bash
    { cat "$src"; printf '%s\n' "$@"; } >"$C/$n.$sh"
  done
}
vi_elems=('POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir vi_mode prompt_char)' 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status)')
mk vi-a rainbow "${vi_elems[@]}"
mk vi-b rainbow "${vi_elems[@]}" 'unset POWERLEVEL9K_VI_VISUAL_MODE_STRING POWERLEVEL9K_VI_OVERWRITE_MODE_STRING'
mk vi-c rainbow "${vi_elems[@]}" 'POWERLEVEL9K_VI_OVERWRITE_MODE_STRING='
for tpl in lean rainbow; do for m in always same-dir; do
  mk "tr-$tpl-$m" "$tpl" "POWERLEVEL9K_TRANSIENT_PROMPT=$m"
done; done
kube="export PATH=$T/lang/bin:\$PATH KUBE_FIX=$T/lang/cloud/kube/plain.yaml KUBECONFIG=$T/lang/cloud/kube/config"
mk soc rainbow "$kube" 'POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir)' 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(kubecontext)'
mk frame rainbow

# NAME|CONFIG|VI(1/'')|COLS ROWS|KEYS ($'...' text)
cases=(
  "frame|frame||80 4|"
  "soc-kubectl|soc||80 4|kubectl get"
  "soc-sudo-helm|soc||80 4|sudo -u root helm x"
  "soc-ls|soc||80 4|ls -l"
  # the status after Ctrl-C on an empty line (p10k: SIGINT, 130 = INT) and
  # after an empty line (kept). (Ctrl-C on a typed line is not compared:
  # ble.sh's discard-line prints the abandoned line again, greyed.)
  "ctrlc-empty|frame||80 8|"$'false\r\x1e\x03'
  "empty-after-false|frame||80 8|"$'false\r\x1e\r'
)
for v in a b c; do
  cases+=("vi-$v-ins|vi-$v|1|80 6|" "vi-$v-cmd|vi-$v|1|80 6|"$'\e' "vi-$v-vis|vi-$v|1|80 6|"$'\ev'
          "vi-$v-line|vi-$v|1|80 6|"$'\eV' "vi-$v-ovr|vi-$v|1|80 6|"$'\eR' "vi-$v-back|vi-$v|1|80 6|"$'\eRx\ei')
done
for tpl in lean rainbow; do for m in always same-dir; do
  cases+=("tr-$tpl-$m-echo|tr-$tpl-$m||80 12|"$'echo hi\r'
          "tr-$tpl-$m-false|tr-$tpl-$m||80 12|"$'false\r'
          "tr-$tpl-$m-cd|tr-$tpl-$m||80 12|"$'cd /etc\r\x1ecd /etc\r\x1eecho x\r')
done; done
pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id cfg vi size keys <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  if BLE=1 VI=$vi "$root/tests/p10k/golden.sh" "ble-$id" "$C/$cfg.zsh" "$C/$cfg.bash" /tmp $size "$keys" \
       >"$T/golden/ble-$id.log" 2>&1; then
    (( pass++ )); echo "SAME  $id"
  else
    (( fail++ )); echo "DIFF  $id  $(sed -n 1p "$T/golden/ble-$id.log" | grep -o '([0-9]* cells)')"
  fi
done
echo "same: $pass   different: $fail"
(( fail == 0 ))
