# =============================================================================
#  lib/p10k/instant.bash - instant prompt, the part that writes it (p10k:
#  instant_prompt_* segments, _p9k_set_instant_prompt, _p9k_dump_instant_prompt,
#  _p9k_delete_instant_prompt). Showing it while the shell starts, and taking
#  it away again, is lib/p10k/instant-show.bash (loaded before anything else).
#
#  As in p10k: from the second prompt of a session on, the prompt for each new
#  directory is rendered once more with only the segments that have an
#  instant_prompt_* function, and kept in the cache (one file per length of
#  the directory's name, one record per key "directory:ssh:%#").
#  Differences: the record is finished terminal text, not prompt escapes, so
#  it is used only at the same terminal width (and TERM); the clock is filled
#  in when it is shown. Segments p10k fills from environment variables at
#  that time (ranger, nnn, ...) are rendered now, and those variables are part
#  of the key instead.
# =============================================================================

# ------------------------------------------------------- instant segments ---
# p10k's instant_prompt_NAME functions that are more than prompt_NAME.
instant_prompt_context() {
  if [[ $_POWERLEVEL9K_ALWAYS_SHOW_CONTEXT == 0 && -n ${DEFAULT_USER-} && ${P9K_SSH:-0} == 0 ]]; then
    if [[ $USER == "$DEFAULT_USER" ]]; then
      (( _POWERLEVEL9K_ALWAYS_SHOW_USER )) || return 0
    fi
  fi
  prompt_context
}
instant_prompt_user() {
  [[ $_POWERLEVEL9K_ALWAYS_SHOW_USER == 0 && $USER == "${DEFAULT_USER-}" ]] && return 0
  prompt_user
}
instant_prompt_ssh() { (( ${P9K_SSH:-0} )) || return 0; prompt_ssh; }
instant_prompt_status() {
  (( _POWERLEVEL9K_STATUS_OK )) && _p9k_prompt_segment prompt_status_OK "$_p9k_color1" green OK_ICON 0 '' ''
  return 0
}
instant_prompt_prompt_char() {
  _p9k_prompt_segment prompt_prompt_char_OK_VIINS "$_p9k_color1" 76 '' 0 '' '❯'
}
instant_prompt_vi_mode() {
  [[ -n $_POWERLEVEL9K_VI_INSERT_MODE_STRING ]] || return 0
  _p9k_prompt_segment prompt_vi_mode_INSERT "$_p9k_color1" blue '' 0 '' "$_POWERLEVEL9K_VI_INSERT_MODE_STRING"
}
instant_prompt_per_directory_history() {
  case ${HISTORY_START_WITH_GLOBAL-} in
    true) _p9k_prompt_segment prompt_per_directory_history_GLOBAL 3 "$_p9k_color1" HISTORY_ICON 0 '' global ;;
    ?*)   _p9k_prompt_segment prompt_per_directory_history_LOCAL 5 "$_p9k_color1" HISTORY_ICON 0 '' local ;;
  esac
  return 0
}
# p10k expands the time and date format when the instant prompt is shown.
# Here: rendered now, and the text and its strftime format noted, so that
# instant-show.bash can put the current value in its place.
instant_prompt_time() {
  _p9k_pe "$_POWERLEVEL9K_TIME_FORMAT"
  [[ $_POWERLEVEL9K_TIME_FORMAT =~ ^%D\{([^}%]*(%[a-zA-Z][^}%]*)*)\}$ ]] &&
    _p9k__ip_tv=$_p9k__pe _p9k__ip_tf=${BASH_REMATCH[1]}
  _p9k_prompt_segment prompt_time "$_p9k_color2" "$_p9k_color1" TIME_ICON 0 '' "${_p9k__pe//%/%%}"
}
instant_prompt_date() {
  _p9k_pe "$_POWERLEVEL9K_DATE_FORMAT"
  [[ $_POWERLEVEL9K_DATE_FORMAT =~ ^%D\{([^}%]*(%[a-zA-Z][^}%]*)*)\}$ ]] &&
    _p9k__ip_dv=$_p9k__pe _p9k__ip_df=${BASH_REMATCH[1]}
  _p9k_prompt_segment prompt_date "$_p9k_color2" "$_p9k_color1" DATE_ICON 0 '' "${_p9k__pe//%/%%}"
}

# ------------------------------------------------------------ the cache ---
# ${XDG_CACHE_HOME:-~/.cache}/p10k-bash-USER/prompt-N (p10k: p10k-USER/prompt-N),
# or the directory in _p9k_instant_dir (bash4humans keeps it in $B4H_HOME)
_p9k_ip_dir() { _p9k__ret=${_p9k_instant_dir:-${XDG_CACHE_HOME:-$HOME/.cache}/p10k-bash-${USER:-$EUID}}; }

# The environment the instant segments above read, as part of the key
# (instant-show.bash builds the same text).
_p9k_ip_env() {
  _p9k__ret="${RANGER_LEVEL-}:${NNNLVL-}:${LF_LEVEL-}:${XPLR_PID-}:${YAZI_LEVEL-}:${MC_TMPDIR-}"
  _p9k__ret+=":${IN_NIX_SHELL-}:${DIRENV_DIR-}:${VIMRUNTIME-}:${CHEZMOI-}:${HISTORY_START_WITH_GLOBAL-}:${P9K_TOOLBOX_NAME-}"
}

