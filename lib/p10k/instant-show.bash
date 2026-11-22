# =============================================================================
#  lib/p10k/instant-show.bash - instant prompt, the part that shows it while
#  the shell starts (p10k: the file the instant-prompt preamble at the top of
#  ~/.zshrc sources, and _p9k_clear_instant_prompt). Standalone and small:
#  it is loaded before anything else, and uses only builtins.
#
#    _p9k_instant_prompt_show    print the kept prompt for this directory and
#                                capture what the rest of start-up prints
#    _p9k_instant_prompt_pause   the real terminal again for a while (ble.sh
#    _p9k_instant_prompt_resume  must load with it), then capture again
#    _p9k_clear_instant_prompt   end: terminal back, prompt erased, captured
#                                output printed (verbose: with p10k's warning)
#
#  The records are written by lib/p10k/instant.bash (see there for the format).
# =============================================================================

_p9k__ip_active=0

_p9k_instant_prompt_show() {
  [[ $- == *i* && -t 0 && -t 1 && -t 2 ]] || return 0
  (( ! _p9k__ip_active )) || return 0
  [[ $PWD == /* ]] || return 0
  local dir=${_p9k_instant_dir:-${XDG_CACHE_HOME:-$HOME/.cache}/p10k-bash-${USER:-$EUID}}
  local f=$dir/prompt-${#PWD}
  [[ -r $f ]] || return 0
  # the key, as p10k's: directory, ssh (from the environment), %#, plus the
  # environment of the instant segments (instant.bash: _p9k_ip_env)
  local ssh=0; [[ -n ${SSH_CLIENT-}${SSH_TTY-}${SSH_CONNECTION-} ]] && ssh=1
  local ch='$'; (( EUID )) || ch='#'
  local env="${RANGER_LEVEL-}:${NNNLVL-}:${LF_LEVEL-}:${XPLR_PID-}:${YAZI_LEVEL-}:${MC_TMPDIR-}"
  env+=":${IN_NIX_SHELL-}:${DIRENV_DIR-}:${VIMRUNTIME-}:${CHEZMOI-}:${HISTORY_START_WITH_GLOBAL-}:${P9K_TOOLBOX_NAME-}"
  local key="$PWD:$ssh:$ch:$env" content=''
  IFS= read -r -d '' content <"$f"
  local tail=${content##*$'\x1e'"$key"$'\x1f'}
  (( ${#tail} != ${#content} )) || return 0
  local -a v=()
  IFS=$'\x1f' read -r -d '' -a v <<<"${tail%%$'\x1e'*}"
  (( ${#v[@]} >= 16 )) || return 0
  v[-1]=${v[-1]%$'\n'}   # (the here-string's newline)
  # TERM and width as when it was kept (it is finished text)
  [[ ${v[0]} == "${TERM-}" && ${v[1]} == "${COLUMNS-}" ]] || return 0
  local mode=${v[2]} height=${v[3]} pre=${v[4]} p1=${v[5]} last=${v[6]} rp=${v[7]}
  local lw=${v[8]} rw=${v[9]} maxage=${v[14]} ind=${v[15]}
  # the clock: the current time in place of the kept one (same width only)
  local t
  if [[ -n ${v[11]} ]]; then
    LC_ALL=C printf -v t "%(${v[11]})T" -1
    (( ${#t} == ${#v[10]} )) && p1=${p1/"${v[10]}"/"$t"} last=${last/"${v[10]}"/"$t"} rp=${rp/"${v[10]}"/"$t"}
  fi
  if [[ -n ${v[13]} ]]; then
    LC_ALL=C printf -v t "%(${v[13]})T" -1
    (( ${#t} == ${#v[12]} )) && p1=${p1/"${v[12]}"/"$t"} last=${last/"${v[12]}"/"$t"} rp=${rp/"${v[12]}"/"$t"}
  fi
  # p10k: the blank line and the ruler only on an old terminal (P9K_TTY:
  # "new" if the terminal was created less than NEW_TTY_MAX_AGE_SECONDS ago)
  if [[ -n $pre ]]; then
    local tty_new=1
    if [[ $maxage != -* ]]; then
      local tty ct now
      tty=$(tty 2>/dev/null) && ct=$(stat -c %Z -- "$tty" 2>/dev/null) && printf -v now '%(%s)T' -1 &&
        (( now - ct >= ${maxage%%.*} )) && tty_new=0
    fi
    (( tty_new )) && pre=''
  fi
  local nl=${pre}${p1}; nl=${nl//[!$'\n']/}
  local -i ph=${#nl}            # lines above the last one
  (( height += ph ))
  # p10k (the root file): make room below (the prompt and its command lines),
  # print, and the right part only if at least 40 columns are left between
  local out=$'\e[0m\r\e[K'
  if (( height > 0 )); then
    local lfs; printf -v lfs '%*s' "$height" ''; out+=${lfs// /$'\n'}$'\e['"${height}A"
  fi
  out+=$pre$p1$last
  if [[ -n $rp ]] && (( rw )); then
    local -i gap=$(( ${COLUMNS:-80} - lw - rw - ind ))
    if (( gap >= 40 )); then
      local sp; printf -v sp '%*s' "$gap" ''
      out+=$sp$rp$'\e[0m\r'
      (( lw )) && out+=$'\e['"${lw}C"
    fi
  fi
  # what start-up prints goes to a file, until _p9k_clear_instant_prompt
  _p9k__ip_out=$dir/output-$$
  rm -f -- "$_p9k__ip_out" 2>/dev/null
  { : >"$_p9k__ip_out"; } 2>/dev/null || return 0
  printf '%s' "$out"
  _p9k__ip_mode=$mode _p9k__ip_ph=$ph
  exec {_p9k__ip_fd0}<&0 {_p9k__ip_fd1}>&1 {_p9k__ip_fd2}>&2 0</dev/null 1>>"$_p9k__ip_out" 2>&1
  _p9k__ip_active=1
}

_p9k_instant_prompt_pause() {
  (( _p9k__ip_active == 1 )) || return 0
  exec 0<&"$_p9k__ip_fd0" 1>&"$_p9k__ip_fd1" 2>&"$_p9k__ip_fd2"
  _p9k__ip_active=2
}
_p9k_instant_prompt_resume() {
  (( _p9k__ip_active == 2 )) || return 0
  exec 0</dev/null 1>>"$_p9k__ip_out" 2>&1
  _p9k__ip_active=1
}

# p10k: _p9k_clear_instant_prompt (also `p10k clear-instant-prompt`)
# (its patterns need extglob both when it is defined and when it runs;
# the shell's own setting is put back each time)
shopt -q extglob || { shopt -s extglob; _p9k__ip_ext=1; }
_p9k_clear_instant_prompt() {
  (( _p9k__ip_active )) || return 0
  exec 0<&"$_p9k__ip_fd0" 1>&"$_p9k__ip_fd1" 2>&"$_p9k__ip_fd2"
  exec {_p9k__ip_fd0}<&- {_p9k__ip_fd1}>&- {_p9k__ip_fd2}>&-
  _p9k__ip_active=0
  # back to where the prompt began, and away with it (p10k: rc, ed)
  printf '\r'; (( _p9k__ip_ph )) && printf '\e[%dA' "$_p9k__ip_ph"; printf '\e[0m\e[J'
  if [[ -s $_p9k__ip_out ]]; then
    local content='' mode=${_POWERLEVEL9K_INSTANT_PROMPT:-$_p9k__ip_mode}
    [[ $mode == verbose ]] && IFS= read -r -d '' content <"$_p9k__ip_out"
    # (p10k leaves out terminal answers and escape sequences when deciding
    # whether anything unexpected was printed)
    local unexpected=$content
    shopt -q extglob || { shopt -s extglob; local _ext=1; }
    unexpected=${unexpected//$'\e[?'+([0-9;])c/}
    unexpected=${unexpected//$'\e['+([0-9])' q'/}
    unexpected=${unexpected//$'\eP'*([!$'\e'])$'\e\\'/}
    unexpected=${unexpected//$'\e'*([!$'\a\e'])@($'\a'|$'\e\\')/}
    unexpected=${unexpected//$'\033[1;32mShell integration activated\033[0m\n'/}
    unexpected=${unexpected//$'\r'/}
    [[ -n ${_ext-} ]] && shopt -u extglob
    P9K_STARTUP_CONSOLE_OUTPUT=("$content" "$unexpected")
    if [[ -n $unexpected ]]; then
      local b=$'\e[1m' n=$'\e[22m' y=$'\e[33m' d=$'\e[39m'
      printf '%s\n' "" "[${y}WARNING${d}]: Console output during bash initialization detected." "" \
        "When using Powerlevel10k with instant prompt, console output during bash" \
        "initialization may indicate issues." "" "You can:" "" \
        "  - ${b}Recommended${n}: Change ${b}~/.bashrc${n} so that it does not perform console I/O" \
        "    after bash4humans is loaded. See the link below for details." "" \
        "    * You ${b}will not${n} see this error message again." \
        "    * Bash will start ${b}quickly${n} and prompt will update ${b}smoothly${n}." "" \
        "  - Suppress this warning either by running ${b}p10k configure${n} or by manually" \
        "    defining the following parameter:" "" \
        "      ${y}typeset${d} -g POWERLEVEL9K_INSTANT_PROMPT=quiet" "" \
        "    * You ${b}will not${n} see this error message again." \
        "    * Bash will start ${b}quickly${n} but prompt will ${b}jump down${n} after initialization." "" \
        "  - Disable instant prompt either by running ${b}p10k configure${n} or by manually" \
        "    defining the following parameter:" "" \
        "      ${y}typeset${d} -g POWERLEVEL9K_INSTANT_PROMPT=off" "" \
        "    * You ${b}will not${n} see this error message again." \
        "    * Bash will start ${b}slowly${n}." "" \
        "  - Do nothing." "" \
        "    * You ${b}will${n} see this error message every time you start bash." \
        "    * Bash will start ${b}quickly${n} but prompt will ${b}jump down${n} after initialization." "" \
        "For details, see:" "https://github.com/romkatv/powerlevel10k#instant-prompt" "" \
        "${y}-- console output produced during bash initialization follows --${d}" ""
    fi
    cat -- "$_p9k__ip_out"
  fi
  rm -f -- "$_p9k__ip_out" 2>/dev/null
  return 0
}
[[ -n ${_p9k__ip_ext-} ]] && shopt -u extglob
unset _p9k__ip_ext
