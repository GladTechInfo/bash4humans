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
#    Alt+J                  clear the command line    Alt+O   stash a draft for Up/Down
#    Ctrl+L / Ctrl+Alt+L    clear the screen: soft (into the scrollback) / hard (scrollback too)
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

# Ctrl+L / Ctrl+Alt+L, as zsh4humans: soft clear (what is on the screen moves
# into the scrollback) / hard clear (the scrollback is erased too). The
# prompt then starts on the top row, or with B4H_PROMPT_AT_BOTTOM=yes on the
# rows at the bottom.
_b4h_clear_seq() {      # soft|hard -> REPLY: what to print; the cursor ends
  local rows=${LINES:-24} s nl  # where the prompt's first line goes
  if [[ $1 == hard ]]; then
    s=$'\e[H\e[2J\e[3J'
  else
    # from the last row, one newline per row scrolls everything away
    printf -v nl '%*s' "$rows" ''
    printf -v s '\e[%dH%s' "$rows" "${nl// /$'\n'}"
  fi
  if [[ $B4H_PROMPT_AT_BOTTOM == yes ]]; then
    local lines=${_p9k_ps1//[!$'\n']/}       # the prompt's height: its line breaks + 1
    local top=$(( rows - ${#lines} ))
    (( top >= 1 )) || top=1
    s+=$'\e['"$top"'H'
  else
    s+=$'\e[H'
  fi
  REPLY=$s
}
# readline: print it, then the prompt's upper lines (readline itself redraws
# only the last one, on the row the cursor is on)
_b4h_key_clear() {
  _b4h_clear_seq "$1"
  printf '%s' "$REPLY"
  local ps=${_p9k_ps1//[$'\001\002']/} i
  local -a l=()
  mapfile -t l <<<"$ps"
  for (( i = 0; i < ${#l[@]} - 1; i++ )); do printf '\e[2K%s\n' "${l[i]}"; done
}

# Alt+O drafts stay outside the history list so history writes and imports
# never see them. An anchor records the next history position at stash time.
_b4h_drafts=()
_b4h_draft_anchors=()
_b4h_draft_browsing=0

_b4h_draft_history_end() {
  if (( _b4h_ble )); then
    ble/history/initialize
    ble/history/get-count -v REPLY || :
  else
    local last
    last=$(HISTTIMEFORMAT= builtin history 1)
    REPLY=1
    [[ $last =~ ^[[:blank:]]*([0-9]+) ]] && REPLY=$(( BASH_REMATCH[1] + 1 ))
  fi
  return 0
}

_b4h_key_stash() {
  [[ -n $READLINE_LINE ]] || return 0
  local REPLY
  _b4h_draft_history_end
  _b4h_drafts+=("$READLINE_LINE")
  _b4h_draft_anchors+=("$REPLY")
  _b4h_draft_browsing=0
  READLINE_LINE= READLINE_POINT=0
}

_b4h_draft_start_browsing() {
  local first=0 next oldest anchor i
  _b4h_draft_history_end; next=$REPLY
  if (( ! _b4h_ble )); then
    IFS= read -r oldest < <(HISTTIMEFORMAT= builtin history) || :
    first=$next
    [[ $oldest =~ ^[[:blank:]]*([0-9]+) ]] && first=${BASH_REMATCH[1]}
  fi
  _b4h_draft_first=$first
  _b4h_draft_end=$(( next + ${#_b4h_drafts[@]} ))
  _b4h_draft_position=$_b4h_draft_end
  _b4h_draft_original=$READLINE_LINE
  _b4h_draft_original_point=$READLINE_POINT
  _b4h_draft_query=${READLINE_LINE:0:READLINE_POINT}
  _b4h_draft_slots=()
  # Each older draft shifts subsequent positions by one. Clamp anchors
  # to the current list if history was cleared or truncated.
  for (( i = 0; i < ${#_b4h_drafts[@]}; i++ )); do
    anchor=${_b4h_draft_anchors[i]}
    (( anchor >= first )) || anchor=$first
    (( anchor <= next )) || anchor=$next
    _b4h_draft_slots+=("$(( anchor + i ))")
    first=$anchor
  done
  _b4h_draft_browsing=1
}

_b4h_draft_history_entry() {
  local event=$1
  if (( _b4h_ble )); then
    if [[ $B4H_HISTORY_LOCAL == yes ]] && (( ${_b4h_hist_foreign[event]-0} )); then
      return 1
    fi
    ble/history/get-entry -v REPLY "$event"
  else
    # Fetch a block in one subprocess so a search over many entries does not
    # fork for each command. NUL separates entries, including multiline ones.
    if (( event < block_start || event >= block_start + ${#history_block[@]} )); then
      block_start=$(( event / 64 * 64 ))
      (( block_start >= _b4h_draft_first )) || block_start=$_b4h_draft_first
      mapfile -d '' -t history_block < <(
        histchars='!^#'
        # Prevent history -p from removing recent entries from this copy.
        # The placeholder is beyond the original end used by the loop.
        set +o history
        HISTFILE= HISTSIZE=-1 HISTCONTROL= HISTIGNORE=
        builtin history -s -- ':' || exit 1
        local n end=$(( _b4h_draft_end - ${#_b4h_drafts[@]} ))
        for (( n = block_start; n < block_start + 64 && n < end; n++ )); do
          builtin history -p "!$n" 2>/dev/null || :
          printf '\0'
        done
      )
    fi
    REPLY=${history_block[event-block_start]-}
    [[ $REPLY == *$'\n' ]] || return 1
    REPLY=${REPLY%$'\n'}
  fi
}

_b4h_draft_recall() {
  local direction=$1 slot i REPLY block_start=0
  local -a history_block=()
  if (( ! _b4h_draft_browsing )) ||
      [[ $READLINE_LINE != "$_b4h_draft_shown" || $READLINE_POINT != "$_b4h_draft_shown_point" ]]; then
    _b4h_draft_start_browsing
  fi
  for (( slot = _b4h_draft_position + direction;
         slot >= _b4h_draft_first && slot < _b4h_draft_end; slot += direction )); do
    for (( i = 0; i < ${#_b4h_draft_slots[@]} && _b4h_draft_slots[i] < slot; i++ )); do :; done
    if [[ ${_b4h_draft_slots[i]-} == "$slot" ]]; then
      REPLY=${_b4h_drafts[i]}
    else
      _b4h_draft_history_entry "$(( slot - i ))" || continue
    fi
    [[ $REPLY == *"$_b4h_draft_query"* ]] || continue
    _b4h_draft_position=$slot
    READLINE_LINE=$REPLY READLINE_POINT=${#REPLY}
    break
  done
  if (( direction > 0 && slot >= _b4h_draft_end )); then
    _b4h_draft_position=$_b4h_draft_end
    READLINE_LINE=$_b4h_draft_original READLINE_POINT=$_b4h_draft_original_point
  fi
  _b4h_draft_shown=$READLINE_LINE _b4h_draft_shown_point=$READLINE_POINT
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

  # Ctrl+L / Ctrl+Alt+L under ble.sh: as ble.sh's own clear-screen, with
  # the soft or hard sequence and the prompt's row from _b4h_clear_seq
  _b4h_ble_clear() {
    ble-edit/content/clear-arg
    ble/edit/enter-command-layout
    ble/textarea#invalidate
    local -a DRAW_BUFF=()
    ble/canvas/panel/goto-top-dock.draw
    ble/canvas/bflush.draw
    local REPLY; _b4h_clear_seq "$1"
    ble/util/buffer "$REPLY"
    _ble_canvas_x=0 _ble_canvas_y=0
    ble/term/visible-bell/cancel-erasure
    ble/edit/leave-command-layout
  }
  function ble/widget/b4h-clear-soft { _b4h_ble_clear soft; }
  function ble/widget/b4h-clear-hard { _b4h_ble_clear hard; }

  function ble/widget/b4h-up-with-drafts {
    if (( ${#_b4h_drafts[@]} )); then
      ble/widget/.EDIT_COMMAND '_b4h_draft_recall -1'
    else
      ble/widget/b4h-up-local
    fi
  }
  function ble/widget/b4h-down-with-drafts {
    if (( ${#_b4h_drafts[@]} )); then
      ble/widget/.EDIT_COMMAND '_b4h_draft_recall 1'
    else
      ble/widget/b4h-down-local
    fi
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
    ble-bind -f up       b4h-up-with-drafts
    ble-bind -f down     b4h-down-with-drafts
    ble-bind -f C-up     b4h-up-global
    ble-bind -f C-down   b4h-down-global
    ble-bind -f M-j      b4h-kill-buffer
    ble-bind -f C-l      b4h-clear-soft
    ble-bind -f C-M-l    b4h-clear-hard
    ble-bind -x M-o      _b4h_key_stash
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
  _b4h_readline_stash() {
    [[ -n $READLINE_LINE ]] || return 0
    if (( ! ${#_b4h_drafts[@]} )); then
      bind -x '"\e[A": _b4h_draft_recall -1'
      bind -x '"\eOA": _b4h_draft_recall -1'
      bind -x '"\e[B": _b4h_draft_recall 1'
      bind -x '"\eOB": _b4h_draft_recall 1'
    fi
    _b4h_key_stash
  }
  bind -x '"\eo": _b4h_readline_stash'
  bind -x '"\C-@": _b4h_key_expand'
  bind -x '"\e[1;3D": _b4h_key_back'
  bind -x '"\e[1;3C": _b4h_key_forward'
  bind -x '"\e[1;3A": _b4h_key_up'
  bind -x '"\e[1;3B": _b4h_key_down'
  bind -x '"\er": _b4h_key_dirhist'
  bind -x '"\es": _b4h_key_sudo'
  bind -x '"\eh": _b4h_key_help'
  bind -x '"\C-l": _b4h_key_clear soft'
  bind -x '"\e\C-l": _b4h_key_clear hard'
  bind '"\e[0n": redraw-current-line'   # after fzf in a completion (cd -<Tab>)
fi
