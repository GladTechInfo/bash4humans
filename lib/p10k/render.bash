# =============================================================================
#  lib/p10k/render.bash - drawing segments and assembling prompt lines.
#
#  Ports of p10k's _p9k_left_prompt_segment, _p9k_right_prompt_segment,
#  _p9k_init_lines, _p9k_build_gap_post and _p9k_set_prompt. p10k compiles
#  these into zsh code that runs at prompt time; here they run directly, with
#  the same rules, and produce a string of zsh prompt escapes that
#  _p9k_pe (core.bash) turns into terminal codes.
# =============================================================================

# --------------------------------------------------------------- expansion ---
# Evaluate a p10k *_EXPANSION string -> _p9k__x.
# Supports p10k's idiom ${$((func(args)))+REST}: call func, then use REST.
_p9k_expand() {
  local s=$1 re='\$\{\$\(\(([A-Za-z_][A-Za-z0-9_]*)\(([^)]*)\)\)\)\+'
  while [[ $s =~ $re ]]; do
    local whole=${BASH_REMATCH[0]} fn=${BASH_REMATCH[1]} args=${BASH_REMATCH[2]}
    local pre=${s%%"$whole"*}
    local post=${s:$(( ${#pre} + ${#whole} ))}
    # find the } that closes this ${
    local depth=1 i c
    for (( i = 0; i < ${#post}; i++ )); do
      c=${post:i:1}
      if [[ $c == '\' ]]; then (( i++ )); continue; fi
      if [[ $c == '{' ]]; then (( depth++ )); elif [[ $c == '}' ]]; then (( --depth == 0 )) && break; fi
    done
    if declare -F "$fn" >/dev/null; then
      if [[ -n $args ]]; then "$fn" $(( args )); else "$fn"; fi
    fi
    s=$pre${post:0:i}${post:i+1}
  done
  [[ $s == *'$'* || $s == *'`'* ]] || { _p9k__x=$s; return; }
  eval "_p9k__x=\"$s\"" 2>/dev/null || _p9k__x=$s
}

# Visible width of a prompt-escape string -> _p9k__ret
_p9k_prompt_length() { _p9k_pe "$1"; _p9k__ret=$_p9k__pw; }

# ------------------------------------------------------------- left side ---
# p10k: _p9k_left_prompt_segment NAME BG FG ICON EXPAND COND CONTENT
_p9k_left_prompt_segment() {
  local name=$1
  # display hidden with `p10k display`?
  # hidden by `p10k display` or SHOW_ON_COMMAND (p10k: the variable is set)
  local disp=_p9k__${_p9k__line_index}l${_p9k__segment_name}
  [[ -n ${!disp+x} ]] && return 0
  # SHOW_ON_UPGLOB: only if a matching file is here or in a parent directory
  _p9k_param "$name" SHOW_ON_UPGLOB ''
  if [[ -n $_p9k__ret ]]; then _p9k_upglob "$_p9k__ret" && return 0; fi

  if [[ -n ${6-} ]]; then
    _p9k_expand "$6"; [[ -n $_p9k__x ]] || return 0
  fi

  local ck="L$name"$'\1'"$2"$'\1'"$3"$'\1'"$4"$'\1'"$_p9k__segment_index"
  local bg_color fg_color bg fg style sep subsep icon start_sep end_sep left_space right_space
  local icon_exp content_exp icon_before prefix suffix vi_color mid self_joined
  if [[ -v _p9k_segc[$ck] ]]; then
    eval "${_p9k_segc[$ck]}"
  else
    _p9k_color "$name" BACKGROUND "$2"; bg_color=$_p9k__ret
    _p9k_background "$bg_color"; bg=$_p9k__ret
    _p9k_color "$name" FOREGROUND "$3"; fg_color=$_p9k__ret
    _p9k_foreground "$fg_color"; fg=$_p9k__ret
    style="%b$bg$fg"
    _p9k_get_icon "$name" LEFT_SEGMENT_SEPARATOR; sep=$_p9k__ret
    _p9k_get_icon "$name" LEFT_SUBSEGMENT_SEPARATOR; subsep=$_p9k__ret
    icon=
    if [[ -n $4 ]]; then _p9k_get_icon "$name" "$4"; icon=$_p9k__ret; fi
    _p9k_get_icon "$name" LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL; start_sep=$_p9k__ret
    [[ -n $start_sep ]] && start_sep="%b%k%F{$bg_color}$start_sep"
    _p9k_get_icon "$name" LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL "$sep"; end_sep=$_p9k__ret
    _p9k_get_icon "$name" WHITESPACE_BETWEEN_LEFT_SEGMENTS ' '; local space=$_p9k__ret
    _p9k_get_icon "$name" LEFT_LEFT_WHITESPACE "$space"; left_space=$_p9k__ret
    [[ $left_space == *%* ]] && left_space+=$style
    _p9k_get_icon "$name" LEFT_RIGHT_WHITESPACE "$space"; right_space=$_p9k__ret
    [[ $right_space == *%* ]] && right_space+=$style
    _p9k_param "$name" VISUAL_IDENTIFIER_EXPANSION '${P9K_VISUAL_IDENTIFIER}'; icon_exp=$_p9k__ret
    _p9k_param "$name" CONTENT_EXPANSION '${P9K_CONTENT}'; content_exp=$_p9k__ret
    _p9k_param "$name" ICON_BEFORE_CONTENT ''; icon_before=$_p9k__ret
    _p9k_param "$name" PREFIX ''; prefix=${_p9k__ret@E}
    _p9k_param "$name" SUFFIX ''; suffix=${_p9k__ret@E}
    _p9k_color "$name" VISUAL_IDENTIFIER_COLOR "$fg_color"; _p9k_foreground "$_p9k__ret"; vi_color=$_p9k__ret
    _p9k_get_icon "$name" LEFT_MIDDLE_WHITESPACE ' '; mid=$_p9k__ret
    _p9k_param "$name" SELF_JOINED false; self_joined=$_p9k__ret
    _p9k_segc[$ck]=$(declare -p bg_color fg_color bg fg style sep subsep icon start_sep end_sep \
      left_space right_space icon_exp content_exp icon_before prefix suffix vi_color mid self_joined \
      | sed 's/^declare -- //; s/^declare -[a-z]* //')
  fi

  # content and icon
  local P9K_CONTENT=$7 P9K_VISUAL_IDENTIFIER=$icon c v
  if [[ $5 == 1 ]]; then _p9k_expand "$7"; P9K_CONTENT=$_p9k__x; fi
  if [[ $icon_exp == '${P9K_VISUAL_IDENTIFIER}' ]]; then v=$icon; else _p9k_expand "$icon_exp"; v=$_p9k__x; fi
  if [[ $content_exp == '${P9K_CONTENT}' ]]; then c=$P9K_CONTENT; else _p9k_expand "$content_exp"; c=$_p9k__x; fi
  c=${c//$'\r'/}
  local e=0
  _p9k_prompt_length "$c"; (( _p9k__ret )) && e=1
  _p9k_prompt_length "$v"; (( _p9k__ret )) && e=$(( e * 10 + 1 )) || e=$(( e * 10 ))
  (( e == 0 )) && return 0          # neither content nor icon: not shown
  local has_c=$(( e >= 10 )) has_v=$(( e % 10 ))

  # opening: first on the line / joined / same background / new background
  local open
  local joined=0
  local jl=${_p9k_left_join[_p9k__segment_index]}
  if [[ $self_joined == false ]]; then
    (( _p9k__segment_index > jl && _p9k__i >= jl && _p9k__i < _p9k__segment_index )) && joined=1
  else
    (( _p9k__i >= jl )) && joined=1
  fi
  if [[ $_p9k__bg == NONE ]]; then
    open=$start_sep$style$left_space
  elif (( joined )); then
    open=$style
  elif [[ $bg_color == "$_p9k__bg" || $bg_color == "${_p9k__bg:-0}" ]]; then
    if [[ -n $fg_color && $fg_color == "$bg_color" ]]; then
      if [[ $fg_color == "$_p9k_color1" ]]; then _p9k_foreground "$_p9k_color2"; else _p9k_foreground "$_p9k_color1"; fi
      open="%b$bg$_p9k__ret$_p9k__ss$style$left_space"
    else
      open="%b$bg$_p9k__ss$style$left_space"
    fi
  else
    open="%b$bg$_p9k__s$style$left_space"
  fi

  local p=$open
  if [[ $icon_before != false ]]; then
    p+=$prefix; [[ $prefix == *%* ]] && local need_style=1 || local need_style=0
    if (( has_v )); then
      local vs="%b$bg$vi_color"
      if [[ $vs != "$style" ]]; then p+="$vs$v$style"
      else (( need_style )) && p+=$style; p+=$v
      fi
      (( has_c && has_v )) && p+=$mid
    elif (( need_style )); then
      p+=$style
    fi
    p+="$c$style"
  else
    p+=$prefix; [[ $prefix == *%* ]] && p+=$style
    p+="$c$style"
    if (( has_v )); then
      (( has_c && has_v )) && p+=$mid
      local vs="%b$bg$vi_color"
      [[ $vs != "$style" ]] && p+=$vs
      p+=$v
    fi
  fi
  p+=$suffix
  [[ $suffix == *%* && -n $right_space ]] && p+=$style
  p+=$right_space

  _p9k__prompt+=$p
  _p9k__s="%F{$bg_color}$sep" _p9k__ss=$subsep _p9k__sss="%F{$bg_color}$end_sep"
  _p9k__i=$_p9k__segment_index _p9k__bg=$bg_color
}

# ------------------------------------------------------------ right side ---
# p10k: _p9k_right_prompt_segment NAME BG FG ICON EXPAND COND CONTENT
_p9k_right_prompt_segment() {
  local name=$1
  # SHOW_ON_UPGLOB: only if a matching file is here or in a parent directory
  _p9k_param "$name" SHOW_ON_UPGLOB ''
  if [[ -n $_p9k__ret ]]; then _p9k_upglob "$_p9k__ret" && return 0; fi
  # From here on p10k has emitted code for this segment, even if it expands
  # to nothing: the line then has a right part (and a gap). See _p9k_set_prompt.
  _p9k__rcode=1
  # hidden by `p10k display` or SHOW_ON_COMMAND (p10k: the variable is set)
  local disp=_p9k__${_p9k__line_index}r${_p9k__segment_name}
  [[ -n ${!disp+x} ]] && return 0

  if [[ -n ${6-} ]]; then
    _p9k_expand "$6"; [[ -n $_p9k__x ]] || return 0
  fi

  local ck="R$name"$'\1'"$2"$'\1'"$3"$'\1'"$4"$'\1'"$_p9k__segment_index"
  local bg_color fg_color bg fg style sep subsep icon start_sep end_sep left_space right_space
  local icon_exp content_exp icon_before prefix suffix vi_color mid self_joined
  if [[ -v _p9k_segc[$ck] ]]; then
    eval "${_p9k_segc[$ck]}"
  else
    _p9k_color "$name" BACKGROUND "$2"; bg_color=$_p9k__ret
    _p9k_background "$bg_color"; bg=$_p9k__ret
    _p9k_color "$name" FOREGROUND "$3"; fg_color=$_p9k__ret
    _p9k_foreground "$fg_color"; fg=$_p9k__ret
    style="%b$bg$fg"
    _p9k_get_icon "$name" RIGHT_SEGMENT_SEPARATOR; sep=$_p9k__ret
    _p9k_get_icon "$name" RIGHT_SUBSEGMENT_SEPARATOR; subsep=$_p9k__ret
    [[ $subsep == *%* ]] && subsep+=$style
    icon=
    if [[ -n $4 ]]; then _p9k_get_icon "$name" "$4"; icon=$_p9k__ret; fi
    _p9k_get_icon "$name" RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL "$sep"; start_sep=$_p9k__ret
    [[ -n $start_sep ]] && start_sep="%b%k%F{$bg_color}$start_sep"
    _p9k_get_icon "$name" RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL; end_sep=$_p9k__ret
    _p9k_get_icon "$name" WHITESPACE_BETWEEN_RIGHT_SEGMENTS ' '; local space=$_p9k__ret
    _p9k_get_icon "$name" RIGHT_LEFT_WHITESPACE "$space"; left_space=$_p9k__ret
    [[ $left_space == *%* ]] && left_space+=$style
    _p9k_get_icon "$name" RIGHT_RIGHT_WHITESPACE "$space"; right_space=$_p9k__ret
    [[ $right_space == *%* ]] && right_space+=$style
    _p9k_param "$name" VISUAL_IDENTIFIER_EXPANSION '${P9K_VISUAL_IDENTIFIER}'; icon_exp=$_p9k__ret
    _p9k_param "$name" CONTENT_EXPANSION '${P9K_CONTENT}'; content_exp=$_p9k__ret
    _p9k_param "$name" ICON_BEFORE_CONTENT ''; icon_before=$_p9k__ret
    _p9k_param "$name" PREFIX ''; prefix=${_p9k__ret@E}
    _p9k_param "$name" SUFFIX ''; suffix=${_p9k__ret@E}
    _p9k_color "$name" VISUAL_IDENTIFIER_COLOR "$fg_color"; _p9k_foreground "$_p9k__ret"; vi_color=$_p9k__ret
    _p9k_get_icon "$name" RIGHT_MIDDLE_WHITESPACE ' '; mid=$_p9k__ret
    _p9k_param "$name" SELF_JOINED false; self_joined=$_p9k__ret
    _p9k_segc[$ck]=$(declare -p bg_color fg_color bg fg style sep subsep icon start_sep end_sep \
      left_space right_space icon_exp content_exp icon_before prefix suffix vi_color mid self_joined \
      | sed 's/^declare -- //; s/^declare -[a-z]* //')
  fi

  local P9K_CONTENT=$7 P9K_VISUAL_IDENTIFIER=$icon c v
  if [[ $5 == 1 ]]; then _p9k_expand "$7"; P9K_CONTENT=$_p9k__x; fi
  if [[ $icon_exp == '${P9K_VISUAL_IDENTIFIER}' ]]; then v=$icon; else _p9k_expand "$icon_exp"; v=$_p9k__x; fi
  if [[ $content_exp == '${P9K_CONTENT}' ]]; then c=$P9K_CONTENT; else _p9k_expand "$content_exp"; c=$_p9k__x; fi
  c=${c//$'\r'/}
  local has_c=0 has_v=0
  _p9k_prompt_length "$c"; (( _p9k__ret )) && has_c=1
  _p9k_prompt_length "$v"; (( _p9k__ret )) && has_v=1
  (( has_c || has_v )) || return 0

  local joined=0 jr=${_p9k_right_join[_p9k__segment_index]}
  if [[ $self_joined == false ]]; then
    (( _p9k__segment_index > jr && _p9k__i >= jr && _p9k__i < _p9k__segment_index )) && joined=1
  else
    (( _p9k__i >= jr )) && joined=1
  fi
  local p
  if [[ $_p9k__bg == NONE ]]; then
    p=$start_sep$style$left_space
  elif (( joined )); then
    p=$_p9k__w$style
  elif [[ $_p9k__bg == "$bg_color" || $_p9k__bg == "${bg_color:-0}" ]]; then
    p=$_p9k__w$style$subsep$left_space
  else
    p="$_p9k__w%F{$bg_color}$sep$style$left_space"
  fi

  if [[ $icon_before != true ]]; then
    p+=$prefix; [[ $prefix == *%* ]] && p+=$style
    p+="$c$style"
    if (( has_v )); then
      local need_style=0
      (( has_c )) && { p+=$mid; [[ $mid == *%* ]] && need_style=1; }
      local vs="%b$bg$vi_color"
      [[ $vs != "$style" || $need_style == 1 ]] && p+=$vs
      p+=$v
    fi
  else
    p+=$prefix; [[ $prefix == *%* ]] && local need_style=1 || local need_style=0
    if (( has_v )); then
      local vs="%b$bg$vi_color"
      if [[ $vs != "$style" ]]; then p+="$vs$v$style"
      else (( need_style )) && p+=$style; p+=$v
      fi
      if (( has_c )); then p+=$mid; [[ $mid == *%* ]] && p+=$style; fi
    elif (( need_style )); then
      p+=$style
    fi
    p+="$c$style"
  fi
  p+=$suffix

  local wfg
  if [[ -n $fg_color && $fg_color == "$bg_color" ]]; then
    if [[ $fg_color == "$_p9k_color1" ]]; then _p9k_foreground "$_p9k_color2"; else _p9k_foreground "$_p9k_color1"; fi
    wfg=$_p9k__ret
  else
    wfg=$fg
  fi
  _p9k__w="${right_space:+$style}$right_space%b$bg$wfg"
  _p9k__sss=$style$right_space
  [[ $right_space == *%* ]] && _p9k__sss+=$style
  [[ -n $end_sep ]] && _p9k__sss+="%k%F{$bg_color}$end_sep$style"
  _p9k__prompt+=$p
  _p9k__i=$_p9k__segment_index _p9k__bg=$bg_color
}

# Every call is also recorded per segment position, so that a keymap change can
# redraw the prompt by replaying the recorded calls instead of running the
# segments again (see _p9k_call_segment and _p9k_redraw_keymap in main.bash).
_p9k_prompt_segment() {
  if (( ! _p9k__replay )); then
    local q; printf -v q '%q ' "$@"
    _p9k__rec[$_p9k__prompt_side$_p9k__segment_index]+=$q$'\n'
  fi
  # _p9k_vcs_refresh only replaces the recording; the replay draws it
  (( ${_p9k__record_only:-0} )) && return 0
  "_p9k_${_p9k__prompt_side}_prompt_segment" "$@"
}

# ------------------------------------------------------------------ lines ---
# p10k: _p9k_init_lines (+ the gap, ruler and join setup of _p9k_init_prompt)
_p9k_init_lines() {
  local -a left=("${_POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[@]}") right=("${_POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[@]}")
  (( _POWERLEVEL9K_PROMPT_ON_NEWLINE )) && left+=(newline _p9k_internal_nothing)
  local s nl=1 nr=1
  for s in "${left[@]}";  do [[ $s == newline ]] && (( nl++ )); done
  for s in "${right[@]}"; do [[ $s == newline ]] && (( nr++ )); done
  local i num_lines
  if (( nr > nl )); then
    for (( i = 0; i < nr - nl; i++ )); do left=(newline "${left[@]}"); done
    num_lines=$nr
  else
    if (( _POWERLEVEL9K_RPROMPT_ON_NEWLINE )); then
      for (( i = 0; i < nl - nr; i++ )); do right=(newline "${right[@]}"); done
    else
      for (( i = 0; i < nl - nr; i++ )); do right+=(newline); done
    fi
    num_lines=$nl
  fi
  _p9k_num_lines=$num_lines

  declare -ga _p9k_line_segments_left=() _p9k_line_segments_right=()
  local cur=''
  for s in "${left[@]}"; do
    if [[ $s == newline ]]; then _p9k_line_segments_left+=("$cur"); cur=''; else cur+="$s "; fi
  done
  _p9k_line_segments_left+=("$cur")
  cur=''
  for s in "${right[@]}"; do
    if [[ $s == newline ]]; then _p9k_line_segments_right+=("$cur"); cur=''; else cur+="$s "; fi
  done
  _p9k_line_segments_right+=("$cur")

  # join indices: a *_joined segment joins the group of the segment before it
  declare -ga _p9k_left_join=(0) _p9k_right_join=(0)
  local -a all=() idx
  for cur in "${_p9k_line_segments_left[@]}"; do all+=($cur); done
  _p9k_left_join+=(1)
  for (( i = 2; i <= ${#all[@]}; i++ )); do
    if [[ ${all[i-1]} == *_joined ]]; then _p9k_left_join+=("${_p9k_left_join[i-1]}"); else _p9k_left_join+=("$i"); fi
  done
  all=()
  for cur in "${_p9k_line_segments_right[@]}"; do all+=($cur); done
  _p9k_right_join+=(1)
  for (( i = 2; i <= ${#all[@]}; i++ )); do
    if [[ ${all[i-1]} == *_joined ]]; then _p9k_right_join+=("${_p9k_right_join[i-1]}"); else _p9k_right_join+=("$i"); fi
  done

  # per-line prefixes and suffixes
  declare -ga _p9k_line_sss_left=() _p9k_line_sss_right=() _p9k_line_never_empty_right=()
  declare -ga _p9k_line_frame_left=() _p9k_line_frame_right=()
  _p9k_get_icon '' LEFT_SEGMENT_SEPARATOR
  _p9k_get_icon prompt_empty_line LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL "$_p9k__ret"
  local empty_end=$_p9k__ret
  local empty_start=${_POWERLEVEL9K_EMPTY_LINE_RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL-}
  empty_start=${empty_start@E}
  for (( i = 1; i <= num_lines; i++ )); do
    _p9k_line_sss_left[i]="%f$empty_end"
    _p9k_line_sss_right[i]=$empty_start
    [[ -n $empty_start ]] && _p9k_line_never_empty_right[i]=1 || _p9k_line_never_empty_right[i]=0
    _p9k_line_frame_left[i]='' _p9k_line_frame_right[i]=''
  done
  if (( num_lines > 0 )); then
    _p9k_prompt_length "$empty_start"
    (( _p9k__ret )) || _p9k_line_never_empty_right[num_lines]=0
  fi

  _p9k_get_icon '' LEFT_SEGMENT_END_SEPARATOR
  _p9k_line_end_left=''
  [[ -n $_p9k__ret ]] && _p9k_line_end_left="$_p9k__ret%b%k%f"
  _p9k_line_end_left_idx=$num_lines
  (( _POWERLEVEL9K_PROMPT_ON_NEWLINE )) && _p9k_line_end_left_idx=$(( num_lines - 1 ))

  if (( num_lines > 1 )); then
    local v
    if [[ -v _POWERLEVEL9K_MULTILINE_FIRST_PROMPT_PREFIX ]] || (( _POWERLEVEL9K_PROMPT_ON_NEWLINE )); then
      _p9k_get_icon '' MULTILINE_FIRST_PROMPT_PREFIX; v=$_p9k__ret
      [[ $v == *%* ]] && v+='%b%k%f'
      _p9k_line_frame_left[1]=$v
    fi
    if [[ -v _POWERLEVEL9K_MULTILINE_LAST_PROMPT_PREFIX ]] || (( _POWERLEVEL9K_PROMPT_ON_NEWLINE )); then
      _p9k_get_icon '' MULTILINE_LAST_PROMPT_PREFIX; v=$_p9k__ret
      [[ $v == *%* ]] && v+='%b%k%f'
      _p9k_line_frame_left[num_lines]=$v
    fi
    _p9k_get_icon '' MULTILINE_FIRST_PROMPT_SUFFIX; v=$_p9k__ret
    if [[ -n $v ]]; then
      [[ $v == *%* ]] && v+='%b%k%f'
      _p9k_line_frame_right[1]=$v; _p9k_line_never_empty_right[1]=1
    fi
    _p9k_get_icon '' MULTILINE_LAST_PROMPT_SUFFIX; v=$_p9k__ret
    if [[ -n $v ]]; then
      [[ $v == *%* ]] && v+='%b%k%f'
      _p9k_line_frame_right[num_lines]=$v
      _p9k_prompt_length "$v"; (( _p9k__ret )) && _p9k_line_never_empty_right[num_lines]=1
    fi
    if (( num_lines > 2 )); then
      if [[ -v _POWERLEVEL9K_MULTILINE_NEWLINE_PROMPT_PREFIX ]] || (( _POWERLEVEL9K_PROMPT_ON_NEWLINE )); then
        _p9k_get_icon '' MULTILINE_NEWLINE_PROMPT_PREFIX; v=$_p9k__ret
        if [[ -n $v ]]; then
          [[ $v == *%* ]] && v+='%b%k%f'
          for (( s = 2; s < num_lines; s++ )); do _p9k_line_frame_left[s]=$v; done
        fi
      fi
      _p9k_get_icon '' MULTILINE_NEWLINE_PROMPT_SUFFIX; v=$_p9k__ret
      if [[ -n $v ]]; then
        [[ $v == *%* ]] && v+='%b%k%f'
        for (( s = 2; s < num_lines; s++ )); do _p9k_line_frame_right[s]=$v; _p9k_line_never_empty_right[s]=1; done
      fi
    fi
  fi

  # gaps (p10k: _p9k_build_gap_post) for lines 1 .. num_lines-1
  declare -ga _p9k_gap_char=() _p9k_gap_style=() _p9k_gap_exp=()
  local kind_l kind_u ch st
  for (( i = 1; i < num_lines; i++ )); do
    if (( i == 1 )); then kind_l=first kind_u=FIRST; else kind_l=newline kind_u=NEWLINE; fi
    _p9k_get_icon '' MULTILINE_${kind_u}_PROMPT_GAP_CHAR; ch=${_p9k__ret:- }
    _p9k_prompt_length "$ch"
    (( _p9k__ret == 1 && ${#ch} == 1 )) || ch=' '
    st=''
    _p9k_color prompt_multiline_${kind_l}_prompt_gap BACKGROUND ''
    [[ -n $_p9k__ret ]] && { _p9k_background "$_p9k__ret"; st+=$_p9k__ret; }
    _p9k_color prompt_multiline_${kind_l}_prompt_gap FOREGROUND ''
    [[ -n $_p9k__ret ]] && { _p9k_foreground "$_p9k__ret"; st+=$_p9k__ret; }
    _p9k_gap_char[i]=$ch _p9k_gap_style[i]=$st
    v=_POWERLEVEL9K_MULTILINE_${kind_u}_PROMPT_GAP_EXPANSION
    _p9k_gap_exp[i]=${!v-}
  done

  # ruler
  _p9k_get_icon '' RULER_CHAR; ch=$_p9k__ret
  _p9k_prompt_length "$ch"
  (( _p9k__ret == 1 && ${#ch} == 1 )) || ch=' '
  _p9k_color prompt_ruler BACKGROUND ''
  if [[ -z $_p9k__ret && $ch == ' ' ]]; then
    _p9k_ruler_char='' _p9k_ruler_style=''
  else
    _p9k_background "$_p9k__ret"; _p9k_ruler_style="%b$_p9k__ret"
    _p9k_color prompt_ruler FOREGROUND ''; _p9k_foreground "$_p9k__ret"; _p9k_ruler_style+=$_p9k__ret
    _p9k_ruler_char=$ch
  fi
}

# ------------------------------------------------------------ the prompt ---
# p10k: _p9k_set_prompt. Builds every line; results:
#   _p9k_ps_lines[1..n]  left part of each line, gap and right part included
#                        for all but the last line (prompt escapes)
#   _p9k_rprompt         right part of the last line (prompt escapes)
_p9k_set_prompt() {
  local -i left_idx=1 right_idx=1 num_lines=$_p9k_num_lines
  local cols=${COLUMNS:-80} ind=${ZLE_RPROMPT_INDENT:-1}
  (( ind < 0 )) && ind=0
  declare -ga _p9k_ps_lines=() _p9k_line_hidden=()
  _p9k_rprompt=''
  local _p9k__line_index _p9k__segment_name _p9k__segment_index _p9k__prompt_side
  local _p9k__prompt _p9k__bg _p9k__i _p9k__s _p9k__ss _p9k__sss _p9k__w _p9k__rcode
  for (( _p9k__line_index = 1; _p9k__line_index <= num_lines; _p9k__line_index++ )); do
    local right='' rexists=0
    if (( ! _POWERLEVEL9K_DISABLE_RPROMPT )); then
      _p9k__prompt='' _p9k__segment_index=$right_idx _p9k__prompt_side=right
      _p9k__bg=NONE _p9k__i=0 _p9k__sss=${_p9k_line_sss_right[_p9k__line_index]} _p9k__w='' _p9k__rcode=0
      for _p9k__segment_name in ${_p9k_line_segments_right[_p9k__line_index-1]}; do
        _p9k__segment_name=${_p9k__segment_name%_joined}
        _p9k_call_segment
        (( _p9k__segment_index++ ))
      done
      right_idx=$_p9k__segment_index
      if (( _p9k__rcode )) || [[ ${_p9k_line_never_empty_right[_p9k__line_index]} == 1 ]]; then
        rexists=1
        # `p10k display`: N/right (segments) and N/right_frame, each when set
        local dr=_p9k__${_p9k__line_index}r drf=_p9k__${_p9k__line_index}r_frame
        right=''
        [[ -n ${!dr+x} ]] || right="$_p9k__prompt$_p9k__sss%b%k%f"
        [[ -n ${!drf+x} ]] || right+=${_p9k_line_frame_right[_p9k__line_index]}
      fi
    fi
    local dl=_p9k__${_p9k__line_index}l dlf=_p9k__${_p9k__line_index}l_frame
    _p9k__prompt=''
    [[ -n ${!dlf+x} ]] || _p9k__prompt=${_p9k_line_frame_left[_p9k__line_index]}
    local lframe=$_p9k__prompt
    _p9k__segment_index=$left_idx _p9k__prompt_side=left
    _p9k__bg=NONE _p9k__i=0 _p9k__sss=${_p9k_line_sss_left[_p9k__line_index]}
    for _p9k__segment_name in ${_p9k_line_segments_left[_p9k__line_index-1]}; do
      _p9k__segment_name=${_p9k__segment_name%_joined}
      _p9k_call_segment
      (( _p9k__segment_index++ ))
    done
    left_idx=$_p9k__segment_index
    _p9k__prompt+="%b%k$_p9k__sss%b%k%f"
    (( _p9k__line_index == _p9k_line_end_left_idx )) && _p9k__prompt+=$_p9k_line_end_left
    # `p10k display N/left=hide`: only the frame remains
    [[ -n ${!dl+x} ]] && _p9k__prompt=$lframe
    # `p10k display N=hide`: the whole line goes (see _p9k_build_ps1)
    local dn=_p9k__${_p9k__line_index}
    [[ -n ${!dn+x} ]] && _p9k_line_hidden[_p9k__line_index]=1

    # dir shortening to fit (p10k: the _p9k__dir placeholder)
    if [[ -n ${_p9k__dir_placeholder-} ]]; then
      _p9k_dir_fit "$_p9k__line_index" "$right" "$num_lines"
    fi

    if (( _p9k__line_index == num_lines )); then
      _p9k_ps_lines[_p9k__line_index]=$_p9k__prompt
      _p9k_rprompt=$right
    elif (( rexists )); then
      local l=$_p9k__prompt
      _p9k_prompt_length "$l$right"
      local m=$(( cols - _p9k__ret - ind - 1 ))
      if (( m < 0 )); then
        _p9k_ps_lines[_p9k__line_index]=$l
      else
        local gap n=$(( m + 1 ))
        printf -v gap '%*s' "$n" ''
        local ch=${_p9k_gap_char[_p9k__line_index]} dg=_p9k__${_p9k__line_index}g
        # `p10k display N/gap=hide`: spaces instead of the gap character
        [[ $ch != ' ' && -z ${!dg+x} ]] && gap=${gap// /$ch}
        if [[ -n ${!dg+x} ]]; then
          :   # plain spaces, unstyled
        elif [[ -n ${_p9k_gap_exp[_p9k__line_index]} ]]; then
          local P9K_GAP=$gap; _p9k_expand "${_p9k_gap_exp[_p9k__line_index]}"; gap=$_p9k__x
          gap="${_p9k_gap_style[_p9k__line_index]}$gap%b%k%f"
        elif [[ -n ${_p9k_gap_style[_p9k__line_index]} ]]; then
          gap="${_p9k_gap_style[_p9k__line_index]}$gap%b%k%f"
        fi
        _p9k_ps_lines[_p9k__line_index]="$l$gap$right"
      fi
    else
      _p9k_ps_lines[_p9k__line_index]=$_p9k__prompt
    fi
  done
}

# Call the segment function for $_p9k__segment_name (p10k: prompt_NAME or custom_*).
_p9k_call_segment() {
  # The instant prompt (p10k: _p9k_set_prompt instant_): only segments with
  # an instant_prompt_NAME function. Those that just call prompt_NAME (or
  # test the same condition) run as usual below; those with a body of their
  # own run that, without the segment's condition; all others are left out.
  if (( ${_p9k__instant:-0} )); then
    case $_p9k__segment_name in
      os_icon|host|dir|dir_writable|root_indicator|chezmoi_shell|direnv|lf|midnight_commander|\
      nix_shell|nnn|ranger|toolbox|vim_shell|xplr|yazi) ;;
      context|date|per_directory_history|prompt_char|ssh|status|time|user|vi_mode)
        local dis=_POWERLEVEL9K_${_p9k__segment_name^^}_DISABLED_DIR_PATTERN
        if [[ -n ${!dis-} ]]; then
          local pat=${!dis}; pat=${pat/#\~/$HOME}
          # shellcheck disable=SC2053
          [[ $PWD == $pat ]] && return 0
        fi
        "instant_prompt_$_p9k__segment_name"
        return 0 ;;
      *) return 0 ;;
    esac
  fi
  local cond_v=_p9k__segment_cond_${_p9k__prompt_side}[$_p9k__segment_index]
  if [[ -n ${!cond_v-} ]]; then
    # "@COMMAND ARGS": the segment runs if the command succeeds (used where
    # p10k tests $commands[x] or $functions[x]); otherwise an expression that
    # must expand to something non-empty.
    if [[ ${!cond_v} == @* ]]; then
      ${!cond_v#@} || return 0
    else
      _p9k_expand "${!cond_v}"; [[ -n $_p9k__x ]] || return 0
    fi
  fi
  local dis=_POWERLEVEL9K_${_p9k__segment_name^^}_DISABLED_DIR_PATTERN
  if [[ -n ${!dis-} ]]; then
    local pat=${!dis}; pat=${pat/#\~/$HOME}
    # shellcheck disable=SC2053
    [[ $PWD == $pat ]] && return 0
  fi
  # Replay (p10k: the prompt is re-expanded, segments are not run again). Only
  # the two segments whose conditions read the keymap are evaluated afresh.
  if (( _p9k__replay )) && [[ $_p9k__segment_name != vi_mode && $_p9k__segment_name != prompt_char ]]; then
    local line rec=${_p9k__rec[$_p9k__prompt_side$_p9k__segment_index]-}
    while IFS= read -r line; do
      [[ -n $line ]] && eval "\"_p9k_\${_p9k__prompt_side}_prompt_segment\" $line"
    done <<<"$rec"
    return 0
  fi
  if [[ $_p9k__segment_name == custom_* ]]; then
    _p9k_custom_prompt "${_p9k__segment_name#custom_}"
  elif declare -F "prompt_$_p9k__segment_name" >/dev/null; then
    "prompt_$_p9k__segment_name"
  fi
}

declare -gA _p9k_segc=()
declare -gA _p9k__rec=()      # recorded _p9k_prompt_segment calls of the last full render
declare -gi _p9k__replay=0
