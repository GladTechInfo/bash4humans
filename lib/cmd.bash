# =============================================================================
#  lib/cmd.bash - the `b4h` command.
#
#    b4h help             this list
#    b4h configure        choose the prompt's look (p10k configure); --from-p10k [FILE] converts ~/.p10k.zsh
#    b4h prompt edit      adjust the prompt's settings by hand (reload: b4h prompt reload)
#    b4h plugins          list, search, enable, disable plugins
#    b4h doctor           what is loaded, what is missing
#    b4h update           update bash4humans and its pinned components
#    b4h ssh HOST [ARGS]  log in to HOST with bash4humans (nothing installed there for good)
#    b4h private          a shell that keeps no history (exit to leave)
#    b4h version
# =============================================================================

b4h() {
  local sub=${1:-help}
  shift 2>/dev/null
  case $sub in
    help|-h|--help) _b4h_help ;;
    doctor)         _b4h_doctor ;;
    configure)      _b4h_configure "$@" ;;
    prompt)         _b4h_prompt_cmd "$@" ;;
    plugins)        _b4h_plugins_cmd "$@" ;;
    update)         _b4h_update ;;
    ssh)            _b4h_ssh "$@" ;;
    private)        B4H_PRIVATE=1 HISTFILE=/dev/null bash -i ;;
    version|--version) echo "bash4humans $B4H_VERSION" ;;
    *) echo "b4h: unknown command '$sub' (b4h help)" >&2; return 2 ;;
  esac
}
complete -W 'help configure prompt doctor update ssh private plugins version' b4h

_b4h_help() {
  sed -n '/^#    b4h help/,/^#    b4h version/p' "$B4H_ROOT/lib/cmd.bash" | sed 's/^#  //'
  cat <<'EOF'

  Also:   abbr, funced, funcsave, add_path, histdel, alias_suffix, zmv,
          cdh, dirh, prevd, nextd.   Keys: see the top of lib/keys.bash.
  Settings: the B4H_* lines in ~/.bashrc (all of them: lib/settings.bash).
EOF
}

_b4h_doctor() {
  . "$B4H_ROOT/versions.conf"
  local ok=ok no=-- v
  [[ -t 1 ]] && ok=$'\e[32mok\e[0m' no=$'\e[33m--\e[0m'
  printf 'bash4humans %s   bash %s   %s\n\n' "$B4H_VERSION" "$BASH_VERSION" "$B4H_ROOT"
  if (( _b4h_ble )); then
    printf '  %s line editor   ble.sh %s\n' "$ok" "$BLE_VERSION"
  else
    printf '  %s line editor   readline (B4H_LINE_EDITOR=%s)\n' "$no" "$B4H_LINE_EDITOR"
  fi
  v=; { read -r v <"$B4H_HOME/deps/ble.sh/.b4h-version"; } 2>/dev/null
  [[ $v == nightly ]] && printf '  %s ble.sh is the unpinned nightly (git, make or gawk was missing)\n' "$no"
  if [[ -n $_b4h_fzf ]]; then printf '  %s fzf          %s (%s)\n' "$ok" "$("$_b4h_fzf" --version | cut -d' ' -f1)" "$_b4h_fzf"
  else printf '  %s fzf          missing: Ctrl+R/Ctrl+T/Alt+C, Alt+Down and cdh need it\n' "$no"; fi
  if declare -F _comp_complete_load >/dev/null || declare -F _completion_loader >/dev/null; then
    printf '  %s completion   bash-completion %s\n' "$ok" "$(IFS=.; echo "${BASH_COMPLETION_VERSINFO[*]:-}")"
  else printf '  %s completion   bash-completion missing\n' "$no"; fi
  if [[ -n $_b4h_tool ]]; then printf '  %s b4h-tool     %s\n' "$ok" "$("$_b4h_tool" --version)"
  else printf '  %s b4h-tool     missing: zmv, "did you mean" and b4h configure --from-p10k are off\n' "$no"; fi
  if command -v pkgfile >/dev/null || [[ -x /usr/lib/command-not-found ]]; then
    printf '  %s packages     unknown commands show their package\n' "$ok"
  else
    printf '  %s packages     install pkgfile (Arch) or command-not-found (Debian) to name the package of unknown commands\n' "$no"
  fi
  if [[ -n ${GITSTATUS_DAEMON_PID-} ]]; then printf '  %s git          gitstatusd (pid %s)\n' "$ok" "$GITSTATUS_DAEMON_PID"
  elif [[ -r $B4H_HOME/deps/gitstatus/gitstatus.plugin.sh ]]; then printf '  %s git          gitstatusd starts on entering a repository\n' "$ok"
  else printf '  %s git          gitstatus missing; the prompt uses git status (slower in big repositories)\n' "$no"; fi
  if [[ -r $_b4h_p_conf ]]; then printf '  %s prompt       %s\n               %s\n' "$ok" "${_b4h_p_conf/#"$HOME"/\~}" "$(_b4h_cfg_summary)"
  else printf '  %s prompt       not configured yet (p10k defaults): b4h configure\n' "$no"; fi
  _p9k_codeset_is_utf8 || printf '  %s glyphs       the locale is not UTF-8: p10k uses ASCII\n' "$no"
  (( ${_p9k__tc_colors:-256} >= 256 )) ||
    printf '  %s colours      %s in this terminal (TERM=%s): colours above that show as the default\n' "$no" "$_p9k__tc_colors" "$TERM"
  (( _b4h_integrate )) && printf '  %s integration  OSC 7 / OSC 133 on\n' "$ok" || printf '  %s integration  off for this session\n' "$no"
}

