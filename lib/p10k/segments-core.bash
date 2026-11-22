# =============================================================================
#  lib/p10k/segments-core.bash - the segments every p10k template uses.
#  Ports of p10k's prompt_dir, prompt_status, prompt_prompt_char,
#  prompt_command_execution_time, prompt_background_jobs, prompt_context,
#  prompt_user, prompt_host, prompt_time, prompt_date, prompt_os_icon.
#  ${FUNCNAME[0]} stands for zsh's $0 (the segment's own name).
# =============================================================================

# ------------------------------------------------------------------ status ---
prompt_status() {
  local me=${FUNCNAME[0]} state
  (( _p9k__status )) && state=ERROR || state=OK
  if (( _POWERLEVEL9K_STATUS_EXTENDED_STATES )); then
    if (( _p9k__status )); then
      if (( ${#_p9k__pipestatus[@]} > 1 )); then state+=_PIPE
      elif (( _p9k__status > 128 )); then state+=_SIGNAL
      fi
    elif [[ "${_p9k__pipestatus[*]}" == *[1-9]* ]]; then
      state+=_PIPE
    fi
  fi
  local flag=_POWERLEVEL9K_STATUS_$state
  (( ${!flag} )) || return 0
  local text c
  if (( _POWERLEVEL9K_STATUS_SHOW_PIPESTATUS )); then
    local -a t=()
    for c in "${_p9k__pipestatus[@]}"; do t+=("${_p9k_exitcode2str[c]}"); done
    local IFS='|'; text="${t[*]}"; unset IFS
  else
    text=${_p9k_exitcode2str[_p9k__status]}
  fi
  if (( _p9k__status )); then
    if (( !_POWERLEVEL9K_STATUS_CROSS && _POWERLEVEL9K_STATUS_VERBOSE )); then
      _p9k_prompt_segment "${me}_$state" red yellow1 CARRIAGE_RETURN_ICON 0 '' "$text"
    else
      _p9k_prompt_segment "${me}_$state" "$_p9k_color1" red FAIL_ICON 0 '' ''
    fi
  elif (( _POWERLEVEL9K_STATUS_VERBOSE || _POWERLEVEL9K_STATUS_OK_IN_NON_VERBOSE )); then
    [[ $state == OK ]] && text=''
    _p9k_prompt_segment "${me}_$state" "$_p9k_color1" green OK_ICON 0 '' "$text"
  fi
}

# ------------------------------------------------------------- prompt_char ---
# The condition strings test _p9k__keymap (viins, vicmd, vivis, vivli) and the
# overwrite state, like p10k's; the flags are computed in _p9k_keymap_flags.
prompt_prompt_char() {
  local me=${FUNCNAME[0]} st fg
  if (( _p9k__status )); then st=ERROR fg=196; else st=OK fg=76; fi
  _p9k_keymap_flags
  if (( _POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE )); then
    _p9k_prompt_segment "${me}_${st}_VIINS" "$_p9k_color1" $fg '' 0 '$_p9k__k_ins_noovr' '❯'
    _p9k_prompt_segment "${me}_${st}_VIOWR" "$_p9k_color1" $fg '' 0 '$_p9k__k_ins_ovr' '▶'
  else
    _p9k_prompt_segment "${me}_${st}_VIINS" "$_p9k_color1" $fg '' 0 '$_p9k__k_ins' '❯'
  fi
  _p9k_prompt_segment "${me}_${st}_VICMD" "$_p9k_color1" $fg '' 0 '$_p9k__k_cmd' '❮'
  _p9k_prompt_segment "${me}_${st}_VIVIS" "$_p9k_color1" $fg '' 0 '$_p9k__k_vis' 'Ⅴ'
}

# The flags below are p10k's condition strings evaluated once. _p9k__keymap is
# zsh's keymap name (viins, vicmd, vivis, vivli), _p9k__region_active 0/1
# (selection active in vicmd), _p9k__zle_state "insert" or "overwrite".
#   _p9k__k_ins       keymap is none of vicmd/vivis/vivli
#   _p9k__k_ins_noovr ... and the state is not overwrite   (p10k: :#*.*overwrite*)
#   _p9k__k_ins_ovr   ... and the state is not insert      (p10k: :#*.*insert*)
#   _p9k__k_cmd       keymap+region == vicmd0
#   _p9k__k_vis       keymap+region is vicmd1, vivis? or vivli?
#   _p9k__k_cmd_any   keymap is vicmd, vivis or vivli
_p9k_keymap_flags() {
  local km=${_p9k__keymap-} ra=${_p9k__region_active-0} zs=${_p9k__zle_state-insert}
  _p9k__k_ins='' _p9k__k_cmd='' _p9k__k_vis='' _p9k__k_ins_noovr='' _p9k__k_ins_ovr='' _p9k__k_cmd_any=''
  case $km in vicmd|vivis|vivli) _p9k__k_cmd_any=1 ;; *) _p9k__k_ins=1 ;; esac
  [[ $km$ra == vicmd0 ]] && _p9k__k_cmd=1
  [[ $km$ra == vicmd1 || $km$ra == vivis? || $km$ra == vivli? ]] && _p9k__k_vis=1
  if [[ -n $_p9k__k_ins ]]; then
    [[ $zs == *overwrite* ]] || _p9k__k_ins_noovr=1
    [[ $zs == *insert* ]] || _p9k__k_ins_ovr=1
  fi
}

# ------------------------------------------------------------------ vi_mode ---
# Exactly p10k's rules: OVERWRITE is a separate state only when
# VI_OVERWRITE_MODE_STRING is *set* (even to ''), VISUAL only when
# VI_VISUAL_MODE_STRING is set; otherwise visual mode shows NORMAL.
prompt_vi_mode() {
  local me=${FUNCNAME[0]}
  _p9k_keymap_flags
  if _p9k_isset _POWERLEVEL9K_VI_OVERWRITE_MODE_STRING; then
    if [[ -n $_POWERLEVEL9K_VI_INSERT_MODE_STRING ]]; then
      _p9k_prompt_segment "${me}_INSERT" "$_p9k_color1" blue '' 0 '$_p9k__k_ins_noovr' "$_POWERLEVEL9K_VI_INSERT_MODE_STRING"
    fi
    _p9k_prompt_segment "${me}_OVERWRITE" "$_p9k_color1" blue '' 0 '$_p9k__k_ins_ovr' "$_POWERLEVEL9K_VI_OVERWRITE_MODE_STRING"
  else
    if [[ -n $_POWERLEVEL9K_VI_INSERT_MODE_STRING ]]; then
      _p9k_prompt_segment "${me}_INSERT" "$_p9k_color1" blue '' 0 '$_p9k__k_ins' "$_POWERLEVEL9K_VI_INSERT_MODE_STRING"
    fi
  fi
  if _p9k_isset _POWERLEVEL9K_VI_VISUAL_MODE_STRING; then
    _p9k_prompt_segment "${me}_NORMAL" "$_p9k_color1" white '' 0 '$_p9k__k_cmd' "$_POWERLEVEL9K_VI_COMMAND_MODE_STRING"
    _p9k_prompt_segment "${me}_VISUAL" "$_p9k_color1" white '' 0 '$_p9k__k_vis' "$_POWERLEVEL9K_VI_VISUAL_MODE_STRING"
  else
    _p9k_prompt_segment "${me}_NORMAL" "$_p9k_color1" white '' 0 '$_p9k__k_cmd_any' "$_POWERLEVEL9K_VI_COMMAND_MODE_STRING"
  fi
}

# ---------------------------------------------------- command_execution_time ---
prompt_command_execution_time() {
  [[ -n ${P9K_COMMAND_DURATION_SECONDS-} ]] || return 0
  _p9k_fcmp "$P9K_COMMAND_DURATION_SECONDS" '>=' "$_POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD" || return 0
  local text us=$_p9k__duration_us   # duration in microseconds
  if (( us < 60000000 )); then
    if (( _POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION == 0 )); then
      text="$(( (us + 500000) / 1000000 ))s"
    else
      local p=$_POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION
      # zsh's local -F N: N decimal places, rounded
      local scale=1 i
      for (( i = 0; i < p; i++ )); do scale=$(( scale * 10 )); done
      local v=$(( (us * scale + 500000) / 1000000 ))
      printf -v text '%d.%0*ds' $(( v / scale )) "$p" $(( v % scale ))
    fi
  else
    local d=$(( (us + 500000) / 1000000 ))
    if [[ $_POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT == H:M:S ]]; then
      printf -v text '%02d' $(( d % 60 ))
      if (( d >= 60 )); then
        printf -v text '%02d:%s' $(( d / 60 % 60 )) "$text"
        if (( d >= 36000 )); then text="$(( d / 3600 )):$text"
        elif (( d >= 3600 )); then text="0$(( d / 3600 )):$text"
        fi
      fi
    else
      text="$(( d % 60 ))s"
      if (( d >= 60 )); then
        text="$(( d / 60 % 60 ))m $text"
        if (( d >= 3600 )); then
          text="$(( d / 3600 % 24 ))h $text"
          (( d >= 86400 )) && text="$(( d / 86400 ))d $text"
        fi
      fi
    fi
  fi
  _p9k_prompt_segment "${FUNCNAME[0]}" red yellow1 EXECUTION_TIME_ICON 0 '' "$text"
}

# --------------------------------------------------------- background_jobs ---
prompt_background_jobs() {
  local msg=''
  if (( _POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE )); then
    if (( _POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE_ALWAYS )); then msg='$_p9k__jobs'
    else msg='$_p9k__jobs_not1'
    fi
  fi
  _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" cyan BACKGROUND_JOBS_ICON 1 '$_p9k__jobs_not0' "$msg"
}

# ----------------------------------------------------------------- context ---
prompt_context() {
  local me=${FUNCNAME[0]} content=''
  if [[ $_POWERLEVEL9K_ALWAYS_SHOW_CONTEXT == 0 && -n ${DEFAULT_USER-} && $P9K_SSH == 0 ]]; then
    if [[ $USER == "$DEFAULT_USER" ]]; then
      (( _POWERLEVEL9K_ALWAYS_SHOW_USER )) || return 0      # p10k: _p9k_prompt_context_init
      content=${USER//\%/%%}
    fi
  fi
  local state
  if (( P9K_SSH )); then
    if [[ -n ${SUDO_COMMAND-} ]]; then state=REMOTE_SUDO; else state=REMOTE; fi
  elif [[ -n ${SUDO_COMMAND-} ]]; then state=SUDO
  else state=DEFAULT
  fi
  local s cond text var
  for s in "$state" ROOT; do
    if [[ $s == ROOT ]]; then cond='$_p9k__is_root'; else cond='$_p9k__not_root'; fi
    text=$content
    if [[ -z $text ]]; then
      var=_POWERLEVEL9K_CONTEXT_${s}_TEMPLATE
      if [[ -v $var ]]; then text=${!var}; text=${text@E}; else text=$_POWERLEVEL9K_CONTEXT_TEMPLATE; fi
    fi
    _p9k_prompt_segment "${me}_$s" "$_p9k_color1" yellow '' 0 "$cond" "$text"
  done
}

prompt_user() {
  local me=${FUNCNAME[0]}
  _p9k_prompt_segment "${me}_ROOT" "$_p9k_color1" yellow ROOT_ICON 0 '$_p9k__is_root' "$_POWERLEVEL9K_USER_TEMPLATE"
  if [[ -n ${SUDO_COMMAND-} ]]; then
    _p9k_prompt_segment "${me}_SUDO" "$_p9k_color1" yellow SUDO_ICON 0 '$_p9k__not_root' "$_POWERLEVEL9K_USER_TEMPLATE"
  else
    _p9k_prompt_segment "${me}_DEFAULT" "$_p9k_color1" yellow USER_ICON 0 '$_p9k__not_root' '%n'
  fi
}

prompt_host() {
  local me=${FUNCNAME[0]}
  if (( P9K_SSH )); then
    _p9k_prompt_segment "${me}_REMOTE" "$_p9k_color1" yellow SSH_ICON 0 '' "$_POWERLEVEL9K_HOST_TEMPLATE"
  else
    _p9k_prompt_segment "${me}_LOCAL" "$_p9k_color1" yellow HOST_ICON 0 '' "$_POWERLEVEL9K_HOST_TEMPLATE"
  fi
}

# --------------------------------------------------------------- time/date ---
prompt_time() {
  _p9k_pe "$_POWERLEVEL9K_TIME_FORMAT"; local t=${_p9k__pe//%/%%}
  if (( _POWERLEVEL9K_TIME_UPDATE_ON_COMMAND )) && [[ -n ${_p9k__line_finished-} ]]; then
    _p9k_pe "$_POWERLEVEL9K_TIME_FORMAT"; t=${_p9k__pe//%/%%}
  fi
  _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color2" "$_p9k_color1" TIME_ICON 0 '' "$t"
}

prompt_date() {
  _p9k_pe "$_POWERLEVEL9K_DATE_FORMAT"; local t=${_p9k__pe//%/%%}
  _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color2" "$_p9k_color1" DATE_ICON 0 '' "$t"
}

# ----------------------------------------------------------------- os_icon ---
prompt_os_icon() {
  _p9k_prompt_segment "${FUNCNAME[0]}" black white '' 0 '' "$_p9k_os_icon"
}

# p10k: the OS detection in _p9k_init_cacheable (same table as the wizard's os_icon_name)
_p9k_init_os() {
  local name uname=$(uname 2>/dev/null)
  if [[ $uname == Linux && "$(uname -o 2>/dev/null)" == Android ]]; then
    _p9k_os=Android name=ANDROID_ICON
  else
    case $uname in
      SunOS)  _p9k_os=Solaris name=SUNOS_ICON ;;
      Darwin) _p9k_os=OSX name=APPLE_ICON ;;
      CYGWIN_NT-*|MSYS_NT-*|MINGW64_NT-*|MINGW32_NT-*) _p9k_os=Windows name=WINDOWS_ICON ;;
      FreeBSD|OpenBSD|DragonFly) _p9k_os=BSD name=FREEBSD_ICON ;;
      Linux)
        _p9k_os=Linux
        local id=''
        if [[ -r /etc/os-release ]]; then
          id=$(sed -n 's/^ID=//p' /etc/os-release | head -1); id=${id//\"/}; id=${id//\'/}
        elif [[ -e /etc/artix-release ]]; then id=artix
        fi
        case $id in
          *arch*) name=LINUX_ARCH_ICON ;;
          *raspbian*) name=LINUX_RASPBIAN_ICON ;;
          *debian*) [[ -f /etc/apt/sources.list.d/raspi.list ]] && name=LINUX_RASPBIAN_ICON || name=LINUX_DEBIAN_ICON ;;
          *ubuntu*) name=LINUX_UBUNTU_ICON ;;
          *elementary*) name=LINUX_ELEMENTARY_ICON ;;
          *fedora*) name=LINUX_FEDORA_ICON ;;
          *coreos*) name=LINUX_COREOS_ICON ;;
          *kali*) name=LINUX_KALI_ICON ;;
          *gentoo*) name=LINUX_GENTOO_ICON ;;
          *mageia*) name=LINUX_MAGEIA_ICON ;;
          *centos*) name=LINUX_CENTOS_ICON ;;
          *opensuse*|*tumbleweed*) name=LINUX_OPENSUSE_ICON ;;
          *sabayon*) name=LINUX_SABAYON_ICON ;;
          *slackware*) name=LINUX_SLACKWARE_ICON ;;
          *linuxmint*) name=LINUX_MINT_ICON ;;
          *alpine*) name=LINUX_ALPINE_ICON ;;
          *aosc*) name=LINUX_AOSC_ICON ;;
          *nixos*) name=LINUX_NIXOS_ICON ;;
          *devuan*) name=LINUX_DEVUAN_ICON ;;
          *manjaro*) name=LINUX_MANJARO_ICON ;;
          *void*) name=LINUX_VOID_ICON ;;
          *artix*) name=LINUX_ARTIX_ICON ;;
          *rhel*) name=LINUX_RHEL_ICON ;;
          amzn) name=LINUX_AMZN_ICON ;;
          endeavouros) name=LINUX_ENDEAVOUROS_ICON ;;
          rocky) name=LINUX_ROCKY_ICON ;;
          almalinux) name=LINUX_ALMALINUX_ICON ;;
          guix) name=LINUX_GUIX_ICON ;;
          neon) name=LINUX_NEON_ICON ;;
          *) name=LINUX_ICON ;;
        esac ;;
      *) _p9k_os=Linux name=LINUX_ICON ;;
    esac
  fi
  _p9k_get_icon prompt_os_icon "$name"
  _p9k_os_icon=$_p9k__ret
}

