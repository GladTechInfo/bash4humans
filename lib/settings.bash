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

# ------------------------------------------------------------ completion ---
: "${B4H_TAB:=menu}"                  # menu: ble.sh's menu with descriptions | fzf: fzf picker
: "${B4H_SUGGEST_ACCEPT:=all}"        # Right arrow takes the whole suggestion (all) or one word (word)
: "${B4H_CNF_SUGGEST:=yes}"           # unknown command: "did you mean" and which package has it

# ---------------------------------------------------------------- history ---
: "${B4H_HISTORY_SHARE:=yes}"         # commands typed in one shell appear in the others

# ----------------------------------------------------------------- prompt ---
# The prompt is Powerlevel10k's, ported to bash. Its look lives in
# ~/.config/bash4humans/p10k.bash (POWERLEVEL9K_* settings, as in ~/.p10k.zsh),
# written by `b4h configure` (p10k's wizard, which the first start runs) or
# converted from ~/.p10k.zsh (`b4h configure --from-p10k`); `b4h prompt edit`.
: "${B4H_TITLE:=yes}"                 # yes: the window title shows user@host: directory
: "${B4H_NOTIFY_MIN:=0}"              # >0: bell + desktop notification after commands this many seconds long

# ---------------------------------------------------- terminal integration ---
# OSC 7 (current directory) and OSC 133 (prompt marks) let a terminal open
# new tabs in the same directory and jump between prompts.
: "${B4H_SHELL_INTEGRATION:=yes}"
: "${B4H_SHELL_INTEGRATION_EXCEPT:=}" # SSH client addresses that get none (terminals that print them as text)

# --------------------------------------------------------------------- ssh ---
# `b4h ssh HOST` copies bash4humans and these files to HOST for that session.
[[ -v B4H_SSH_SEND_FILES ]] || B4H_SSH_SEND_FILES=()
: "${B4H_RCFILE:=$HOME/.bashrc}"      # the rc file `b4h ssh` sends (the one that loads bash4humans)
: "${B4H_WIZARD:=yes}"                # no: never offer `b4h configure` on the first start
: "${B4H_KEYMAP:=emacs}"              # emacs (standard keys) | vi
