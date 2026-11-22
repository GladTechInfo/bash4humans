# =============================================================================
#  lib/prompt.bash - the prompt: Powerlevel10k, ported to bash (lib/p10k),
#  and the terminal integration of bash4humans.
#
#  Config:   ~/.config/bash4humans/p10k.bash - a p10k configuration (the
#            POWERLEVEL9K_* settings of ~/.p10k.zsh, converted to bash).
#            `b4h configure` (= `p10k configure`) writes it; the first start
#            runs that wizard, as p10k does. `b4h configure --from-p10k`
#            converts an existing ~/.p10k.zsh. Hand edits: `b4h prompt edit`.
#  Terminal: OSC 133 prompt marks (p10k's TERM_SHELL_INTEGRATION, switched
#            on here as zsh4humans does), OSC 7 (current directory), the
#            window title, a notification after long commands.
# =============================================================================

_b4h_p_conf=${XDG_CONFIG_HOME:-$HOME/.config}/bash4humans/p10k.bash
# A `b4h ssh` session brings its config along (see _b4h_ssh)
[[ $B4H_HOME == *bash4humans-ssh* && -r $B4H_HOME/p10k.bash ]] && _b4h_p_conf=$B4H_HOME/p10k.bash

# --------------------------------------------------------- terminal marks ---
_b4h_integrate=0
if [[ $B4H_SHELL_INTEGRATION == yes ]]; then
  _b4h_integrate=1
  for _b4h_f in $B4H_SHELL_INTEGRATION_EXCEPT; do
    [[ ${SSH_CONNECTION%% *} == "$_b4h_f" ]] && _b4h_integrate=0
  done
  unset _b4h_f
fi
_b4h_osc7() {
  (( _b4h_integrate )) && printf '\e]7;file://%s%s\a' "$HOSTNAME" "${PWD// /%20}"
  return 0
}