# p10k: _p9k_delete_instant_prompt (INSTANT_PROMPT=off)
_p9k_delete_instant_prompt() {
  _p9k_ip_dir
  [[ -d $_p9k__ret ]] || return 0
  rm -f -- "$_p9k__ret"/prompt-* 2>/dev/null
  return 0
}

# The instant prompt for this directory as one record (run in a subshell:
# it renders the prompt a second time and must leave the real one alone):
# TERM US COLUMNS US mode US command-lines US before US lines US last-line US
# right US last-width US right-width US time US time-format US date US
# date-format US NEW_TTY_MAX_AGE_SECONDS US ZLE_RPROMPT_INDENT   (US = \x1f)
_p9k_ip_render() {
  _p9k__instant=1 _p9k__replay=0 _p9k__ip_tv='' _p9k__ip_tf='' _p9k__ip_dv='' _p9k__ip_df=''
  # dir truncation starts afresh, as before each prompt (_p9k_precmd)
  _p9k__dir_seen=0; unset _p9k__dir_placeholder _p9k__dir_line
  _p9k_set_prompt
  local n=$_p9k_num_lines i first=1 p1='' last='' lw=0 rp='' rw=0
  _p9k__pe_mark=0
  for (( i = 1; i <= n; i++ )); do
    [[ -n ${_p9k_line_hidden[i]-} ]] && continue
    _p9k__pe_cont=$(( ! first )); first=0
    _p9k_pe "${_p9k_ps_lines[i]}"
    if (( i < n )); then p1+=$_p9k__pe$'\n'; else last=$_p9k__pe lw=$_p9k__pw; fi
  done
  if [[ -n $_p9k_rprompt && -z ${_p9k_line_hidden[n]-} ]]; then
    _p9k__pe_cont=0; _p9k_pe "$_p9k_rprompt"; rp=$_p9k__pe rw=$_p9k__pw
    (( _p9k__si_right )) && rp=$'\e]133;P;k=r\a'$rp$'\e]133;B\a'
  fi
  (( _p9k__si )) && p1=$'\e]133;A\a'$p1 last+=$'\e]133;B\a'
  # p10k shows the blank line and the ruler in the instant prompt of an old
  # terminal (instant-show.bash decides)
  local pre=''
  if (( _POWERLEVEL9K_PROMPT_ADD_NEWLINE && _POWERLEVEL9K_PROMPT_ADD_NEWLINE_COUNT > 0 )); then
    printf -v pre '%*s' "$_POWERLEVEL9K_PROMPT_ADD_NEWLINE_COUNT" ''; pre=${pre// /$'\n'}
  fi
  if (( _POWERLEVEL9K_SHOW_RULER )) && [[ -n $_p9k_ruler_char ]]; then
    local r cols=${COLUMNS:-80} ind=${ZLE_RPROMPT_INDENT:-1}
    printf -v r '%*s' $(( cols - ind > 0 ? cols - ind : 0 )) ''
    _p9k__pe_cont=0; _p9k_pe "$_p9k_ruler_style${r// /$_p9k_ruler_char}%k%f"; pre+=$_p9k__pe$'\n'
  fi
  local us=$'\x1f'
  printf '%s' "${TERM-}$us${COLUMNS:-80}$us$_POWERLEVEL9K_INSTANT_PROMPT$us${_POWERLEVEL9K_INSTANT_PROMPT_COMMAND_LINES-1}$us$pre$us$p1$us$last$us$rp$us$lw$us$rw$us$_p9k__ip_tv$us$_p9k__ip_tf$us$_p9k__ip_dv$us$_p9k__ip_df$us$_POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS$us${ZLE_RPROMPT_INDENT:-1}"
}

# p10k: _p9k_dump_instant_prompt, run from _p9k_precmd (p10k: after the
# prompt, from the second prompt on, once per key and session).
declare -gA _p9k__ip_dumped=()
_p9k_dump_instant_prompt() {
  [[ $_POWERLEVEL9K_INSTANT_PROMPT == off ]] && return 0
  (( ! ${_p9k__instant_prompt_disabled:-0} && _p9k__prompt_idx > 1 )) || return 0
  [[ $PWD == /* ]] || return 0
  local ch='$'; (( EUID )) || ch='#'
  _p9k_ip_env
  local key="$PWD:${P9K_SSH:-0}:$ch:$_p9k__ret"
  [[ -n ${_p9k__ip_dumped[$key]-} ]] && return 0
  _p9k__ip_dumped[$key]=1
  local rec; rec=$(_p9k_ip_render) || return 0
  # the separators must not occur inside
  [[ $key$rec != *$'\x1e'* && $key != *$'\x1f'* ]] || return 0
  _p9k_ip_dir; local dir=$_p9k__ret
  [[ -d $dir ]] || mkdir -p -m 700 -- "$dir" 2>/dev/null || return 0
  [[ -w $dir ]] || return 0
  local f=$dir/prompt-${#PWD} content=''
  [[ -r $f ]] && IFS= read -r -d '' content <"$f"
  # (p10k: a file that already has this key starts again from nothing)
  [[ $content == *$'\x1e'"$key"$'\x1f'* ]] && content=''
  local tmp=$f.tmp.$$
  { printf '%s' "$content"$'\x1e'"$key"$'\x1f'"$rec" >"$tmp" && mv -f -- "$tmp" "$f"; } 2>/dev/null ||
    rm -f -- "$tmp" 2>/dev/null
  return 0
}
