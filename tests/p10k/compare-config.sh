#!/bin/bash
# tests/p10k/compare-config.sh ZSH_CONFIG BASH_CONFIG
# Source the original in zsh and the conversion in bash, list every
# POWERLEVEL9K_* variable as NAME=value or NAME[i]=value, and diff the lists.
#   -z FILE / -b FILE   print one side only (to check the dumps themselves)
dump_zsh() {
  zsh -f -c '
    function p10k() { :; }
    source "$1" >/dev/null 2>&1
    local v i
    for v in ${(k)parameters[(I)POWERLEVEL9K_*]}; do
      if [[ ${parameters[$v]} == array* ]]; then
        local -a a=("${(@P)v}")
        if (( ${#a} == 0 )); then print -r -- "${v}=()"; fi
        for (( i = 1; i <= ${#a}; i++ )); do print -r -- "${v}[$((i-1))]=${a[i]}"; done
      else
        print -r -- "${v}=${(P)v}"
      fi
    done' zsh "$1"
}
dump_bash() {
  bash --norc -c '
    _p9k_unset_config() { unset "${!POWERLEVEL9K_@}" DEFAULT_USER; }
    p10k() { :; }
    source "$1" >/dev/null 2>&1
    for v in "${!POWERLEVEL9K_@}"; do
      if [[ $(declare -p "$v") == "declare -a"* ]]; then
        eval "n=\${#$v[@]}"
        (( n == 0 )) && printf "%s=()\n" "$v"
        eval "for (( i = 0; i < n; i++ )); do printf \"%s[%s]=%s\n\" \"$v\" \"\$i\" \"\${$v[i]}\"; done"
      else
        printf "%s=%s\n" "$v" "${!v}"
      fi
    done' bash "$1"
}
case $1 in
  -z) dump_zsh "$2" | LC_ALL=C sort ;;
  -b) dump_bash "$2" | LC_ALL=C sort ;;
  *)  diff <(dump_zsh "$1" | LC_ALL=C sort) <(dump_bash "$2" | LC_ALL=C sort) ;;
esac
