# =============================================================================
#  lib/p10k/main.bash - Powerlevel10k for bash: loading, initialisation and
#  the per-prompt hook. Source this file, then a p10k configuration (bash
#  form), then call `p10k_init` - or let `p10k reload` do both.
# =============================================================================

_p9k_root=${BASH_SOURCE[0]%/*}
. "$_p9k_root/data.bash"
. "$_p9k_root/core.bash"
. "$_p9k_root/render.bash"
. "$_p9k_root/segments-core.bash"
for _p9k_f in "$_p9k_root"/segments-*.bash; do
  [[ $_p9k_f == */segments-core.bash ]] || . "$_p9k_f"
done
unset _p9k_f
[[ -r $_p9k_root/expand.bash ]] && . "$_p9k_root/expand.bash"
. "$_p9k_root/command.bash"
. "$_p9k_root/parser.bash"
. "$_p9k_root/showcmd.bash"
. "$_p9k_root/transient.bash"
. "$_p9k_root/instant.bash"
. "$_p9k_root/wizard.bash"

# ------------------------------------------------------------ hot reload ---
# p10k: _p9k__param_sig. A text that changes when any POWERLEVEL9K_* setting
# (name, value, elements) changes, or DEFAULT_USER, ZLE_RPROMPT_INDENT,
# P9K_SSH, the terminal's colour count or one of the p10k-on-* hook
# functions -> _p9k__ret
_p9k_param_sig() {
  local v sig='' f
  for v in "${!POWERLEVEL9K_@}"; do
    local -n _r=$v
    sig+=$v$'\1'${#_r[@]}$'\1'"${_r[*]}"$'\2'
    unset -n _r
  done
  sig+=${DEFAULT_USER-}$'\1'${ZLE_RPROMPT_INDENT:-1}$'\1'${P9K_SSH-}$'\1'${GITSTATUS_DAEMON-}$'\1'
  # p10k: $terminfo[colors] (read again only when TERM changes)
  [[ ${_p9k__tc_term-unset} == "${TERM-}" ]] || _p9k_term_colors_init
  sig+=$_p9k__tc_colors$'\1'${_p9k_force_term_shell_integration-}$'\1'${TERM_PROGRAM-}$'\1'
  # (p10k includes the hooks' bodies; reading them in bash needs a subshell
  # per prompt, so here only whether each one exists)
  for f in p10k-on-init p10k-on-pre-prompt p10k-on-post-prompt p10k-on-post-widget; do
    declare -F "$f" >/dev/null && sig+=$f
    sig+=$'\1'
  done
  _p9k__ret=$sig
}

# ---------------------------------------------------------------- ssh ---
# p10k: _p9k_init_ssh (after Pure), run when p10k is loaded, before the
# configuration. A value inherited from a parent shell on the same terminal
# is kept (exported P9K_SSH and _P9K_SSH_TTY).
_p9k_init_ssh() {
  # (while the instant prompt captures start-up, stdin is /dev/null: tty
  # and who -m ask the terminal it saved)
  local tfd=0; (( ${_p9k__ip_active:-0} )) && tfd=$_p9k__ip_fd0
  local tty; tty=$(tty <&"$tfd" 2>/dev/null)
  [[ -n ${P9K_SSH-} && ${_P9K_SSH_TTY-} == "$tty" ]] && return 0
  P9K_SSH=0 _P9K_SSH_TTY=$tty
  export P9K_SSH _P9K_SSH_TTY
  if [[ -n ${SSH_CLIENT-}${SSH_TTY-}${SSH_CONNECTION-} ]]; then
    P9K_SSH=1
    return 0
  fi
  # Changing user on a remote system can lose SSH_CONNECTION: ask `who`.
  command -v who >/dev/null || return 0
  local ipv6='(([0-9a-fA-F]+:)|:){2,}[0-9a-fA-F]+'   # simplified, as in p10k
  local ipv4='([0-9]{1,3}\.){3}[0-9]+'
  local hostname='([.][^. ]+){2}'                  # two non-consecutive dots
  local w line
  if ! w=$(who -m <&"$tfd" 2>/dev/null); then
    # the lines of `who` for this terminal
    w=''
    while IFS= read -r line; do
      [[ $line == *[[:space:]]"${tty#/dev/}"[[:space:]]* ]] && w+=${w:+ }$line
    done < <(who 2>/dev/null)
  fi
  local re="\(?($ipv4|$ipv6|$hostname)\)?\$"
  [[ $w =~ $re ]] && P9K_SSH=1
  return 0
}
_p9k_init_ssh

# ----------------------------------------------------------------- deinit ---
# p10k: _p9k_deinit, before changed settings are applied again (hot reload,
# `p10k reload`, `p10k configure`). gitstatusd stops (the init starts it with
# the new options) and the state p10k keeps in _p9k_* variables is forgotten:
# the cached git status per repository and the count of prompts. (The
# command's start time too: see _p9k_precmd.)
_p9k_deinit() {
  [[ -n ${GITSTATUS_DAEMON_PID-} ]] && _p9k_gs_stop
  _p9k__gitstatus_last=() _p9k_git_slow=()
  unset _p9k__gitstatus_next_dir _p9k__vcs_timeout
  _p9k__prompt_idx=0
  return 0
}

# ------------------------------------------------------------------- init ---
# Icons for the font mode (p10k: _p9k_init_icons), including ICON_PADDING=none.
# _p9k_init_icons MODE PADDING (the wizard passes its own choices).
_p9k_init_icons() {
  local mode=$1
  [[ -n $mode ]] || _p9k_codeset_is_utf8 || mode=ascii
  _p9k_icons_load "$mode" "${POWERLEVEL9K_LEGACY_ICON_SPACING:-false}"
  if [[ $2 == none && $mode != ascii ]]; then
    local k v
    for k in "${!icons[@]}"; do
      v=${icons[$k]}
      while [[ $v == *' ' ]]; do v=${v% }; done
      icons[$k]=$v
    done
    for k in LEFT_SEGMENT_END_SEPARATOR MULTILINE_LAST_PROMPT_PREFIX VCS_TAG_ICON VCS_BOOKMARK_ICON \
             VCS_COMMIT_ICON VCS_BRANCH_ICON VCS_REMOTE_BRANCH_ICON; do
      icons[$k]+=' '
    done
  fi
}

_p9k_init() {
  _p9k_param_sig; _p9k__param_sig=$_p9k__ret   # for hot reload
  _p9k_cache=() _p9k_segc=()
  _p9k_init_icons "${POWERLEVEL9K_MODE-}" "${POWERLEVEL9K_ICON_PADDING-}"

  # Settings with defaults; remove earlier copies first (p10k reload).
  local var
  for var in "${!_POWERLEVEL9K_@}"; do unset "$var"; done
  _p9k_init_params

  if [[ $_POWERLEVEL9K_COLOR_SCHEME == light ]]; then _p9k_color1=7 _p9k_color2=0
  else _p9k_color1=0 _p9k_color2=7
  fi

  _p9k_init_toolbox

  _p9k_init_os

  # exit code -> text (p10k: _p9k_exitcode2str with zsh's signal names)
  declare -ga _p9k_exitcode2str=()
  local i sig
  for (( i = 0; i < 256; i++ )); do _p9k_exitcode2str[i]=$i; done
  if (( !_POWERLEVEL9K_STATUS_HIDE_SIGNAME )); then
    for (( i = 1; i < ${#_p9k_zsh_signals[@]}; i++ )); do
      sig=${_p9k_zsh_signals[i]}
      (( _POWERLEVEL9K_STATUS_VERBOSE_SIGNAME )) && sig="SIG${sig}($i)"
      (( 128 + i < 256 )) && _p9k_exitcode2str[128+i]=$sig
    done
  fi

  _p9k_init_lines
  _p9k_init_vcs

  # Per-position show conditions (p10k: _p9k_prompt_NAME_init). An init
  # function may set _p9k__segment_cond_SIDE[INDEX] to an expression; when it
  # expands to nothing the segment is not run at all for that prompt.
  declare -ga _p9k__segment_cond_left=() _p9k__segment_cond_right=() _p9k__precompute=()
  local _p9k__prompt_side _p9k__segment_index line elem
  for _p9k__prompt_side in left right; do
    local -n _p9k_ls=_p9k_line_segments_$_p9k__prompt_side
    _p9k__segment_index=1
    for line in "${_p9k_ls[@]}"; do
      for elem in $line; do
        elem=${elem%_joined}
        declare -F "_p9k_prompt_${elem}_init" >/dev/null && "_p9k_prompt_${elem}_init"
        (( _p9k__segment_index++ ))
      done
    done
    unset -n _p9k_ls
  done
  _p9k_init_display
  _p9k_init_show_on_command
  _p9k_init_transient
  # p10k: the interface scan serves ip, vpn_ip and public_ip's VPN icon
  if [[ -n $_POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE || -n $_POWERLEVEL9K_IP_INTERFACE ||
        -n $_POWERLEVEL9K_VPN_IP_INTERFACE ]]; then
    _p9k_prompt_net_iface_init
  fi

  _p9k_num_cpus=$(nproc 2>/dev/null); (( _p9k_num_cpus )) || _p9k_num_cpus=1
  # p10k: INSTANT_PROMPT=off removes the kept instant prompts
  [[ $_POWERLEVEL9K_INSTANT_PROMPT == off ]] && _p9k_delete_instant_prompt

  # Terminal shell integration (p10k: TERM_SHELL_INTEGRATION; Warp always,
  # as p10k's _p9k_precmd_first forces it there): OSC 133 marks for the
  # prompt (_p9k_build_ps1), the command (PS0) and its end (_p9k_precmd).
  # (Not ported: kitty's cmdline_url and iTerm2's PS2 mark, which hang on
  # those terminals' zsh integration.)
  # _p9k_force_term_shell_integration=1: on whatever the config says (p10k:
  # __p9k_force_term_shell_integration, which zsh4humans sets; bash4humans
  # sets this one)
  _p9k__si=$_POWERLEVEL9K_TERM_SHELL_INTEGRATION
  [[ ${_p9k_force_term_shell_integration-} == 1 || ${TERM_PROGRAM-} == WarpTerminal ||
     ${ITERM_SHELL_INTEGRATION_INSTALLED-} == Yes ]] && _p9k__si=1
  _p9k__si_right=0 _p9k__iterm_cmd=-1 _p9k__ps0_c=''
  if (( _p9k__si )); then
    _p9k__iterm_cmd=0 _p9k__ps0_c=$'\e]133;C;\a'
    if [[ ${TERM_PROGRAM-} == WarpTerminal ||
          ( ${TERM_PROGRAM-} == iTerm.app && ${TERM_PROGRAM_VERSION-} =~ ^(3\.([7-9]|[1-9][0-9])|[4-9]\.|[1-9][0-9]+\.) ) ]]; then
      _p9k__si_right=1
    fi
  fi

  # Default directory classes (p10k: _p9k_init_prompt), or expand the icons of given ones.
  if _p9k_segment_in_use dir; then
    if _p9k_isset _POWERLEVEL9K_DIR_CLASSES; then
      for (( i = 2; i < ${#_POWERLEVEL9K_DIR_CLASSES[@]}; i += 3 )); do
        _POWERLEVEL9K_DIR_CLASSES[i]=${_POWERLEVEL9K_DIR_CLASSES[i]@E}
      done
    else
      declare -ga _POWERLEVEL9K_DIR_CLASSES=()
      _p9k_get_icon prompt_dir_ETC ETC_ICON;                  _POWERLEVEL9K_DIR_CLASSES+=('/etc|/etc/*' ETC "$_p9k__ret")
      _p9k_get_icon prompt_dir_HOME HOME_ICON;                _POWERLEVEL9K_DIR_CLASSES+=('~' HOME "$_p9k__ret")
      _p9k_get_icon prompt_dir_HOME_SUBFOLDER HOME_SUB_ICON;  _POWERLEVEL9K_DIR_CLASSES+=('~/*' HOME_SUBFOLDER "$_p9k__ret")
      _p9k_get_icon prompt_dir_DEFAULT FOLDER_ICON;           _POWERLEVEL9K_DIR_CLASSES+=('*' DEFAULT "$_p9k__ret")
    fi
  fi
  # P9K_TTY: "new" if the terminal was created moments ago (p10k: zstat +ctime $TTY).
  _p9k__initialized=0
  P9K_TTY=old
  # (instant prompt capturing: the terminal it saved, see _p9k_init_ssh)
  local tfd=0; (( ${_p9k__ip_active:-0} )) && tfd=$_p9k__ip_fd0
  local tty; tty=$(tty <&"$tfd" 2>/dev/null)
  if [[ $_POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS == -* ]]; then
    P9K_TTY=new
  elif [[ -e $tty ]]; then
    local ct now; ct=$(stat -c %Z -- "$tty" 2>/dev/null); printf -v now '%(%s)T' -1
    [[ -n $ct ]] && (( now - ct < ${_POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS%%.*} )) && P9K_TTY=new
  fi
  export P9K_TTY
}

# --------------------------------------------------------------- per prompt ---
# Run first in PROMPT_COMMAND (status and PIPESTATUS must be read first).
_p9k_precmd() {
  local st=$? pst=("${PIPESTATUS[@]}") ran=0
  local _p9k__in_precmd=1   # late gitstatus answers: prompt_vcs draws them
  # p10k (_p9k_precmd_impl, first prompt): no settings at all (other than
  # MODE, CONFIG_FILE, GITSTATUS_DIR) -> the configuration wizard, if the
  # terminal allows; afterwards its config is loaded.
  if (( ! ${_p9k__configured:-0} )); then
    _p9k__configured=1
    local v any=0
    for v in "${!POWERLEVEL9K_@}"; do
      [[ $v == POWERLEVEL9K_@(MODE|CONFIG_FILE|GITSTATUS_DIR) ]] || { any=1; break; }
    done
    if (( ! any )) && _p9k_can_configure -q; then
      if ( _p9k_wizard ); then
        # shellcheck disable=SC1090
        . "$__p9k_cfg_path"
        _p9k__force_must_init=1
      else
        _p9k__instant_prompt_disabled=1
      fi
    fi
  fi
  # Settings changed since the last init: apply them again (p10k:
  # _p9k_must_init). Not with DISABLE_HOT_RELOAD, unless `p10k reload` (or
  # `p10k configure`) asked; even then only if something changed.
  local reinit=0
  if (( ${_p9k__force_must_init:-0} || ! _POWERLEVEL9K_DISABLE_HOT_RELOAD )) && _p9k_param_sig &&
     [[ $_p9k__ret != "${_p9k__param_sig-}" ]]; then
    _p9k__force_must_init=0 reinit=1
    local keep_init=$_p9k__initialized keep_tty=$P9K_TTY
    _p9k_deinit
    _p9k_init
    _p9k__initialized=$keep_init P9K_TTY=$keep_tty
  fi
  _p9k__force_must_init=0
  # A redraw (_p9k_redraw_prompt) is not a new command: nothing is printed
  # before the prompt again and the shell-integration marks are not sent.
  local redraw=${_p9k__redrawing:-0}
  if [[ -n ${_p9k__t0-} ]]; then
    ran=1
    _p9k__status=$st _p9k__pipestatus=("${pst[@]}")
    # P9K_TTY (p10k: _p9k_preexec2 / _p9k_precmd_impl): a successful clear or
    # reset makes the terminal "new" again; any other command makes it "old".
    # (After a re-init p10k has forgotten the command: "old".)
    local last; last=$(HISTTIMEFORMAT= history 1 2>/dev/null); last=${last#*[0-9]  }
    if (( st == 0 && ! reinit )) && [[ $last =~ ^[[:space:]]*(clear([[:space:]]+-x?(T[a-zA-Z0-9_\'\"-]*)?)*|reset)[[:space:]]*$ ]]; then
      P9K_TTY=new
    else
      P9K_TTY=old
    fi
    if (( reinit )); then
      # p10k's _p9k_deinit forgot when the command started: no duration
      unset P9K_COMMAND_DURATION_SECONDS
      _p9k__duration_us=0
    else
      local now=${EPOCHREALTIME//[.,]/}
      _p9k__duration_us=$(( now - _p9k__t0 ))
      printf -v P9K_COMMAND_DURATION_SECONDS '%d.%06d' $(( _p9k__duration_us / 1000000 )) $(( _p9k__duration_us % 1000000 ))
    fi
    _p9k__t0=''
  elif [[ -z ${_p9k__status-} ]]; then
    _p9k__status=0 _p9k__pipestatus=(0)
    unset P9K_COMMAND_DURATION_SECONDS
    _p9k__duration_us=0
  else
    unset P9K_COMMAND_DURATION_SECONDS   # empty command line: p10k shows no duration
    # p10k (_p9k_save_status): a line given up with Ctrl-C (SIGINT) takes
    # the new status, 130; an empty line only if the status changed; the
    # pipe status is then that status alone. Plain bash: $? is 130 after
    # Ctrl-C and unchanged after an empty line, so "if changed" covers both.
    # ble.sh: Ctrl-C is its discard-line widget (noted in _p9k__ble_sigint),
    # and $? after it means nothing.
    if (( ! redraw )); then
      if (( ${_p9k_ble:-0} )); then
        if (( ${_p9k__ble_sigint:-0} )); then st=130; else st=$_p9k__status; fi
      fi
      (( st != _p9k__status )) && _p9k__status=$st _p9k__pipestatus=("$st")
    fi
  fi
  (( redraw )) || _p9k__ble_sigint=0

  # zsh %h / %!: the number the next command gets (bash's \! in PS1).
  local hl; hl=$(HISTTIMEFORMAT= history 1 2>/dev/null); hl=${hl#"${hl%%[! ]*}"}; hl=${hl%%[!0-9]*}
  _p9k__histno=$(( ${hl:-0} + 1 ))

  # A new terminal turns "old" once its first prompt has been shown.
  (( ! ran && ${_p9k__initialized:-0} )) && [[ $P9K_TTY == new ]] && P9K_TTY=old

  local j; j=$(jobs -p); local -a jl=()
  [[ -n $j ]] && mapfile -t jl <<<"$j"
  _p9k__jobs=${#jl[@]}
  _p9k__jobs_not0=$_p9k__jobs; (( _p9k__jobs == 0 )) && _p9k__jobs_not0=''
  _p9k__jobs_not1=$_p9k__jobs; (( _p9k__jobs == 1 )) && _p9k__jobs_not1=''
  if (( EUID == 0 )); then _p9k__is_root=1 _p9k__not_root=''; else _p9k__is_root='' _p9k__not_root=1; fi

  # Blank line and ruler (p10k: display states empty_line and ruler, set
  # before each prompt): hide on a new terminal; print (before the prompt)
  # normally; show (inside the prompt) with a transient prompt or a
  # p10k-on-post-prompt hook, so that redrawing the prompt removes them too.
  local mode=print
  if [[ $P9K_TTY == new ]]; then mode=hide
  elif [[ $_POWERLEVEL9K_TRANSIENT_PROMPT != off ]] || declare -F p10k-on-post-prompt >/dev/null; then mode=show
  fi
  (( _POWERLEVEL9K_PROMPT_ADD_NEWLINE )) && _p9k__display_v[empty_line]=$mode
  (( _POWERLEVEL9K_SHOW_RULER )) && _p9k__display_v[ruler]=$mode

  # p10k: the user's hooks p10k-on-init (first prompt) and p10k-on-pre-prompt;
  # SHOW_ON_COMMAND segments start hidden
  local _p9k__in_hook=1   # the prompt is built below anyway
  (( ${_p9k__initialized:-0} )) || ! declare -F p10k-on-init >/dev/null || p10k-on-init
  _p9k__initialized=1
  _p9k_show_on_command_reset
  declare -F p10k-on-pre-prompt >/dev/null && p10k-on-pre-prompt
  unset _p9k__in_hook

  local pre='' e=${_p9k__display_v[empty_line]} rl=${_p9k__display_v[ruler]}
  # a redraw: what was printed before the prompt is on screen already
  (( redraw )) && { [[ $e == print ]] && e=hide; [[ $rl == print ]] && rl=hide; }
  if (( _POWERLEVEL9K_PROMPT_ADD_NEWLINE && _POWERLEVEL9K_PROMPT_ADD_NEWLINE_COUNT > 0 )) && [[ $e != hide ]]; then
    local nl; printf -v nl '%*s' "$_POWERLEVEL9K_PROMPT_ADD_NEWLINE_COUNT" ''
    if [[ $e == print ]]; then printf '%s' "${nl// /$'\n'}"; else pre+=${nl// /$'\n'}; fi
  fi
  if (( _POWERLEVEL9K_SHOW_RULER )) && [[ $rl != hide ]]; then
    local r=''
    if [[ -n $_p9k_ruler_char ]]; then
      local cols=${COLUMNS:-80} ind=${ZLE_RPROMPT_INDENT:-1}
      printf -v r '%*s' $(( cols - ind > 0 ? cols - ind : 0 )) ''
      r=${r// /$_p9k_ruler_char}
      # readline needs \001..\002 around codes only when this goes into PS1
      _p9k__pe_mark=$(( ! ${_p9k_ble:-0} )) _p9k__pe_cont=0
      [[ $rl == show ]] || _p9k__pe_mark=0
      _p9k_pe "$_p9k_ruler_style$r%k%f"; r=$_p9k__pe
    fi
    if [[ $rl == print ]]; then printf '%s\n' "$r"; else pre+=$r$'\n'; fi
  fi
  _p9k__ps_pre=$pre

  _p9k__dir_seen=0; unset _p9k__dir_placeholder _p9k__dir_line
  # p10k resets these before each prompt (_p9k_precmd_impl); the line editor
  # then updates them (see _p9k_ble_keymap below).
  _p9k__keymap=main _p9k__zle_state=insert _p9k__region_active=0
  (( ${_p9k_ble:-0} )) && _p9k_ble_keymap
  _p9k__rec=()
  # values some segments compute before the prompt (p10k: its async worker)
  _p9k_fetch_cwd
  (( ++_p9k__prompt_idx ))
  # p10k: _p9k_iterm2_precmd (TERM_SHELL_INTEGRATION). The command ended:
  # OSC 133;D with its status (and a C first if no command started, an
  # empty line). _p9k__iterm_cmd: -1 off, 0 none yet, 1 prompt, 2 command.
  if (( ! redraw && _p9k__iterm_cmd >= 0 )); then
    if (( _p9k__iterm_cmd )) && [[ -t 1 ]]; then
      (( _p9k__iterm_cmd == 1 )) && printf '\e]133;C;\a'
      printf '\e]133;D;%s\a' "$st"
    fi
    _p9k__iterm_cmd=1
  fi
  _p9k_vcs_precmd            # ble.sh: ask gitstatusd now, wait in prompt_vcs
  local f; for f in "${_p9k__precompute[@]}"; do "$f"; done
  _p9k_set_prompt
  _p9k_build_ps1
  # the instant prompt for this directory (lib/p10k/instant.bash). p10k
  # writes it after the prompt is drawn (a zle -F callback); under ble.sh
  # its idle queue does the same; plain readline has no such hook.
  if (( ! redraw )); then
    if (( ${_p9k_ble:-0} )); then ble/util/idle.push _p9k_dump_instant_prompt
    else _p9k_dump_instant_prompt
    fi
  fi
  _p9k__clm=${COLUMNS:-80}   # used by the next prompt (see _p9k_dir_fit)
  # answers still to come redraw the prompt from ble.sh's idle loop
  (( ${_p9k_ble:-0} && _p9k__gs_inflight )) && _p9k_gs_watch
}

# Build the prompt again while a line is being edited, e.g. after a key
# binding changed the directory (zsh4humans does this with p10k: it runs the
# precmd hooks again). The last command's status stays; there is no
# duration, as on an empty line. The caller lets the line editor redraw.
_p9k_redraw_prompt() {
  local _p9k__redrawing=1
  _p9k_precmd
}

# Prompt-escape strings -> PS1 (and the right part of the last line).
_p9k_build_ps1() {
  local i n=${#_p9k_ps_lines[@]} ps=${_p9k__ps_pre-}
  _p9k__pe_mark=$(( ! ${_p9k_ble:-0} ))
  # readline wants \001..\002 around codes, ble.sh none
  local mo=$'\001' me=$'\002'; (( ${_p9k_ble:-0} )) && mo='' me=''
  # ble.sh redraws a changed prompt over the old one (Alt+arrows, transient
  # prompt) without erasing what is left of a longer old line: each line
  # but the last ends in "erase to end of line" (ble.sh passes it through
  # as zero-width). readline: _b4h_prompt_refresh erases the lines itself.
  local el=''; (( ${_p9k_ble:-0} )) && el=$'\e[K'
  # p10k (TERM_SHELL_INTEGRATION): OSC 133;A before the prompt (and before
  # a blank line or ruler kept in it), 133;B after its last line
  (( _p9k__si )) && ps=$mo$'\e]133;A\a'$me$ps
  local first=1 lw=0 wraps=0 c0=${COLUMNS:-80}
  for (( i = 1; i <= n; i++ )); do
    # `p10k display N=hide`: the line and its line break are left out
    [[ -n ${_p9k_line_hidden[i]-} ]] && continue
    # one zsh PROMPT: colour state runs on from line to line
    _p9k__pe_cont=$(( ! first )); first=0
    _p9k_pe "${_p9k_ps_lines[i]}"
    ps+=$_p9k__pe
    lw=$_p9k__pw          # width of the last line shown
    # screen rows added by lines wider than the terminal (for ble.sh below;
    # a full row followed by a line break takes one row, not two)
    if (( c0 > 0 )); then
      if (( i < n )); then (( lw > 0 && (wraps += (lw - 1) / c0) )); else (( wraps += lw / c0 )); fi
    fi
    (( i < n )) && ps+=$el$'\n'
  done
  _p9k_rps=''
  if [[ -n $_p9k_rprompt && -z ${_p9k_line_hidden[n]-} ]]; then
    _p9k__pe_mark=0 _p9k__pe_cont=0; _p9k_pe "$_p9k_rprompt"
    local rp=$_p9k__pe rw=$_p9k__pw cols=${COLUMNS:-80} ind=${ZLE_RPROMPT_INDENT:-1}
    # p10k: Warp and iTerm2 3.7+ also mark the right prompt
    (( _p9k__si_right )) && rp=$'\e]133;P;k=r\a'$rp$'\e]133;B\a'
    # zsh shows RPROMPT only if it fits beside the last line:
    # left + right < COLUMNS - ZLE_RPROMPT_INDENT (with nothing typed yet).
    # A last line wider than the terminal wraps; zsh counts what is on its
    # last screen row.
    (( cols > 0 )) && lw=$(( lw % cols ))
    if (( lw + rw >= cols - ind )); then
      :
    elif (( ${_p9k_ble:-0} )); then
      # ble.sh puts the right prompt against the last column; zsh leaves
      # ZLE_RPROMPT_INDENT columns free after it.
      local pad; printf -v pad '%*s' "$(( ind > 0 ? ind : 0 ))" ''
      _p9k_rps=$rp$pad
      # ble.sh lays the right prompt out from the prompt's first row; zsh's
      # RPROMPT belongs to the last one, so empty lines go first (one per
      # line break in PS1, including a blank line or ruler kept in it, and
      # one per row a wide line wraps onto).
      local nls=${ps//[!$'\n']/}
      for (( i = 0; i < ${#nls} + wraps; i++ )); do _p9k_rps=$'\n'$_p9k_rps; done
    else
      # readline: draw at the right edge, then put the cursor back
      local col=$(( cols - ind - rw + 1 ))
      (( col > 1 )) && ps+=$'\001\e7\e['"${col}G$rp"$'\e8\002'
    fi
  fi
  (( _p9k__si )) && ps+=$mo$'\e]133;B\a'$me
  _p9k_ps1=$ps
  (( _p9k__gen++ ))
}

# ------------------------------------------------------- keymap (ble.sh) ---
# zsh's view of the line editor, as p10k reads it: KEYMAP (main, viins, vicmd),
# REGION_ACTIVE (p10k folds 2, line-wise, into 1, and reads it only in vicmd)
# and ZLE_STATE (insert/overwrite). Taken from ble.sh's keymap stack:
#   vi_imap -> viins   vi_nmap/vi_omap -> vicmd 0   vi_xmap/vi_smap -> vicmd 1
#   emacs   -> main    (zsh's emacs keymap is linked to main)
# vi_cmap (the ':' line) leaves the previous state, as zsh has no such keymap.
_p9k_ble_keymap() {
  local km=${_ble_decode_keymap-} i=${#_ble_decode_keymap_stack[@]}
  while [[ $km != vi_?map && $km != emacs ]]; do
    (( i-- )) || return 0
    km=${_ble_decode_keymap_stack[i]}
  done
  case $km in
    vi_imap) _p9k__keymap=viins ;;
    vi_nmap|vi_omap) _p9k__keymap=vicmd _p9k__region_active=0 ;;
    vi_xmap|vi_smap) _p9k__keymap=vicmd _p9k__region_active=1 ;;
    emacs) _p9k__keymap=main ;;
    *) return 0 ;;
  esac
  [[ -n ${_ble_edit_overwrite_mode-} ]] && _p9k__zle_state=overwrite || _p9k__zle_state=insert
}

# Called by ble.sh after a mode change: if the state the prompt shows changed,
# rebuild PS1 from the recorded segments and let ble.sh redraw it.
_p9k_redraw_keymap() {
  (( _p9k__initialized )) || return 0
  local old=$_p9k__keymap.$_p9k__zle_state.$_p9k__region_active
  _p9k_ble_keymap
  [[ $old == "$_p9k__keymap.$_p9k__zle_state.$_p9k__region_active" ]] && return 0
  _p9k_replay_render
}

# Rebuild PS1 from the recorded segment calls (nothing is run again).
_p9k_replay_render() {
  _p9k__replay=1
  _p9k__dir_seen=1
  _p9k_set_prompt
  _p9k__replay=0
  local clm=$_p9k__clm
  _p9k_build_ps1
  _p9k__clm=$clm
  return 0
}

# PS1 under ble.sh is the sequence \q{p9k-ps1}. It prints _p9k_ps1 and tells
# ble.sh that the result depends on _p9k__gen, so bumping _p9k__gen (done by
# _p9k_build_ps1) makes ble.sh draw the new prompt on its next redraw. Unlike
# ble/prompt/clear this does not run PROMPT_COMMAND again.
_p9k__gen=0
_p9k_ble_q() {
  ble/prompt/unit/add-hash '$_p9k__gen'
  if (( ${#_p9k_show_on_command[@]} )) || declare -F p10k-on-post-widget >/dev/null; then
    # SHOW_ON_COMMAND and p10k-on-post-widget: the prompt depends on the line
    ble/prompt/unit/add-hash '$_ble_edit_str'
    local g=${_p9k__display_gen:-0} ch=1
    _p9k_show_on_command_update "${_ble_edit_str-}" && ch=0
    if declare -F p10k-on-post-widget >/dev/null && [[ ${_ble_edit_str-} != "${_p9k__pw_last-}" ]]; then
      _p9k__pw_last=${_ble_edit_str-}
      local -a P9K_COMMANDS=()
      [[ -n $_p9k__pw_last ]] && _p9k_parse_buffer "$_p9k__pw_last" "$_POWERLEVEL9K_COMMANDS_MAX_TOKEN_COUNT"
      local _p9k__in_hook=1        # display changes are redrawn below
      p10k-on-post-widget
    fi
    (( ch == 0 || ${_p9k__display_gen:-0} != g )) && _p9k_replay_render
  fi
  ble/prompt/print "$_p9k_ps1"
}

_p9k_ble_hooks() {
  # ble.sh calls update-mode-indicator on every vi mode change; overwrite-mode
  # is the emacs Insert key. Both are loaded on demand, hence eval-after-load.
  ble/function#advice after ble/widget/overwrite-mode _p9k_redraw_keymap
  # Ctrl-C (emacs keymap): zsh would get SIGINT, status 130 (_p9k_precmd)
  ble/function#advice before ble/widget/discard-line '_p9k__ble_sigint=1'
  _p9k_ble_vi_hook() {
    ble/function#advice after ble/keymap:vi/update-mode-indicator _p9k_redraw_keymap
    # The prompt shows the mode (as in zsh, where no "-- INSERT --" line exists).
    if _p9k_segment_in_use vi_mode || _p9k_segment_in_use prompt_char; then
      bleopt keymap_vi_mode_show=
    fi
  }
  blehook/eval-after-load keymap_vi _p9k_ble_vi_hook
}

# --------------------------------------------------------------- the hooks ---
p10k_init() {
  _p9k__force_must_init=0
  # ble.sh loaded (BLE_VERSION is set by ble.sh, attached or not)?
  if [[ -n ${BLE_VERSION-} ]]; then _p9k_ble=1; else _p9k_ble=0; fi
  _p9k_init
  _p9k__t0=''
  # PS0 runs as a command starts: the start time; with shell integration
  # also OSC 133;C (p10k: _p9k_iterm2_preexec). The subscript is evaluated
  # as arithmetic, which does the assignments; it ends in 0, element 0 of
  # an unset array: empty. (A negative index would be an error.)
  PS0='${_p9k__t0_set[_p9k__t0=${EPOCHREALTIME//[.,]/}, _p9k__iterm_cmd = _p9k__iterm_cmd < 0 ? -1 : 2, 0]}${_p9k__ps0_c}'
  PS1='${_p9k_ps1}'
  [[ $PROMPT_COMMAND == *_p9k_precmd* ]] || PROMPT_COMMAND="_p9k_precmd${PROMPT_COMMAND:+; $PROMPT_COMMAND}"
  if (( ${_p9k_ble:-0} )); then
    eval 'function ble/prompt/backslash:p9k-ps1 { _p9k_ble_q; }'
    PS1='\q{p9k-ps1}'
    eval 'function ble/prompt/backslash:p9k-rps1 { ble/prompt/unit/add-hash '"'"'$_p9k__gen'"'"'; ble/prompt/print "$_p9k_rps"; }'
    bleopt prompt_rps1='\q{p9k-rps1}'
    bleopt exec_restore_pipestatus=1
    # zsh shows no "[ble: exit N]" / "[ble: elapsed ...]" lines; the prompt has these
    bleopt exec_errexit_mark= exec_elapsed_mark=
    _p9k_ble_hooks
    _p9k_ble_transient_setup
  fi
}
