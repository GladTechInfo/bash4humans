# =============================================================================
#  lib/p10k/showcmd.bash - *_SHOW_ON_COMMAND: a segment is shown only while
#  the command line being typed runs one of the listed commands (e.g.
#  kubecontext only while typing kubectl or helm). Port of p10k's
#  _p9k_show_on_command (built in _p9k_init_prompt) and its use in
#  _p9k_widget_hook / _p9k_on_expand.
#
#  Each prompt starts with these segments hidden (the line is empty). Under
#  ble.sh the prompt is told that it depends on the line's text, so every
#  edit re-checks the commands (parser.bash) and redraws when a segment
#  appears or disappears. Plain readline has no such hook: there they stay
#  hidden, as on an empty line.
# =============================================================================

# _p9k_init_show_on_command -> _p9k_show_on_command: triples
#   PATTERN  (bash extended pattern for one parsed command)
#   unused   (p10k: an index into its display table)
#   NAME     (the display name LINE/SIDE/SEGMENT, as for `p10k display`)
_p9k_init_show_on_command() {
  declare -ga _p9k_show_on_command=()
  local i side elem var pat line
  for side in left right; do
    local -n _ls=_p9k_line_segments_$side
    i=0
    for line in "${_ls[@]}"; do
      (( i++ ))
      for elem in $line; do
        elem=${elem%_joined}; elem=${elem//-/_}
        var=_POWERLEVEL9K_${elem^^}_SHOW_ON_COMMAND
        _p9k_isset "$var" || continue
        local -n _cmds=$var
        local IFS='|'; pat="${_cmds[*]}"; unset IFS
        unset -n _cmds
        # zsh $'(|*[/\0])(cmd|cmd)'; the parser separates words with \x1f
        local us=$'\x1f'
        pat="@(|*[/$us])@(${pat//(/@(})"
        _p9k_show_on_command+=("$pat" 0 "$i/$side/$elem")
      done
    done
    unset -n _ls
  done
}

# Hide them all (a new prompt: nothing typed yet).
_p9k_show_on_command_reset() {
  local k
  for (( k = 0; k < ${#_p9k_show_on_command[@]}; k += 3 )); do
    _p9k_display_apply "${_p9k_show_on_command[k+2]}" hide
  done
  _p9k__soc_buffer=''
}

# Re-check against BUFFER; status 0 if any segment changed (show <-> hide).
_p9k_show_on_command_update() {
  [[ $1 == "${_p9k__soc_buffer-}" ]] && return 1
  _p9k__soc_buffer=$1
  local -a P9K_COMMANDS=()
  [[ -n $1 ]] && _p9k_parse_buffer "$1" "$_POWERLEVEL9K_COMMANDS_MAX_TOKEN_COUNT"
  local k c st changed=1 had=0
  shopt -q extglob && had=1; shopt -s extglob
  for (( k = 0; k < ${#_p9k_show_on_command[@]}; k += 3 )); do
    st=hide
    for c in "${P9K_COMMANDS[@]}"; do
      # shellcheck disable=SC2053
      [[ $c == ${_p9k_show_on_command[k]} ]] && { st=show; break; }
    done
    local v=${_p9k_show_on_command[k+2]}
    if [[ ${_p9k__display_v[$v]} != "$st" ]]; then _p9k_display_apply "$v" "$st"; changed=0; fi
  done
  (( had )) || shopt -u extglob
  return $changed
}
