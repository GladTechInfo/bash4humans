# =============================================================================
#  lib/options.bash - environment, shell options and history.
#
#  zsh option            bash equivalent used here
#  auto_cd               autocd             type a directory name to enter it
#  glob_dots             dotglob            * matches names starting with .
#  extended_glob, **     extglob globstar
#  interactive_comments  interactive_comments
#  hist_verify           histverify         !! is expanded for editing, not run
#  no_flow_control       stty -ixon         Ctrl+S and Ctrl+Q stay free
#  share_history         history -a/-n each prompt (ble.sh: history_share)
# =============================================================================

umask o-w

[[ ":$PATH:" == *":$HOME/bin:"* || ! -d $HOME/bin ]] || PATH=$HOME/bin:$PATH
[[ ":$PATH:" == *":$HOME/.local/bin:"* || ! -d $HOME/.local/bin ]] || PATH=$HOME/.local/bin:$PATH
# (during the instant prompt stdin is /dev/null: the terminal it saved)
if (( ${_p9k__ip_active:-0} )); then GPG_TTY=$(tty <&"$_p9k__ip_fd0"); else GPG_TTY=$(tty); fi
export GPG_TTY
: "${PAGER:=less}"
: "${LESS:=-iRFXMx4}"
export PAGER LESS
if [[ -z ${LS_COLORS-} ]] && command -v dircolors >/dev/null; then
  eval "$(dircolors -b)"
fi

shopt -s autocd dotglob extglob globstar interactive_comments histverify \
         histappend cmdhist checkwinsize no_empty_cmd_completion
stty -ixon 2>/dev/null

# --------------------------------------------------------------- history ---
HISTFILE=${HISTFILE:-$HOME/.bash_history}
HISTSIZE=-1                     # unlimited
HISTFILESIZE=-1
HISTCONTROL=ignoreboth          # skip repeats and lines starting with a space
HISTTIMEFORMAT='%F %T  '        # when each command ran (`history` shows it)

# Private mode (`b4h private`): nothing is written to the history file.
if [[ -n ${B4H_PRIVATE-} ]]; then
  HISTFILE=/dev/null             # read nothing, keep nothing (ble.sh would fall back to ~/.bash_history if unset)
  B4H_HISTORY_SHARE=no
fi

if (( _b4h_ble )); then
  bleopt history_share="$([[ $B4H_HISTORY_SHARE == yes ]] && echo 1)"
fi

# --------------------------------------------------------------- direnv ---
if [[ $B4H_DIRENV == yes ]] && command -v direnv >/dev/null; then
  eval "$(direnv hook bash)"
fi

# ---------------------------------------------------------------- keymap ---
[[ $B4H_KEYMAP == vi ]] && set -o vi
