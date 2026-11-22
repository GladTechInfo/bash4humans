# =============================================================================
#  lib/dirs.bash - directory history, as in z4h and fish.
#
#    Alt+Left / Alt+Right   back / forward (also: prevd, nextd)
#    Alt+Up / Alt+Down      parent / pick a subdirectory with fzf
#    Alt+R, cdh             pick a directory from the persistent history (fzf)
#    cd -<Tab>              the same directories as completions
#    dirh                   list this shell's back / forward history
#
#  The persistent history is shared by all shells, as zsh4humans' dir-history:
#  $B4H_HOME/dir-history, newest first, at most B4H_DIR_HISTORY_SIZE lines.
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
  [[ -n $to ]] || return 1
  cd -- "$to" || return
}

prevd() { _b4h_cd_back || echo 'prevd: no previous directory' >&2; }
nextd() { _b4h_cd_forward || echo 'nextd: no next directory' >&2; }

dirh() {
  local i
  for (( i = 0; i < ${#_b4h_back[@]}; i++ )); do printf '  %s\n' "${_b4h_back[i]}"; done
  printf '\e[1m> %s\e[0m\n' "$PWD"
  for (( i = ${#_b4h_fwd[@]} - 1; i >= 0; i-- )); do printf '  %s\n' "${_b4h_fwd[i]}"; done
}

# --------------------------------------------------- persistent history ---
_b4h_dirhist_file=$B4H_HOME/dir-history
_b4h_dirhist_last=

# Before each prompt (and after Alt+arrows): when the directory has changed,
# move it to the top of the file. Every shell does this, so the file holds
# the directories of all of them. `b4h private` shells leave it alone.
_b4h_dirhist_note() {
  [[ $PWD == "$_b4h_dirhist_last" ]] && return 0
  _b4h_dirhist_last=$PWD
  (( B4H_DIR_HISTORY_SIZE > 0 )) || return 0
  [[ -z ${B4H_PRIVATE-} && $PWD == /* && $PWD != *$'\n'* ]] || return 0
  # (byte-wise matching is faster, and exact for a fixed string)
  local LC_ALL=C s n tmp=$_b4h_dirhist_file.tmp.$$
  local -a l=()
  [[ -r $_b4h_dirhist_file ]] && mapfile -t l <"$_b4h_dirhist_file"
  n=${#l[@]}
  # one string, a newline before and after each line
  local IFS=$'\n'
  s=$'\n'"${l[*]}"$'\n'
  (( n )) || s=$'\n'
  # drop the directory where it was; the old count is one less if it was there
  local len=${#s}
  s=${s//$'\n'"$PWD"$'\n'/$'\n'}
  (( ${#s} == len )) || n=$(( n - 1 ))
  # newest first; one line too many (or more, if the size was lowered) goes
  while (( n + 1 > B4H_DIR_HISTORY_SIZE && n > 0 )); do
    s=${s%$'\n'*$'\n'}$'\n'
    n=$(( n - 1 ))
  done
  # write a new file in one go, then rename it: another shell never reads
  # half a file
  printf '%s' "$PWD$s" >"$tmp" 2>/dev/null && mv -f -- "$tmp" "$_b4h_dirhist_file" 2>/dev/null
  return 0
}

# The history as existing directories other than this one, newest first.
# The result is in the array _b4h_dirs.
_b4h_dirhist_list() {
  _b4h_dirs=()
  [[ -r $_b4h_dirhist_file ]] || return 0
  local -a l=()
  local d
  mapfile -t l <"$_b4h_dirhist_file"
  for d in "${l[@]}"; do
    [[ $d == /* && $d != "$PWD" && -d $d ]] && _b4h_dirs+=("$d")
  done
}

# Pick one with fzf (it shows ~ for the home directory) and go there.
_b4h_cd_history() {
  [[ -n $_b4h_fzf ]] || return 1
  local -a _b4h_dirs
  _b4h_dirhist_list
  (( ${#_b4h_dirs[@]} )) || return 1
  local d to
  # each line: the full path, a tab, what is shown; fzf shows field 2 only
  to=$(for d in "${_b4h_dirs[@]}"; do printf '%s\t%s\n' "$d" "${d/#"$HOME"/\~}"; done |
       "$_b4h_fzf" --height=40% --reverse --prompt='cd ' --delimiter=$'\t' --with-nth=2 \
                   --tiebreak=index --no-multi) || return 1
  to=${to%%$'\t'*}
  [[ -n $to ]] || return 1
  cd -- "$to" || return
}

cdh() {
  [[ -n $_b4h_fzf ]] || { echo 'cdh: needs fzf (b4h doctor)' >&2; return 1; }
  _b4h_cd_history
  return 0
}

# cd -<Tab>: the persistent history (zsh: the directory stack). ble.sh
# shows it as a menu; plain readline would only insert the paths' common
# start, so there fzf picks one (as zsh4humans does), as fzf's own **<Tab>
# does. Anything else goes to the completion cd had before.
_b4h_cd_comp_prev=
if _b4h_f=$(complete -p cd 2>/dev/null) && [[ $_b4h_f =~ -F\ ([^ ]+) ]]; then
  _b4h_cd_comp_prev=${BASH_REMATCH[1]}
fi
unset _b4h_f
_b4h_comp_cd() {
  if [[ ${COMP_WORDS[COMP_CWORD]} == - ]]; then
    local -a _b4h_dirs
    local d
    _b4h_dirhist_list
    COMPREPLY=()
    if (( ! _b4h_ble )) && [[ -n $_b4h_fzf ]]; then
      (( ${#_b4h_dirs[@]} )) || return 0
      local to
      to=$(for d in "${_b4h_dirs[@]}"; do printf '%s\t%s\n' "$d" "${d/#"$HOME"/\~}"; done |
           "$_b4h_fzf" --height=40% --reverse --prompt='cd ' --delimiter=$'\t' --with-nth=2 \
                       --tiebreak=index --no-multi)
      # readline redraws the line when the terminal answers this request
      # (ESC [ 0 n, bound to redraw-current-line in keys.bash)
      printf '\e[5n' >/dev/tty
      [[ -n $to ]] && printf -v 'COMPREPLY[0]' '%q' "${to%%$'\t'*}"
      return 0
    fi
    for d in "${_b4h_dirs[@]}"; do COMPREPLY+=("$(printf '%q' "$d")"); done
    compopt -o nosort 2>/dev/null
    return 0
  fi
  if [[ -n $_b4h_cd_comp_prev ]]; then
    "$_b4h_cd_comp_prev" "$@"
  else
    compopt -o filenames
    mapfile -t COMPREPLY < <(compgen -d -- "${COMP_WORDS[COMP_CWORD]}")
  fi
}
complete -o nospace -F _b4h_comp_cd cd