_b4h_update() {
  if [[ -d $B4H_ROOT/.git && ! -L $B4H_HOME/b4h ]]; then
    git -C "$B4H_ROOT" pull --ff-only -q || { echo 'b4h update: git pull failed' >&2; return 1; }
  else
    echo "b4h update: $B4H_ROOT is a development copy; not pulling"
  fi
  _b4h_deps_ensure
  printf '%(%s)T\n' -1 >"$B4H_HOME/.last-update"
  echo 'b4h update: done - open a new shell (or: exec bash) to use it'
}

# Offer an update every B4H_AUTO_UPDATE_DAYS when B4H_AUTO_UPDATE=ask.
_b4h_auto_update_check() {
  [[ $B4H_AUTO_UPDATE == ask ]] || return 0
  local last=0 now answer
  printf -v now '%(%s)T' -1
  # No record yet (a fresh install): start counting from now instead of asking.
  if [[ ! -e $B4H_HOME/.last-update ]]; then printf '%s\n' "$now" >"$B4H_HOME/.last-update"; return 0; fi
  { read -r last <"$B4H_HOME/.last-update"; } 2>/dev/null
  (( now - ${last:-0} > B4H_AUTO_UPDATE_DAYS * 86400 )) || return 0
  read -r -p 'bash4humans: check for updates? [y/N] ' answer
  if [[ $answer == [yY]* ]]; then _b4h_update; else printf '%s\n' "$now" >"$B4H_HOME/.last-update"; fi
}

# ---------------------------------------------------------------- b4h ssh ---
# Copies bash4humans (with its built components), your rc file (B4H_RCFILE) and
# B4H_SSH_SEND_FILES to HOST:~/.cache/bash4humans-ssh, then starts bash
# with them. The host's own ~/.bashrc is not touched. The copy is reused
# while it is current, so later logins send nothing. HOST needs bash 5.
_b4h_ssh() {
  (( $# )) || { echo 'usage: b4h ssh HOST [ssh options]' >&2; return 2; }
  local bundle=$B4H_HOME/ssh-bundle.tar.gz stage sha f
  local -a ctl=(-o ControlMaster=auto -o "ControlPath=$B4H_HOME/ssh-%C" -o ControlPersist=60)

  # Rebuild the bundle when anything in it is newer.
  if [[ ! -s $bundle ]] || [[ -n $(find -L "$B4H_ROOT" "$B4H_HOME/deps" "$B4H_RCFILE" "${B4H_SSH_SEND_FILES[@]/#\~/$HOME}" \
                                    "$_b4h_p_conf" -newer "$bundle" -print -quit 2>/dev/null) ]]; then
    stage=$(mktemp -d) || return 1
    mkdir -p "$stage/files"
    cp -rL -- "$B4H_ROOT" "$stage/b4h" && rm -rf -- "$stage/b4h/.git" "$stage/b4h/tools/b4h-tool/target"
    cp -a -- "$B4H_HOME/deps" "$stage/deps"
    cp -- "$B4H_RCFILE" "$stage/bashrc"
    # the prompt's config: the host shows the same prompt (lib/prompt.bash)
    [[ -r $_b4h_p_conf ]] && cp -- "$_b4h_p_conf" "$stage/p10k.bash"
    for f in "${B4H_SSH_SEND_FILES[@]}"; do
      f=${f/#\~/$HOME}
      [[ -e $f ]] && cp -a -- "$f" "$stage/files/"
    done
    tar -C "$stage" -czf "$bundle.tmp" . && mv -- "$bundle.tmp" "$bundle"
    rm -rf -- "$stage"
  fi
  sha=$(sha256sum <"$bundle"); sha=${sha%% *}

  # Upload only if the host's copy differs. Remote commands go through
  # sh -c so they work whatever the login shell is (csh on BSD).
  local arch; arch=$(uname -m)
  local up="d=\$HOME/.cache/bash4humans-ssh; if [ \"\$(cat \$d/.sha 2>/dev/null)\" = $sha ]; then exit 0; fi; exit 3"
  ssh "${ctl[@]}" "$@" "sh -c '$up'"
  case $? in
    0) ;;
    3)
      local put="d=\$HOME/.cache/bash4humans-ssh; rm -rf \$d && mkdir -p \$d && tar -xzf - -C \$d &&
        for f in \$d/files/* \$d/files/.[!.]*; do [ -e \"\$f\" ] && { [ -e \"\$HOME/\${f##*/}\" ] || cp -a \"\$f\" \"\$HOME/\"; }; done;
        [ \"\$(uname -m)\" = $arch ] || rm -rf \$d/deps/fzf \$d/deps/bin; echo $sha > \$d/.sha"
      ssh "${ctl[@]}" "$@" "sh -c '$put'" <"$bundle" || { echo 'b4h ssh: upload failed' >&2; return 1; }
      ;;
    *) return 1 ;;
  esac
  ssh -t "${ctl[@]}" "$@" "sh -c 'if command -v bash >/dev/null; then B4H_HOME=\$HOME/.cache/bash4humans-ssh exec bash --rcfile \$HOME/.cache/bash4humans-ssh/bashrc -i; else exec \$SHELL -l; fi'"
}
