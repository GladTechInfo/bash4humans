# =============================================================================
#  lib/p10k/command.bash - the `p10k` command and custom_* segments.
#  Port of p10k's `function p10k` and _p9k_custom_prompt. The help texts are
#  p10k's own (data.bash), printed through the prompt-escape interpreter.
# =============================================================================

# print -rP equivalent: zsh prompt escapes -> terminal codes, plus a newline
_p9k_print_p() { _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$1"; printf '%s\n' "$_p9k__pe"; }

p10k() {
  # p10k: `p10k finalize` alone is handled before anything else
  if [[ $# == 1 && $1 == finalize ]]; then _p9k_instant_prompt_finalize; return 0; fi
  if (( ! $# )); then _p9k_print_p "$_p9k_p10k_usage" >&2; return 1; fi
  case $1 in
    finalize)
      _p9k_print_p "$_p9k_p10k_finalize_usage" >&2
      return 1 ;;
    clear-instant-prompt)
      declare -F _p9k_clear_instant_prompt >/dev/null && _p9k_clear_instant_prompt
      return 0 ;;
    segment)
      shift
      local state='' bg=0 fg='' icon='' cond='' text='' ref=0 expand=0 a
      # options as p10k's zsh getopts ':s:b:f:i:c:t:reh' (with +r / +e)
      while (( $# )); do
        a=$1
        case $a in
          -s|-b|-f|-i|-c|-t)
            (( $# >= 2 )) || { _p9k_print_p "$_p9k_p10k_segment_usage" >&2; return 1; }
            case $a in
              -s) state=$2 ;; -b) bg=$2 ;; -f) fg=$2 ;; -i) icon=$2 ;; -t) text=$2 ;;
              -c) cond=${2:-'${_p9k__never-}'} ;;   # p10k: an empty condition is '${:-}'
            esac
            shift 2 ;;
          -s?*|-b?*|-f?*|-i?*|-c?*|-t?*) set -- "${a:0:2}" "${a:2}" "${@:2}" ;;
          -r) ref=1; shift ;;  +r) ref=0; shift ;;
          -e) expand=1; shift ;; +e) expand=0; shift ;;
          -h) _p9k_print_p "$_p9k_p10k_segment_usage"; return 0 ;;
          -[re][re]*|+[re][re]*) set -- "${a:0:2}" "${a:0:1}${a:2}" "${@:2}" ;;
          *) _p9k_print_p "$_p9k_p10k_segment_usage" >&2; return 1 ;;
        esac
      done
      if [[ -z ${_p9k__prompt_side-} ]]; then
        _p9k_print_p "%1F[ERROR]%f %Bp10k segment%b: can be called only during prompt rendering." >&2
        return 1
      fi
      (( ref )) || icon=$'\1'$icon
      local st=''; [[ -n $state ]] && st=_${state^^}
      "_p9k_${_p9k__prompt_side}_prompt_segment" "prompt_${_p9k__segment_name}$st" \
        "$bg" "${fg:-$_p9k_color1}" "$icon" "$expand" "$cond" "$text"
      return 0 ;;
    help)
      local var=_p9k_p10k_${2-}_usage
      if [[ -n ${2-} ]] && _p9k_isset "$var"; then _p9k_print_p "${!var}"; return 0
      elif (( $# == 1 )); then _p9k_print_p "$_p9k_p10k_usage"; return 0
      else _p9k_print_p "$_p9k_p10k_usage" >&2; return 1
      fi ;;
    *)
      if declare -F "_p9k_p10k_cmd_$1" >/dev/null; then "_p9k_p10k_cmd_$1" "${@:2}"; return; fi
      _p9k_print_p "$_p9k_p10k_usage" >&2
      return 1 ;;
  esac
}

# p10k: p10k-instant-prompt-finalize, "the final stage of initialization",
# called at the very end of the rc file. In zsh it sets prompt_cr/prompt_sp
# according to whether instant prompt is active; bash has neither option, and
# the instant prompt (bash4humans) hooks in here when it is active.
_p9k_instant_prompt_finalize() {
  declare -F _p9k_instant_prompt_finalize_hook >/dev/null && _p9k_instant_prompt_finalize_hook
  return 0
}

