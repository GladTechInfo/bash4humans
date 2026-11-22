#!/bin/bash
# tests/p10k/matrix-wizard.sh [FILTER] : configs made by the real p10k wizard, converted
# to bash, compared with real p10k in two repositories.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; W=$T/wz; mkdir -p "$W"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
"$root/tests/p10k/make-git-fixtures.sh" "$T/git" >/dev/null
declare -a combos=(
  "L1|style=lean time=2 lines=2 gap=3 frame=4 orn=1 spacing=2 icons=2 flow=2"
  "L2|style=lean lines=1 icons=1 flow=1"
  "L3|style=lean colors=2 lines=2 gap=2 frame=2 orn=3"
  "L4|style=lean charset=2 lines=2 gap=3"
  "L5|style=lean lines=2 gap=1 frame=3 orn=4 padding=n time=1"
  "C1|style=classic color=1 sep=1 head=3 tail=1 lines=2 gap=1 frame=1"
  "C2|style=classic color=2 sep=2 head=1 tail=2 lines=2 gap=2 frame=2 icons=2 flow=2"
  "C3|style=classic color=3 sep=3 head=4 tail=4 lines=1"
  "C4|style=classic color=4 sep=4 head=5 tail=5 lines=2 gap=3 frame=4 spacing=2 time=2"
  "C5|style=classic charset=2 lines=2 gap=3"
  "R1|style=rainbow sep=1 head=3 tail=1 lines=2 gap=1 frame=1 icons=2 flow=2"
  "R2|style=rainbow sep=3 head=4 tail=4 lines=1 icons=1"
  "R3|style=rainbow sep=4 head=5 tail=5 lines=2 gap=2 frame=2 orn=3"
  "R4|style=rainbow sep=2 head=2 tail=3 lines=2 gap=3 frame=3 orn=4 padding=n transient=y"
  "R5|style=rainbow charset=2 lines=1"
  "P1|style=pure rprompt=1 lines=2 spacing=2"
  "P2|style=pure rprompt=2 time=2 lines=1"
  "P3|style=pure rprompt=2 lines=2 time=1"
  "P4|style=pure colors=2 rprompt=1 lines=1 spacing=1"
)
pass=0 fail=0
for c in "${combos[@]}"; do
  id=${c%%|*} opts=${c#*|}
  [[ -n ${1-} && $id != *$1* ]] && continue
  if [[ ! -s $W/$id.zsh ]]; then
    "$root/tests/p10k/wizard-real.sh" "$W/$id.zsh" $opts >"$W/$id.gen.log" 2>&1 || { echo "GEN-FAIL $id"; (( fail++ )); continue; }
  fi
  "$HOME/.cache/bash4humans/deps/bin/b4h-tool" p10k-config "$W/$id.zsh" "$W/$id.bash" 2>"$W/$id.conv.log" || { echo "CONV-FAIL $id"; cat "$W/$id.conv.log"; }
  mask=''; [[ $opts == *time=[12]* ]] && mask=1
  for repo in ahead dirty; do
    if MASK_DIGITS=$mask "$root/tests/p10k/golden.sh" "wz-$id-$repo" "$W/$id.zsh" "$W/$id.bash" "$T/git/$repo" 100 8 \
         >"$T/golden/wz-$id-$repo.log" 2>&1; then
      (( pass++ )); echo "SAME  $id-$repo   ($opts)"
    else
      (( fail++ )); echo "DIFF  $id-$repo  $(sed -n 1p "$T/golden/wz-$id-$repo.log" | grep -o '([0-9]* cells)')   ($opts)"
    fi
  done
done
echo "same: $pass   different: $fail"
