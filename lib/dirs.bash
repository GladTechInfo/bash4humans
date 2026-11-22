# =============================================================================
#  lib/dirs.bash - directory history, as in z4h and fish.
#
#    Alt+Left / Alt+Right   back / forward (also: prevd, nextd)
#    Alt+Up / Alt+Down      parent / pick a subdirectory with fzf
#    dirh                   list the history
#    cdh                    pick a recent directory with fzf
# =============================================================================

_b4h_back=()
_b4h_fwd=()

# cd records where it came from. autocd ("type a directory name") and
# `cd -` go through here too.
cd() {
  local old=$PWD
  builtin cd "$@" || return
  if [[ $PWD != "$old" ]]; then
    _b4h_back+=("$old")
    _b4h_fwd=()
  fi
}

_b4h_cd_back() {    # returns 1 when there is nowhere to go
  (( ${#_b4h_back[@]} )) || return 1
  local to=${_b4h_back[-1]} from=$PWD
  builtin cd -- "$to" 2>/dev/null || return 1
  unset '_b4h_back[-1]'
  _b4h_fwd+=("$from")
}

_b4h_cd_forward() {
  (( ${#_b4h_fwd[@]} )) || return 1
  local to=${_b4h_fwd[-1]} from=$PWD
  builtin cd -- "$to" 2>/dev/null || return 1
  unset '_b4h_fwd[-1]'
  _b4h_back+=("$from")
}

_b4h_cd_up() { [[ $PWD != / ]] && cd ..; }

_b4h_cd_down() {    # one level of subdirectories, picked with fzf
  [[ -n $_b4h_fzf ]] || return 1
  local to
  to=$(find . -mindepth 1 -maxdepth 1 -type d -printf '%P\n' 2>/dev/null | sort |
       "$_b4h_fzf" --height=40% --reverse --prompt='cd ') || return 1
  [[ -n $to ]] && cd -- "$to"
}

prevd() { _b4h_cd_back || echo 'prevd: no previous directory' >&2; }
nextd() { _b4h_cd_forward || echo 'nextd: no next directory' >&2; }

dirh() {
  local i
  for (( i = 0; i < ${#_b4h_back[@]}; i++ )); do printf '  %s\n' "${_b4h_back[i]}"; done
  printf '\e[1m> %s\e[0m\n' "$PWD"
  for (( i = ${#_b4h_fwd[@]} - 1; i >= 0; i-- )); do printf '  %s\n' "${_b4h_fwd[i]}"; done
}

cdh() {
  [[ -n $_b4h_fzf ]] || { dirh; return; }
  local to
  to=$(printf '%s\n' "${_b4h_fwd[@]}" "${_b4h_back[@]}" | tac | awk 'NF && !seen[$0]++' |
       "$_b4h_fzf" --height=40% --reverse --prompt='cdh ') || return
  [[ -n $to ]] && cd -- "$to"
}
