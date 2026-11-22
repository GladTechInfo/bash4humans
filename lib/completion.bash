# =============================================================================
#  lib/completion.bash - bash-completion, fzf, and how completion behaves.
# =============================================================================

# ------------------------------------------------------- bash-completion ---
# The system copy wins if installed (it matches the system's packages);
# otherwise the pinned copy in $B4H_HOME. Must load before fzf's completion.
if ! declare -F _comp_complete_load >/dev/null && ! declare -F _completion_loader >/dev/null; then
  for _b4h_f in /usr/share/bash-completion/bash_completion /etc/bash_completion \
                "$B4H_HOME/deps/bash-completion/bash_completion"; do
    [[ -r $_b4h_f ]] && { . "$_b4h_f"; break; }
  done
  unset _b4h_f
fi

# git ships its completion outside bash-completion on some systems (Arch:
# /usr/share/git/completion). Load it on first use: returning 124 tells
# bash to retry the completion with the newly defined function.
_b4h_git_completion_load() {
  local f
  for f in /usr/share/bash-completion/completions/git /usr/share/git/completion/git-completion.bash \
           /usr/share/git-core/contrib/completion/git-completion.bash; do
    [[ -r $f ]] && { . "$f"; return 124; }
  done
  complete -r git gitk 2>/dev/null
  return 1
}
complete -p git >/dev/null 2>&1 || complete -o bashdefault -o default -F _b4h_git_completion_load git gitk

# ------------------------------------------------------------------- fzf ---
# A system fzf is used if present; otherwise the pinned copy is added to
# the end of PATH.
if ! command -v fzf >/dev/null && [[ -x $B4H_HOME/deps/fzf/bin/fzf ]]; then
  PATH=$PATH:$B4H_HOME/deps/fzf/bin
fi
_b4h_fzf=$(command -v fzf)

if [[ -n $_b4h_fzf ]]; then
  if (( _b4h_ble )); then
    # ble.sh wraps fzf's own bindings: Ctrl+R history, Ctrl+T files, Alt+C cd,
    # and ** + TAB fuzzy completion.
    ble-import -d integration/fzf-completion
    ble-import -d integration/fzf-key-bindings
  elif "$_b4h_fzf" --bash >/dev/null 2>&1; then
    eval "$("$_b4h_fzf" --bash)"
  else
    for _b4h_f in /usr/share/fzf/key-bindings.bash /usr/share/doc/fzf/examples/key-bindings.bash; do
      [[ -r $_b4h_f ]] && { . "$_b4h_f"; break; }
    done
    unset _b4h_f
  fi
fi

# ---------------------------------------------------------- behaviour ---
if (( _b4h_ble )); then
  bleopt complete_menu_style=desc        # menu shows a description per entry, like fish
  bleopt complete_auto_complete=1        # grey suggestion as you type
  bleopt edit_bell=                      # no beep
  bleopt prompt_eol_mark=$'\e[7m%\e[0m'  # output without a final newline ends in %, as in zsh
  bleopt exec_errexit_mark=              # the prompt already shows the exit status
  bleopt exec_elapsed_mark=              # ... and the run time
  ble-face auto_complete='fg=244'        # suggestion colour: grey, no background
  if [[ $B4H_TAB == fzf && -n $_b4h_fzf ]]; then
    ble-import -d integration/fzf-menu
    bleopt integration_fzf_menu_enabled=1 2>/dev/null
  fi
else
  bind 'set completion-ignore-case on'
  bind 'set colored-stats on'
  bind 'set colored-completion-prefix on'
  bind 'set mark-symlinked-directories on'
  bind 'set visible-stats on'
  bind 'set bell-style none'
  bind 'set show-all-if-ambiguous off'   # zsh no_auto_menu: list on the second TAB
fi
