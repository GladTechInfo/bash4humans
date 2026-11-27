#!/bin/bash
# tests/p10k/matrix-git.sh [FILTER] : golden comparisons in git repositories in known states.
T=${B4H_TEST_DIR:-/tmp/b4h-test}
mkdir -p "$T/golden"
export GOLDEN_TTY_AGE=-1
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
# Anchor the private fixture tree so unrelated siblings in /tmp cannot
# change a shortest-unique path between the two captures.
fixture=$(mktemp -d /tmp/b4h-fixture.XXXXXXXX) || exit 1
trap 'rm -rf -- "$fixture"' EXIT
: >"$fixture/.shorten_folder_marker"
"$root/tests/p10k/make-git-fixtures.sh" "$fixture/git" >/dev/null || exit 1
pass=0 fail=0
for tpl in lean lean-8colors classic rainbow pure robbyrussell; do
  for repo in clean dirty ahead behind stash tag detached long wip merge gitlab; do
    [[ -n ${1-} && $tpl-$repo != *$1* ]] && continue
    if "$root/tests/p10k/golden.sh" "git-$tpl-$repo" "$HOME/src/powerlevel10k/config/p10k-$tpl.zsh" \
         "$root/p10k/config/p10k-$tpl.bash" "$fixture/git/$repo" 100 8 >"$T/golden/git-$tpl-$repo.log" 2>&1; then
      (( pass++ )); echo "SAME  $tpl-$repo"
    else
      (( fail++ )); echo "DIFF  $tpl-$repo  $(sed -n 1p "$T/golden/git-$tpl-$repo.log" | grep -o '([0-9]* cells)')"
    fi
  done
done
echo "same: $pass   different: $fail"
(( fail == 0 ))
