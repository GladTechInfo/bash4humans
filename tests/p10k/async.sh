#!/bin/bash
# tests/p10k/async.sh [FILTER] : the vcs segment when gitstatusd answers late,
# under ble.sh, against real p10k. gs-hold pauses the daemon (optionally for N
# seconds), so the prompt after the command shows the LOADING state (the last
# known status greyed, or "loading" in a repository not seen yet), and once the
# daemon answers both shells redraw the prompt with the fresh status.
# Each shell starts on fresh copies of the repositories (GOLDEN_PRE).
T=${B4H_TEST_DIR:-/tmp/b4h-test}; A=$T/async
mkdir -p "$T/golden"
export GOLDEN_TTY_AGE=-1
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
"$root/tests/p10k/make-git-fixtures.sh" "$T/git" >/dev/null
mkdir -p "$A/bin"; cp "$root/tests/p10k/gs-hold" "$A/bin/"; chmod +x "$A/bin/gs-hold"
pre="rm -rf $A/repo $A/other; cp -a $T/git/clean $A/repo; cp -a $T/git/dirty $A/other"

# NAME|TEMPLATE|KEYS  (golden.sh waits 2 s after the keys)
cases=(
  "plain|lean|"
  "hold-modify|lean|gs-hold; echo x >>a"$'\r'
  "hold-modify-resume|lean|gs-hold 1; echo x >>a"$'\r'
  "hold-cd|lean|gs-hold; cd ../other"$'\r'
  "hold-cd-resume|lean|gs-hold 1; cd ../other"$'\r'
  "hold-cd-back|lean|cd ../other"$'\r\x1e'"gs-hold; echo y >>../repo/a; cd ../repo"$'\r'
  "rb-hold-modify|rainbow|gs-hold; echo x >>a"$'\r'
  "rb-hold-modify-resume|rainbow|gs-hold 1; echo x >>a"$'\r'
  "rb-hold-cd|rainbow|gs-hold; cd ../other"$'\r'
  "pure-cd|pure|cd ../other"$'\r'
  "pure-hold-cd-resume|pure|gs-hold 1; cd ../other"$'\r'
  "classic-hold-leave|classic|gs-hold; cd /tmp"$'\r'
)
pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id tpl keys <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  require_hold=''
  [[ $keys != *gs-hold* ]] || require_hold=1
  if GOLDEN_REQUIRE_HOLD=$require_hold BLE=1 GOLDEN_PRE=$pre GOLDEN_ENV="PATH=$A/bin:$PATH" \
       "$root/tests/p10k/golden.sh" "async-$id" "$HOME/src/powerlevel10k/config/p10k-$tpl.zsh" \
       "$root/p10k/config/p10k-$tpl.bash" "$A/repo" 100 8 "$keys" >"$T/golden/async-$id.log" 2>&1; then
    # Equal screens alone can pass when neither shell draws a Git segment.
    expected=''
    case $id in
      hold-cd) expected='other loading' ;;
      hold-cd-resume) expected='main +1 !1 ?2' ;;
    esac
    if [[ -n $expected ]] && ! grep -Fq "$expected" "$T/golden/async-$id/bash.txt"; then
      (( fail++ )); echo "DIFF  $id: expected '$expected'"
    else
      (( pass++ )); echo "SAME  $id"
    fi
  else
    (( fail++ )); echo "DIFF  $id  $(sed -n 1p "$T/golden/async-$id.log" | grep -o '([0-9]* cells)')"
  fi
done

# public_ip and gcloud's project name: fetched in the background; the fake
# curl and gcloud answer after 1.5 s, when the first prompt is already shown
# (golden.sh takes the screen after 3 s). Then the same after a command.
C=$A/cfg; mkdir -p "$C" "$A/fake"
cp "$root/tests/p10k/fake/curl" "$root/tests/p10k/fake/gcloud" "$A/fake/"; chmod +x "$A/fake/"*
"$root/tests/p10k/make-lang-fixtures.sh" "$T/lang" >/dev/null   # gcloud configuration
mk() {  # mk NAME TEMPLATE LINES...  -> $C/NAME.zsh and $C/NAME.bash
  local n=$1 tpl=$2 sh src; shift 2
  for sh in zsh bash; do
    src=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh
    [[ $sh == bash ]] && src=$root/p10k/config/p10k-$tpl.bash
    { cat "$src"; printf '%s\n' "$@"; } >"$C/$n.$sh"
  done
}
mk pubip lean 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status public_ip)' 'POWERLEVEL9K_PUBLIC_IP_METHODS=(curl)'
mk pubip-rb rainbow 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(public_ip)' 'POWERLEVEL9K_PUBLIC_IP_METHODS=(curl)'
mk gcloud lean 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(gcloud)'
mk gcloud-rb rainbow 'POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(gcloud)'
# NAME|CONFIG|KEYS
cases2=(
  "pubip-first|pubip|"
  "pubip-rb-first|pubip-rb|"
  "pubip-after|pubip|false"$'\r'
  "gcloud-first|gcloud|"
  "gcloud-rb-first|gcloud-rb|"
  "gcloud-after|gcloud|true"$'\r'
)
for c in "${cases2[@]}"; do
  IFS='|' read -r id cfg keys <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  if BLE=1 GOLDEN_ENV="PATH=$A/fake:$A/bin:$PATH CLOUDSDK_CONFIG=$T/lang/cloud/gcloud" \
       "$root/tests/p10k/golden.sh" "async-$id" "$C/$cfg.zsh" "$C/$cfg.bash" /tmp 100 8 "$keys" \
       >"$T/golden/async-$id.log" 2>&1; then
    (( pass++ )); echo "SAME  $id"
  else
    (( fail++ )); echo "DIFF  $id  $(sed -n 1p "$T/golden/async-$id.log" | grep -o '([0-9]* cells)')"
  fi
done
echo "same: $pass   different: $fail"
(( fail == 0 ))
