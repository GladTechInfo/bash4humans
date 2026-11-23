# =============================================================================
#  lib/settings.bash - default for every setting. Set any of these in
#  ~/.bashrc *before* bash4humans is loaded to change it.
# =============================================================================

# ---------------------------------------------------------------- general ---
: "${B4H_HOME:=$HOME/.cache/bash4humans}"   # where b4h and its components live
: "${B4H_LINE_EDITOR:=ble}"           # ble: suggestions, highlighting, menus | readline: plain bash editing
: "${B4H_GREETING:=}"                 # command run when a shell starts, e.g. fastfetch
: "${B4H_AUTO_UPDATE:=no}"            # ask: offer `b4h update` every B4H_AUTO_UPDATE_DAYS | no
: "${B4H_AUTO_UPDATE_DAYS:=28}"
: "${B4H_START_TMUX:=no}"             # yes: start (or attach to) tmux in every terminal
: "${B4H_DIRENV:=no}"                 # yes: load .envrc files with direnv
: "${B4H_GIT_BASE:=https://github.com}"  # where b4h install USER/REPO fetches from
: "${B4H_FIX_LOCALE:=yes}"            # yes: no UTF-8 locale in effect -> LC_ALL=C.UTF-8 (or another UTF-8 one) | no

# ------------------------------------------------------------ completion ---
: "${B4H_TAB:=menu}"                  # menu: ble.sh's menu with descriptions | fzf: fzf picker
: "${B4H_SUGGEST_ACCEPT:=all}"        # Right arrow takes the whole suggestion (all) or one word (word)
: "${B4H_CNF_SUGGEST:=yes}"           # unknown command: "did you mean" and which package has it

# ---------------------------------------------------------------- history ---
: "${B4H_HISTORY_SHARE:=yes}"         # commands typed in one shell appear in the others
: "${B4H_HISTORY_LOCAL:=yes}"         # yes: Up/Down search this shell's history, not what other shells add meanwhile (Ctrl+Up/Down: all; ble.sh only) | no
: "${B4H_DIR_HISTORY_SIZE:=10000}"    # directories kept for Alt+R / cdh / cd -<Tab>, across shells (0: none)

# -------------------------------------------------------------- clipboard ---
: "${B4H_CLIPBOARD_COMMANDS:=yes}"    # yes: the commands x (cut), c (copy) and v (paste), unless taken

# ----------------------------------------------------------------- prompt ---
# The prompt is Powerlevel10k's, ported to bash. Its look lives in
# ~/.config/bash4humans/p10k.bash (POWERLEVEL9K_* settings, as in ~/.p10k.zsh),
# written by `b4h configure` (p10k's wizard, which the first start runs) or
# converted from ~/.p10k.zsh (`b4h configure --from-p10k`); `b4h prompt edit`.
: "${B4H_TITLE:=yes}"                 # yes: set the window title (formats below) | no
# The title's formats, in bash prompt escapes (\u user, \h host, \w directory)
# and $B4H_COMMAND (the command line that runs). Single quotes in ~/.bashrc.
# Defaults as zsh4humans: user@host only over SSH. Empty: leave the title.
if [[ -n ${SSH_CONNECTION-} ]]; then
  [[ -v B4H_TITLE_IDLE ]]    || B4H_TITLE_IDLE='\u@\h: \w'               # at the prompt
  [[ -v B4H_TITLE_RUNNING ]] || B4H_TITLE_RUNNING='\u@\h: $B4H_COMMAND'  # while a command runs
else
  [[ -v B4H_TITLE_IDLE ]]    || B4H_TITLE_IDLE='\w'
  [[ -v B4H_TITLE_RUNNING ]] || B4H_TITLE_RUNNING='$B4H_COMMAND'
fi
: "${B4H_NOTIFY_MIN:=0}"              # >0: bell + desktop notification after commands this many seconds long

# ---------------------------------------------------- terminal integration ---
# OSC 7 (current directory) and OSC 133 (prompt marks) let a terminal open
# new tabs in the same directory and jump between prompts.
: "${B4H_SHELL_INTEGRATION:=yes}"
: "${B4H_SHELL_INTEGRATION_EXCEPT:=}" # SSH client addresses that get none (terminals that print them as text)

# --------------------------------------------------------------------- ssh ---
# `b4h ssh HOST` copies bash4humans and these files to HOST for that session.
[[ -v B4H_SSH_SEND_FILES ]] || B4H_SSH_SEND_FILES=()
# Hosts where a plain `ssh HOST` does the same (patterns: build-server '*.lab');
# empty: ssh is never changed. Only interactive logins (no remote command).
[[ -v B4H_SSH_HOSTS ]] || B4H_SSH_HOSTS=()
: "${B4H_SSH_RETRIEVE_HISTORY:=}"     # a file: after each b4h ssh session, its new history lines are appended to it
: "${B4H_RCFILE:=$HOME/.bashrc}"      # the rc file `b4h ssh` sends (the one that loads bash4humans)
: "${B4H_WIZARD:=yes}"                # no: never offer `b4h configure` on the first start
: "${B4H_KEYMAP:=emacs}"              # emacs (standard keys) | vi