# p10k reload: re-read the settings before the next prompt (only once p10k
# has been initialised; p10k_init creates _p9k__force_must_init).
_p9k_p10k_cmd_reload() {
  if (( $# )); then _p9k_print_p "$_p9k_p10k_reload_usage" >&2; return 1; fi
  _p9k_isset _p9k__force_must_init || return 0
  _p9k__force_must_init=1
}

# custom_NAME: POWERLEVEL9K_CUSTOM_NAME is a command line; its output is the
# content (shown only if non-empty; the first word must be a function or a
# command). Colours: p10k's color2 background, color1 foreground.
_p9k_custom_prompt() {
  local name=${1^^} v=_POWERLEVEL9K_CUSTOM_${1^^}
  local command=${!v-}
  [[ -n $command ]] || return 0
  local -a w; read -r -a w <<<"$command"
  _p9k_unquote "${w[0]-}"; local cmd=$_p9k__ret
  declare -F "$cmd" >/dev/null || type -P "$cmd" >/dev/null || return 0
  local content; content=$(eval "$command")
  [[ -n $content ]] || return 0
  _p9k_prompt_segment "prompt_custom_$1" "$_p9k_color2" "$_p9k_color1" "CUSTOM_${name}_ICON" 0 '' "$content"
}

# ---------------------------------------------------------------- display ---
# p10k: _p9k_init_display. The parts that `p10k display` names, in p10k's
# order: empty_line, ruler, then for each line N (also as N-n-1, e.g. -1 for
# the last line): N, N/left_frame, N/right_frame, N/left, N/right, N/gap,
# N/left/SEGMENT..., N/right/SEGMENT...
#   _p9k_display_names  the names in that order (negative forms included)
#   _p9k_display_canon  name -> its positive form
#   _p9k__display_v     positive name -> show | hide | print
_p9k_init_display() {
  declare -ga _p9k_display_names=(empty_line ruler)
  declare -gA _p9k_display_canon=([empty_line]=empty_line [ruler]=ruler)
  # (p10k starts both as hide; before each prompt the enabled ones are set)
  declare -gA _p9k__display_v=([empty_line]=hide [ruler]=hide)
  local n=${#_p9k_line_segments_left[@]} i j part name
  for (( i = 1; i <= n; i++ )); do
    j=$(( i - n - 1 ))
    for part in '' /left_frame /right_frame /left /right /gap; do
      _p9k_display_add "$i$part" "$j$part"
    done
    for name in ${_p9k_line_segments_left[i-1]}; do _p9k_display_add "$i/left/${name%_joined}" "$j/left/${name%_joined}"; done
    for name in ${_p9k_line_segments_right[i-1]}; do _p9k_display_add "$i/right/${name%_joined}" "$j/right/${name%_joined}"; done
  done
}
_p9k_display_add() {
  _p9k_display_names+=("$1" "$2")
  _p9k_display_canon[$1]=$1 _p9k_display_canon[$2]=$1
  _p9k__display_v[$1]=show
}

# Apply VALUE to the positive name: the variable the renderer reads
# (p10k: _p9k__N, _p9k__Nl, _p9k__Nr_frame, _p9k__Ng, _p9k__Nl<segment>).
_p9k_display_apply() {
  local name=$1 new=$2 var
  _p9k__display_v[$name]=$new
  [[ $name == empty_line || $name == ruler ]] && return 0
  local num=${name%%/*} rest=${name#"${name%%/*}"}
  rest=${rest//\//}; rest=${rest/#left/l}; rest=${rest/#right/r}; rest=${rest/#gap/g}
  var=_p9k__$num$rest
  if [[ $new == hide ]]; then printf -v "$var" '%s' ''; else unset "$var"; fi
}

# p10k display [-a] [-r] [-h] [NAME=VALUE[,VALUE...]]...
#   NAME may be a pattern (e.g. '*/right', '1/left/*'); with several values
#   each call moves to the next one (cycling); -a: reply=(name value ...);
#   -r: redraw the prompt now.
_p9k_p10k_cmd_display() {
  if (( ! $# )); then _p9k_print_p "$_p9k_p10k_display_usage" >&2; return 1; fi
  local redraw=0 dump=0 opt
  while (( $# )) && [[ $1 == -* ]]; do
    case $1 in
      -r) redraw=1 ;; -a) dump=1 ;;
      -h) _p9k_print_p "$_p9k_p10k_display_usage"; return 0 ;;
      -[arh]*) set -- "${1:0:2}" "-${1:2}" "${@:2}"; continue ;;
      *) _p9k_print_p "$_p9k_p10k_display_usage" >&2; return 1 ;;
    esac
    shift
  done
  local k name changed=0
  if (( dump )); then
    reply=()
    (( $# )) || set -- '*'
    # zsh lists matching keys of its table in hash order; positive names only once
    _p9k_zsh_key_order "${_p9k_display_names[@]}"
    local -A seen=()
    for opt; do
      for k in "${_p9k__keys[@]}"; do
        # shellcheck disable=SC2053
        [[ $k == $opt ]] || continue
        name=${_p9k_display_canon[$k]}
        [[ -n ${seen[$name]-} ]] && continue
        seen[$name]=1
        reply+=("$name" "${_p9k__display_v[$name]}")
      done
    done
    (( redraw )) && _p9k_display_redraw
    return 0
  fi
  local pair pat vals cur new i
  for pair; do
    pat=${pair%%=*} vals=${pair#*=}
    local -a list=(); IFS=, read -r -a list <<<"$vals"
    local -A done_=()
    for k in "${_p9k_display_names[@]}"; do
      # shellcheck disable=SC2053
      [[ $k == $pat ]] || continue
      name=${_p9k_display_canon[$k]}
      [[ -n ${done_[$name]-} ]] && continue
      done_[$name]=1
      cur=${_p9k__display_v[$name]}
      # the value after the current one in the list (the first if absent)
      new=${list[0]-}
      for (( i = ${#list[@]} - 1; i >= 0; i-- )); do
        if [[ ${list[i]} == "$cur" ]]; then new=${list[i+1]:-${list[0]}}; break; fi
      done
      [[ $new == "$cur" ]] && continue
      _p9k_display_apply "$name" "$new"
      changed=1
    done
  done
  (( changed || redraw )) && _p9k_display_redraw
  return 0
}

# A display change: rebuild the prompt from the recorded segments (under
# ble.sh it is redrawn at once; at a readline prompt from the next one).
_p9k_display_redraw() {
  (( ${_p9k__initialized:-0} )) || return 0
  (( _p9k__display_gen++ ))
  # inside a hook run while the prompt is drawn, the caller redraws
  [[ -n ${_p9k__in_hook-} || -n ${_p9k__prompt_side-} ]] && return 0
  _p9k_replay_render
}
