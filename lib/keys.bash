# =============================================================================
#  lib/keys.bash - key bindings (z4h's set, plus fish's Alt+S and Alt+H).
#
#    Right / Ctrl+F         accept the grey suggestion (ble.sh)
#    Alt+M                  accept the whole suggestion (ble.sh)
#    Up / Down              history entries containing what is typed: this shell's
#                           (ble.sh: not what other shells add meanwhile)
#    Ctrl+Up / Ctrl+Down    history entries starting with what is typed: all shells'
#    Ctrl+R                 fuzzy history (fzf)       Ctrl+T  files    Alt+C  cd
#    Ctrl+Backspace, Ctrl+H delete a word             Ctrl+Alt+Backspace  a shell word
#    Ctrl+Left / Right      word left / right         Ctrl+Delete  delete word right
#    Ctrl+Shift+Left/Right  shell word left / right   Ctrl+Shift+Delete  delete shell word right
#    Ctrl+/ , Shift+Tab     undo                      Alt+/   redo (ble.sh)
#    Alt+J                  clear the command line    Alt+O   stash it (back with Up)
#    Ctrl+Space             expand the word: alias, ~, $VAR, glob
#    Alt+Left / Right       previous / next directory
#    Alt+Up / Down          parent directory / pick a subdirectory
#    Alt+R                  pick a directory from the history of all shells
#    Alt+S                  toggle sudo               Alt+H   manual page
#
#  (A "shell word" is a whole argument: /usr/local/bin is one, three words.)
# =============================================================================

# Directory keys: change directory, then redraw the prompt in place.
_b4h_key_back()    { _b4h_cd_back    && _b4h_prompt_refresh; return 0; }
_b4h_key_forward() { _b4h_cd_forward && _b4h_prompt_refresh; return 0; }
_b4h_key_up()      { _b4h_cd_up      && _b4h_prompt_refresh; return 0; }
_b4h_key_down()    { _b4h_cd_down    && _b4h_prompt_refresh; return 0; }
_b4h_key_dirhist() { _b4h_cd_history && _b4h_prompt_refresh; return 0; }

# Alt+O (zsh4humans' z4h-stash-buffer): the line goes into the history
# without running, and the line is cleared. Up brings it back.
_b4h_key_stash() {
  [[ -n $READLINE_LINE ]] || return 0
  history -s -- "$READLINE_LINE"
  READLINE_LINE= READLINE_POINT=0
}