# --------------------------------------------------------------------- dir ---
# Part markers, as in p10k: \1 delimiter position, \2 anchor (never shortened),
# \3 ... \1 \3 shortened span. With truncate_to_unique the shortening is
# decided at display time (_p9k_dir_fit), shortest-unique prefixes first.
prompt_dir() {
  local me=${FUNCNAME[0]} cwd=$PWD p
  if (( _POWERLEVEL9K_DIR_PATH_ABSOLUTE )); then
    p=$cwd
  else
    p=$cwd
    [[ $p == "$HOME" || $p == "$HOME"/* ]] && p="~${p#"$HOME"}"
  fi
  local -a parts=()
  local IFS=/; read -r -a parts <<<"$p"; unset IFS
  [[ $p == */ && $p != / ]] && parts+=('')
  [[ $p == / ]] && parts=('' '')

  local fake_first=0 expand=0 shortenlen=${_POWERLEVEL9K_SHORTEN_DIR_LENGTH:--1} delim
  if [[ -v _POWERLEVEL9K_SHORTEN_DELIMITER ]]; then delim=$_POWERLEVEL9K_SHORTEN_DELIMITER
  elif _p9k_codeset_is_utf8; then delim=$'…'
  else delim='..'
  fi
  [[ -z ${_POWERLEVEL9K_SHORTEN_DIR_LENGTH-} ]] && shortenlen=-1

  local n=${#parts[@]} i
  case $_POWERLEVEL9K_SHORTEN_STRATEGY in
    truncate_absolute|truncate_absolute_chars)
      if (( shortenlen > 0 && ${#p} > shortenlen )); then
        _p9k_shorten_delim_len "$delim"
        if (( ${#p} > shortenlen + _p9k__ret )); then
          local rem=$shortenlen dir len
          i=$(( n - 1 ))
          while true; do
            dir=${parts[i]}; len=$(( ${#dir} + (i > 0) ))
            if (( len <= rem )); then (( rem -= len, i-- ))
            else
              parts[i]=$'\1'${dir: -rem}
              parts=("${parts[@]:i}")
              break
            fi
          done
        fi
      fi ;;
    truncate_with_package_name|truncate_middle|truncate_from_right)
      if [[ $_POWERLEVEL9K_SHORTEN_STRATEGY == truncate_with_package_name ]] && command -v jq >/dev/null &&
         (( ${#_POWERLEVEL9K_DIR_PACKAGE_FILES[@]} )); then
        _p9k_dir_package_name parts fake_first
      fi
      if (( shortenlen > 0 )); then
        _p9k_shorten_delim_len "$delim"
        local d=$_p9k__ret pref=$shortenlen suf=0 dir
        [[ $_POWERLEVEL9K_SHORTEN_STRATEGY == truncate_middle ]] && suf=$pref
        for (( i = 1; i < ${#parts[@]} - 1; i++ )); do
          dir=${parts[i]}
          if (( ${#dir} > pref + suf + d )); then
            if (( suf )); then parts[i]=${dir:0:pref}$'\1'${dir: -suf}; else parts[i]=${dir:0:pref}$'\1'; fi
          fi
        done
      fi ;;
    truncate_to_last)
      shortenlen=${_POWERLEVEL9K_SHORTEN_DIR_LENGTH:-1}
      (( shortenlen > 0 )) || shortenlen=1
      if (( n > shortenlen + 1 )) || { [[ ${p:0:1} != / ]] && (( n > shortenlen )); }; then
        fake_first=1
        parts=("${parts[@]: -shortenlen}")
      fi ;;
    truncate_to_first_and_last)
      if (( shortenlen > 0 )); then
        i=$shortenlen
        [[ $p == /* ]] && (( i++ ))
        for (( ; i < n - shortenlen; i++ )); do parts[i]=$'\1'; done
      fi ;;
    truncate_to_unique)
      expand=1
      delim=${_POWERLEVEL9K_SHORTEN_DELIMITER-'*'}
      shortenlen=${_POWERLEVEL9K_SHORTEN_DIR_LENGTH:-1}
      (( shortenlen >= 0 )) || shortenlen=1
      _p9k_dir_unique ;;
    truncate_with_folder_marker)
      if [[ -n $_POWERLEVEL9K_SHORTEN_FOLDER_MARKER ]]; then
        local dir=$cwd; local -a m=()
        for (( i = n - 2; i > 0; i-- )); do
          dir=${dir%/*}
          _p9k_has_marker "$dir" && m+=("$i")
        done
        m+=(0)
        local -a np=() k
        # collapse runs between markers to one \1
        for (( k = 0; k + 1 < ${#m[@]}; k++ )); do
          if (( m[k] - m[k+1] > 2 )); then
            local a=$(( m[k+1] + 1 )) b=$(( m[k] - 1 ))
            parts=("${parts[@]:0:a}" $'\1' "${parts[@]:b+1}")
          fi
        done
      fi ;;
    *)
      if (( shortenlen > 0 )); then
        local len=$n
        [[ -z ${parts[0]} ]] && (( len-- ))
        if (( len > shortenlen )); then parts=($'\1' "${parts[@]: -shortenlen}"); fi
      fi ;;
  esac

  # writability
  local w=0
  if (( _POWERLEVEL9K_DIR_SHOW_WRITABLE )) && [[ ! -w $cwd ]]; then w=1; fi
  (( w && _POWERLEVEL9K_DIR_SHOW_WRITABLE > 2 )) && [[ ! -e $cwd ]] && w=2

  local state=$me icon='' a b c
  for (( i = 0; i + 2 < ${#_POWERLEVEL9K_DIR_CLASSES[@]}; i += 3 )); do
    a=${_POWERLEVEL9K_DIR_CLASSES[i]} b=${_POWERLEVEL9K_DIR_CLASSES[i+1]} c=${_POWERLEVEL9K_DIR_CLASSES[i+2]}
    if _p9k_zglob_match "$cwd" "$a"; then
      [[ -n $b ]] && state+=_${b^^}
      icon=$'\1'$c
      break
    fi
  done
  if (( w )); then
    if (( _POWERLEVEL9K_DIR_SHOW_WRITABLE == 1 )); then state=${me}_NOT_WRITABLE
    elif (( w == 2 )); then state+=_NON_EXISTENT
    else state+=_NOT_WRITABLE
    fi
    icon=LOCK_ICON
  fi
  local state_u=${state^^}
  state_u=${state_u#PROMPT_}

  local style='%b'
  _p9k_color "$state" BACKGROUND blue; _p9k_background "$_p9k__ret"; style+=$_p9k__ret
  _p9k_color "$state" FOREGROUND "$_p9k_color1"; _p9k_foreground "$_p9k__ret"; style+=$_p9k__ret

  for i in "${!parts[@]}"; do parts[i]=${parts[i]//\%/%%}; done
  local np=${#parts[@]}
  if [[ $_POWERLEVEL9K_HOME_FOLDER_ABBREVIATION != '~' && $fake_first == 0 && ( $p == '~' || $p == '~/'* ) ]]; then
    parts[0]=$_POWERLEVEL9K_HOME_FOLDER_ABBREVIATION
    [[ ${parts[0]} == *%* ]] && parts[0]+=$style
  elif [[ $_POWERLEVEL9K_DIR_OMIT_FIRST_CHARACTER == 1 && $fake_first == 0 && $np -gt 1 && -z ${parts[0]} && -n ${parts[1]} ]]; then
    parts=("${parts[@]:1}"); np=${#parts[@]}
  fi

  local last_style=''
  _p9k_param "$state" PATH_HIGHLIGHT_BOLD ''; [[ $_p9k__ret == true ]] && last_style+=%B
  if [[ -v _POWERLEVEL9K_DIR_PATH_HIGHLIGHT_FOREGROUND || -v _POWERLEVEL9K_${state_u}_PATH_HIGHLIGHT_FOREGROUND ]]; then
    _p9k_color "$state" PATH_HIGHLIGHT_FOREGROUND ''; _p9k_foreground "$_p9k__ret"; last_style+=$_p9k__ret
  fi
  if [[ -n $last_style ]]; then
    local lp=${parts[np-1]}
    parts[np-1]="$last_style${lp//$'\1'/$'\1'$last_style}$style"
  fi

  local anchor_style=''
  _p9k_param "$state" ANCHOR_BOLD ''; [[ $_p9k__ret == true ]] && anchor_style+=%B
  if [[ -v _POWERLEVEL9K_DIR_ANCHOR_FOREGROUND || -v _POWERLEVEL9K_${state_u}_ANCHOR_FOREGROUND ]]; then
    _p9k_color "$state" ANCHOR_FOREGROUND ''; _p9k_foreground "$_p9k__ret"; anchor_style+=$_p9k__ret
  fi
  if [[ -n $anchor_style ]]; then
    local lim=$np
    [[ -n $last_style ]] && lim=$(( np - 1 ))
    for (( i = 0; i < lim; i++ )); do
      [[ ${parts[i]} == *$'\2' ]] && parts[i]="$anchor_style${parts[i]%$'\2'}$style"
    done
    [[ -n $last_style ]] && parts[np-1]=${parts[np-1]//$'\2'/}
  else
    for i in "${!parts[@]}"; do parts[i]=${parts[i]//$'\2'/}; done
  fi

  local shortened_fg='' dd=$delim
  if [[ -v _POWERLEVEL9K_DIR_SHORTENED_FOREGROUND || -v _POWERLEVEL9K_${state_u}_SHORTENED_FOREGROUND ]]; then
    _p9k_color "$state" SHORTENED_FOREGROUND ''; _p9k_foreground "$_p9k__ret"; shortened_fg=$_p9k__ret
    [[ $dd == *%* ]] && dd+=$style$shortened_fg
  else
    [[ $dd == *%* ]] && dd+=$style
  fi

  local sep
  if [[ $cwd == / && $_POWERLEVEL9K_DIR_OMIT_FIRST_CHARACTER == 1 ]]; then
    sep=/
  else
    sep=''
    if [[ -v _POWERLEVEL9K_DIR_PATH_SEPARATOR_FOREGROUND || -v _POWERLEVEL9K_${state_u}_PATH_SEPARATOR_FOREGROUND ]]; then
      _p9k_color "$state" PATH_SEPARATOR_FOREGROUND ''; _p9k_foreground "$_p9k__ret"; sep=$_p9k__ret
    fi
    _p9k_param "$state" PATH_SEPARATOR /; sep+=${_p9k__ret@E}
    [[ $sep == *%* ]] && sep+=$style
  fi

  # Build the full and (for truncate_to_unique) the shortened forms.
  _p9k__dir_sep=$sep _p9k__dir_dd=$dd _p9k__dir_sfg=$shortened_fg _p9k__dir_style=$style
  _p9k__dir_parts=("${parts[@]}")
  _p9k_dir_render -1
  local content=$_p9k__ret
  if (( _POWERLEVEL9K_DIR_HYPERLINK )) && [[ $cwd == /* ]]; then
    _p9k_url_escape "$cwd"
    content=$'%{\e]8;;file://'"$_p9k__ret"$'\a%}'"$content"$'%{\e]8;;\a%}'
  fi
  if (( expand && ! ${_p9k__dir_seen-0} )); then
    _p9k__dir_seen=1
    _p9k__dir_placeholder=$content
    _p9k__dir_line=$_p9k__line_index
  fi
  _p9k_prompt_segment "$state" blue "$_p9k_color1" "$icon" 0 '' "$content"
}

# Render the dir parts. $1 = columns to save (-1: none; shorten nothing).
# Shortenable parts are \3SHORT\1\3 with the full name kept in _p9k__dir_full[i]
# and the columns saved in _p9k__dir_saved[i]; shortened left to right.
_p9k_dir_render() {
  local need=$1 i out='' part
  for (( i = 0; i < ${#_p9k__dir_parts[@]}; i++ )); do
    part=${_p9k__dir_parts[i]}
    if [[ -n ${_p9k__dir_saved[i]-} ]]; then
      if (( need > 0 )); then
        part=${_p9k__dir_short[i]}
        (( need -= _p9k__dir_saved[i] ))
      else
        part=${_p9k__dir_full[i]}
      fi
    fi
    # \3X\1Y\3 or X\1Y: shortened text with the delimiter
    if [[ $part == *$'\1'* ]]; then
      local x=${part%%$'\1'*} y=${part#*$'\1'}
      x=${x//$'\3'/} y=${y//$'\3'/}
      if [[ -n $_p9k__dir_sfg ]]; then part="$_p9k__dir_sfg$x$_p9k__dir_dd$y$_p9k__dir_style"
      else part="$x$_p9k__dir_dd$y"
      fi
    fi
    (( i )) && out+=$_p9k__dir_sep
    out+=$part
  done
  _p9k__ret=$out
}

# truncate_to_unique: mark anchors (\2) and prepare shortest-unique forms.
_p9k_dir_unique() {
  declare -ga _p9k__dir_full=() _p9k__dir_short=() _p9k__dir_saved=()
  local -a rparts=("${parts[@]}")
  local i=1 e=$(( n - shortenlen )) orig_first=''
  local -a orig=()
  if [[ -n $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER ]]; then
    (( e += shortenlen ))
    local k=$(( shortenlen > n ? n : shortenlen ))
    orig=("${parts[1]-}" "${parts[@]: -k}")
  elif [[ ${p:0:1} == / ]]; then
    (( i++ ))
  fi
  local rtail parent
  local -a rr=("${rparts[@]:i}")
  local IFS=/; rtail="${rr[*]}"; unset IFS
  parent=${cwd%/}
  if [[ -n $rtail ]]; then parent=${cwd:0:${#cwd}-${#rtail}-1}; fi
  _p9k_prompt_length "$delim"; local real_delim_len=$_p9k__ret
  [[ -n ${parts[i-1]} ]] && parts[i-1]+=$'\2'
  local d=${_POWERLEVEL9K_SHORTEN_DELIMITER_LENGTH:--1}
  (( d >= 0 )) || d=$real_delim_len
  local sub rsub dir j
  for (( ; i < e; i++ )); do
    sub=${parts[i]} rsub=${rparts[i]} dir=$parent/$rsub
    if [[ -n $_POWERLEVEL9K_SHORTEN_FOLDER_MARKER ]] && _p9k_has_marker "$dir"; then
      parts[i]+=$'\2'
    else
      # first non-dot character, then the shortest prefix matching one directory
      j=0; while [[ ${rsub:j:1} == . ]]; do (( j++ )); done
      (( j++ ))
      for (( ; j + d < ${#rsub}; j++ )); do
        local -a matching=()
        local x
        for x in "$parent/${rsub:0:j}"*/; do [[ -d $x ]] && matching+=("$x"); done
        (( ${#matching[@]} == 1 )) && break
      done
      local saved=$(( ${#rsub} - j - d ))
      if (( saved > 0 )); then
        _p9k__dir_full[i]=$sub
        _p9k__dir_short[i]=$'\3'"${rsub:0:j}"$'\1\3'
        _p9k__dir_saved[i]=$saved
      fi
    fi
    parent+=/$rsub
  done
  if [[ -n $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER ]]; then
    local last=-1 first=-1 off=${_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER#*:}
    for (( j = 0; j < ${#parts[@]}; j++ )); do
      if [[ ${parts[j]} == *$'\2' ]]; then (( first < 0 )) && first=$j; last=$j; fi
    done
    if [[ $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER == last* ]]; then e=$(( last + 1 + off )); else e=$(( first + 1 + off )); fi
    if (( last >= 0 && e > 1 && e <= ${#parts[@]} )); then
      parts=("${parts[@]:e-1}")
      _p9k_dir_shift $(( e - 1 ))
      fake_first=1
    elif [[ $p == /?* ]]; then
      parts[1]=${orig[0]}$'\2'
    fi
    local cnt=$(( ${#parts[@]} < shortenlen ? ${#parts[@]} : shortenlen ))
    for (( j = cnt; j > 0; j-- )); do
      [[ ${parts[-j]} == *$'\2' ]] && continue
      parts[-j]=${orig[-j]}$'\2'
    done
  else
    for (( ; i < ${#parts[@]}; i++ )); do parts[i]+=$'\2'; done
  fi
  # anchors that are also shortenable keep their \2 on the full form
  for j in "${!_p9k__dir_full[@]}"; do
    [[ ${parts[j]} == *$'\2' ]] && _p9k__dir_full[j]=${parts[j]}
  done
}

# After the line is assembled: shorten the directory until the line fits.
# (p10k: the %{d%} placeholder and _p9k__d / _p9k__h arithmetic in _p9k_set_prompt.)
_p9k_dir_fit() {
  local line=$1 right=$2 num_lines=$3 cols=${COLUMNS:-80} ind=${ZLE_RPROMPT_INDENT:-1}
  [[ ${_p9k__dir_line-} == "$line" ]] || return 0
  (( ${#_p9k__dir_saved[@]} )) || return 0
  _p9k_prompt_length "$_p9k__prompt$right"
  local x=$_p9k__ret
  local m=$(( cols - x - ind - 1 )) h=0
  if (( line == num_lines && (_POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS > 0) )) || { (( line == num_lines )) && _p9k_fcmp "$_POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT" '>' 0; }; then
    local a=$_POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS f
    # p10k evaluates this with the width of the *previous* prompt (_p9k__clm, 0
    # before the first one), so the first prompt only reserves MIN_COMMAND_COLUMNS.
    local pct=${_POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT%%.*}
    f=$(( pct * ${_p9k__clm:-0} / 100 ))
    (( h = a < f ? f : a ))
  fi
  if [[ $_POWERLEVEL9K_DIR_MAX_LENGTH =~ ^[0-9]+%?$ ]]; then
    _p9k_prompt_length "$_p9k__dir_placeholder"; local dlen=$_p9k__ret lim=''
    if [[ $_POWERLEVEL9K_DIR_MAX_LENGTH == *% ]]; then
      lim=$(( dlen - ${_POWERLEVEL9K_DIR_MAX_LENGTH%\%} * cols / 100 ))
    else
      lim=$(( dlen - _POWERLEVEL9K_DIR_MAX_LENGTH ))
      (( lim <= 0 )) && lim=''
    fi
    [[ -n $lim ]] && (( h < m + lim )) && h=$(( m + lim ))
  fi
  local need=$(( h - m ))
  (( need > 0 )) || return 0
  _p9k_dir_render "$need"
  local short=$_p9k__ret
  _p9k__prompt=${_p9k__prompt/"$_p9k__dir_placeholder"/"$short"}
}

# Does DIR contain one of the folder markers (POWERLEVEL9K_SHORTEN_FOLDER_MARKER is "(a|b|c)")?
_p9k_has_marker() {
  local pat=${_POWERLEVEL9K_SHORTEN_FOLDER_MARKER#(}; pat=${pat%)}
  local IFS='|' m
  for m in $pat; do
    compgen -G "$1/$m" >/dev/null 2>&1 && return 0
  done
  return 1
}

# zsh extended glob (as used in DIR_CLASSES) against a path; ~ means $HOME.
# Supports the forms the templates use: '~', '~/x(/*)#', '*', and plain globs.
_p9k_zglob_match() {
  local s=$1 pat=$2 alt
  if [[ $pat == *'|'* && $pat != *'('* ]]; then
    local IFS='|'
    for alt in $pat; do unset IFS; _p9k_zglob_match "$s" "$alt" && return 0; done
    return 1
  fi
  pat=${pat/#\~/$HOME}
  if [[ $pat == *'(/*)#' ]]; then
    local base=${pat%'(/*)#'}
    [[ $s == $base || $s == $base/* ]]
    return
  fi
  [[ $s == $pat ]]
}

_p9k_shorten_delim_len() {
  _p9k__ret=${_POWERLEVEL9K_SHORTEN_DELIMITER_LENGTH:--1}
  (( _p9k__ret >= 0 )) || _p9k_prompt_length "$1"
}

_p9k_url_escape() {
  local s=$1 out='' c i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    case $c in
      [a-zA-Z0-9/:_.\-\!\'\(\)~]) out+=$c ;;
      *) printf -v c '%%%%%02X' "'$c"; out+=$c ;;
    esac
  done
  _p9k__ret=$out
}

_p9k_dir_package_name() { :; }   # truncate_with_package_name: see segments-more.bash

# Drop the first N entries of the shortened-form arrays (they follow parts).
_p9k_dir_shift() {
  local by=$1 k
  local -A f=() s=() v=()
  for k in "${!_p9k__dir_saved[@]}"; do
    (( k >= by )) || continue
    f[$((k-by))]=${_p9k__dir_full[k]} s[$((k-by))]=${_p9k__dir_short[k]} v[$((k-by))]=${_p9k__dir_saved[k]}
  done
  _p9k__dir_full=() _p9k__dir_short=() _p9k__dir_saved=()
  for k in "${!v[@]}"; do
    _p9k__dir_full[k]=${f[$k]} _p9k__dir_short[k]=${s[$k]} _p9k__dir_saved[k]=${v[$k]}
  done
}
