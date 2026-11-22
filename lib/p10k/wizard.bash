# =============================================================================
#  lib/p10k/wizard.bash - `p10k configure`: port of p10k's internal/wizard.zsh
#  and internal/configure.zsh. The same screens, questions, conditions and
#  previews; the configuration is made as p10k makes it (its template with the
#  wizard's edits: sub, uncomment, rep), then converted to bash by
#  `b4h-tool p10k-config`.
#
#  Differences that follow from bash, not from choice:
#   - The rc file the wizard offers to edit is ~/.bashrc; inside bash4humans
#     (which loads the config itself) that question is skipped, as p10k skips
#     it inside zsh4humans.
#   - The default config file is ~/.p10k.bash (POWERLEVEL9K_CONFIG_FILE).
#
#  zsh arrays start at 1. The wizard's arrays here are sparse bash arrays
#  whose first index is 1 too, so every [n] reads as in wizard.zsh.
# =============================================================================

# p10k: configure.zsh (sizes, paths) -----------------------------------------
__p9k_wizard_columns=47   # fewer probably work; not tried upstream
__p9k_wizard_lines=14     # the bottleneck is ask_tails with nerd fonts

# ~ for the home directory, % doubled: a path as shown on screen -> _p9k__ret
_p9k_wizard_u() {
  local p=$1
  [[ $p == "$HOME" || $p == "$HOME"/* ]] && p="~${p#"$HOME"}"
  _p9k__ret=${p//\%/%%}
}

# Paths the wizard uses (p10k: _p9k_can_configure sets __p9k_cfg_path*).
_p9k_wizard_paths() {
  __p9k_zd=$HOME
  _p9k_wizard_u "$__p9k_zd"; __p9k_zd_u=$_p9k__ret
  __p9k_zshrc=$(realpath -m -- "$__p9k_zd/.bashrc" 2>/dev/null) || __p9k_zshrc=$__p9k_zd/.bashrc
  __p9k_zshrc_u=$__p9k_zd_u/.bashrc
  # (a p10k config unsets POWERLEVEL9K_CONFIG_FILE as it loads; bash4humans
  # names its own place in _p9k_default_cfg)
  : "${POWERLEVEL9K_CONFIG_FILE:=${_p9k_default_cfg:-$HOME/.p10k.bash}}"
  __p9k_cfg_path_o=$POWERLEVEL9K_CONFIG_FILE
  __p9k_cfg_basename=${__p9k_cfg_path_o##*/}
  __p9k_cfg_path=$(realpath -m -- "$__p9k_cfg_path_o" 2>/dev/null) || __p9k_cfg_path=$__p9k_cfg_path_o
  _p9k_wizard_u "$__p9k_cfg_path_o"; __p9k_cfg_path_u=$_p9k__ret
  __p9k_templates=${_p9k_root%/lib/p10k}/p10k/templates
  _p9k_wizard_u "$__p9k_templates"; __p9k_templates_u=$_p9k__ret
}

# p10k: _p9k_can_configure [-q]
_p9k_can_configure() {
  local q=0; [[ ${1-} == -q ]] && q=1
  _p9k_can_configure_error() { (( q )) || _p9k_print_p "%1F[ERROR]%f %Bp10k configure%b: $1" >&2; }
  _p9k_wizard_paths
  local r=0 dir style
  if [[ ! -e $__p9k_zd ]]; then _p9k_can_configure_error "$__p9k_zd_u does not exist"; r=1
  elif [[ ! -d $__p9k_zd ]]; then _p9k_can_configure_error "$__p9k_zd_u is not a directory"; r=1
  elif [[ -d $__p9k_cfg_path ]]; then _p9k_can_configure_error "$__p9k_cfg_path_u is a directory"; r=1
  elif [[ -d $__p9k_zshrc ]]; then _p9k_can_configure_error "$__p9k_zshrc_u is a directory"; r=1
  fi
  if (( ! r )); then
    dir=${__p9k_cfg_path%/*}; [[ -n $dir ]] || dir=/
    while [[ ! -e $dir && $dir != / ]]; do dir=${dir%/*}; [[ -n $dir ]] || dir=/; done
    if [[ ! -d $dir ]]; then
      _p9k_can_configure_error "cannot create $__p9k_cfg_path_u because ${dir//\%/%%} is not a directory"; r=1
    elif [[ ! -w $dir ]]; then
      _p9k_can_configure_error "cannot create $__p9k_cfg_path_u because ${dir//\%/%%} is readonly"; r=1
    elif [[ -e $__p9k_cfg_path && ! -f $__p9k_cfg_path && ! -h $__p9k_cfg_path ]]; then
      _p9k_can_configure_error "$__p9k_cfg_path_u is a special file"; r=1
    elif [[ -e $__p9k_zshrc && ! -f $__p9k_zshrc && ! -h $__p9k_zshrc ]]; then
      _p9k_can_configure_error "$__p9k_zshrc_u a special file"; r=1
    elif [[ -e $__p9k_zshrc && ! -r $__p9k_zshrc ]]; then
      _p9k_can_configure_error "$__p9k_zshrc_u is not readable"; r=1
    fi
  fi
  if (( ! r )); then
    for style in lean lean-8colors classic rainbow pure; do
      if [[ ! -r $__p9k_templates/p10k-$style.zsh ]]; then
        _p9k_can_configure_error "$__p9k_templates_u/p10k-$style.zsh is not readable"; r=1; break
      fi
    done
  fi
  if (( ! r )); then
    _p9k_wizard_tty_size
    if (( LINES < __p9k_wizard_lines || COLUMNS < __p9k_wizard_columns )); then
      _p9k_can_configure_error "terminal size too small; must be at least $__p9k_wizard_columns columns by $__p9k_wizard_lines lines"; r=1
    elif [[ ! -t 0 || ! -t 1 ]]; then
      _p9k_can_configure_error "no TTY"; r=2
    fi
  fi
  unset -f _p9k_can_configure_error
  return "$r"
}

# The terminal's size now (zsh keeps LINES and COLUMNS current by itself).
_p9k_wizard_tty_size() {
  local s
  s=$(stty size </dev/tty 2>/dev/null) || return 0
  [[ $s == [0-9]*' '[0-9]* ]] || return 0
  LINES=${s% *} COLUMNS=${s#* }
}

# p10k: p9k_configure, run by `p10k configure`
_p9k_p10k_cmd_configure() {
  if (( $# )); then _p9k_print_p "$_p9k_p10k_configure_usage" >&2; return 1; fi
  _p9k_can_configure || return
  ( _p9k_wizard -f )
  local ret=$?
  case $ret in
    0)
      # shellcheck disable=SC1090
      . "$__p9k_cfg_path"
      _p9k__force_must_init=1 ;;
    69) return 0 ;;
    *) return "$ret" ;;
  esac
}

# --------------------------------------------------------------- the wizard ---
# Run in a subshell: `quit` ends it with exit, as in p10k.
_p9k_wizard() {
  local force=0 opt OPTIND=1
  while getopts 'f' opt; do
    case $opt in
      f) force=1 ;;
      *) return 1 ;;
    esac
  done
  if (( OPTIND <= $# )); then
    printf '%s\n' "wizard: invalid arguments: $*" >&2
    return 1
  fi
  # Inside bash4humans the config is loaded by b4h itself (p10k: z4h).
  local in_b4h=0
  [[ -n ${B4H_VERSION-} ]] && in_b4h=1
  local in_z4h_wizard=0 success=0

  local font_base_url='https://github.com/romkatv/powerlevel10k-media/raw/master'
  local prompt_indent=2
  local -A pure_original=([grey]=242 [red]=1 [yellow]=3 [blue]=4 [magenta]=5 [cyan]=6 [white]=7)
  local -A pure_snazzy=([grey]=242 [red]='#FF5C57' [yellow]='#F3F99D' [blue]='#57C7FF' [magenta]='#FF6AC1' [cyan]='#9AEDFE' [white]='#F1F1F0')
  local -a bg_color=([1]=240 238 236 234)
  local -a sep_color=([1]=248 246 244 242)
  local -a prefix_color=([1]=250 248 246 244)

  local left_circle='\uE0B6' right_circle='\uE0B4' left_arc='\uE0B7' right_arc='\uE0B5'
  local left_triangle='\uE0B2' right_triangle='\uE0B0' left_angle='\uE0B3' right_angle='\uE0B1'
  local fade_in='░▒▓' fade_out='▓▒░' vertical_bar='\u2502'
  local cursor='%1{\e[07m \e[27m%}'
  local time_24h='16:23:42' time_12h='04:23:42 PM'

  # The previews (wizard.zsh: lean_left ... rainbow_right), 4 parts each:
  # line 1 left, line 1 right / frame, line 2 left, line 2 right / frame.
  # Written in bash syntax; the few nested zsh expansions use helper strings
  # that print_prompt computes first (_c1, _rbi, _rbt, _py, _pyr, _pgt).
  local -a lean_left=([1]='%${frame_color[color]}F╭─ '
    '${extra_icons[1]:+%f${extra_icons[1]} }%31F${extra_icons[2]}%B%39F~%b%31F/%B%39Fsrc%b%f ${prefixes[1]}%76F${extra_icons[3]}master%f '
    '%${frame_color[color]}F╰─' '%76F$prompt_char%f ${buffer:-$cursor}')
  local -a lean_right=([1]=' ${prefixes[2]}%101F${extra_icons[4]}5s%f${time:+ ${prefixes[3]}%66F${extra_icons[5]}$time%f}'
    ' %${frame_color[color]}F─╮%f' '' ' %${frame_color[color]}F─╯%f')
  local -a lean_8colors_left=([1]='%${frame_color[color]}F╭─ '
    '${extra_icons[1]:+%f${extra_icons[1]} }%4F${extra_icons[2]}%4F~/src%f ${prefixes[1]}%2F${extra_icons[3]}master%f '
    '%${frame_color[color]}F╰─' '%2F$prompt_char%f ${buffer:-$cursor}')
  local -a lean_8colors_right=([1]=' ${prefixes[2]}%3F${extra_icons[4]}5s%f${time:+ ${prefixes[3]}%6F${extra_icons[5]}$time%f}'
    ' %${frame_color[color]}F─╮%f' '' ' %${frame_color[color]}F─╯%f')
  local -a classic_left=([1]='%${frame_color[color]}F╭─'
    '%F{${bg_color[color]}}$left_tail%K{${bg_color[color]}} ${extra_icons[1]:+%255F${extra_icons[1]} %${sep_color[color]}F$left_subsep%f }%31F${extra_icons[2]}%B%39F~%b%K{${bg_color[color]}}%31F/%B%39Fsrc%b%K{${bg_color[color]}} %${sep_color[color]}F$left_subsep%f %${prefix_color[color]}F${prefixes[1]}%76F${extra_icons[3]}master %k%${bg_color[color]}F$left_head%f'
    '%${frame_color[color]}F╰─' '%f ${buffer:-$cursor}')
  local -a classic_right=([1]='%${bg_color[color]}F$right_head%K{${bg_color[color]}}%f %${prefix_color[color]}F${prefixes[2]}%101F5s ${extra_icons[4]}${time:+%${sep_color[color]}F$right_subsep %${prefix_color[color]}F${prefixes[3]}%66F$time ${extra_icons[5]}}%k%F{${bg_color[color]}}$right_tail%f'
    '%${frame_color[color]}F─╮%f' '' '%${frame_color[color]}F─╯%f')
  local -a pure_left=([1]=''
    '%F{${pure_color[blue]}}~/src%f %F{${pure_color[grey]}}master%f ${pure_use_rprompt-$_py}'
    '' '%F{${pure_color[magenta]}}$prompt_char%f ${buffer:-$cursor}')
  local -a pure_right=([1]='${pure_use_rprompt+$_pyr${time:+ }}${time:+$_pgt}' '' '' '')
  local -a rainbow_left=([1]='%${frame_color[color]}F╭─'
    '%F{$_c1}$left_tail${extra_icons[1]:+$_rbi}%K{4}%254F ${extra_icons[2]}%B%255F~%b%K{4}%254F/%B%255Fsrc%b%K{4} %K{2}%4F$left_sep %0F${prefixes[1]}${extra_icons[3]}master %k%2F$left_head%f'
    '%${frame_color[color]}F╰─' '%f ${buffer:-$cursor}')
  local -a rainbow_right=([1]='%3F$right_head%K{3} %0F${prefixes[2]}5s ${extra_icons[4]}%3F${time:+$_rbt}%k$right_tail%f'
    '%${frame_color[color]}F─╮%f' '' '%${frame_color[color]}F─╯%f')

  # ---- output helpers (zsh print -P / print -nP; escapes first, as print does)
  pp()  { local s; printf -v s '%b' "$1"; _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$s"; printf '%s\n' "$_p9k__pe"; }
  ppn() { local s; printf -v s '%b' "$1"; _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$s"; printf '%s' "$_p9k__pe"; }
  # zsh: print [-P] ARGS... (the forms the widgets use)
  print() {
    local p=0 n=0 l=0 a
    while [[ ${1-} == -* && ${1-} != -- ]]; do
      a=${1#-}
      [[ $a == *P* ]] && p=1; [[ $a == *n* ]] && n=1; [[ $a == *l* ]] && l=1
      shift
    done
    [[ ${1-} == -- ]] && shift
    local out='' s sep=' '; (( l )) && sep=$'\n'
    local first=1
    for a in "$@"; do
      printf -v s '%b' "$a"
      if (( p )); then _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$s"; s=$_p9k__pe; fi
      (( first )) || out+=$sep
      first=0 out+=$s
    done
    (( n )) || out+=$'\n'
    printf '%s' "$out"
  }

  # p10k: prompt_length -> REPLY (visible width of a prompt-escape string)
  prompt_length() { _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$1"; REPLY=$_p9k__pw; }
  # zsh ${(g::)s}: echo-style escapes -> REPLY
  unescape() { printf -v REPLY '%b' "$1"; }
  spaces() { local s=''; (( $1 > 0 )) && printf -v s '%*s' "$1" ''; printf '%s' "$s"; }
  # ${(pl:N::C:)}: N copies of C -> stdout
  repeat() { local s=''; (( $1 > 0 )) && { printf -v s '%*s' "$1" ''; s=${s// /$2}; }; printf '%s' "$s"; }

  print_prompt() {
    local left_t=${style}_left right_t=${style}_right
    local -n _l=$left_t _r=$right_t
    # helpers for the previews (see above)
    local _c1=4; [[ -n ${extra_icons[1]} ]] && _c1=7
    local _rbi="%K{7}%232F ${extra_icons[1]} %K{4}%7F$left_sep"
    local _rbt="%7F$right_sep%K{7} %0F${prefixes[3]}$time ${extra_icons[5]}%7F"
    local _py="%F{${pure_color[yellow]}}5s%f " _pyr="%F{${pure_color[yellow]}}5s%f"
    local _pgt="%F{${pure_color[grey]}}$time%f"
    local -a left=() right=()
    local i s
    for i in 1 2 3 4; do eval "s=\"${_l[i]-}\""; left[i]=$s; done
    if (( ! disable_rprompt )); then
      for i in 1 2 3 4; do eval "s=\"${_r[i]-}\""; right[i]=$s; done
    fi
    unset -n _l _r
    local nl=4
    if (( num_lines == 1 )); then
      left=([1]="${left[2]}" "${left[4]}") right=([1]="${right[1]-}" "${right[3]-}") nl=2
    else
      local c=76
      [[ $style == pure ]] && c=${pure_color[magenta]}
      [[ $style == lean_8colors ]] && c=2
      (( left_frame )) || left=([1]='' "${left[2]}" '' "%F{$c}$prompt_char%f ${buffer:-$cursor}")
      (( right_frame )) || right=([1]="${right[1]-}" '' '' '')
    fi
    local left_indent=$prompt_indent right_indent=$prompt_indent
    unescape "${left[1]}${left[2]}${right[1]-}${right[2]-}"; prompt_length "$REPLY"
    local width=$REPLY
    while (( wizard_columns - width <= left_indent + right_indent )); do
      if (( right_indent )); then
        (( --right_indent ))
      elif (( left_indent )); then
        (( --left_indent ))
      else
        print -P '  [%3Fnot enough horizontal space to display this%f]'
        return 0
      fi
    done
    local l r gap fill
    for (( i = 1; i < nl; i += 2 )); do
      unescape "${left[i]}${left[i+1]}"; l=$REPLY
      unescape "${right[i]-}${right[i+1]-}"; r=$REPLY
      prompt_length "$l$r"
      gap=$(( wizard_columns - left_indent - right_indent - REPLY ))
      if (( num_lines == 2 && i == 1 )); then fill=$gap_char; else fill=' '; fi
      spaces "$left_indent"
      ppn "$l"
      ppn "%${frame_color[color]}F$(repeat "$gap" "$fill")%f"
      if [[ -n $r ]]; then pp "$r"; else printf '\n'; fi
    done
  }

  href() {
    local url=${1//\%/%%}; url=${url//\\/\\\\}
    if (( _p9k_term_has_href )); then
      printf '%s\n' '%{\e]8;;'"$url"'\a%}'"$url"'%{\e]8;;\a%}'
    else
      printf '%s\n' "$url"
    fi
  }

  flowing() {
    local wizard_columns=${wizard_columns:-0}
    (( wizard_columns )) || wizard_columns=$COLUMNS
    local centered=0 indentation=0
    while (( $# )); do
      case $1 in
        -c) centered=1; shift ;;
        +c) centered=0; shift ;;
        -i) indentation=$2; shift 2 ;;
        -i*) indentation=${1#-i}; shift ;;
        --) shift; break ;;
        *) break ;;
      esac
    done
    local line='' word
    local -a lines=()
    for word in "$@"; do
      unescape "$line $word"; prompt_length "$REPLY"
      if (( REPLY > wizard_columns )); then
        [[ -z $line ]] || lines+=("$line")
        line=''
      fi
      if [[ -n $line ]]; then
        line+=' '
      elif (( ${#lines[@]} )); then
        line=$(spaces "$indentation")
      fi
      line+=$word
    done
    [[ -z $line ]] || lines+=("$line")
    for line in "${lines[@]}"; do
      unescape "$line"; prompt_length "$REPLY"
      (( centered && REPLY < wizard_columns )) && spaces $(( (wizard_columns - REPLY) / 2 ))
      pp "$line"
    done
  }

  clear() {
    if command -v clear >/dev/null && command clear 2>/dev/null; then
      return
    fi
    tput clear 2>/dev/null
    printf '\e[H\e[2J\e[3J'
  }
  hide_cursor() { tput civis 2>/dev/null; }
  show_cursor() {
    local cnorm; cnorm=$(tput cnorm 2>/dev/null)
    if [[ $cnorm == *$'\e[?25h' || $cnorm == *$'\e[?25h\e'* ]]; then
      printf '\e[?25h'
    else
      printf '%s' "$cnorm"
    fi
  }
  consume_input() {
    local key
    while read -t 0 2>/dev/null && read -r -s -n1 key 2>/dev/null; do :; done
  }

  quit() {
    consume_input
    if [[ ${1-} == '-c' ]]; then
      pp ''
      pp '%b%k%f%u%s'
      pp '%F{3}--- stack trace (most recent call first) ---%f'
      local i
      for (( i = 1; i < ${#FUNCNAME[@]}; i++ )); do
        printf '%s:%s\n' "${BASH_SOURCE[i]}" "${BASH_LINENO[i-1]}"
      done
      pp '%F{3}--- end of stack trace ---%f'
      pp ''
      pp 'Press %BENTER%b to continue.'
      hide_cursor
      read -r -s
    fi
    restore_screen
    printf '\n'
    if (( force )); then
      flowing Powerlevel10k configuration wizard has been aborted. To run it again, type:
      pp ""
      pp "  %2Fp10k%f %Bconfigure%b"
      pp ""
    else
      flowing                                                                        \
        Powerlevel10k configuration wizard has been aborted. It will run again       \
        next time unless you define at least one Powerlevel10k configuration option. \
        To define an option that does nothing except for disabling Powerlevel10k     \
        configuration wizard, type the following command:
      pp ""
      pp "  %2Fecho%f %3F'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true'%f >> $__p9k_zshrc_u"
      pp ""
      flowing To run Powerlevel10k configuration wizard right now, type:
      pp ""
      pp "  %2Fp10k%f %Bconfigure%b"
      pp ""
    fi
    quit() { :; }
    stty echo 2>/dev/null
    show_cursor
    exit 1
  }

  # ---- screens: widgets with priorities (p10k: add_widget, render_screen)
  local -a screen_widgets=()
  local max_priority=0 prompt_idx=0 choice=''

  add_widget() {
    local priority=$1 render=''
    shift
    (( $# )) && printf -v render '%q ' "$@"
    screen_widgets+=("$priority" "$render")
    (( priority <= max_priority )) || max_priority=$priority
  }

  render_screen_pass() {
    local pass=$1 prev_pass=0 cur_pass prev_render='' cur_render i
    local -a w=("${screen_widgets[@]}" 0 '')
    for (( i = 0; i < ${#w[@]}; i += 2 )); do
      cur_pass=${w[i]} cur_render=${w[i+1]}
      if (( prev_pass <= pass && (cur_pass == 0 || cur_pass > pass) )); then
        eval "$prev_render"
      fi
      prev_pass=$cur_pass prev_render=$cur_render
    done
  }

  get_columns() { _p9k_wizard_tty_size; REPLY=$(( COLUMNS > 88 ? 88 : COLUMNS )); }

  render_screen() {
    hide_cursor
    while true; do
      while true; do
        get_columns; wizard_columns=$REPLY
        wizard_lines=$LINES
        if (( wizard_columns < __p9k_wizard_columns )); then
          clear
          flowing -c %1FNot enough horizontal space.%f
          printf '\n'
          flowing Make terminal window %Bwider%b or press %BCtrl-C%b to abort Powerlevel10k configuration wizard.
        elif (( wizard_lines < __p9k_wizard_lines )); then
          clear
          flowing -c %1FNot enough vertical space.%f
          printf '\n'
          flowing Make terminal window %Btaller%b or press %BCtrl-C%b to abort Powerlevel10k configuration wizard.
        else
          break
        fi
        while get_columns; (( REPLY == wizard_columns && LINES == wizard_lines )); do
          sleep 1
        done
      done

      local -a passes=()
      local i p content n
      for (( i = 0; i < ${#screen_widgets[@]}; i += 2 )); do passes+=("${screen_widgets[i]}"); done
      mapfile -t passes < <(printf '%s\n' "${passes[@]}" | sort -nu)
      for p in "${passes[@]}"; do
        content=$(render_screen_pass "$p")
        n=${content//[!$'\n']/}; n=$(( ${#n} + 1 ))
        (( n > wizard_lines )) && continue
        clear
        printf '%s' "$content"
        show_cursor
        return 0
      done

      clear
      flowing -c %1FNot enough vertical space.%f
      printf '\n'
      flowing Make terminal window %Btaller%b or press %BCtrl-C%b to abort Powerlevel10k configuration wizard.
      while get_columns; (( REPLY == wizard_columns && LINES == wizard_lines )); do
        sleep 1
      done
    done
  }

  # Run a widget command with temporary variables (zsh: VAR=value cmd, where
  # an array value arrives as text and print_prompt evals it). A name starting
  # with @ is an array (1-based), with % an associative array.
  with() {
    local _a
    while (( $# )) && [[ $1 != -- ]]; do
      _a=$1; shift
      case $_a in
        @*) local -a _t; eval "_t=${_a#*=}"; _a=${_a%%=*}; _a=${_a#@}
            local -a "$_a"; local -n _w=$_a; _w=()
            local _i; for _i in "${!_t[@]}"; do _w[_i+1]=${_t[_i]}; done
            unset -n _w; unset _t ;;
        %*) _a=${_a#%}; local -A "${_a%%=*}"; eval "${_a%%=*}=${_a#*=}" ;;
        *) local "$_a" ;;
      esac
    done
    shift
    "$@"
  }
  # array -> "@name=( 'v1' 'v2' )" for with()
  arr_arg() {
    local -n _s=$2; local s='(' v
    for v in "${_s[@]}"; do printf -v v '%q' "$v"; s+=" $v"; done
    REPLY="@$1=$s )"
  }
  assoc_arg() {
    local -n _s=$2; local s='(' k v
    for k in "${!_s[@]}"; do printf -v v '%q' "${_s[$k]}"; printf -v k '%q' "$k"; s+=" [$k]=$v"; done
    REPLY="%$1=$s )"
  }

  add_prompt_n() {
    add_widget 0 with "$@" -- print_prompt
    local num_lines=$num_lines a
    for a; do [[ $a == num_lines=* ]] && num_lines=${a#*=}; done
    if (( num_lines == 2 )); then
      add_widget $(( 100 - ++prompt_idx )) print -P '  [%3Fnot enough vertical space to display this%f]'
    fi
  }

  add_prompt() {
    add_widget 0 print
    add_widget 1
    add_prompt_n "$@"
    add_widget 0 print
    add_widget 2
  }

  ask() {
    local choices=$1
    local lines=0 columns=0 wizard_lines=0 wizard_columns=0
    add_widget 0 print -P "(q)  Quit and do nothing."
    add_widget 0 print
    add_widget $(( max_priority + 1 ))
    add_widget 0 print -P "%BChoice [${choices}q]: %b"
    while true; do
      get_columns
      if (( LINES != lines || REPLY != columns )); then
        render_screen
        lines=$wizard_lines
        columns=$wizard_columns
      fi
      choice=''
      if IFS= read -r -s -n1 -t1 choice; then
        choice=${choice,,}
        if [[ $choice == q ]]; then
          quit
        fi
        if [[ -n $choice && $choices == *"$choice"* ]]; then
          screen_widgets=()
          max_priority=0
          prompt_idx=0
          return
        fi
      fi
    done
  }

  local greeting_printed=0
  print_greeting() {
    (( greeting_printed )) && return
    if (( in_z4h_wizard )); then
      :
    elif (( force )); then
      flowing -c This is %4FPowerlevel10k configuration wizard%f. \
                 It will ask you a few questions and configure your prompt.
    else
      flowing -c This is %4FPowerlevel10k configuration wizard%f.   \
                 You are seeing it because you "haven't" defined any \
                 Powerlevel10k configuration options. It will ask   \
                 you a few questions and configure your prompt.
    fi
    pp ""
  }

  # ---- font installation (Termux, iTerm2), as in p10k
  iterm_get() { /usr/libexec/PlistBuddy -c "Print :$1" ~/Library/Preferences/com.googlecode.iterm2.plist; }
  local terminal='' iterm2_font_size='' iterm2_old_font=0 can_install_font=0
  _wz_font_check() {
    [[ ${P9K_SSH-0} == 0 ]] || return 1
    if [[ "$(uname)" == Linux && "$(uname -o)" == Android ]]; then
      command -v termux-reload-settings >/dev/null || return 1
      command -v curl >/dev/null || return 1
      if [[ -f ~/.termux/font.ttf ]]; then
        [[ -r ~/.termux/font.ttf ]] || return 1
        [[ -w ~/.termux/font.ttf ]] || return 1
        ! grep -q 'MesloLGS NF' ~/.termux/font.ttf 2>/dev/null || return 1
      fi
      if [[ -f ~/.termux ]]; then
        [[ -d ~/.termux && -w ~/.termux ]] || return 1
      else
        [[ -w ~ ]] || return 1
      fi
      terminal=Termux
      return 0
    fi
    if [[ "$(uname)" == Darwin && ${TERM_PROGRAM-} == iTerm.app ]]; then
      command -v curl >/dev/null || return 1
      [[ ${TERM_PROGRAM_VERSION-} == [2-9]* ]] || return 1
      if [[ -f ~/Library/Fonts ]]; then
        [[ -d ~/Library/Fonts && -w ~/Library/Fonts ]] || return 1
      else
        [[ -d ~/Library && -w ~/Library ]] || return 1
      fi
      [[ -x /usr/libexec/PlistBuddy && -x /usr/bin/plutil && -x /usr/bin/defaults ]] || return 1
      local plist=~/Library/Preferences/com.googlecode.iterm2.plist
      [[ -f $plist && -r $plist && -w $plist ]] || return 1
      local guid1 guid2 font
      guid1=$(iterm_get '"Default Bookmark Guid"' 2>/dev/null) || return 1
      guid2=$(iterm_get '"New Bookmarks":0:"Guid"' 2>/dev/null) || return 1
      font=$(iterm_get '"New Bookmarks":0:"Normal Font"' 2>/dev/null) || return 1
      [[ $guid1 == "$guid2" ]] || return 1
      [[ ! $font =~ ^MesloLGS-NF-Regular\ [0-9]+$ ]] || return 1
      [[ $font =~ \ ([0-9]+)$ ]] || return 1
      [[ $font =~ ^MesloLGSNer-Regular\ [0-9]+$ ]] && iterm2_old_font=1
      iterm2_font_size=${BASH_REMATCH[1]}
      [[ $font =~ \ ([0-9]+)$ ]] && iterm2_font_size=${BASH_REMATCH[1]}
      terminal=iTerm2
      return 0
    fi
    return 1
  }
  _wz_font_check && can_install_font=1

  run_command() {
    local msg=$1 err
    shift
    [[ -n $msg ]] && ppn "$msg ..."
    if ! err=$("$@" 2>&1); then
      pp " %1FERROR%f"
      pp ""
      ppn "%BCommand:%b "
      printf '%q ' "$@"; printf '\n'
      if [[ -n $err ]]; then
        pp ""
        printf '%s\n' "$err"
      fi
      quit -c
    fi
    [[ -n $msg ]] && pp " %2FOK%f"
  }

  install_font() {
    clear
    case $terminal in
      Termux)
        command mkdir -p -- ~/.termux || quit -c
        run_command "Downloading %BMesloLGS NF Regular.ttf%b" \
          curl -fsSL -o ~/.termux/font.ttf "$font_base_url/MesloLGS%20NF%20Regular.ttf"
        run_command "Reloading %BTermux%b settings" termux-reload-settings
        ;;
      iTerm2)
        command mkdir -p -- ~/Library/Fonts || quit -c
        local style file
        for style in Regular Bold Italic 'Bold Italic'; do
          file="MesloLGS NF ${style}.ttf"
          run_command "Downloading %B$file%b" \
            curl -fsSL -o ~/Library/Fonts/"$file".tmp "$font_base_url/${file// /%20}"
          command mv -f -- ~/Library/Fonts/"$file"{.tmp,} || quit -c
        done
        ppn "Changing %BiTerm2%b settings ..."
        local size=$iterm2_font_size
        [[ $size == 12 ]] && size=13
        local -a settings=(
          '"Normal Font"'                                 string '"MesloLGS-NF-Regular '$size'"'
          '"Terminal Type"'                               string '"xterm-256color"'
          '"Horizontal Spacing"'                          real   1
          '"Vertical Spacing"'                            real   1
          '"Minimum Contrast"'                            real   0
          '"Use Bold Font"'                               bool   1
          '"Use Bright Bold"'                             bool   1
          '"Use Italic Font"'                             bool   1
          '"ASCII Anti Aliased"'                          bool   1
          '"Non-ASCII Anti Aliased"'                      bool   1
          '"Use Non-ASCII Font"'                          bool   0
          '"Ambiguous Double Width"'                      bool   0
          '"Draw Powerline Glyphs"'                       bool   1
          '"Only The Default BG Color Uses Transparency"' bool   1
        )
        local i k t v
        for (( i = 0; i < ${#settings[@]}; i += 3 )); do
          k=${settings[i]} t=${settings[i+1]} v=${settings[i+2]}
          /usr/libexec/PlistBuddy -c "Set :\"New Bookmarks\":0:$k $v" \
            ~/Library/Preferences/com.googlecode.iterm2.plist 2>/dev/null && continue
          run_command "" /usr/libexec/PlistBuddy -c \
            "Add :\"New Bookmarks\":0:$k $t $v" ~/Library/Preferences/com.googlecode.iterm2.plist
        done
        pp " %2FOK%f"
        ppn "Updating %BiTerm2%b settings cache ..."
        run_command "" /usr/bin/defaults read com.googlecode.iterm2
        sleep 3
        pp " %2FOK%f"
        sleep 1
        clear
        hide_cursor
        printf '\n'
        flowing +c "%2FMeslo Nerd Font%f" successfully installed.
        pp ""
        local out keep=1
        if out=$(/usr/bin/defaults read 'Apple Global Domain' NSQuitAlwaysKeepsWindows 2>/dev/null) &&
           [[ $out == 1 ]] && out=$(iterm_get OpenNoWindowsAtStartup 2>/dev/null) && [[ $out == false ]]; then
          keep=0
        fi
        if (( keep )); then
          flowing +c Please "%Brestart iTerm2%b" for the changes to take effect.
          pp ""
          flowing +c -i 5 "  1. Click" "%BiTerm2 → Quit iTerm2%b" or press "%B⌘ Q%b."
          flowing +c -i 5 "  2. Open %BiTerm2%b."
          pp ""
          flowing +c "It's" important to "%Brestart iTerm2%b" by following the instructions above.   \
                     "It's" "%Bnot enough%b" to close iTerm2 by clicking on the red circle. You must \
                     click "%BiTerm2 → Quit iTerm2%b" or press "%B⌘ Q%b."
        else
          flowing +c Please "%Brestart your computer%b" for the changes to take effect.
        fi
        while true; do sleep 60 2>/dev/null; done
        ;;
    esac
    return 0
  }

  ask_font() {
    (( can_install_font )) || return 0
    add_widget 0 print_greeting
    if (( iterm2_old_font )); then
      add_widget 0 flowing -c A new version of '%2FMeslo Nerd Font%f' is available. '%BInstall?%b'
    else
      add_widget 0 flowing -c %BInstall '%b%2FMeslo Nerd Font%f%B?%b'
    fi
    add_widget 0 print
    add_widget 0 print -P "%B(y)  Yes (recommended).%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(n)  No. Use the current font.%b"
    add_widget 0 print
    add_widget 1
    ask yn
    greeting_printed=1
    case $choice in
      y) ask_remove_font || return; install_font ;;
      n) ;;
    esac
    return 0
  }

  print_file_path() {
    local file=$1
    if (( ${#file} > wizard_columns - 2 )); then
      file=${file:0:wizard_columns-5}...
    fi
    add_widget 0 print -P "  %B${file//\%/%%}%b"
  }

  ask_remove_font() {
    local font dir
    local -a fonts=()
    local protected=0
    shopt -s globstar nullglob
    for font in {,/System,~}/Library/Fonts/**/*[Mm]eslo*.ttf {,/System,~}/Library/Fonts/**/*[Mm]eslo*.otf; do
      font=$(realpath -- "$font" 2>/dev/null) || continue
      [[ -f $font && -r $font ]] || continue
      [[ $font == ~/Library/Fonts/'MesloLGS NF '@(Regular|Bold|Italic|Bold\ Italic).ttf ]] && continue
      grep -aq 'MesloLGS NF' -- "$font" 2>/dev/null || continue
      fonts+=("$font")
      dir=${font%/*}
      [[ -w $dir ]] || protected=1
    done
    shopt -u globstar nullglob
    (( ${#fonts[@]} )) || return 0
    add_widget 0 flowing -c A variant of "%2FMeslo Nerd Font%f" is already installed.
    add_widget 0 print -P ""
    for font in "${fonts[@]}"; do
      add_widget 0 print_file_path "$font"
    done
    add_widget 0 print -P ""
    if (( protected )); then
      if (( ${#fonts[@]} == 1 )); then
        add_widget 0 flowing Please %Bdelete%b this file and run '%2Fp10k%f %Bconfigure%b.'
      else
        add_widget 0 flowing Please %Bdelete%b these files and run '%2Fp10k%f %Bconfigure%b.'
      fi
      add_widget 0 print
      restore_screen
      local i
      for (( i = 0; i < ${#screen_widgets[@]}; i += 2 )); do
        (( screen_widgets[i] == 0 )) && eval "${screen_widgets[i+1]}"
      done
      exit 1
    fi
    if (( ${#fonts[@]} == 1 )); then
      add_widget 0 flowing -c "%BDelete this file?%b"
    else
      add_widget 0 flowing -c "%BDelete these files?%b"
    fi
    add_widget 0 print -P ""
    add_widget 0 print -P "%B(y)  Yes (recommended).%b"
    add_widget 0 print -P ""
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask yr
    case $choice in
      r) return 1 ;;
      y) rm -f -- "${fonts[@]}" || quit -c ;;
    esac
    return 0
  }

  # ---- the questions (p10k: ask_*)
  ask_diamond() {
    local extra=''
    add_widget 0 print_greeting
    add_widget 0 flowing -c %BDoes this look like a%b %2Fdiamond%f '%B(rotated square)?%b'
    add_widget 0 flowing -c reference: "$(href https://graphemica.com/%E2%97%86)"
    add_widget 0 print
    add_widget 0 flowing -c -- "--->  \uE0B2\uE0B0  <---"
    add_widget 0 print
    add_widget 3
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print
    add_widget 2
    if (( can_install_font )); then
      extra+=r
      add_widget 0 print -P "(r)  Restart from the beginning."
    fi
    ask "yn$extra"
    greeting_printed=1
    case $choice in
      r) return 1 ;;
      y) cap_diamond=1 ;;
      n) cap_diamond=0 ;;
    esac
    return 0
  }

  ask_lock() {
    [[ -n ${2-} ]] && add_widget 0 flowing -c "$2"
    add_widget 0 flowing -c "%BDoes this look like a %b%2Flock%f%B?%b"
    add_widget 0 flowing -c "reference: $(href https://fontawesome.com/icons/lock)"
    add_widget 0 print
    add_widget 0 flowing -c -- "--->  $1  <---"
    add_widget 0 print
    add_widget 3
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y) cap_lock=1 ;;
      n) cap_lock=0 ;;
    esac
    return 0
  }

  ask_python() {
    add_widget 0 flowing -c %BDoes this look like a "%b%2FPython logo%f%B?%b"
    add_widget 0 flowing -c reference: "$(href https://fontawesome.com/icons/python)"
    add_widget 0 print -P ""
    add_widget 0 flowing -c -- "--->  \uE63C  <---"
    add_widget 0 print -P ""
    add_widget 3
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print -P ""
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y) cap_python=1 ;;
      n) cap_python=0 ;;
    esac
    return 0
  }

  ask_quotes() {
    add_widget 0 flowing -c %BDoes this look like%b "%2F><%f" %Bbut taller and "fatter?%b"
    add_widget 0 print -P ""
    add_widget 0 flowing -c -- "--->  \u276F\u276E  <---"
    add_widget 0 print -P ""
    add_widget 3
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print -P ""
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y) cap_quotes=1 ;;
      n) cap_quotes=0 ;;
    esac
    return 0
  }

  ask_arrow() {
    # p10k: true as long as zsh knows Unicode 9 (the glyph is one column wide)
    unescape "$1"; prompt_length "$REPLY"
    if (( REPLY != 1 )); then
      cap_arrow=0
      return
    fi
    [[ -n ${2-} ]] && add_widget 0 flowing -c "$2"
    add_widget 0 flowing -c %BDoes this look like an%b "%2Fupwards arrow%f%B?%b"
    add_widget 0 flowing -c reference: "$(href https://graphemica.com/%F0%9F%A0%89)"
    add_widget 0 print -P ""
    add_widget 0 flowing -c -- "--->  $1  <---"
    add_widget 0 print -P ""
    add_widget 3
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print -P ""
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y) cap_arrow=1 ;;
      n) cap_arrow=0 ;;
    esac
    return 0
  }

  print_indented() {
    local max_width=$1 text=$2
    local indent=$(( (wizard_columns - max_width) / 2 ))
    pp "$(spaces "$indent")$text"
  }

  ask_width() {
    add_widget 0 flowing -c %BWhat digit is the%b "%2Fdownwards arrow%f" %Bpointing "at?%b"
    add_widget 0 print -P ""
    add_widget 0 print_indented 11 '%3F\UF0734%f %3F\UF0734%f %3F\UF0734%f %2F\UF072E%f'
    add_widget 0 print_indented 11 '     111222'
    add_widget 0 print -P ""
    add_widget 3
    add_widget 0 print -P "%B(1)  It is pointing at '1'.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(2)  It is pointing at '2'.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(3)  Something else.%b"
    add_widget 0 print -P ""
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 123r
    case $choice in
      r) return 1 ;;
      1) cap_arrow=1 ;;
      2|3) cap_arrow=0 ;;
    esac
    return 0
  }

  ask_icon_padding() {
    if [[ $POWERLEVEL9K_MODE == @(powerline|compatible|ascii) ]]; then
      POWERLEVEL9K_ICON_PADDING=none
      return 0
    fi
    local text="X"
    text+="%1F${icons[VCS_GIT_ICON]// }%fX"
    text+="%2F${icons[VCS_GIT_GITHUB_ICON]// }%fX"
    text+="%3F${icons[TIME_ICON]// }%fX"
    text+="%4F${icons[RUBY_ICON]// }%fX"
    text+="%5F${icons[HOME_ICON]// }%fX"
    text+="%6F${icons[HOME_SUB_ICON]// }%fX"
    text+="%1F${icons[FOLDER_ICON]// }%fX"
    text+="%2F${icons[RAM_ICON]// }%fX"

    add_widget 0 flowing -c %BDo all these icons "%b%2Ffit between the crosses%f%B?%b"
    add_widget 0 print -P ""
    add_widget 0 flowing -c -- "--->  $text  <---"
    add_widget 0 print -P ""
    add_widget 3
    add_widget 0 flowing +c -i 5 "%B(y)  Yes." Icons are very close to the crosses but there is "%b%2Fno overlap%f%B.%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 flowing +c -i 5 "%B(n)  No." Some icons "%b%2Foverlap%f%B" neighbouring crosses.%b
    add_widget 0 print -P ""
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y)
        POWERLEVEL9K_ICON_PADDING=none
        options+=('small icons') ;;
      n)
        POWERLEVEL9K_ICON_PADDING=moderate
        options+=('large icons')
        up_triangle+=' '
        down_triangle+=' '
        slanted_bar='\uE0BD ' ;;
    esac
    return 0
  }

  ask_style() {
    if (( term_colors < 256 )); then
      style=lean_8colors
      left_frame=0
      right_frame=0
      frame_color=([1]=0 7 2 4)
      color_name=([1]=Black White Green Blue)
      options+=(lean_8colors)
      return 0
    fi
    local extra=''
    add_widget 0 flowing -c "%BPrompt Style%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Lean.%b"
    add_prompt style=lean left_frame=0 right_frame=0
    add_widget 0 print -P "%B(2)  Classic.%b"
    add_prompt style=classic
    add_widget 0 print -P "%B(3)  Rainbow.%b"
    add_prompt style=rainbow
    if [[ $POWERLEVEL9K_MODE != ascii ]]; then
      extra+=4
      add_widget 0 print -P "%B(4)  Pure.%b"
      add_prompt style=pure
    fi
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask "123${extra}r"
    case $choice in
      r) return 1 ;;
      1) style=lean; left_frame=0; right_frame=0; options+=(lean) ;;
      2) style=classic; options+=(classic) ;;
      3) style=rainbow; options+=(rainbow) ;;
      4) style=pure; empty_line=1; options+=(pure) ;;
    esac
    return 0
  }

  ask_charset() {
    [[ $style == @(lean*|classic|rainbow) && $POWERLEVEL9K_MODE != ascii ]] || return 0
    add_widget 0 flowing -c "%BCharacter Set%b"
    add_widget 0 print -P ""
    add_widget 1
    add_widget 0 print -P "%B(1)  Unicode.%b"
    add_prompt
    add_widget 0 print -P "%B(2)  ASCII.%b"
    add_prompt         \
      left_sep=        \
      right_sep=       \
      left_subsep='|'  \
      right_subsep='|' \
      left_head=       \
      right_head=      \
      prompt_char='>'  \
      left_frame=0     \
      right_frame=0
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    case $choice in
      r) return 1 ;;
      1) options+=(unicode) ;;
      2)
        options+=(ascii)
        left_sep=
        right_sep=
        left_subsep='|'
        right_subsep='|'
        left_head=
        right_head=
        prompt_char='>'
        left_frame=0
        right_frame=0
        POWERLEVEL9K_MODE=ascii
        POWERLEVEL9K_ICON_PADDING=none
        cap_diamond=0
        cap_python=0
        cap_arrow=0
        cap_lock=0
        cap_quotes=0
        ;;
    esac
    return 0
  }

  ask_color_scheme() {
    (( term_colors < 256 )) && return
    if [[ $style == lean ]]; then
      add_widget 0 flowing -c "%BPrompt Colors%b"
      add_widget 0 print -P ""
      add_widget 1
      add_widget 0 print -P "%B(1)  256 colors.%b"
      add_prompt style=lean
      add_widget 0 print -P "%B(2)  8 colors.%b"
      add_prompt style=lean_8colors
      add_widget 0 print -P "(r)  Restart from the beginning."
      ask 12r
      case $choice in
        r) return 1 ;;
        1) style=lean ;;
        2)
          style=lean_8colors
          frame_color=([1]=0 7 2 4)
          color_name=([1]=Black White Green Blue)
          ;;
      esac
      # options=(${options:#lean} $style)
      local -a o=() x
      for x in "${options[@]}"; do [[ $x == lean ]] || o+=("$x"); done
      options=("${o[@]}" "$style")
    elif [[ $style == pure && $has_truecolor == 1 ]]; then
      add_widget 0 flowing -c "%BPrompt Colors%b"
      add_widget 0 print -P ""
      add_widget 1
      add_widget 0 print -P "%B(1)  Original.%b"
      assoc_arg pure_color pure_original; add_prompt "$REPLY"
      add_widget 0 print -P "%B(2)  Snazzy.%b"
      assoc_arg pure_color pure_snazzy; add_prompt "$REPLY"
      add_widget 0 print -P "(r)  Restart from the beginning."
      ask 12r
      local k
      case $choice in
        r) return 1 ;;
        1)
          pure_color=(); for k in "${!pure_original[@]}"; do pure_color[$k]=${pure_original[$k]}; done
          options+=(original) ;;
        2)
          pure_color=(); for k in "${!pure_snazzy[@]}"; do pure_color[$k]=${pure_snazzy[$k]}; done
          options+=(snazzy) ;;
      esac
    fi
    return 0
  }

  ask_color() {
    [[ $style != classic ]] && return
    add_widget 0 flowing -c "%BPrompt Color%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  ${color_name[1]}.%b"
    add_prompt color=1
    add_widget 0 print -P "%B(2)  ${color_name[2]}.%b"
    add_prompt color=2
    add_widget 0 print -P "%B(3)  ${color_name[3]}.%b"
    add_prompt color=3
    add_widget 0 print -P "%B(4)  ${color_name[4]}.%b"
    add_prompt color=4
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 1234r
    case $choice in
      r) return 1 ;;
      [1-4]) color=$choice ;;
    esac
    local n=${color_name[color],,}
    options+=("${n//ı/i}")
    return 0
  }

  print_frame_marker() {
    local label="(1)  ${color_name[1]}."
    local n=$(( wizard_columns - 7 ))
    local m=$(( n - ${#label} ))
    pp "$(spaces "$n")frame"
    pp "%B$label%b$(spaces "$m")    |"
    pp "$(spaces "$n")    v"
  }

  ask_ornaments_color() {
    [[ $style != @(rainbow|lean*) || $num_lines == 1 ]] && return
    [[ $gap_char == ' ' && $left_frame == 0 && $right_frame == 0 ]] && return
    local -a ornaments=()
    [[ $gap_char != ' ' ]]          && ornaments+=(Connection)
    (( left_frame || right_frame )) && ornaments+=(Frame)
    # zsh ${(j: & :)ornaments}; quoted, as an unquoted & in a bash 5.2
    # replacement stands for the matched text
    local j="${ornaments[*]}"; j=${j// /" & "}
    add_widget 0 flowing -c "%B$j Color%b"
    if (( left_frame || right_frame )); then
      add_widget 0 print_frame_marker
      add_widget 3 print -P "%B(1)  ${color_name[1]}.%b"
      add_prompt_n color=1
      add_widget 0 print
      add_widget 2
    else
      add_widget 1
      add_widget 0 print -P "%B(1)  ${color_name[1]}.%b"
      add_prompt color=1
    fi
    add_widget 0 print -P "%B(2)  ${color_name[2]}.%b"
    add_prompt color=2
    add_widget 0 print -P "%B(3)  ${color_name[3]}.%b"
    add_prompt color=3
    add_widget 0 print -P "%B(4)  ${color_name[4]}.%b"
    add_prompt color=4
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 1234r
    case $choice in
      r) return 1 ;;
      [1-4]) color=$choice ;;
    esac
    local n=${color_name[color],,}
    options+=("${n//ı/i}-ornaments")
    return 0
  }

  ask_time() {
    add_widget 0 flowing -c "%BShow current time?%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(n)  No.%b"
    add_prompt time=
    add_widget 0 print -P "%B(1)  12-hour format.%b"
    add_prompt "time=$time_12h"
    add_widget 0 print -P "%B(2)  24-hour format.%b"
    add_prompt "time=$time_24h"
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask n12r
    case $choice in
      r) return 1 ;;
      n) time= ;;
      1) time=$time_12h; options+=('12h time') ;;
      2) time=$time_24h; options+=('24h time') ;;
    esac
    return 0
  }

  ask_use_rprompt() {
    [[ $style != pure ]] && return
    add_widget 0 flowing -c "%BNon-permanent content location%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Left.%b"
    add_prompt
    add_widget 0 print -P "%B(2)  Right.%b"
    add_prompt pure_use_rprompt=
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    case $choice in
      r) return 1 ;;
      1) ;;
      2) pure_use_rprompt=; options+=(rprompt) ;;
    esac
    return 0
  }

  os_icon_name() {
    local uname; uname=$(uname)
    if [[ $uname == Linux && "$(uname -o 2>/dev/null)" == Android ]]; then
      echo ANDROID_ICON
      return
    fi
    case $uname in
      SunOS)                     echo SUNOS_ICON ;;
      Darwin)                    echo APPLE_ICON ;;
      CYGWIN_NT-*|MSYS_NT-*|MINGW64_NT-*|MINGW32_NT-*) echo WINDOWS_ICON ;;
      FreeBSD|OpenBSD|DragonFly) echo FREEBSD_ICON ;;
      Linux)
        local os_release_id='' line
        if [[ -r /etc/os-release ]]; then
          local -a ids=()
          while IFS= read -r line || [[ -n $line ]]; do
            [[ $line == ID=* ]] && ids+=("$line")
          done </etc/os-release
          if (( ${#ids[@]} == 1 )); then
            _p9k_unquote "${ids[0]#ID=}"; os_release_id=$_p9k__ret
          fi
        elif [[ -e /etc/artix-release ]]; then
          os_release_id=artix
        fi
        case $os_release_id in
          *arch*)                  echo LINUX_ARCH_ICON ;;
          *raspbian*)              echo LINUX_RASPBIAN_ICON ;;
          *debian*)
            if [[ -f /etc/apt/sources.list.d/raspi.list ]]; then
              echo LINUX_RASPBIAN_ICON
            else
              echo LINUX_DEBIAN_ICON
            fi ;;
          *ubuntu*)                echo LINUX_UBUNTU_ICON ;;
          *elementary*)            echo LINUX_ELEMENTARY_ICON ;;
          *fedora*)                echo LINUX_FEDORA_ICON ;;
          *coreos*)                echo LINUX_COREOS_ICON ;;
          *kali*)                  echo LINUX_KALI_ICON ;;
          *gentoo*)                echo LINUX_GENTOO_ICON ;;
          *mageia*)                echo LINUX_MAGEIA_ICON ;;
          *centos*)                echo LINUX_CENTOS_ICON ;;
          *opensuse*|*tumbleweed*) echo LINUX_OPENSUSE_ICON ;;
          *sabayon*)               echo LINUX_SABAYON_ICON ;;
          *slackware*)             echo LINUX_SLACKWARE_ICON ;;
          *linuxmint*)             echo LINUX_MINT_ICON ;;
          *alpine*)                echo LINUX_ALPINE_ICON ;;
          *aosc*)                  echo LINUX_AOSC_ICON ;;
          *nixos*)                 echo LINUX_NIXOS_ICON ;;
          *devuan*)                echo LINUX_DEVUAN_ICON ;;
          *manjaro*)               echo LINUX_MANJARO_ICON ;;
          *void*)                  echo LINUX_VOID_ICON ;;
          *artix*)                 echo LINUX_ARTIX_ICON ;;
          *rhel*)                  echo LINUX_RHEL_ICON ;;
          amzn)                    echo LINUX_AMZN_ICON ;;
          endeavouros)             echo LINUX_ENDEAVOUROS_ICON ;;
          rocky)                   echo LINUX_ROCKY_ICON ;;
          almalinux)               echo LINUX_ALMALINUX_ICON ;;
          guix)                    echo LINUX_GUIX_ICON ;;
          neon)                    echo LINUX_NEON_ICON ;;
          *)                       echo LINUX_ICON ;;
        esac ;;
    esac
  }

  ask_extra_icons() {
    if [[ $style == pure || $POWERLEVEL9K_MODE == @(powerline|compatible|ascii) ]]; then
      return 0
    fi
    local os_icon dir_icon vcs_icon branch_icon duration_icon time_icon
    unescape "${icons[$(os_icon_name)]-}"; os_icon=$REPLY
    unescape "${icons[HOME_SUB_ICON]-}"; dir_icon=$REPLY
    unescape "${icons[VCS_GIT_GITHUB_ICON]-}"; vcs_icon=$REPLY
    unescape "${icons[VCS_BRANCH_ICON]-}"; branch_icon=$REPLY
    unescape "${icons[EXECUTION_TIME_ICON]-}"; duration_icon=$REPLY
    unescape "${icons[TIME_ICON]-}"; time_icon=$REPLY
    branch_icon=${branch_icon// }
    local -a few=('' '' '' '' '')
    local -a many=("$os_icon" "$dir_icon " "$vcs_icon $branch_icon " "$duration_icon " "$time_icon ")
    add_widget 0 flowing -c "%BIcons%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Few icons.%b"
    arr_arg extra_icons few; add_prompt "$REPLY"
    add_widget 0 print -P "%B(2)  Many icons.%b"
    arr_arg extra_icons many; add_prompt "$REPLY"
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    local i
    case $choice in
      r) return 1 ;;
      1) extra_icons=(); for i in "${!few[@]}"; do extra_icons[i+1]=${few[i]}; done; options+=('few icons') ;;
      2) extra_icons=(); for i in "${!many[@]}"; do extra_icons[i+1]=${many[i]}; done; options+=('many icons') ;;
    esac
    return 0
  }

  ask_prefixes() {
    if [[ $style == pure ]]; then
      return 0
    fi
    local -a concise=('' '' '')
    local -a fluent=('on ' 'took ' 'at ')
    add_widget 0 flowing -c "%BPrompt Flow%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Concise.%b"
    arr_arg prefixes concise; add_prompt "$REPLY"
    add_widget 0 print -P "%B(2)  Fluent.%b"
    arr_arg prefixes fluent; add_prompt "$REPLY"
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    local i
    case $choice in
      r) return 1 ;;
      1) prefixes=(); for i in "${!concise[@]}"; do prefixes[i+1]=${concise[i]}; done; options+=(concise) ;;
      2) prefixes=(); for i in "${!fluent[@]}"; do prefixes[i+1]=${fluent[i]}; done; options+=(fluent) ;;
    esac
    return 0
  }

  ask_separators() {
    if [[ $style != @(classic|rainbow) || $cap_diamond != 1 ]]; then
      return 0
    fi
    local extra=''
    add_widget 0 flowing -c "%BPrompt Separators%b"
    add_widget 0 print -Pl "              separator" "%B(1)  Angled.%b /" "            /"
    add_widget 3 print -P "%B(1)  Angled.%b"
    add_prompt_n "left_sep=$right_triangle" "right_sep=$left_triangle" "left_subsep=$right_angle" "right_subsep=$left_angle"
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "%B(2)  Vertical.%b"
    add_prompt left_sep='' right_sep='' "left_subsep=$vertical_bar" "right_subsep=$vertical_bar"
    if [[ $POWERLEVEL9K_MODE == nerdfont-* ]]; then
      extra+=3
      add_widget 0 print -P "%B(3)  Slanted.%b"
      add_prompt "left_sep=$down_triangle" "right_sep=$up_triangle" "left_subsep=$slanted_bar" "right_subsep=$slanted_bar"
      extra+=4
      add_widget 0 print -P "%B(4)  Round.%b"
      add_prompt "left_sep=$right_circle" "right_sep=$left_circle" "left_subsep=$right_arc" "right_subsep=$left_arc"
    fi
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask "12${extra}r"
    case $choice in
      r) return 1 ;;
      1)
        left_sep=$right_triangle
        right_sep=$left_triangle
        left_subsep=$right_angle
        right_subsep=$left_angle
        options+=('angled separators') ;;
      2)
        left_sep=''
        right_sep=''
        left_subsep=$vertical_bar
        right_subsep=$vertical_bar
        options+=('vertical separators') ;;
      3)
        left_sep=$down_triangle
        right_sep=$up_triangle
        left_subsep=$slanted_bar
        right_subsep=$slanted_bar
        options+=('slanted separators') ;;
      4)
        left_sep=$right_circle
        right_sep=$left_circle
        left_subsep=$right_arc
        right_subsep=$left_arc
        options+=('round separators') ;;
    esac
    return 0
  }

  ask_heads() {
    if [[ $style != @(classic|rainbow) || $POWERLEVEL9K_MODE == ascii ]]; then
      return 0
    fi
    local extra=''
    add_widget 0 flowing -c "%BPrompt Heads%b"
    add_widget 0 print -Pl "                  head" "%B(1)  Flat.%b         |" "                   v"
    add_widget 3 print -P "%B(1)  Flat.%b"
    add_prompt_n left_head= right_head=
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "%B(2)  Blurred.%b"
    add_prompt "left_head=$fade_out" "right_head=$fade_in"
    if (( cap_diamond )); then
      extra+=3
      add_widget 0 print -P "%B(3)  Sharp.%b"
      add_prompt "left_head=$right_triangle" "right_head=$left_triangle"
      if [[ $POWERLEVEL9K_MODE == nerdfont-* ]]; then
        extra+=4
        add_widget 0 print -P "%B(4)  Slanted.%b"
        add_prompt "left_head=$down_triangle" "right_head=$up_triangle"
        extra+=5
        add_widget 0 print -P "%B(5)  Round.%b"
        add_prompt "left_head=$right_circle" "right_head=$left_circle"
      fi
    fi
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask "12${extra}r"
    case $choice in
      r) return 1 ;;
      1) left_head= right_head=; options+=('flat heads') ;;
      2) left_head=$fade_out right_head=$fade_in; options+=('blurred heads') ;;
      3) left_head=$right_triangle right_head=$left_triangle; options+=('sharp heads') ;;
      4) left_head=$down_triangle right_head=$up_triangle; options+=('slanted heads') ;;
      5) left_head=$right_circle right_head=$left_circle; options+=('round heads') ;;
    esac
    return 0
  }

  print_tail_marker() {
    local label='(1)  Flat.'
    local n=$(( wizard_columns - 7 ))
    local m=$(( n - ${#label} ))
    pp "$(spaces "$n")tail"
    pp "%B$label%b$(spaces "$m")  |"
    pp "$(spaces "$n")  v"
  }

  ask_tails() {
    if [[ $style != @(classic|rainbow) || $POWERLEVEL9K_MODE == ascii ]]; then
      return 0
    fi
    local extra=''
    add_widget 0 flowing -c "%BPrompt Tails%b"
    add_widget 0 print_tail_marker
    add_widget 3 print -P "%B(1)  Flat.%b"
    add_prompt_n left_tail='' right_tail=''
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "%B(2)  Blurred.%b"
    add_prompt "left_tail=$fade_in" "right_tail=$fade_out"
    if (( cap_diamond )); then
      extra+=3
      add_widget 0 print -P "%B(3)  Sharp.%b"
      add_prompt "left_tail=$left_triangle" "right_tail=$right_triangle"
      if [[ $POWERLEVEL9K_MODE == nerdfont-* ]]; then
        extra+=4
        add_widget 0 print -P "%B(4)  Slanted.%b"
        add_prompt "left_tail=$up_triangle" "right_tail=$down_triangle"
        extra+=5
        add_widget 0 print -P "%B(5)  Round.%b"
        add_prompt "left_tail=$left_circle" "right_tail=$right_circle"
      fi
    fi
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask "12${extra}r"
    case $choice in
      r) return 1 ;;
      1) left_tail='' right_tail=''; options+=('flat tails') ;;
      2) left_tail=$fade_in right_tail=$fade_out; options+=('blurred tails') ;;
      3) left_tail=$left_triangle right_tail=$right_triangle; options+=('sharp tails') ;;
      4) left_tail=$up_triangle right_tail=$down_triangle; options+=('slanted tails') ;;
      5) left_tail=$left_circle right_tail=$right_circle; options+=('round tails') ;;
    esac
    return 0
  }

  ask_num_lines() {
    add_widget 0 flowing -c "%BPrompt Height%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  One line.%b"
    add_prompt num_lines=1
    add_widget 0 print -P "%B(2)  Two lines.%b"
    add_prompt num_lines=2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    case $choice in
      r) return 1 ;;
      1) num_lines=1; options+=('1 line') ;;
      2) num_lines=2; options+=('2 lines') ;;
    esac
    return 0
  }

  ask_gap_char() {
    [[ $num_lines != 2 || $style == pure ]] && return
    local dot dash
    if [[ $POWERLEVEL9K_MODE == ascii ]]; then
      dot='.' dash='-'
    else
      dot='·' dash='─'
    fi
    add_widget 0 flowing -c "%BPrompt Connection%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Disconnected.%b"
    add_prompt gap_char=" "
    add_widget 0 print -P "%B(2)  Dotted.%b"
    add_prompt "gap_char=$dot"
    add_widget 0 print -P "%B(3)  Solid.%b"
    add_prompt "gap_char=$dash"
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 123r
    case $choice in
      r) return 1 ;;
      1) gap_char=" "; options+=(disconnected) ;;
      2) gap_char=$dot; options+=(dotted) ;;
      3) gap_char=$dash; options+=(solid) ;;
    esac
    return 0
  }

  ask_frame() {
    if [[ $style != @(classic|rainbow|lean*) || $num_lines != 2 || $POWERLEVEL9K_MODE == ascii ]]; then
      return 0
    fi
    add_widget 0 flowing -c "%BPrompt Frame%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  No frame.%b"
    add_prompt left_frame=0 right_frame=0
    add_widget 0 print -P "%B(2)  Left.%b"
    add_prompt left_frame=1 right_frame=0
    add_widget 0 print -P "%B(3)  Right.%b"
    add_prompt left_frame=0 right_frame=1
    add_widget 0 print -P "%B(4)  Full.%b"
    add_prompt left_frame=1 right_frame=1
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 1234r
    case $choice in
      r) return 1 ;;
      1) left_frame=0; right_frame=0; options+=('no frame') ;;
      2) left_frame=1; right_frame=0; options+=('left frame') ;;
      3) left_frame=0; right_frame=1; options+=('right frame') ;;
      4) left_frame=1; right_frame=1; options+=('full frame') ;;
    esac
    return 0
  }

  ask_empty_line() {
    add_widget 0 flowing -c "%BPrompt Spacing%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(1)  Compact.%b"
    add_widget 0 print
    add_widget 1
    add_prompt_n
    add_prompt_n
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "%B(2)  Sparse.%b"
    add_widget 0 print
    add_widget 1
    add_prompt_n
    add_widget 0 print
    add_prompt_n
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 12r
    case $choice in
      r) return 1 ;;
      1) empty_line=0; options+=(compact) ;;
      2) empty_line=1; options+=(sparse) ;;
    esac
    return 0
  }

  print_instant_prompt_link() {
    local link='https://github.com/romkatv/powerlevel10k#instant-prompt'
    (( wizard_columns < ${#link} )) && return
    printf '\n'
    flowing -c "$(href "$link")"
  }

  ask_instant_prompt() {
    add_widget 0 flowing -c "%BInstant Prompt Mode%b"
    add_widget 0 print_instant_prompt_link
    add_widget 1
    add_widget 0 print
    add_widget 2
    add_widget 0 flowing +c -i 5 "%B(1)  Verbose (recommended).%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 flowing +c -i 5 "%B(2)  Quiet.%b" "Choose" this if "you've" read and understood \
      instant prompt documentation.
    add_widget 0 print
    add_widget 1
    add_widget 0 flowing +c -i 5 "%B(3)  Off.%b" "Choose" this if "you've" tried instant prompt \
      and found it incompatible with your zsh configuration files.
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask 123r
    case $choice in
      r) return 1 ;;
      1) instant_prompt=verbose; options+=(instant_prompt=verbose) ;;
      2) instant_prompt=quiet; options+=(instant_prompt=quiet) ;;
      3) instant_prompt=off; options+=(instant_prompt=off) ;;
    esac
    return 0
  }

  ask_transient_prompt() {
    local disable_rprompt=$(( num_lines == 1 ))
    local p=76
    [[ $style == pure ]] && p=${pure_color[magenta]}
    [[ $style == lean_8colors ]] && p=2
    p="%F{$p}$prompt_char%f"
    local ind; ind=$(spaces "$prompt_indent")
    add_widget 0 flowing -c "%BEnable Transient Prompt?%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 print -P "$ind$p %2Fgit%f pull"
    add_widget 3
    add_widget 0 print -P "$ind$p %2Fgit%f branch x"
    (( empty_line )) && add_widget 0 print
    add_prompt_n "buffer=%2Fgit%f checkout x$cursor" "disable_rprompt=$disable_rprompt"
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "%B(n)  No.%b"
    add_widget 0 print
    add_widget 1
    add_widget 0 with "buffer=%2Fgit%f pull" "disable_rprompt=$disable_rprompt" -- print_prompt
    add_widget 3
    (( empty_line )) && { add_widget 0 print; add_widget 3; }
    add_prompt_n "buffer=%2Fgit%f branch x" "disable_rprompt=$disable_rprompt"
    (( empty_line )) && add_widget 0 print
    add_prompt_n "buffer=%2Fgit%f checkout x$cursor" "disable_rprompt=$disable_rprompt"
    add_widget 0 print
    add_widget 2
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask ynr
    case $choice in
      r) return 1 ;;
      y) transient_prompt=1; options+=(transient_prompt) ;;
      n) transient_prompt=0 ;;
    esac
    return 0
  }

  # a backup file name in $TMPDIR or /tmp (as p10k chooses) -> tmpdir, tmpdir_u
  _wz_tmpdir() {
    if [[ -n ${TMPDIR-} && ( ( -d $TMPDIR && -w $TMPDIR ) || ! ( -d /tmp && -w /tmp ) ) ]]; then
      tmpdir=$TMPDIR tmpdir_u='$TMPDIR'
    else
      tmpdir=/tmp tmpdir_u=/tmp
    fi
  }

  ask_config_overwrite() {
    config_backup=
    config_backup_u=0
    if [[ ! -e $__p9k_cfg_path ]]; then
      return 0
    fi
    add_widget 0 flowing -c Powerlevel10k config file already exists.
    add_widget 0 flowing -c "%BOverwrite" "%b%2F${__p9k_cfg_path_u//\\/\\\\}%f%B?%b"
    add_widget 0 print -P ""
    add_widget 0 print -P "%B(y)  Yes.%b"
    add_widget 0 print -P ""
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask yr
    case $choice in
      r) return 1 ;;
      y)
        local tmpdir tmpdir_u; _wz_tmpdir
        if ! command -v mktemp >/dev/null ||
           ! config_backup=$(mktemp "$tmpdir/$__p9k_cfg_basename.XXXXXXXXXX" 2>/dev/null); then
          config_backup=$tmpdir/$__p9k_cfg_basename.${EPOCHREALTIME/,/.}
        fi
        cp -- "$__p9k_cfg_path" "$config_backup" || quit -c
        local q; printf -v q '%q' "${config_backup##*/}"
        config_backup_u=$tmpdir_u/$q
        ;;
    esac
    return 0
  }

  # p10k: check_zshrc_integration, for ~/.bashrc: does it source the config?
  # (Instant prompt for bash belongs to bash4humans; nothing to add for it.)
  check_zshrc_integration() {
    zshrc_content= zshrc_has_cfg=0 zshrc_has_instant_prompt=1
    [[ -e $__p9k_zshrc ]] || return 0
    zshrc_content=$(<"$__p9k_zshrc") || return
    local f0=$__p9k_cfg_path_o f1 g1
    printf -v f1 '%q' "$f0"
    g1=$f1; [[ $f1 == "$HOME"/* ]] && g1="~/${f1#"$HOME"/}"
    local -a pats=("$f0" "$f1" "'$f0'" "\"$f0\"" "$g1"
      '~/.p10k.bash' '$HOME/.p10k.bash' '"$HOME/.p10k.bash"' '"$HOME"/.p10k.bash'
      '${HOME}/.p10k.bash' '"${HOME}/.p10k.bash"' '$POWERLEVEL9K_CONFIG_FILE' '"$POWERLEVEL9K_CONFIG_FILE"')
    local line p
    while IFS= read -r line; do
      line=${line%%#*}
      for p in "${pats[@]}"; do
        if [[ $line =~ (^|[^A-Za-z0-9_])(source|\.)[[:space:]]+(--[[:space:]]+)?([^[:space:]]+) ]] &&
           [[ ${BASH_REMATCH[4]} == "$p" ]]; then
          zshrc_has_cfg=1
        fi
      done
    done <<<"$zshrc_content"
    return 0
  }

  ask_zshrc_edit() {
    zshrc_content=
    zshrc_backup=
    zshrc_backup_u=
    zshrc_has_cfg=0
    zshrc_has_instant_prompt=0
    write_zshrc=0

    if (( in_b4h )); then
      zshrc_has_cfg=1
      zshrc_has_instant_prompt=1
      return
    fi

    check_zshrc_integration || quit -c
    [[ $instant_prompt == off ]] && zshrc_has_instant_prompt=1
    (( zshrc_has_cfg && zshrc_has_instant_prompt )) && return

    add_widget 0 flowing -c %BApply changes to "%b%2F${__p9k_zshrc_u//\\/\\\\}%f%B?%b"
    add_widget 0 print -P ""
    add_widget 1
    local modifiable=y
    if [[ ! -w $__p9k_zd ]]; then
      modifiable=
      add_widget 0 flowing -c %3FWARNING:%f %2F${__p9k_zd_u//\\/\\\\}%f %3Fis readonly.%f
      add_widget 0 print -P ""
    elif [[ -e $__p9k_zshrc && ! -w $__p9k_zshrc ]]; then
      local owner; owner=$(stat -c %u -- "$__p9k_zshrc" 2>/dev/null) || quit -c
      if (( owner == EUID )); then
        add_widget 0 flowing -c %3FNOTE:%f %2F${__p9k_zshrc_u//\\/\\\\}%f %3Fis readonly.%f
      else
        modifiable=
        add_widget 0 flowing -c                                           \
          %3FWARNING:%f %2F${__p9k_zshrc_u//\\/\\\\}%f %3Fis readonly and \
          not owned by the user. Cannot modify it.%f
      fi
      add_widget 0 print -P ""
    fi
    if [[ $modifiable == y ]]; then
      add_widget 0 print -P "%B(y)  Yes (recommended).%b"
    else
      add_widget 0 print -P "%1F(y)  Yes (disabled).%f"
    fi
    add_widget 0 print -P ""
    add_widget 0 flowing +c -i 5 "%B(n)  No." I know which changes to apply and will do it myself.%b
    add_widget 0 print -P ""
    add_widget 0 print -P "(r)  Restart from the beginning."
    ask "${modifiable}nr"
    case $choice in
      r) return 1 ;;
      n) return 0 ;;
      y)
        write_zshrc=1
        if [[ -n $zshrc_content ]]; then
          local tmpdir tmpdir_u; _wz_tmpdir
          if ! command -v mktemp >/dev/null ||
             ! zshrc_backup=$(mktemp "$tmpdir/.bashrc.XXXXXXXXXX" 2>/dev/null); then
            zshrc_backup=$tmpdir/.bashrc.${EPOCHREALTIME/,/.}
          fi
          if ! cp -p -- "$__p9k_zshrc" "$zshrc_backup" 2>/dev/null; then
            # cp -p fails on some network filesystems: content and mode separately
            cp -- "$__p9k_zshrc" "$zshrc_backup" || quit -c
            chmod --reference="$__p9k_zshrc" -- "$zshrc_backup" || quit -c
          fi
          local writable=1
          if [[ ! -w $zshrc_backup ]]; then
            chmod u+w -- "$zshrc_backup" || quit -c
            writable=0
          fi
          printf '%s\n' "$zshrc_content" >"$zshrc_backup" || quit -c
          (( writable )) || chmod u-w -- "$zshrc_backup" || quit -c
          local q; printf -v q '%q' "${zshrc_backup##*/}"
          zshrc_backup_u=$tmpdir_u/$q
        fi
        ;;
    esac
    return 0
  }

  # p10k: generate_config - the template with the wizard's edits. Written in
  # bash form (from p10k/config); b4h-tool converts only if that is missing.
  generate_config() {
    local base
    base=$(<"$__p9k_templates/p10k-${style//_/-}.zsh") || return
    local -a lines
    mapfile -t lines <<<"$base"

    # zsh: lines=("${(@)lines/#(#b)([[:space:]]#)typeset -g POWERLEVEL9K_$1=*/...}")
    sub() {
      local i l ws
      for i in "${!lines[@]}"; do
        l=${lines[i]}
        ws=${l%%[![:space:]]*}
        [[ ${l:${#ws}} == "typeset -g POWERLEVEL9K_$1="* ]] && lines[i]="${ws}typeset -g POWERLEVEL9K_$1=$2"
      done
    }
    # zsh: lines=("${(@)lines/#(#b)([[:space:]]#)\# $1(  |)/$match[1]$1$match[2]$match[2]}")
    uncomment() {
      local i l ws rest
      for i in "${!lines[@]}"; do
        l=${lines[i]}
        ws=${l%%[![:space:]]*}
        rest=${l:${#ws}}
        if [[ $rest == "# $1  "* ]]; then
          lines[i]="$ws$1    ${rest:$(( ${#1} + 4 ))}"
        elif [[ $rest == "# $1"* ]]; then
          lines[i]="$ws$1${rest:$(( ${#1} + 2 ))}"
        fi
      done
    }
    # zsh: lines=("${(@)lines//$1/$2}")
    rep() {
      local i
      for i in "${!lines[@]}"; do lines[i]=${lines[i]//"$1"/"$2"}; done
    }

    # The wizard's edits of the template in `lines` (p10k: generate_config).
    # Applied to p10k's zsh template and to the same template converted to
    # bash (p10k/config), which then needs no converter: the edits touch the
    # POWERLEVEL9K_* lines and comments, which the conversion leaves as they
    # are (tests/p10k/wizard.sh checks both results).
    edits() {
    if [[ $style == pure ]]; then
      rep "local grey=242" "local grey='${pure_color[grey]}'"
      rep "local red=1" "local red='${pure_color[red]}'"
      rep "local yellow=3" "local yellow='${pure_color[yellow]}'"
      rep "local blue=4" "local blue='${pure_color[blue]}'"
      rep "local magenta=5" "local magenta='${pure_color[magenta]}'"
      rep "local cyan=6" "local cyan='${pure_color[cyan]}'"
      rep "local white=7" "local white='${pure_color[white]}'"
    else
      sub MODE "$POWERLEVEL9K_MODE"

      sub ICON_PADDING "$POWERLEVEL9K_ICON_PADDING"

      if [[ $POWERLEVEL9K_MODE == compatible ]]; then
        sub STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION "'х'"
        sub STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION "'х'"
        sub STATUS_ERROR_PIPE_VISUAL_IDENTIFIER_EXPANSION "'х'"
      fi

      if [[ $POWERLEVEL9K_MODE == @(compatible|powerline) ]]; then
        uncomment 'typeset -g POWERLEVEL9K_LOCK_ICON'
        sub LOCK_ICON "'∅'"
        uncomment 'typeset -g POWERLEVEL9K_NORDVPN_VISUAL_IDENTIFIER_EXPANSION'
        sub NORDVPN_VISUAL_IDENTIFIER_EXPANSION "'nord'"
        uncomment 'typeset -g POWERLEVEL9K_RANGER_VISUAL_IDENTIFIER_EXPANSION'
        sub RANGER_VISUAL_IDENTIFIER_EXPANSION "'▲'"
        uncomment 'typeset -g POWERLEVEL9K_YAZI_VISUAL_IDENTIFIER_EXPANSION'
        sub YAZI_VISUAL_IDENTIFIER_EXPANSION "'▲'"
        uncomment 'typeset -g POWERLEVEL9K_KUBECONTEXT_DEFAULT_VISUAL_IDENTIFIER_EXPANSION'
        sub KUBECONTEXT_DEFAULT_VISUAL_IDENTIFIER_EXPANSION "'○'"
        uncomment 'typeset -g POWERLEVEL9K_AZURE_VISUAL_IDENTIFIER_EXPANSION'
        sub AZURE_VISUAL_IDENTIFIER_EXPANSION "'az'"
        uncomment 'typeset -g POWERLEVEL9K_AWS_EB_ENV_VISUAL_IDENTIFIER_EXPANSION'
        sub AWS_EB_ENV_VISUAL_IDENTIFIER_EXPANSION "'eb'"
        uncomment 'typeset -g POWERLEVEL9K_BACKGROUND_JOBS_VISUAL_IDENTIFIER_EXPANSION'
        sub BACKGROUND_JOBS_VISUAL_IDENTIFIER_EXPANSION "'≡'"
      fi

      if [[ $POWERLEVEL9K_MODE == @(awesome-patched|awesome-fontconfig) && $cap_python == 0 ]]; then
        uncomment 'typeset -g POWERLEVEL9K_VIRTUALENV_VISUAL_IDENTIFIER_EXPANSION'
        uncomment 'typeset -g POWERLEVEL9K_ANACONDA_VISUAL_IDENTIFIER_EXPANSION'
        uncomment 'typeset -g POWERLEVEL9K_PYENV_VISUAL_IDENTIFIER_EXPANSION'
        uncomment 'typeset -g POWERLEVEL9K_PYTHON_ICON'
        sub VIRTUALENV_VISUAL_IDENTIFIER_EXPANSION "'🐍'"
        sub ANACONDA_VISUAL_IDENTIFIER_EXPANSION "'🐍'"
        sub PYENV_VISUAL_IDENTIFIER_EXPANSION "'🐍'"
        sub PYTHON_ICON "'🐍'"
      fi

      case $POWERLEVEL9K_MODE in
        nerdfont-complete)
          sub BATTERY_STAGES "'\\uf58d\\uf579\\uf57a\\uf57b\\uf57c\\uf57d\\uf57e\\uf57f\\uf580\\uf581\\uf578'" ;;
        nerdfont-v3)
          sub BATTERY_STAGES "'\\UF008E\\UF007A\\UF007B\\UF007C\\UF007D\\UF007E\\UF007F\\UF0080\\UF0081\\UF0082\\UF0079'" ;;
      esac

      if [[ $style == @(classic|rainbow) ]]; then
        if [[ $style == classic ]]; then
          sub BACKGROUND "${bg_color[color]}"
          sub LEFT_SUBSEGMENT_SEPARATOR "'%${sep_color[color]}F$left_subsep'"
          sub RIGHT_SUBSEGMENT_SEPARATOR "'%${sep_color[color]}F$right_subsep'"
          sub VCS_LOADING_FOREGROUND "${sep_color[color]}"
          rep '%248F' "%${prefix_color[color]}F"
        else
          sub LEFT_SUBSEGMENT_SEPARATOR "'$left_subsep'"
          sub RIGHT_SUBSEGMENT_SEPARATOR "'$right_subsep'"
        fi
        sub RULER_FOREGROUND "${frame_color[color]}"
        sub MULTILINE_FIRST_PROMPT_GAP_FOREGROUND "${frame_color[color]}"
        sub MULTILINE_FIRST_PROMPT_PREFIX "'%${frame_color[color]}F╭─'"
        sub MULTILINE_NEWLINE_PROMPT_PREFIX "'%${frame_color[color]}F├─'"
        sub MULTILINE_LAST_PROMPT_PREFIX "'%${frame_color[color]}F╰─'"
        sub MULTILINE_FIRST_PROMPT_SUFFIX "'%${frame_color[color]}F─╮'"
        sub MULTILINE_NEWLINE_PROMPT_SUFFIX "'%${frame_color[color]}F─┤'"
        sub MULTILINE_LAST_PROMPT_SUFFIX "'%${frame_color[color]}F─╯'"
        sub LEFT_SEGMENT_SEPARATOR "'$left_sep'"
        sub RIGHT_SEGMENT_SEPARATOR "'$right_sep'"
        sub LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL "'$left_tail'"
        sub LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL "'$left_head'"
        sub RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL "'$right_head'"
        sub RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL "'$right_tail'"
      fi

      if [[ -n ${extra_icons[1]}${extra_icons[2]-}${extra_icons[3]-}${extra_icons[4]-}${extra_icons[5]-} ]]; then
        # p10k writes the icon table's text, where a glyph is an escape
        # (backslash, u, 4 hex digits); this table holds the glyph itself
        local branch_icon=${icons[VCS_BRANCH_ICON]// } esc='' ch code bs=$'\x5c' i
        for (( i = 0; i < ${#branch_icon}; i++ )); do
          ch=${branch_icon:i:1}
          printf -v code '%d' "'$ch"
          if (( code > 127 )); then printf -v ch '%su%04X' "$bs" "$code"; fi
          esc+=$ch
        done
        sub VCS_BRANCH_ICON "'$esc '"
        uncomment os_icon
      else
        uncomment 'typeset -g POWERLEVEL9K_DIR_CLASSES'
        uncomment 'typeset -g POWERLEVEL9K_VCS_VISUAL_IDENTIFIER_EXPANSION'
        uncomment 'typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION'
        uncomment 'typeset -g POWERLEVEL9K_TIME_VISUAL_IDENTIFIER_EXPANSION'
        sub VCS_VISUAL_IDENTIFIER_EXPANSION ''
        sub COMMAND_EXECUTION_TIME_VISUAL_IDENTIFIER_EXPANSION ''
        sub TIME_VISUAL_IDENTIFIER_EXPANSION ''
      fi

      if [[ -n ${prefixes[1]-}${prefixes[2]-}${prefixes[3]-} ]]; then
        uncomment 'typeset -g POWERLEVEL9K_VCS_PREFIX'
        uncomment 'typeset -g POWERLEVEL9K_COMMAND_EXECUTION_TIME_PREFIX'
        uncomment 'typeset -g POWERLEVEL9K_CONTEXT_PREFIX'
        uncomment 'typeset -g POWERLEVEL9K_KUBECONTEXT_PREFIX'
        uncomment 'typeset -g POWERLEVEL9K_TIME_PREFIX'
        uncomment 'typeset -g POWERLEVEL9K_TOOLBOX_PREFIX'
        if [[ $style == @(lean|classic) ]]; then
          local fg
          if [[ $style == classic ]]; then fg="%${prefix_color[color]}F"; else fg="%f"; fi
          sub VCS_PREFIX "'${fg}on '"
          sub COMMAND_EXECUTION_TIME_PREFIX "'${fg}took '"
          sub CONTEXT_PREFIX "'${fg}with '"
          sub KUBECONTEXT_PREFIX "'${fg}at '"
          sub TIME_PREFIX "'${fg}at '"
          sub TOOLBOX_PREFIX "'${fg}in '"
        fi
      fi

      sub MULTILINE_FIRST_PROMPT_GAP_CHAR "'$gap_char'"

      if [[ $style == @(classic|rainbow) && $num_lines == 2 ]]; then
        if (( ! right_frame )); then
          sub MULTILINE_FIRST_PROMPT_SUFFIX ''
          sub MULTILINE_NEWLINE_PROMPT_SUFFIX ''
          sub MULTILINE_LAST_PROMPT_SUFFIX ''
        fi
        if (( ! left_frame )); then
          sub MULTILINE_FIRST_PROMPT_PREFIX ''
          sub MULTILINE_NEWLINE_PROMPT_PREFIX ''
          sub MULTILINE_LAST_PROMPT_PREFIX ''
          sub STATUS_OK false
          sub STATUS_ERROR false
        fi
      fi

      if [[ $style == lean* ]]; then
        sub RULER_FOREGROUND "${frame_color[color]}"
        sub MULTILINE_FIRST_PROMPT_GAP_FOREGROUND "${frame_color[color]}"
        if (( right_frame )); then
          sub MULTILINE_FIRST_PROMPT_SUFFIX "'%${frame_color[color]}F─╮'"
          sub MULTILINE_NEWLINE_PROMPT_SUFFIX "'%${frame_color[color]}F─┤'"
          sub MULTILINE_LAST_PROMPT_SUFFIX "'%${frame_color[color]}F─╯'"
          sub RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL "' '"
        fi
        if (( left_frame )); then
          sub MULTILINE_FIRST_PROMPT_PREFIX "'%${frame_color[color]}F╭─'"
          sub MULTILINE_NEWLINE_PROMPT_PREFIX "'%${frame_color[color]}F├─'"
          sub MULTILINE_LAST_PROMPT_PREFIX "'%${frame_color[color]}F╰─'"
          sub LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL "' '"
        fi
      fi

      if [[ $style == @(classic|rainbow) ]]; then
        if (( num_lines == 2 && ! left_frame )); then
          uncomment prompt_char
        else
          uncomment vi_mode
        fi
      fi

      if [[ $POWERLEVEL9K_MODE == ascii ]]; then
        sub 'STATUS_OK_VISUAL_IDENTIFIER_EXPANSION' "'ok'"
        sub 'STATUS_OK_PIPE_VISUAL_IDENTIFIER_EXPANSION' "'ok'"
        sub 'STATUS_ERROR_VISUAL_IDENTIFIER_EXPANSION' "'err'"
        sub 'STATUS_ERROR_SIGNAL_VISUAL_IDENTIFIER_EXPANSION' ""
        sub 'STATUS_ERROR_PIPE_VISUAL_IDENTIFIER_EXPANSION' "'err'"
        sub 'BATTERY_STAGES' "('battery')"
        sub 'PROMPT_CHAR_{OK,ERROR}_VIINS_CONTENT_EXPANSION' "'>'"
        sub 'PROMPT_CHAR_{OK,ERROR}_VICMD_CONTENT_EXPANSION' "'<'"
        sub 'PROMPT_CHAR_{OK,ERROR}_VIVIS_CONTENT_EXPANSION' "'V'"
        sub 'PROMPT_CHAR_{OK,ERROR}_VIOWR_CONTENT_EXPANSION' "'^'"
        rep "-i '⭐'" "-i '*'"
        rep '…' '..'
        # (the same in the converted template, where timewarrior's zsh
        # expansion with … is a helper call: b4h-tool's ASCII variant)
        rep '_p9k_x_timewarrior()' '_p9k_x_timewarrior_ascii()'
        rep '⇣' '<'
        rep '⇡' '>'
        rep '⇠' '<-'
        rep '⇢' '->'
        rep '─' '-'
      fi
    fi

    if [[ -v pure_use_rprompt ]]; then
      local segment
      for segment in command_execution_time virtualenv context; do
        rep "    $segment" "    tmp_$segment"
        uncomment "$segment"
        rep "    tmp_$segment  " "    # $segment"
      done
    fi

    if [[ -n $time ]]; then
      uncomment time
      if [[ $time == "$time_12h" ]]; then
        sub TIME_FORMAT "'%D{%I:%M:%S %p}'"
      fi
    fi

    if (( num_lines == 1 )); then
      local -a tmp=()
      local line
      for line in "${lines[@]}"; do
        [[ $line == '    newline'* || $line == *'===[ Line #'* ]] || tmp+=("$line")
      done
      lines=("${tmp[@]}")
    fi

    if (( empty_line )); then sub PROMPT_ADD_NEWLINE true; else sub PROMPT_ADD_NEWLINE false; fi

    sub INSTANT_PROMPT "$instant_prompt"
    (( transient_prompt )) && sub TRANSIENT_PROMPT always
    return 0
    }   # edits

    edits
    local -a zlines=("${lines[@]}")
    # the bash form: the converted template (its first two lines are the
    # converter's note, kept at the top), edited the same way
    # (mapfile, not $(<...): its last lines are blank - zsh's closing
    # statements, blanked by the conversion - and belong to the result)
    local bnote=''
    local -a blines=()
    local btpl=${_p9k_root%/lib/p10k}/p10k/config/p10k-${style//_/-}.bash
    if [[ -r $btpl ]] && mapfile -t lines <"$btpl" && (( ${#lines[@]} > 2 )); then
      bnote=${lines[0]}$'\n'${lines[1]}
      lines=("${lines[@]:2}")
      edits
      blines=("${lines[@]}")
    fi

    _p9k_strftime '%Y-%m-%d at %H:%M %Z'
    local header="# Generated by Powerlevel10k configuration wizard on $_p9k__ret."$'\n'
    header+="# Based on romkatv/powerlevel10k/config/p10k-${style//_/-}.zsh"
    local sum_cmd; sum_cmd=$(type -P sum)
    if [[ $sum_cmd == @(/bin|/usr/bin|/usr/local/bin)/sum ]]; then
      local -a sum
      local crlf=$'\r\n'
      if read -r -a sum < <(sum <<<"${base//$crlf/$'\n'}" 2>/dev/null) && (( ${#sum[@]} == 2 )); then
        header+=", checksum ${sum[0]}"
      fi
    fi
    header+=$'.\n'
    local line="# Wizard options: ${options[0]}" opt
    for opt in "${options[@]:1}"; do
      if (( ${#line} + ${#opt} > 85 )); then
        header+=$line
        header+=$',\n'
        line="# $opt"
      else
        line+=", $opt"
      fi
    done
    header+=$line
    header+=$'.\n# Type `p10k configure` to generate another config.\n#'

    local cfg_dir=${__p9k_cfg_path%/*}
    command mkdir -p -- "${cfg_dir:-/}" || return

    # The bash form written directly; p10k's own (zsh) form is kept only for
    # the tests (_P9K_WIZARD_KEEP_ZSH)
    [[ -n ${_P9K_WIZARD_KEEP_ZSH-} ]] && printf '%s\n' "$header" "${zlines[@]}" >"$_P9K_WIZARD_KEEP_ZSH"
    if (( ${#blines[@]} )); then
      # (p10k: print -lr -- $header $lines >$__p9k_cfg_path)
      printf '%s\n' "$bnote" "$header" "${blines[@]}" >"$__p9k_cfg_path"
      return
    fi
    # no bash template: p10k's form, converted by b4h-tool
    local zcfg; zcfg=$(mktemp "${cfg_dir:-/}/.p10k-wizard.XXXXXXXXXX") || return
    printf '%s\n' "$header" "${zlines[@]}" >"$zcfg" || { rm -f -- "$zcfg"; return 1; }
    local tool
    tool=$(type -P b4h-tool) || tool=${B4H_HOME:-$HOME/.cache/bash4humans}/deps/bin/b4h-tool
    if [[ -e $__p9k_cfg_path ]]; then
      rm -f -- "$__p9k_cfg_path" || { rm -f -- "$zcfg"; return 1; }
    fi
    if ! "$tool" p10k-config "$zcfg" "$__p9k_cfg_path"; then
      rm -f -- "$zcfg"
      return 1
    fi
    rm -f -- "$zcfg"
  }

  change_zshrc() {
    (( write_zshrc )) || return 0
    local tmp=$__p9k_zshrc.$USER.tmp.$$ r=0
    [[ ! -e $__p9k_zshrc ]] || cp -p -- "$__p9k_zshrc" "$tmp" || return
    {
      local writable=1
      if [[ -e $tmp && ! -w $tmp ]]; then
        chmod u+w -- "$tmp" || r=1
        writable=0
      fi
      (( r )) || : >"$tmp" || r=1
      if (( ! r )) && [[ -n $zshrc_content ]]; then
        printf '%s\n' "$zshrc_content" >>"$tmp" || r=1
      fi
      if (( ! r && ! zshrc_has_cfg )); then
        printf '\n%s\n%s\n' "# To customize prompt, run \`p10k configure\` or edit $__p9k_cfg_path_u." \
          "[[ ! -f $__p9k_cfg_path_u ]] || source $__p9k_cfg_path_u" >>"$tmp" || r=1
      fi
      (( r )) || (( writable )) || chmod u-w -- "$tmp" || r=1
      (( r )) || command mv -f -- "$tmp" "$__p9k_zshrc" || r=1
    }
    rm -f -- "$tmp"
    (( r )) && return 1

    if [[ -n $zshrc_backup_u ]]; then
      pp ""
      flowing +c See "%B${__p9k_zshrc_u//\\/\\\\}%b" changes:
      pp "
  %2Fdiff%f %B$zshrc_backup_u%b %B$__p9k_zshrc_u%b"
    fi
    return 0
  }

  # the screen to come back to (zsh: echoti smcup / rmcup)
  if tput smcup >/dev/null 2>&1 && tput rmcup >/dev/null 2>&1; then
    tput smcup 2>/dev/null
    restore_screen() { tput rmcup 2>/dev/null; restore_screen() { :; }; }
  else
    restore_screen() { :; }
  fi

  # what quit, the end and a signal leave behind (zsh: always { ... }). It
  # runs at the end of _p9k_wizard; the EXIT trap covers `exit` (quit, a
  # signal), which leaves while this function's variables are still in scope.
  _wz_cleanup() {
    trap - EXIT INT TERM
    (( success )) || quit
    consume_input
    stty echo 2>/dev/null
    show_cursor
    restore_screen
  }
  trap '_wz_cleanup' EXIT
  trap 'exit 1' INT TERM

  _p9k_wizard_main
  local ret=$?
  _wz_cleanup
  return "$ret"
}

# The wizard's main part (wizard.zsh from `if (( force ))` to the end); the
# variables and functions of _p9k_wizard are visible here.
_p9k_wizard_main() {
  if (( force )); then
    _p9k_can_configure || return
  else
    _p9k_can_configure -q || return
  fi

  local term_colors; term_colors=$(tput colors 2>/dev/null) || term_colors=8
  [[ $term_colors =~ ^[0-9]+$ ]] || term_colors=8
  local has_truecolor=0
  [[ ${COLORTERM-} == @(24bit|truecolor) ]] && has_truecolor=1

  stty -echo 2>/dev/null

  local _p9k_term_has_href=0
  [[ ${VTE_VERSION-} =~ ^([1-9][0-9]{0,2}|[1-3][0-9]{3}|4[0-5][0-9]{2}|460[0-2]|4801)$ ]] || _p9k_term_has_href=1

  local instant_prompt zshrc_content zshrc_backup zshrc_backup_u zshrc_has_cfg zshrc_has_instant_prompt write_zshrc
  local POWERLEVEL9K_MODE POWERLEVEL9K_ICON_PADDING style config_backup config_backup_u
  local gap_char prompt_char down_triangle up_triangle slanted_bar
  local left_sep right_sep left_subsep right_subsep left_tail right_tail left_head right_head time
  local num_lines empty_line color left_frame right_frame transient_prompt
  local cap_diamond cap_python cap_arrow cap_lock cap_quotes disable_rprompt=0 buffer=''
  local -a extra_icons frame_color color_name prefixes options
  local -A pure_color
  local REPLY k
  while true; do
    instant_prompt=verbose zshrc_content= zshrc_backup= zshrc_backup_u=
    zshrc_has_cfg=0 zshrc_has_instant_prompt=0 write_zshrc=0
    POWERLEVEL9K_MODE= POWERLEVEL9K_ICON_PADDING=moderate style= config_backup= config_backup_u=
    gap_char=' ' prompt_char='❯' down_triangle='\uE0BC' up_triangle='\uE0BA' slanted_bar='\u2571'
    left_sep= right_sep= left_subsep= right_subsep= left_tail= right_tail= left_head= right_head= time=
    num_lines=2 empty_line=0 color=2 left_frame=1 right_frame=1 transient_prompt=0
    cap_diamond=0 cap_python=0 cap_arrow=0 cap_lock=0 cap_quotes=0
    extra_icons=([1]='' '' '')
    frame_color=([1]=244 242 240 238)
    color_name=([1]=Lightest Light Dark Darkest)
    prefixes=([1]='' '')
    options=()
    pure_color=()
    if (( has_truecolor )); then
      for k in "${!pure_snazzy[@]}"; do pure_color[$k]=${pure_snazzy[$k]}; done
    else
      for k in "${!pure_original[@]}"; do pure_color[$k]=${pure_original[$k]}; done
    fi

    unset pure_use_rprompt

    if [[ ${TERM-} != @(dumb|linux) ]] && _p9k_codeset_is_utf8; then
      ask_font || continue
      ask_diamond || continue
      if [[ ${AWESOME_GLYPHS_LOADED-} == 1 ]]; then
        POWERLEVEL9K_MODE=awesome-mapped-fontconfig
      else
        ask_lock '\uF023' || continue
        if (( ! cap_lock )); then
          ask_lock '\uE138' "Let's try another one." || continue
          if (( cap_lock )); then
            if (( cap_diamond )); then
              POWERLEVEL9K_MODE=awesome-patched
              ask_python || continue
            else
              POWERLEVEL9K_MODE=flat
            fi
          else
            if (( cap_diamond )); then
              POWERLEVEL9K_MODE=powerline
            else
              ask_quotes || continue
              if (( cap_quotes )); then POWERLEVEL9K_MODE=compatible; else POWERLEVEL9K_MODE=ascii; fi
            fi
          fi
        elif (( ! cap_diamond )); then
          POWERLEVEL9K_MODE=awesome-fontconfig
        else
          ask_arrow '\UF0737' || continue
          if (( cap_arrow )); then
            ask_width || continue
          fi
          if (( cap_arrow )); then
            POWERLEVEL9K_MODE=nerdfont-v3
          else
            ask_arrow '\uFC35' "Let's try another one." || continue
            if (( cap_arrow )); then
              POWERLEVEL9K_MODE=nerdfont-complete
            else
              POWERLEVEL9K_MODE=awesome-fontconfig
              ask_python || continue
            fi
          fi
        fi
      fi
    else
      POWERLEVEL9K_MODE=ascii
    fi

    if [[ $POWERLEVEL9K_MODE == powerline ]]; then
      options+=(powerline)
    elif (( cap_diamond )); then
      options+=("$POWERLEVEL9K_MODE + powerline")
    else
      options+=("$POWERLEVEL9K_MODE")
    fi
    (( cap_python )) && options[-1]+=' + python'
    if (( cap_diamond )); then
      left_sep=$right_triangle
      right_sep=$left_triangle
      left_subsep=$right_angle
      right_subsep=$left_angle
      left_head=$right_triangle
      right_head=$left_triangle
    else
      left_sep=
      right_sep=
      left_head=
      right_head=
      if [[ $POWERLEVEL9K_MODE == ascii ]]; then
        left_subsep='|'
        right_subsep='|'
        prompt_char='>'
        left_frame=0
        right_frame=0
      else
        left_subsep=$vertical_bar
        right_subsep=$vertical_bar
      fi
    fi

    _p9k_init_icons "$POWERLEVEL9K_MODE" "$POWERLEVEL9K_ICON_PADDING"
    ask_icon_padding     || continue
    _p9k_init_icons "$POWERLEVEL9K_MODE" "$POWERLEVEL9K_ICON_PADDING"

    ask_style            || continue
    ask_charset          || continue
    ask_color_scheme     || continue
    ask_color            || continue
    ask_use_rprompt      || continue
    ask_time             || continue
    ask_separators       || continue
    ask_heads            || continue
    ask_tails            || continue
    ask_num_lines        || continue
    ask_gap_char         || continue
    ask_frame            || continue
    ask_ornaments_color  || continue
    ask_empty_line       || continue
    ask_extra_icons      || continue
    ask_prefixes         || continue
    ask_transient_prompt || continue
    ask_instant_prompt   || continue
    ask_config_overwrite || continue
    ask_zshrc_edit       || continue
    break
  done

  restore_screen

  if (( ! in_z4h_wizard )); then
    printf '\n'
    flowing +c New config: "%U${__p9k_cfg_path_u//\\/\\\\}%u."
    if [[ -n $config_backup ]]; then
      flowing +c Backup of the old config: "%U${config_backup_u//\\/\\\\}%u."
    fi
    if [[ -n $zshrc_backup ]]; then
      flowing +c Backup of "%U${__p9k_zshrc_u//\\/\\\\}%u:" "%U${zshrc_backup_u//\\/\\\\}%u."
    fi
  fi

  generate_config || return
  change_zshrc    || return

  if (( ! in_z4h_wizard )); then
    pp ""
    flowing +c File feature requests and bug reports at "$(href https://github.com/romkatv/powerlevel10k/issues)"
    pp ""
  fi

  success=1
  return 0
}