# ---------------------------------------------------------- Ctrl+Space ---
# Expand the word at the cursor in place, as zsh4humans' z4h-expand
# (_expand_alias, then expand-word): an alias where a command goes, else
# ~ / ~user, $NAME / ${NAME}, then a glob (the matches, quoted). Unlike zsh,
# $(...) and the other expansions are left as they are: expanding them
# would run commands. Works on READLINE_LINE / READLINE_POINT, which both
# readline (bind -x) and ble.sh (ble-bind -x) provide.
_b4h_key_expand() {
  local line=$READLINE_LINE pt=$READLINE_POINT
  local left=${line:0:pt} right=${line:pt}
  # the word: the non-blank text around the cursor
  local wl=${left##*[[:space:]]} wr=${right%%[[:space:]]*}
  local word=$wl$wr start=$(( pt - ${#wl} ))
  local end=$(( start + ${#word} ))
  [[ -n $word ]] || return 0
  local before=${line:0:start} out=
  # what comes before the word, without the blanks
  local pre=${before%"${before##*[![:space:]]}"}
  if [[ $word =~ ^[A-Za-z0-9_.:+@%-]+$ && ( -z $pre || $pre == *[\;\|\&\(] ) &&
        -n ${BASH_ALIASES[$word]+set} ]]; then
    out=${BASH_ALIASES[$word]}
  elif [[ $word != *[\'\"\\\`]* ]] && _b4h_expand_word "$word"; then
    out=$REPLY
  fi
  [[ -n $out && $out != "$word" ]] || return 0
  READLINE_LINE=$before$out${line:end}
  READLINE_POINT=$(( start + ${#out} ))
}

# One word: ~, $NAME, ${NAME}, then a glob. The result (quoted for the
# shell) goes into REPLY; status 1 when there is nothing to do safely.
_b4h_expand_word() {
  local w=$1 r= name t rest
  REPLY=
  # ~ ~+ ~- ~user at the start
  if [[ $w == '~'* ]]; then
    t=${w%%/*} rest=${w:${#t}}
    case $t in
      '~')  t=$HOME ;;
      '~+') t=$PWD ;;
      '~-') t=${OLDPWD-} ;;
      *)
        # a user name only (checked first), so eval runs no other code
        [[ ${t:1} =~ ^[A-Za-z_][A-Za-z0-9_.-]*$ ]] || return 1
        eval "t=$t"
        [[ $t != '~'* ]] || return 1        # no such user
        ;;
    esac
    [[ -n $t ]] || return 1
    w=$t$rest
  fi
  # $NAME and ${NAME}; anything else after a $ is left alone. A value is
  # never globbed: a variable holding * stays *, as zsh does.
  local value_glob=0
  while [[ $w == *'$'* ]]; do
    r+=${w%%'$'*}
    w=${w#*'$'}
    if [[ $w =~ ^\{([A-Za-z_][A-Za-z0-9_]*)\}(.*)$ || $w =~ ^([A-Za-z_][A-Za-z0-9_]*)(.*)$ ]]; then
      name=${BASH_REMATCH[1]} w=${BASH_REMATCH[2]}
      t=${!name-}
      [[ $t == *[\*\?\[]* ]] && value_glob=1
      r+=$t
    else
      return 1
    fi
  done
  r+=$w
  # a glob: the matching names, each quoted, in the shell's order
  if (( ! value_glob )) && [[ $r == *[\*\?\[]* ]]; then
    local -a m=()
    local ng=0 IFS=
    [[ :$BASHOPTS: == *:nullglob:* ]] && ng=1
    shopt -s nullglob
    # unquoted on purpose: globbed, but with IFS empty never split; the
    # text was expanded above, so nothing in it runs
    # shellcheck disable=SC2206
    m=( $r )
    (( ng )) || shopt -u nullglob
    (( ${#m[@]} )) || return 1
    local q
    for t in "${m[@]}"; do printf -v q '%q' "$t"; REPLY+=${REPLY:+ }$q; done
    return 0
  fi
  [[ $r != "$1" ]] || return 1
  printf -v REPLY '%q' "$r"
}

if (( _b4h_ble )); then
  # ble.sh: widgets run inside the editor, so the prompt can be redrawn
  # cleanly. Bindings go in once the emacs keymap has loaded.
  function ble/widget/b4h-back    { _b4h_key_back; }
  function ble/widget/b4h-forward { _b4h_key_forward; }
  function ble/widget/b4h-up      { _b4h_key_up; }
  # Alt+J: the whole command line goes (into the kill ring, Ctrl+Y brings it)
  function ble/widget/b4h-kill-buffer {
    ble/widget/end-of-text
    ble/widget/kill-backward-text
  }
  # ---- local and global history (zsh4humans: zle set-local-history) ----
  # Up/Down search the history this shell started with and the commands
  # run in it; what other shells add meanwhile (B4H_HISTORY_SHARE) is left
  # out. Ctrl+Up/Down search all of it. ble.sh brings other shells' lines in
  # with its own `history -n` (ble/builtin/history/option:n): the positions
  # each import adds are remembered, and a local search steps over them.
  _b4h_hist_foreign=()      # position in ble.sh's history -> 1: came from another shell
  _b4h_hist_local=0         # 1 while a search started by Up/Down runs
  _b4h_hist_import() {      # around option:n
    # (ble.sh loads the history on first use; that first load is this
    # shell's own start-up history, so nothing is marked then)
    local loaded=${_ble_history_count-} before after i
    [[ -n $loaded ]] && ble/history/get-count -v before
    ble/function#advice/do
    [[ -n $loaded ]] || return 0
    ble/history/get-count -v after
    if (( after < before )); then
      _b4h_hist_foreign=()  # the history was read again from the start: positions changed
    else
      for (( i = before; i < after; i++ )); do _b4h_hist_foreign[i]=1; done
    fi
  }
  # Around ble.sh's history searches: `index` (the caller's variable) holds
  # the match. In a local search a match from another shell is passed over
  # and the search goes on from the next entry in the same direction.
  _b4h_hist_skip_backward() {
    while :; do
      ble/function#advice/do
      (( ADVICE_EXIT == 0 && _b4h_hist_local && ${_b4h_hist_foreign[index]-0} )) || return 0
      (( --index >= 0 )) || { ADVICE_EXIT=1; return 0; }
    done
  }
  _b4h_hist_skip_forward() {
    local count
    while :; do
      ble/function#advice/do
      (( ADVICE_EXIT == 0 && _b4h_hist_local && ${_b4h_hist_foreign[index]-0} )) || return 0
      ble/history/get-count -v count
      (( ++index < count )) || { ADVICE_EXIT=1; return 0; }
    done
  }
  ble/function#advice around ble/builtin/history/option:n _b4h_hist_import
  ble/function#advice around ble/history/isearch-backward-blockwise _b4h_hist_skip_backward
  ble/function#advice around ble/history/isearch-forward _b4h_hist_skip_forward
  # The widgets: they say which kind of search runs, then start ble.sh's.
  _b4h_hist_set_local() { _b4h_hist_local=0; [[ $B4H_HISTORY_LOCAL == yes ]] && _b4h_hist_local=1; }
  function ble/widget/b4h-up-local     { _b4h_hist_set_local; ble/widget/history-substring-search-backward; }
  function ble/widget/b4h-down-local   { _b4h_hist_set_local; ble/widget/history-substring-search-forward; }
  function ble/widget/b4h-up-global    { _b4h_hist_local=0; ble/widget/history-search-backward; }
  function ble/widget/b4h-down-global  { _b4h_hist_local=0; ble/widget/history-search-forward; }

  # Alt+O: into ble.sh's own history list (ble.sh keeps it, not bash)
  _b4h_key_stash_ble() {
    [[ -n $READLINE_LINE ]] || return 0
    ble/history/add "$READLINE_LINE"
    READLINE_LINE= READLINE_POINT=0
  }

  _b4h_ble_keys() {
    ble-bind -f C-h      kill-backward-cword
    ble-bind -f C-BS     kill-backward-cword
    ble-bind -f C-M-h    kill-backward-sword
    ble-bind -f C-M-BS   kill-backward-sword
    ble-bind -f M-BS     kill-backward-sword
    ble-bind -f C-_      emacs/undo
    ble-bind -f C-/      emacs/undo
    ble-bind -f S-TAB    emacs/undo
    ble-bind -f M-/      emacs/redo
    ble-bind -f C-left   backward-cword
    ble-bind -f C-right  forward-cword
    ble-bind -f C-delete kill-forward-cword
    ble-bind -f C-S-left   backward-sword
    ble-bind -f C-S-right  forward-sword
    ble-bind -f C-S-delete kill-forward-sword
    ble-bind -f up       b4h-up-local
    ble-bind -f down     b4h-down-local
    ble-bind -f C-up     b4h-up-global
    ble-bind -f C-down   b4h-down-global
    ble-bind -f M-j      b4h-kill-buffer
    ble-bind -x M-o      _b4h_key_stash_ble
    ble-bind -x C-@      _b4h_key_expand
    ble-bind -x C-SP     _b4h_key_expand
    ble-bind -f M-left   b4h-back
    ble-bind -f M-right  b4h-forward
    ble-bind -f M-up     b4h-up
    ble-bind -x M-down   _b4h_key_down
    ble-bind -x M-r      _b4h_key_dirhist
    ble-bind -x M-s      _b4h_key_sudo
    ble-bind -x M-h      _b4h_key_help
    # Enter on a line found with Up/Down runs it, as in zsh (ble.sh's
    # default only ends the search; Ctrl+J ran it)
    ble-bind -m nsearch -f C-m nsearch/accept-line
    ble-bind -m nsearch -f RET nsearch/accept-line
  }
  blehook/eval-after-load keymap_emacs _b4h_ble_keys

  # Keys while a suggestion is shown: Alt+M takes all of it (z4h); Right
  # takes all of it or one word (B4H_SUGGEST_ACCEPT).
  _b4h_ble_suggest_keys() {
    ble-bind -m auto_complete -f M-m auto_complete/insert
    [[ $B4H_SUGGEST_ACCEPT == word ]] && ble-bind -m auto_complete -f right auto_complete/insert-word
  }
  blehook/eval-after-load complete _b4h_ble_suggest_keys
else
  # readline
  bind '"\C-h": backward-kill-word'
  bind '"\e\C-h": shell-backward-kill-word'
  bind '"\e\C-?": shell-backward-kill-word'
  bind '"\C-_": undo'
  bind '"\e[Z": undo'
  bind '"\e[1;5D": backward-word'
  bind '"\e[1;5C": forward-word'
  bind '"\e[3;5~": kill-word'
  bind '"\e[1;6D": shell-backward-word'
  bind '"\e[1;6C": shell-forward-word'
  bind '"\e[3;6~": shell-kill-word'
  bind '"\e[A": history-substring-search-backward'
  bind '"\eOA": history-substring-search-backward'
  bind '"\e[B": history-substring-search-forward'
  bind '"\eOB": history-substring-search-forward'
  bind '"\e[1;5A": history-search-backward'
  bind '"\e[1;5B": history-search-forward'
  bind '"\ej": kill-whole-line'
  # (only lower-case: Alt+Shift+O is ESC O, the start of arrow keys in
  # some terminal modes)
  bind -x '"\eo": _b4h_key_stash'
  bind -x '"\C-@": _b4h_key_expand'
  bind -x '"\e[1;3D": _b4h_key_back'
  bind -x '"\e[1;3C": _b4h_key_forward'
  bind -x '"\e[1;3A": _b4h_key_up'
  bind -x '"\e[1;3B": _b4h_key_down'
  bind -x '"\er": _b4h_key_dirhist'
  bind -x '"\es": _b4h_key_sudo'
  bind -x '"\eh": _b4h_key_help'
  bind '"\e[0n": redraw-current-line'   # after fzf in a completion (cd -<Tab>)
fi
