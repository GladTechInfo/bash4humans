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
# ------------------------------------------------- TAB with fzf (B4H_TAB=fzf) ---
# As zsh4humans' Tab: fzf with several picks - Ctrl+Space marks an entry,
# Ctrl+A marks all, Enter inserts what is marked (or the entry under the
# cursor); Tab / Shift+Tab move, the list wraps round; Alt+J / Ctrl+U clear
# the query. Built on ble.sh's fzf-menu integration: its SELECTOR (which
# ble.sh lets users replace) picks; one pick goes back to ble.sh as usual
# (it adds / after a directory, a space after a file); several come back
# through a file and are inserted together after ble.sh's step.
_b4h_fzf_tab_picks=${TMPDIR:-/tmp}/b4h-fzf-picks.$$

_b4h_fzf_tab_setup() {
  # The candidates arrive as "INDEX<sep>ITEM<sep>DESCRIPTION". Runs in a
  # subshell (ble.sh reads its output): extra picks go to a file.
  function ble/contrib/integration:fzf-menu/SELECTOR {
    local -a opts=(--ansi --query "$common_prefix" -d "$sep" --with-nth=2.. --nth=1
                   --multi --cycle
                   --layout=reverse --border=horizontal
                   --bind 'ctrl-space:toggle+down,ctrl-a:toggle-all,tab:down,btab:up,alt-j:clear-query,ctrl-u:clear-query')
    local ret; ble/util/c2w 0x2500
    ((ret == 1)) || opts+=(--no-unicode)
    [[ :$comp_type: == *:i:* ]] && opts+=(--ignore-case)
    # B4H_TAB_RECURSE=yes (zsh4humans' recurse-dirs): for each directory
    # offered, what is under it too, as items "r:PATH" (not one of ble.sh's
    # numbered candidates); .git skipped, depth and number capped.
    local -a extra=()
    if [[ $B4H_TAB_RECURSE == yes ]]; then
      # ble.sh gives the candidates with ~ expanded; what was typed (COMPS)
      # says whether to write ~/ again
      local i dir path ins kind tilde=
      [[ ${COMPS-} == '~'* ]] && tilde=1
      for (( i = 0; i < ${#cand_cand[@]}; i++ )); do
        dir=${cand_cand[i]}
        # shellcheck disable=SC2088  # a literal ~/, on purpose
        [[ $dir == '~/'* ]] && dir=$HOME/${dir#\~/}
        [[ -d $dir ]] || continue
        while IFS= read -r path; do
          kind=file; [[ -d $path ]] && kind=directory
          # shown as ble.sh shows its own (expanded, matching the query);
          # inserted with ~/ again when ~ was typed
          ins=$path
          # shellcheck disable=SC2088
          [[ -n $tilde && $path == "$HOME"/* ]] && ins='~/'${path#"$HOME"/}
          extra+=("r:$ins$sep$path$sep - $kind")
        done < <(find "$dir" -mindepth 1 -maxdepth "$B4H_TAB_RECURSE_DEPTH" -name .git -prune -o -print 2>/dev/null |
                 head -n "$B4H_TAB_RECURSE_MAX")
      done
    fi
    # Size the picker ourselves so older fzf versions can open it inline too.
    local rows=${LINES:-24} height=$(( $# + ${#extra[@]} + 4 )) limit
    limit=$(( rows * 40 / 100 ))
    (( limit >= 6 )) || limit=6
    (( height <= limit )) || height=$limit
    (( height < rows )) || height=$(( rows > 1 ? rows - 1 : 1 ))
    opts+=("--height=$height")
    local -a picked
    mapfile -t picked < <({ builtin eval -- "printf '%s\n' \"\$@\"$_ble_contrib_fzf_menu_filter"
                             (( ${#extra[@]} )) && printf '%s\n' "${extra[@]}"; } | fzf "${opts[@]}" | cut -d "$sep" -f 1)
    if (( ${#picked[@]} == 1 )) && [[ ${picked[0]} != r:* ]]; then
      printf '%s\n' "${picked[0]}"               # one of ble.sh's: ble.sh inserts it
    elif (( ${#picked[@]} )); then
      # several, or a path from below a directory: inserted after ble.sh's
      # step, each quoted (a ~/ typed stays ~/)
      local p q
      for p in "${picked[@]}"; do
        if [[ $p == r:* ]]; then
          p=${p#r:}
          # shellcheck disable=SC2088
          if [[ $p == '~/'* ]]; then printf -v q '%q' "${p#\~/}"; q="~/$q"; else printf -v q '%q' "$p"; fi
          printf '%s\n' "$q"
        else
          printf '%s\n' "${cand_word[p]}"
        fi
      done >"$_b4h_fzf_tab_picks"
    fi
  }
  _b4h_fzf_tab_move_below_wrapped_input() {
    [[ ${bleopt_integration_fzf_menu_enabled-} ]] || return 0
    (( cand_count > 1 && _ble_textarea_gendy > _ble_textarea_cur[1] )) || return 0
    # Move the terminal cursor to the last row without changing the edit point.
    local -a DRAW_BUFF=()
    ble/canvas/panel#goto.draw "$_ble_textarea_panel" "$_ble_textarea_gendx" "$_ble_textarea_gendy"
    ble/canvas/bflush.draw
  }
  ble/function#advice before ble/contrib/integration:fzf-menu/.select-and-insert _b4h_fzf_tab_move_below_wrapped_input

  # After ble.sh's step: several picks replace the word being completed,
  # each as ble.sh quoted it, with a space after the last.
  _b4h_fzf_tab_insert_picks() {
    [[ -s $_b4h_fzf_tab_picks ]] || return 0
    local -a words; mapfile -t words <"$_b4h_fzf_tab_picks"
    rm -f -- "$_b4h_fzf_tab_picks"
    local IFS=' '
    ble/complete/insert "$COMP1" "$COMP2" "${words[*]}" ' '
  }
  ble/function#advice after ble/contrib/integration:fzf-menu/.select-and-insert _b4h_fzf_tab_insert_picks
}

if (( _b4h_ble )); then
  bleopt complete_menu_style=desc        # menu shows a description per entry, like fish
  bleopt complete_auto_complete=1        # grey suggestion as you type
  bleopt edit_bell=                      # no beep
  bleopt prompt_eol_mark=$'\e[7m%\e[0m'  # output without a final newline ends in %, as in zsh
  bleopt exec_errexit_mark=              # the prompt already shows the exit status
  bleopt exec_elapsed_mark=              # ... and the run time
  ble-face auto_complete='fg=244'        # suggestion colour: grey, no background
  if [[ $B4H_TAB == fzf && -n $_b4h_fzf ]]; then
    ble-import -d -C _b4h_fzf_tab_setup integration/fzf-menu
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
