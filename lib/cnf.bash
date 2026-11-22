# =============================================================================
#  lib/cnf.bash - what happens when a command is not found, plus zmv.
#
#    alias_suffix txt=nano pdf=xdg-open   typing notes.txt runs nano notes.txt (zsh's alias -s)
#    unknown command                      "did you mean" + which package provides it
#    zmv 'PATTERN' 'TARGET'               bulk rename (zsh's zmv), via b4h-tool
# =============================================================================

_b4h_tool=$B4H_HOME/deps/bin/b4h-tool
[[ -x $_b4h_tool ]] || _b4h_tool=

# ---------------------------------------------------------- suffix aliases ---
declare -gA _b4h_suffix=()
alias_suffix() {
  local a
  if (( ! $# )); then
    for a in "${!_b4h_suffix[@]}"; do printf 'alias_suffix %s=%q\n' "$a" "${_b4h_suffix[$a]}"; done | sort
    return
  fi
  for a; do
    [[ $a == ?*=?* ]] || { echo "alias_suffix: use EXT=COMMAND" >&2; return 2; }
    _b4h_suffix[${a%%=*}]=${a#*=}
    # ble.sh also shows it as you type: "notes.txt " becomes "nano notes.txt ",
    # which works for paths with a / too (bash's not-found hook never sees those).
    (( _b4h_ble )) && ble-sabbrev -s "$a"
  done
}

# bash calls this (in a subshell) for any command it cannot find.
command_not_found_handle() {
  local cmd=$1 ext=${1##*.}
  if [[ $cmd == *?.?* && -n ${_b4h_suffix[$ext]-} && -e $cmd ]]; then
    eval "${_b4h_suffix[$ext]}"' "$@"'
    return
  fi

  printf 'bash: %s: command not found\n' "$cmd" >&2
  [[ $B4H_CNF_SUGGEST == yes ]] || return 127

  # Did you mean: names one or two typos away (PATH, aliases, functions, builtins).
  if [[ -n $_b4h_tool && $cmd != */* ]]; then
    local -a near
    mapfile -t near < <(compgen -A alias -A function -A builtin -A keyword |
                        grep -v '^_' | "$_b4h_tool" suggest "$cmd" 2>/dev/null)
    if (( ${#near[@]} )); then
      local list
      printf -v list '%s, ' "${near[@]}"
      if [[ -t 2 ]]; then printf '\e[33mdid you mean:\e[0m %s\n' "${list%, }" >&2
      else printf 'did you mean: %s\n' "${list%, }" >&2; fi
    fi
  fi

  # Which package provides it.
  if command -v pkgfile >/dev/null; then
    local pkgs; pkgs=$(pkgfile -b -- "$cmd" 2>/dev/null)
    [[ -n $pkgs ]] && printf '\e[33min package:\e[0m %s   (sudo pacman -S %s)\n' "${pkgs//$'\n'/, }" "${pkgs%%$'\n'*}" >&2
  elif [[ -x /usr/lib/command-not-found ]]; then
    /usr/lib/command-not-found --no-failure-msg -- "$cmd" >&2
  fi
  return 127
}

# --------------------------------------------------------------------- zmv ---
# The alias turns off filename expansion for the rest of the line, so the
# patterns reach zmv as typed even without quotes (zsh does the same with
# `noglob zmv`); the function turns it back on first thing.
_b4h_zmv() {
  set +f
  [[ -n $_b4h_tool ]] || { echo 'zmv: b4h-tool is not installed (b4h doctor)' >&2; return 1; }
  local -a dg=()
  shopt -q dotglob && dg=(--dotglob)
  "$_b4h_tool" mv "${dg[@]}" "$@"
}
alias zmv='set -f; _b4h_zmv'
