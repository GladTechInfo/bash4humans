#!/bin/bash
# tests/p10k/matrix.sh [FILTER] : golden comparisons for every template x place x state.
# Uses fixture directories under $B4H_TEST_DIR/fixture. Prints SAME/DIFF per case.
T=${B4H_TEST_DIR:-/tmp/b4h-test}; F=$T/fixture
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
g=$root/tests/p10k/golden.sh
deep=$F/apple-tree-long-name/banana-split-directory/cherry-orchard-more/dir
declare -a cases=(
  # name            dir        cols  keys
  "home|$HOME|100|"
  "etc|/etc|100|"
  "root|/|100|"
  "ro|$F/ro|100|"
  "deep-wide|$deep|120|"
  "deep-narrow|$deep|60|"
  "error|$F|100|false\r"
  "pipe|$F|100|true | false | true\r"
  "slow|$F|100|sleep 4\r"
  "job|$F|100|sleep 30 &\rclear\r"
)
pass=0 fail=0
for tpl in lean lean-8colors classic rainbow pure robbyrussell; do
  for c in "${cases[@]}"; do
    IFS='|' read -r name dir cols keys <<<"$c"
    [[ -n ${1-} && $tpl-$name != *$1* ]] && continue
    rows=12
    [[ $name == slow ]] && rows=14
    if "$g" "$tpl-$name" "$HOME/src/powerlevel10k/config/p10k-$tpl.zsh" "$root/p10k/config/p10k-$tpl.bash" \
         "$dir" "$cols" "$rows" "$(printf '%b' "$keys")" >"$T/golden/$tpl-$name.log" 2>&1; then
      (( pass++ )); echo "SAME  $tpl-$name"
    else
      (( fail++ )); echo "DIFF  $tpl-$name  $(sed -n 1p "$T/golden/$tpl-$name.log" | grep -o '([0-9]* cells)')"
    fi
  done
done
echo "same: $pass   different: $fail"
