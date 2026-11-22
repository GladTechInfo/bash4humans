# =============================================================================
#  lib/p10k/transient.bash - TRANSIENT_PROMPT (off | always | same-dir).
#  Port of p10k's _p9k_transient_prompt and _p9k_on_widget_zle-line-finish.
#
#  When a command line is accepted, p10k redraws the prompt above it as just
#  the prompt character, so the scrollback keeps only commands. With
#  same-dir, only when the directory is the one of the previous prompt.
#  Needs ble.sh: its prompt_ps1_final / prompt_rps1_final are drawn at that
#  moment. (Plain readline cannot redraw a prompt it has finished with.)
# =============================================================================

# p10k: built in _p9k_init_prompt -> _p9k_transient_prompt (zsh escapes).
# '%(?.OK.ERROR)' becomes a choice made here from the status.
_p9k_init_transient() {
  _p9k_transient_ok='' _p9k_transient_err='' _p9k_transient_end=''
  [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == off ]] && return 0
  local P9K_CONTENT
  _p9k_color prompt_prompt_char_OK_VIINS FOREGROUND 76; _p9k_foreground "$_p9k__ret"
  _p9k_transient_ok=$_p9k__ret
  P9K_CONTENT='❯'
  _p9k_param prompt_prompt_char_OK_VIINS CONTENT_EXPANSION '${P9K_CONTENT}'
  _p9k_expand "$_p9k__ret"; _p9k_transient_ok+=$_p9k__x
  _p9k_color prompt_prompt_char_ERROR_VIINS FOREGROUND 196; _p9k_foreground "$_p9k__ret"
  _p9k_transient_err=$_p9k__ret
  P9K_CONTENT='❯'
  _p9k_param prompt_prompt_char_ERROR_VIINS CONTENT_EXPANSION '${P9K_CONTENT}'
  _p9k_expand "$_p9k__ret"; _p9k_transient_err+=$_p9k__x
  # the end separator is always added (usually a space); the style reset
  # only when it is something else
  _p9k_get_icon '' LEFT_SEGMENT_END_SEPARATOR
  _p9k_transient_end=$_p9k__ret
  [[ -n $_p9k__ret && $_p9k__ret != ' ' ]] && _p9k_transient_end+=%b%k%f
  _p9k__last_prompt_pwd=''
}

# Decided once per command line (p10k: in zle-line-finish): transient or not.
_p9k_transient_decide() {
  [[ ${_p9k__t_decided-} == "$_p9k__gen" ]] && return 0
  _p9k__t_decided=$_p9k__gen _p9k__t_use=0
  # p10k-on-post-prompt runs as the line is accepted; display changes it
  # makes apply to the prompt that stays on screen
  if declare -F p10k-on-post-prompt >/dev/null; then
    local g=${_p9k__display_gen:-0} _p9k__in_hook=1
    p10k-on-post-prompt
    (( ${_p9k__display_gen:-0} != g )) && { _p9k_replay_render; _p9k__t_decided=$_p9k__gen; }
  fi
  [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == off || -z $_p9k_transient_ok ]] && return 0
  if [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == always || $PWD == "$_p9k__last_prompt_pwd" ]]; then
    _p9k__t_use=1
  else
    _p9k__last_prompt_pwd=$PWD
  fi
}

# \q{p9k-final}: the left prompt drawn when the line is accepted
_p9k_ble_final() {
  _p9k_transient_decide
  if (( _p9k__t_use )); then
    local s='%b%k%s%u'
    if (( ${_p9k__status:-0} == 0 )); then s+=$_p9k_transient_ok; else s+=$_p9k_transient_err; fi
    s+="%b%k%f%s%u$_p9k_transient_end"
    # p10k: with TERM_SHELL_INTEGRATION, OSC 133;A ... 133;B around it
    (( _p9k__si )) && s=$'%{\e]133;A\a%}'$s$'%{\e]133;B\a%}'
    _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$s"
    ble/prompt/print "$_p9k__pe"
  else
    ble/prompt/print "$_p9k_ps1"
  fi
}
# \q{p9k-rfinal}: the right prompt then (none when transient)
_p9k_ble_rfinal() {
  _p9k_transient_decide
  (( _p9k__t_use )) || ble/prompt/print "$_p9k_rps"
}

_p9k_ble_transient_setup() {
  eval 'function ble/prompt/backslash:p9k-final { _p9k_ble_final; }'
  eval 'function ble/prompt/backslash:p9k-rfinal { _p9k_ble_rfinal; }'
  if [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == off ]]; then
    bleopt prompt_ps1_final= prompt_rps1_final=
  else
    bleopt prompt_ps1_final='\q{p9k-final}' prompt_rps1_final='\q{p9k-rfinal}'
  fi
}
