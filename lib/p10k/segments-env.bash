# =============================================================================
#  lib/p10k/segments-env.bash - segments that only report the environment:
#  a parent program (ranger, yazi, nnn, lf, xplr, vim, mc, chezmoi, nix,
#  toolbox/distrobox, direnv), SSH, root, write access, history number, proxy.
#  Ports of the same-named prompt_* and _p9k_prompt_*_init functions of p10k.
#
#  An _init function runs once at start-up for each place the segment appears
#  and may set a condition (see _p9k_init in main.bash); p10k writes these
#  conditions in zsh, here they are bash expressions with the same result:
#    zsh ${X:#0}  "X unless it is exactly 0"  ->  bash ${X/#0/} is empty for
#                 X=0 and X='', and non-empty for every other value used here.
# =============================================================================

# zsh ${(Q)STRING} -> _p9k__ret: balanced '...' and "..." quotes and
# backslashes removed; a string with an unbalanced quote is left as it is.
# Nothing is expanded or run (the text comes from files such as ~/.aws/config).
_p9k_unquote() {
  local s=$1 w='' c q='' i
  for (( i = 0; i < ${#s}; i++ )); do
    c=${s:i:1}
    if [[ $q == "'" ]]; then
      if [[ $c == "'" ]]; then q=''; else w+=$c; fi
    elif [[ $q == '"' ]]; then
      if [[ $c == '"' ]]; then q=''
      elif [[ $c == '\' && ${s:i+1:1} == [\\\"\$\`] ]]; then w+=${s:i+1:1}; (( i++ ))
      else w+=$c; fi
    elif [[ $c == '\' ]]; then w+=${s:i+1:1}; (( i++ ))
    elif [[ $c == "'" || $c == '"' ]]; then q=$c
    else w+=$c
    fi
  done
  if [[ -n $q ]]; then _p9k__ret=$s; else _p9k__ret=$w; fi
}

# A condition that is never true (p10k: '${:-}').
_p9k_cond_never() { _p9k_set_cond '${_p9k__never-}'; }
_p9k_set_cond() { printf -v "_p9k__segment_cond_${_p9k__prompt_side}[$_p9k__segment_index]" '%s' "$1"; }

# ------------------------------------------------- parent file managers etc. ---
prompt_ranger() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow RANGER_ICON 0 '' "${RANGER_LEVEL-}"; }
_p9k_prompt_ranger_init() { _p9k_set_cond '${RANGER_LEVEL-}'; }

prompt_yazi() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow YAZI_ICON 0 '' "${YAZI_LEVEL-}"; }
_p9k_prompt_yazi_init() { _p9k_set_cond '${YAZI_LEVEL-}'; }

prompt_nnn() { _p9k_prompt_segment "${FUNCNAME[0]}" 6 "$_p9k_color1" NNN_ICON 0 '' "${NNNLVL-}"; }
_p9k_prompt_nnn_init() { _p9k_set_cond '${NNNLVL/#0/}'; }

prompt_lf() { _p9k_prompt_segment "${FUNCNAME[0]}" 6 "$_p9k_color1" LF_ICON 0 '' "${LF_LEVEL-}"; }
_p9k_prompt_lf_init() { _p9k_set_cond '${LF_LEVEL/#0/}'; }

prompt_xplr() { _p9k_prompt_segment "${FUNCNAME[0]}" 6 "$_p9k_color1" XPLR_ICON 0 '' ''; }
_p9k_prompt_xplr_init() { _p9k_set_cond '${XPLR_PID-}'; }

prompt_vim_shell() { _p9k_prompt_segment "${FUNCNAME[0]}" green "$_p9k_color1" VIM_ICON 0 '' ''; }
_p9k_prompt_vim_shell_init() { _p9k_set_cond '${VIMRUNTIME-}'; }

prompt_midnight_commander() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow MIDNIGHT_COMMANDER_ICON 0 '' ''; }
_p9k_prompt_midnight_commander_init() { _p9k_set_cond '${MC_TMPDIR-}'; }

prompt_chezmoi_shell() { _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" CHEZMOI_ICON 0 '' ''; }
_p9k_prompt_chezmoi_shell_init() { _p9k_set_cond '${CHEZMOI-}'; }

# ---------------------------------------------------------------- nix_shell ---
# Content: IN_NIX_SHELL when it is "pure" or "impure", else just the icon.
prompt_nix_shell() {
  local v=${IN_NIX_SHELL-}
  [[ $v == pure || $v == impure ]] || v=''
  _p9k_prompt_segment "${FUNCNAME[0]}" 4 "$_p9k_color1" NIX_SHELL_ICON 0 '' "$v"
}
# NIX_SHELL_INFER_FROM_PATH=true: also shown when PATH has an entry under
# /nix/store/ (zsh: ${path[(r)/nix/store/*]}).
_p9k_prompt_nix_shell_init() {
  if (( _POWERLEVEL9K_NIX_SHELL_INFER_FROM_PATH )); then
    _p9k_set_cond '${IN_NIX_SHELL/#0/}${$((_p9k_nix_store_path()))+$_p9k__nixp}'
  else
    _p9k_set_cond '${IN_NIX_SHELL/#0/}'
  fi
}
_p9k_nix_store_path() {
  local d; _p9k__nixp=''
  local IFS=:
  for d in $PATH; do [[ $d == /nix/store/* ]] && { _p9k__nixp=$d; break; }; done
}

# ------------------------------------------------------------------ toolbox ---
prompt_toolbox() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow TOOLBOX_ICON 0 '' "${P9K_TOOLBOX_NAME-}"; }
_p9k_prompt_toolbox_init() { _p9k_set_cond '${P9K_TOOLBOX_NAME-}'; }

# p10k: _p9k_init_toolbox. Toolbox/podman: name="..." in /run/.containerenv
# (must be exactly one word); distrobox: the host name, if it starts with $NAME.
_p9k_init_toolbox() {
  [[ -z ${P9K_TOOLBOX_NAME-} ]] || return 0
  if [[ -f /run/.containerenv && -r /run/.containerenv ]]; then
    local line v=''
    while IFS= read -r line; do
      [[ $line == name=* ]] && v+=${line#name=}' '
    done </run/.containerenv
    # split at blanks, then zsh ${(Q)...} on each word
    local -a words; read -r -a words <<<"$v"
    (( ${#words[@]} == 1 )) || return 0
    _p9k_unquote "${words[0]}"
    [[ -n $_p9k__ret ]] || return 0
    P9K_TOOLBOX_NAME=$_p9k__ret
  elif [[ -n ${DISTROBOX_ENTER_PATH-} ]]; then
    local name=${HOSTNAME%%.*}
    if [[ -n $name && $name == "${NAME-}"* ]]; then
      P9K_TOOLBOX_NAME=$name
    fi
  fi
}

# ------------------------------------------------------------------- direnv ---
# p10k also shows it while DIRENV_DIR is not yet set when its own precmd is not
# the last one; in bash, direnv's hook puts itself in front of PROMPT_COMMAND,
# so DIRENV_DIR is already current when the prompt is built.
prompt_direnv() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow DIRENV_ICON 0 '${DIRENV_DIR-}' ''; }
_p9k_prompt_direnv_init() { _p9k_set_cond '${DIRENV_DIR-}'; }

# --------------------------------------------------------------------- ssh ---
prompt_ssh() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow SSH_ICON 0 '' ''; }
_p9k_prompt_ssh_init() { (( P9K_SSH )) || _p9k_cond_never; }

# ------------------------------------------------------------ root_indicator ---
prompt_root_indicator() { _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow ROOT_ICON 0 '$_p9k__is_root' ''; }

# -------------------------------------------------------------- dir_writable ---
prompt_dir_writable() {
  [[ -w $PWD ]] || _p9k_prompt_segment "${FUNCNAME[0]}_FORBIDDEN" red yellow1 LOCK_ICON 0 '' ''
}

# ----------------------------------------------------------------- history ---
# %h is the number the next command will get in the history.
prompt_history() { _p9k_prompt_segment "${FUNCNAME[0]}" grey50 "$_p9k_color1" '' 0 '' '%h'; }

# ------------------------------------------------------------------- proxy ---
# The proxy host:port if all *_proxy variables that are set agree on one
# (scheme, user and path removed), else just the icon.
prompt_proxy() {
  local -a p=() u=()
  local v x seen
  for v in "${all_proxy-}" "${http_proxy-}" "${https_proxy-}" "${ftp_proxy-}" \
           "${ALL_PROXY-}" "${HTTP_PROXY-}" "${HTTPS_PROXY-}" "${FTP_PROXY-}"; do
    [[ -n $v ]] || continue
    # zsh local -U: unique values, first occurrence kept
    seen=0; for x in "${u[@]}"; do [[ $x == "$v" ]] && seen=1; done
    (( seen )) || u+=("$v")
  done
  for v in "${u[@]}"; do
    v=${v#*://}; v=${v##*@}; v=${v%%/*}
    # still unique after stripping (the array is -U in p10k)
    seen=0; for x in "${p[@]}"; do [[ $x == "$v" ]] && seen=1; done
    (( seen )) || p+=("$v")
  done
  (( ${#p[@]} == 1 )) || p=('')
  _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" blue PROXY_ICON 0 '' "${p[0]}"
}
_p9k_prompt_proxy_init() {
  _p9k_set_cond '${all_proxy-}${http_proxy-}${https_proxy-}${ftp_proxy-}${ALL_PROXY-}${HTTP_PROXY-}${HTTPS_PROXY-}${FTP_PROXY-}'
}
