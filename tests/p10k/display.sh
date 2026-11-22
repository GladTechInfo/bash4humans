#!/bin/bash
# tests/p10k/display.sh [FILTER] : `p10k display` and the p10k-on-* hooks
# against real p10k. A hook or command line is added to the rainbow (two
# lines, frames, gap) and lean templates; keys are typed into both shells.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; C=$T/dispcfg; mkdir -p "$C"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
mk() {  # mk NAME TEMPLATE LINES...
  local n=$1 tpl=$2 sh src; shift 2
  for sh in zsh bash; do
    src=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh
    [[ $sh == bash ]] && src=$root/p10k/config/p10k-$tpl.bash
    { cat "$src"; echo 'POWERLEVEL9K_MULTILINE_FIRST_PROMPT_GAP_CHAR=·'; printf '%s\n' "$@"; } >"$C/$n.$sh"
  done
}
for tpl in rainbow lean; do
  mk "$tpl-base" "$tpl"
  mk "$tpl-dir" "$tpl" "p10k-on-pre-prompt() { p10k display '1/left/dir=hide'; }"
  mk "$tpl-parts" "$tpl" "p10k-on-pre-prompt() { p10k display '-1/right=hide' '1/gap=hide' '*/left_frame=hide'; }"
  mk "$tpl-line1" "$tpl" "p10k-on-pre-prompt() { p10k display '1=hide'; }"
  mk "$tpl-right" "$tpl" "p10k-on-pre-prompt() { p10k display '*/right=hide' '*/right_frame=hide'; }"
  mk "$tpl-empty" "$tpl" 'POWERLEVEL9K_PROMPT_ADD_NEWLINE=true' "p10k-on-pre-prompt() { p10k display 'empty_line=hide'; }"
  mk "$tpl-hot" "$tpl" 'POWERLEVEL9K_DISABLE_HOT_RELOAD=false'
done
# NAME|CONFIG|KEYS (steps separated by \x1e)
cases=()
for tpl in rainbow lean; do
  cases+=(
    "$tpl-dir|$tpl-dir|"
    "$tpl-parts|$tpl-parts|"
    "$tpl-line1|$tpl-line1|"
    "$tpl-right|$tpl-right|"
    "$tpl-empty|$tpl-empty|"$'true\r'
    "$tpl-cycle|$tpl-base|"$'p10k display 1/right=hide,show\r\x1ep10k display 1/right=hide,show\r\x1ep10k display 1/right=hide,show\r'
    "$tpl-dump|$tpl-base|"$'p10k display 1/left_frame=hide; p10k display -a \'*/left*\' \'empty_line\' \'ruler\'; echo "${reply[@]}"\r'
    # the full list compared sorted: zsh lists [(I)*] matches in an order
    # the port does not reproduce for names sharing a hash bucket
    "$tpl-noreload|$tpl-base|"$'POWERLEVEL9K_DIR_FOREGROUND=1 POWERLEVEL9K_DIR_BACKGROUND=3\r'
    "$tpl-reload|$tpl-base|"$'POWERLEVEL9K_DIR_FOREGROUND=1 POWERLEVEL9K_DIR_BACKGROUND=3\r\x1ep10k reload\r'
    "$tpl-hot|$tpl-hot|"$'POWERLEVEL9K_DIR_FOREGROUND=1 POWERLEVEL9K_DIR_BACKGROUND=3\r\x1eunset POWERLEVEL9K_DIR_BACKGROUND\r'
    "$tpl-dumpall|$tpl-base|"$'p10k display -a; printf "%s %s\\n" "${reply[@]}" | sort | paste -s -d" "\r'
  )
done
pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id cfg keys <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  if "$root/tests/p10k/golden.sh" "disp-$id" "$C/$cfg.zsh" "$C/$cfg.bash" /tmp 120 14 "$keys" \
       >"$T/golden/disp-$id.log" 2>&1; then
    (( pass++ )); echo "SAME  $id"
  else
    (( fail++ )); echo "DIFF  $id  $(sed -n 1p "$T/golden/disp-$id.log" | grep -o '([0-9]* cells)')"
  fi
done
echo "same: $pass   different: $fail"
