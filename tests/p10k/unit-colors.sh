#!/bin/bash
# tests/p10k/unit-colors.sh : colours as zsh prints them for different
# terminals. zsh's `print -P` against the port's prompt-escape interpreter
# (_p9k_pe), byte for byte, for each TERM below: zsh uses terminfo's setaf /
# setab for colours 8 and above, the default colour where the terminal has
# too few, and 3N / 4N where terminfo gives no colour count.
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
terms=(xterm-256color xterm xterm-16color rxvt-88color screen screen-256color linux dumb vt100 tmux-256color)
strings=(
  '%F{0}a%F{7}b%F{8}c%F{9}d%F{15}e%F{16}f%F{87}g%F{88}h%F{231}i%F{255}j%F{256}k%f'
  '%K{0}a%K{7}b%K{8}c%K{9}d%K{15}e%K{16}f%K{87}g%K{88}h%K{231}i%K{255}j%K{256}k%k'
  '%F{red}a%K{blue}b%F{default}c%K{default}d%f%k'
  '%F{#ff8000}a%K{#102030}b%F{12}c%B%K{100}d%b%f%k'
  # (%NK is left out: zsh 5.8, here, makes it colour 0 - a bug fixed in 5.9,
  # which the port follows)
  '%4F%K{3}a%9F%K{10}b%200F%K{250}c%f%k'
  '%B%F{244}bold grey%b%F{196}red%U%K{24}u%u%s%f%k'
  '%F{009}a%K{ 12}b%f%k'
  # attributes re-applied after %B %b %u %s, in zsh's order
  '%S%F{3}%Ba%U%K{200}b%sc%ud%be%S%Uf%bg%u%s'
  '%B%U%S%F{#123456}%K{9}x%u%s%b%B%S%F{100}y%s%b%f%k'
)
pass=0 fail=0
for t in "${terms[@]}"; do
  i=0
  for s in "${strings[@]}"; do
    (( i++ ))
    z=$(TERM=$t zsh -fc 'print -nP -- "$1"' zsh "$s" | od -An -c | tr -s ' ')
    b=$(TERM=$t bash -c '. "$1/lib/p10k/main.bash"; _p9k__pe_mark=0 _p9k__pe_cont=0
      _p9k_pe "$2"; printf %s "$_p9k__pe"' bash "$root" "$s" | od -An -c | tr -s ' ')
    if [[ $z == "$b" ]]; then (( pass++ )); echo "SAME  $t #$i"
    else (( fail++ )); echo "DIFF  $t #$i  $s"; echo "   zsh:  $z"; echo "   bash: $b"
    fi
  done
done
echo "same: $pass   different: $fail"
