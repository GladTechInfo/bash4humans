#!/usr/bin/env bash
# =============================================================================
#  install.sh - install bash4humans for the current user, in the style of
#  zsh4humans: a few questions, then a new shell whose first prompt runs
#  Powerlevel10k's configuration wizard (or converts your ~/.p10k.zsh).
#
#    bash -c "$(curl -fsSL https://raw.githubusercontent.com/GladTechInfo/bash4humans/main/install.sh)"
#
#  Changes only your home directory:
#    ~/.cache/bash4humans/   bash4humans and its components
#    ~/.bashrc               replaced (old copy in ~/bash-backup/<date>/) or extended
#    ~/.bash_profile         created only if login shells would not read ~/.bashrc
#  Undo: copy the files back from ~/bash-backup/<date>/ and remove ~/.cache/bash4humans.
#
#  Environment: B4H_SOURCE=DIR installs from a local copy instead of cloning;
#               B4H_REPO=URL clones from elsewhere.
# =============================================================================
set -uo pipefail

B4H_HOME=${B4H_HOME:-$HOME/.cache/bash4humans}
REPO=${B4H_REPO:-https://github.com/GladTechInfo/bash4humans.git}

say()   { printf '\e[33mbash4humans\e[0m: %s\n' "$*" >&2; }
die()   { say "$*"; exit 1; }
bold()  { printf '\e[1m%s\e[0m' "$*"; }

# One key, from the terminal even when this script arrived through a pipe.
ask() {   # ask "1 2 q" -> $choice
  local valid=" $1 " key
  while true; do
    printf '\e[1mChoice [%s]:\e[0m ' "${1// /}" >&2
    IFS= read -rsn1 key </dev/tty || exit 1
    printf '%s\n' "$key" >&2
    [[ $key == [qQ] ]] && { say 'nothing changed'; exit 1; }
    [[ $valid == *" $key "* ]] && { choice=$key; return; }
    say "invalid choice: $key"
  done
}

# ------------------------------------------------------------------ checks ---
(( BASH_VERSINFO[0] >= 5 )) || die "needs bash 5 or later (this is $BASH_VERSION)"
[[ -r /dev/tty ]] || die 'needs a terminal for its questions'
for tool in tar mktemp sha256sum; do command -v $tool >/dev/null || die "needs $tool"; done
command -v curl >/dev/null || command -v wget >/dev/null || die 'needs curl or wget'
[[ -n ${B4H_SOURCE-} ]] || command -v git >/dev/null || die 'needs git'

printf '\n'; bold 'bash4humans'; printf ' - a friendlier bash: suggestions, highlighting, fuzzy search,\nPowerlevel10k (ported to bash). Only interactive shells change; scripts see plain bash.\n\n'

# --------------------------------------------------------------- questions ---
printf 'What \e[1mkeybindings\e[0m do you prefer?\n\n'
printf '  (1)  Standard. I delete characters with \e[33mBackspace\e[0m.\n'
printf '  (2)  Like in \e[32mvi\e[0m. I delete characters with \e[33mX\e[0m in command mode.\n'
printf '  (q)  Quit and do nothing.\n\n'
ask '1 2'; keymap=emacs; [[ $choice == 2 ]] && keymap=vi

printf '\nHow much should the \e[1mline editor\e[0m do?\n\n'
printf '  (1)  Everything: grey suggestions, syntax highlighting, menus (ble.sh). \e[1mRecommended\e[0m.\n'
printf '  (2)  Plain bash editing; starts faster (about 0.06 s instead of 0.3 s).\n'
printf '  (q)  Quit and do nothing.\n\n'
ask '1 2'; editor=ble; [[ $choice == 2 ]] && editor=readline

printf '\nDo you want \e[32mbash\e[0m to always run in \e[32mtmux\e[0m?\n\n'
printf '  (y)  Yes.\n  (n)  No.\n  (q)  Quit and do nothing.\n\n'
ask 'y n Y N'; tmux=no; [[ $choice == [yY] ]] && tmux=yes

direnv=no
if command -v direnv >/dev/null; then
  printf '\nDo you use \e[32mdirenv\e[0m?\n\n  (y)  Yes.\n  (n)  No.\n  (q)  Quit and do nothing.\n\n'
  ask 'y n Y N'; [[ $choice == [yY] ]] && direnv=yes
fi

rcs=()
for f in .bashrc .bash_profile .bash_login .profile; do [[ -e $HOME/$f ]] && rcs+=("$f"); done
backup=bash-backup/$(date +%Y%m%d-%H%M%S)
mode=replace
if [[ -e $HOME/.bashrc ]] && grep -q 'bash4humans' "$HOME/.bashrc"; then
  mode=keep-b4h
  printf '\nYour ~/.bashrc already loads bash4humans; it stays as it is.\n'
elif [[ -e $HOME/.bashrc ]]; then
  printf '\nYou have these bash \e[1mstartup files\e[0m:\n\n'
  for f in "${rcs[@]}"; do printf '    \e[4m~/%s\e[0m\n' "$f"; done
  printf '\nWhat should happen to \e[4m~/.bashrc\e[0m?\n\n'
  printf '  (1)  Replace it; keep a copy in \e[4m~/%s\e[0m and its lines, commented out,\n' "$backup"
  printf '       at the end of the new one. \e[1mRecommended\e[0m.\n'
  printf '  (2)  Keep it and add bash4humans at its end.\n'
  printf '  (q)  Quit and do nothing.\n\n'
  ask '1 2'; [[ $choice == 2 ]] && mode=append
fi

chsh_to=''
bash_path=$(command -v bash)
if [[ ${SHELL##*/} != bash ]]; then
  printf '\nYour login shell is \e[33m%s\e[0m. Make \e[32mbash\e[0m your login shell?\n\n' "$SHELL"
  printf '  (y)  Yes (runs: chsh -s %s, which asks for your password).\n  (n)  No.\n  (q)  Quit and do nothing.\n\n' "$bash_path"
  ask 'y n Y N'; [[ $choice == [yY] ]] && chsh_to=$bash_path
fi

# ----------------------------------------------------------------- install ---
printf '\n'
mkdir -p -- "$B4H_HOME"
if [[ -n ${B4H_SOURCE-} ]]; then
  say "copying from $B4H_SOURCE"
  rm -rf -- "$B4H_HOME/b4h" && cp -r -- "$B4H_SOURCE" "$B4H_HOME/b4h" || die 'copy failed'
elif [[ -d $B4H_HOME/b4h/.git ]]; then
  say 'updating bash4humans'
  git -C "$B4H_HOME/b4h" pull -q --ff-only || say 'update failed; keeping the present copy'
elif [[ -L $B4H_HOME/b4h ]]; then
  say "using the development copy at $(readlink "$B4H_HOME/b4h")"
else
  say 'downloading bash4humans'
  git clone -q --depth 1 "$REPO" "$B4H_HOME/b4h" || die 'git clone failed'
fi

# Back up every startup file that exists, whatever happens next.
if (( ${#rcs[@]} )) && [[ $mode != keep-b4h ]]; then
  mkdir -p -- "$HOME/$backup"
  for f in "${rcs[@]}"; do cp -p -- "$HOME/$f" "$HOME/$backup/"; done
  say "copies of ${rcs[*]} are in ~/$backup"
fi

settings() {   # the template with the answers filled in
  sed -e "s/^B4H_KEYMAP=[a-z]*/B4H_KEYMAP=$keymap/" -e "s/^B4H_LINE_EDITOR=[a-z]*/B4H_LINE_EDITOR=$editor/" \
      -e "s/^B4H_START_TMUX=[a-z]*/B4H_START_TMUX=$tmux/" -e "s/^B4H_DIRENV=[a-z]*/B4H_DIRENV=$direnv/" \
      "$B4H_HOME/b4h/bashrc.template"
}
case $mode in
  replace)
    { settings
      if [[ -e $HOME/$backup/.bashrc ]]; then
        printf '\n# ---- your previous ~/.bashrc (copy in ~/%s), commented out: copy back what you need ----\n' "$backup"
        sed 's/^/# /' -- "$HOME/$backup/.bashrc"
      fi
    } >"$HOME/.bashrc.b4h-new" && mv -- "$HOME/.bashrc.b4h-new" "$HOME/.bashrc"
    say 'wrote ~/.bashrc' ;;
  append)
    { printf '\n# ---- bash4humans (added by its installer on %s) ----\n' "$(date +%F)"
      settings | sed -n '/^# -* settings ---/,$p'
    } >>"$HOME/.bashrc"
    say 'added bash4humans to the end of ~/.bashrc' ;;
esac

# Login shells (ssh, consoles) read ~/.bash_profile, ~/.bash_login or ~/.profile
# - only the first that exists - and not ~/.bashrc. Make sure it gets read.
login=''
for f in .bash_profile .bash_login .profile; do [[ -e $HOME/$f ]] && { login=$f; break; }; done
if [[ -z $login ]]; then
  printf '# ~/.bash_profile - login shells: read ~/.bashrc as well (written by bash4humans)\n[[ -r ~/.bashrc ]] && . ~/.bashrc\n' >"$HOME/.bash_profile"
  say 'wrote ~/.bash_profile so login shells load ~/.bashrc'
elif ! grep -q 'bashrc' "$HOME/$login"; then
  printf '\n# Added by bash4humans: login shells read ~/.bashrc too.\n[[ -r ~/.bashrc ]] && . ~/.bashrc\n' >>"$HOME/$login"
  say "added a line to ~/$login so login shells load ~/.bashrc"
fi

# Components now, rather than on the first start.
B4H_ROOT=$B4H_HOME/b4h B4H_LINE_EDITOR=$editor
. "$B4H_ROOT/lib/settings.bash"
. "$B4H_ROOT/lib/deps.bash"
_b4h_deps_ensure

if [[ -n $chsh_to ]]; then
  chsh -s "$chsh_to" </dev/tty || say "chsh failed; run it yourself later: chsh -s $chsh_to"
fi

say 'done - starting bash'
exec bash -i </dev/tty