# ------------------------------------------------------------ window title ---
# B4H_TITLE_IDLE at the prompt, B4H_TITLE_RUNNING while a command runs
# (zsh4humans' term-title precmd / preexec). Both are bash prompt strings,
# expanded with ${var@P}; the command line is in $B4H_COMMAND, which is
# inserted as text (a value is never expanded again).
_b4h_title_set() {    # $1: format, $2: the command line (or nothing)
  [[ $B4H_TITLE == yes && -n $1 ]] || return 0
  local B4H_COMMAND=$2 fmt=$1 t
  # control characters (a newline in a command, escapes) become spaces:
  # nothing from the command line can end the title sequence early
  B4H_COMMAND=${B4H_COMMAND//[[:cntrl:]]/ }
  B4H_COMMAND=${B4H_COMMAND#"${B4H_COMMAND%%[![:space:]]*}"}   # leading blanks
  (( ${#B4H_COMMAND} <= 200 )) || B4H_COMMAND="${B4H_COMMAND:0:199}…"
  t=${fmt@P}
  printf '\e]0;%s\a' "${t//[[:cntrl:]]/ }"
}
_b4h_title_idle() { _b4h_title_set "$B4H_TITLE_IDLE"; }

# The command that starts: ble.sh passes it to its PREEXEC hook. Plain
# readline has no such hook; PS0 (printed as a command starts) calls
# _b4h_title_ps0 in a subshell, which takes the command from the history,
# if it was recorded there (a line starting with a space is not: then the
# history's last entry is an older command, and the title stays as it is).
_b4h_title_preexec() { _b4h_title_set "$B4H_TITLE_RUNNING" "$1"; }
_b4h_hist_next=
_b4h_title_ps0() {
  [[ $B4H_TITLE == yes && -n $B4H_TITLE_RUNNING ]] || return 0
  local h n
  h=$(HISTTIMEFORMAT= builtin history 1)
  h=${h#"${h%%[![:space:]]*}"}       # leading blanks
  n=${h%%[!0-9]*}                    # the entry's number
  [[ -n $n && $n == "$_b4h_hist_next" ]] || return 0
  h=${h#"$n"}; h=${h#"${h%%[![:space:]]*}"}
  _b4h_title_set "$B4H_TITLE_RUNNING" "$h"
}
_b4h_ps0_title='$(_b4h_title_ps0)'

# ------------------------------------------------------------ prompt hooks ---
# Runs after p10k's _p9k_precmd (which reads the status first) in
# PROMPT_COMMAND: shared history (ble.sh shares it itself), the terminal's
# directory and title, and the notification after a long command.
_b4h_precmd() {
  if (( ! _b4h_ble )) && [[ $B4H_HISTORY_SHARE == yes && -n ${HISTFILE-} && $HISTFILE != /dev/null ]]; then
    history -a; history -n
  fi
  _b4h_osc7
  _b4h_dirhist_note
  _b4h_title_idle
  if (( ! _b4h_ble )); then
    # readline: the number the next command gets in the history (HISTCMD
    # here; \! lags behind once the history has entries), and the title
    # code at the end of PS0 (p10k sets PS0 again whenever it initialises)
    _b4h_hist_next=$HISTCMD
    [[ $PS0 == *"$_b4h_ps0_title" ]] || PS0+=$_b4h_ps0_title
  fi
  # P9K_COMMAND_DURATION_SECONDS: set by p10k when a command ran
  if (( B4H_NOTIFY_MIN > 0 )) && [[ -n ${P9K_COMMAND_DURATION_SECONDS-} ]]; then
    local secs=${P9K_COMMAND_DURATION_SECONDS%.*}
    if (( secs >= B4H_NOTIFY_MIN )); then
      printf '\a'
      if command -v notify-send >/dev/null && [[ -n ${DISPLAY-}${WAYLAND_DISPLAY-} ]]; then
        notify-send -a bash "Finished after ${secs}s" "$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]* *//')" 2>/dev/null &
        disown 2>/dev/null
      fi
    fi
  fi
  return 0
}

# After a key changes the directory (Alt+arrows): build the prompt again,
# keeping what has been typed (zsh4humans runs p10k's precmd again).
_b4h_prompt_refresh() {
  _b4h_osc7
  _b4h_dirhist_note
  _b4h_title_idle
  _p9k_redraw_prompt
  # ble.sh: the new prompt's hash (_p9k_ble_q) makes it redraw by itself.
  # (ble/prompt/clear would leave the old first line on screen.)
  if (( ! _b4h_ble )); then
    # readline redraws only the last line of the prompt; rewrite the lines
    # above it (they are on screen just above the cursor's line)
    # (mapfile, not read -a: a blank line kept in the prompt is a line too)
    local ps=${_p9k_ps1//[$'\001\002']/} i
    local -a l=()
    mapfile -t l <<<"$ps"
    local n=${#l[@]}
    (( n > 1 )) || return 0
    printf '\e[%dA\r' $(( n - 1 ))
    for (( i = 0; i < n - 1; i++ )); do printf '\e[2K%s\n' "${l[i]}"; done
  fi
}

# ------------------------------------------------------------- the prompt ---
. "$B4H_ROOT/lib/p10k/main.bash"
# p10k configs unset POWERLEVEL9K_CONFIG_FILE as they load; the wizard and
# `p10k configure` still write here
_p9k_default_cfg=$_b4h_p_conf
POWERLEVEL9K_CONFIG_FILE=$_b4h_p_conf
(( _b4h_integrate )) && _p9k_force_term_shell_integration=1

_b4h_prompt_apply() {
  if [[ -r $_b4h_p_conf ]]; then
    # shellcheck disable=SC1090
    . "$_b4h_p_conf"
  elif [[ $B4H_WIZARD != yes || $B4H_HOME == *bash4humans-ssh* ]]; then
    # no wizard on the first prompt (p10k: any POWERLEVEL9K_* setting stops it)
    POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true
  fi
  p10k_init
  [[ $PROMPT_COMMAND == *_b4h_precmd* ]] || PROMPT_COMMAND+="${PROMPT_COMMAND:+; }_b4h_precmd"
  if (( _b4h_ble )); then
    blehook PREEXEC!=_b4h_title_preexec    # (!= adds it once)
  fi
  # plain readline: no ^C echoed on Ctrl-C (zsh's line editor shows none)
  (( _b4h_ble )) || bind 'set echo-control-characters off' 2>/dev/null
}

# A short summary of the config: its "Wizard options" header lines.
_b4h_cfg_summary() {
  [[ -r $_b4h_p_conf ]] || { echo 'none (p10k defaults)'; return; }
  local s
  s=$(awk '/^# Wizard options:/{f=1; sub(/^# Wizard options: */,""); printf "%s", $0; next}
           f && /^# / { if ($0 ~ /Type `p10k configure`/) exit; sub(/^# */," "); printf "%s", $0; next } f{exit}' "$_b4h_p_conf")
  echo "${s:-hand-made (no wizard options)}"
}

# ------------------------------------------------------------- commands ---
# b4h configure                  the wizard (p10k configure)
# b4h configure --from-p10k [F]  convert F (default ~/.p10k.zsh) into the config
_b4h_configure() {
  case ${1-} in
    '') p10k configure ;;
    --from-p10k)
      local f=${2:-$HOME/.p10k.zsh} tool
      [[ -r $f ]] || { echo "b4h configure: cannot read $f" >&2; return 1; }
      tool=${_b4h_tool:-$B4H_HOME/deps/bin/b4h-tool}
      [[ -x $tool ]] || { echo 'b4h configure: b4h-tool is missing (b4h doctor)' >&2; return 1; }
      mkdir -p -- "${_b4h_p_conf%/*}" || return 1
      local tmp=$_b4h_p_conf.new.$$
      "$tool" p10k-config "$f" "$tmp" || { rm -f -- "$tmp"; echo "b4h configure: could not convert $f" >&2; return 1; }
      if [[ -e $_b4h_p_conf ]]; then
        cp -p -- "$_b4h_p_conf" "$_b4h_p_conf.bak" && echo "b4h configure: the old config is in ${_b4h_p_conf/#"$HOME"/\~}.bak"
      fi
      mv -f -- "$tmp" "$_b4h_p_conf" || return 1
      # shellcheck disable=SC1090
      . "$_b4h_p_conf"
      _p9k__force_must_init=1   # the next prompt applies it (as p10k configure)
      echo "b4h configure: prompt taken from ${f/#"$HOME"/\~}"
      ;;
    *) echo 'usage: b4h configure [--from-p10k [FILE]]' >&2; return 2 ;;
  esac
}

# b4h prompt edit | reload
_b4h_prompt_cmd() {
  case ${1-} in
    edit)
      [[ -e $_b4h_p_conf ]] || { echo 'b4h prompt: no config yet; b4h configure makes one' >&2; return 1; }
      "${VISUAL:-${EDITOR:-nano}}" "$_b4h_p_conf" || return
      _b4h_prompt_cmd reload ;;
    reload)
      # shellcheck disable=SC1090
      [[ -r $_b4h_p_conf ]] && . "$_b4h_p_conf"
      p10k reload ;;
    *) echo 'usage: b4h prompt edit | reload' >&2; return 2 ;;
  esac
}

# On the first interactive start, before p10k's wizard (which the first
# prompt runs when there is no config): offer the look of an existing
# ~/.p10k.zsh instead.
_b4h_cfg_first_run() {
  [[ ! -e $_b4h_p_conf && -r $HOME/.p10k.zsh && $B4H_WIZARD == yes && -t 0 && -t 1 ]] || return 0
  [[ $B4H_HOME == *bash4humans-ssh* ]] && return 0
  local key
  printf '\n\e[1mbash4humans\e[0m: use the look of your Powerlevel10k prompt (~/.p10k.zsh)?\n'
  printf '  (y)  Yes, convert it      (n)  No, choose a look now (p10k configure)\n\nChoice: '
  read -rsn1 key || return 0; printf '\n'
  [[ $key == [yY] ]] && _b4h_configure --from-p10k
  return 0
}
