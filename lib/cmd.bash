# =============================================================================
#  lib/cmd.bash - the `b4h` command.
#
#    b4h help             this list
#    b4h configure        choose the prompt's look (p10k configure); --from-p10k [FILE] converts ~/.p10k.zsh
#    b4h prompt edit      adjust the prompt's settings by hand (reload: b4h prompt reload)
#    b4h plugins          list, search, enable, disable plugins
#    b4h install U/R[@REF] a plugin from any GitHub repository (load U/R[/DIR], source U/R/FILE, uninstall U/R)
#    b4h doctor           what is loaded, what is missing
#    b4h update           update bash4humans and its pinned components
#    b4h ssh HOST [ARGS]  log in to HOST with bash4humans (nothing installed there for good)
#    b4h private          a shell that keeps no history (exit to leave)
#    b4h clipboard        how x, c and v reach the clipboard here
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
    install)        _b4h_repo_install "$@" ;;
    load)           _b4h_repo_load "$@" ;;
    source)         _b4h_repo_source "$@" ;;
    uninstall)      _b4h_repo_uninstall "$@" ;;
    update)         _b4h_update ;;
    ssh)            _b4h_ssh "$@" ;;
    private)        B4H_PRIVATE=1 HISTFILE=/dev/null bash -i ;;
    clipboard)      _b4h_clipboard_info ;;
    version|--version) echo "bash4humans $B4H_VERSION" ;;
    *) echo "b4h: unknown command '$sub' (b4h help)" >&2; return 2 ;;
  esac
}
complete -W 'help configure prompt doctor update ssh private clipboard plugins install load source uninstall version' b4h

_b4h_help() {
  sed -n '/^#    b4h help/,/^#    b4h version/p' "$B4H_ROOT/lib/cmd.bash" | sed 's/^#  //'
  cat <<'EOF'

  Also:   abbr, funced, funcsave, add_path, histdel, alias_suffix, zmv,
          cdh, dirh, prevd, nextd, x / c / v (clipboard).
  Keys:   see the top of lib/keys.bash.
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
  else printf '  %s b4h-tool     missing: zmv, "did you mean" and b4h configure --from-p10k are off (b4h update tries again)\n' "$no"; fi
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
  if [[ -n ${_b4h_locale_fixed-} ]]; then
    printf '  %s locale       LC_ALL=%s: no UTF-8 locale was in effect (B4H_FIX_LOCALE)\n' "$ok" "$_b4h_locale_fixed"
  elif ! _b4h_locale_is_utf8; then
    printf '  %s locale       not UTF-8 and no UTF-8 locale installed: line editing and glyphs suffer\n' "$no"
  fi
  _p9k_codeset_is_utf8 || printf '  %s glyphs       the locale is not UTF-8: p10k uses ASCII\n' "$no"
  (( ${_p9k__tc_colors:-256} >= 256 )) ||
    printf '  %s colours      %s in this terminal (TERM=%s): colours above that show as the default\n' "$no" "$_p9k__tc_colors" "$TERM"
  (( _b4h_integrate )) && printf '  %s integration  OSC 7 / OSC 133 on\n' "$ok" || printf '  %s integration  off for this session\n' "$no"
  local REPLY; _b4h_clip_tool
  if [[ $REPLY == osc52 ]]; then printf '  %s clipboard    the terminal'"'"'s (OSC 52); v pastes the last copy made here\n' "$ok"
  else printf '  %s clipboard    %s\n' "$ok" "$REPLY"; fi
}

_b4h_update() {
  if [[ -d $B4H_ROOT/.git && ! -L $B4H_HOME/b4h ]]; then
    git -C "$B4H_ROOT" pull --ff-only -q || { echo 'b4h update: git pull failed' >&2; return 1; }
  else
    echo "b4h update: $B4H_ROOT is a development copy; not pulling"
  fi
  _b4h_deps_retry=1 _b4h_deps_ensure     # (components that failed are tried again)
  _b4h_repos_update                      # repositories from b4h install
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
# As zsh4humans' teleportation, also:
#  - the session's history is kept on HOST in ~/.cache/bash4humans-ssh.history,
#    not in the host's ~/.bash_history; B4H_SSH_RETRIEVE_HISTORY=FILE brings
#    each session's new lines back here (appended to FILE);
#  - a terminal HOST does not know ($TERM missing from its terminfo) gets its
#    description compiled there into ~/.cache/bash4humans-ssh.terminfo
#    (TERMINFO for the session; nothing system-wide), or, without `tic`
#    there, TERM=xterm-256color.
# With B4H_SSH_HOSTS set, a plain `ssh HOST` to a matching host does this.
# Per host (as zsh4humans' :z4h:ssh:HOST styles):
#  - B4H_SSH_TERM=('*.lab=xterm-256color' ...): the TERM used there;
#  - B4H_SSH_RETRIEVE_FILES=(~/.notes ...): after the session, each file is
#    copied back from HOST to the same path here (retrieve-extra-files);
#  - a function b4h_ssh_configure, if you define one, runs before each
#    connection with the host's name in $1. It may change, for that session
#    only, B4H_SSH_SEND_FILES, B4H_SSH_RETRIEVE_FILES, B4H_SSH_SESSION_TERM
#    and B4H_SSH_PRELUDE (commands run on HOST before bash4humans starts,
#    e.g. 'export EDITOR=vim').
_b4h_ssh() {
  (( $# )) || { echo 'usage: b4h ssh HOST [ssh options]' >&2; return 2; }
  local stage sha f out rc REPLY
  _b4h_ssh_parse "$@"; local host=$REPLY

  # This session's settings: copies the hook may change (local, so the
  # changes end with the session). TERM: the first B4H_SSH_TERM pattern
  # that matches the host, else this terminal's.
  local -a B4H_SSH_SEND_FILES=("${B4H_SSH_SEND_FILES[@]}")
  local -a B4H_SSH_RETRIEVE_FILES=("${B4H_SSH_RETRIEVE_FILES[@]}")
  local -a B4H_SSH_PRELUDE=("${B4H_SSH_PRELUDE[@]}")
  local B4H_SSH_SESSION_TERM=$TERM p
  for p in "${B4H_SSH_TERM[@]}"; do
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    [[ $host == ${p%%=*} ]] && { B4H_SSH_SESSION_TERM=${p#*=}; break; }
  done
  declare -F b4h_ssh_configure >/dev/null && b4h_ssh_configure "$host"

  # One bundle per set of files sent (the hook may choose them per host).
  local key; key=$(printf '%s\0' "${B4H_SSH_SEND_FILES[@]}" | sha256sum); key=${key:0:12}
  local bundle=$B4H_HOME/ssh-bundle-$key.tar.gz
  local -a ctl=(-o ControlMaster=auto -o "ControlPath=$B4H_HOME/ssh-%C" -o ControlPersist=60)

  # Rebuild the bundle when anything in it is newer.
  if [[ ! -s $bundle ]] || [[ -n $(find -L "$B4H_ROOT" "$B4H_HOME/deps" "$B4H_RCFILE" "${B4H_SSH_SEND_FILES[@]/#\~/$HOME}" \
                                    "$_b4h_p_conf" -newer "$bundle" -print -quit 2>/dev/null) ]]; then
    stage=$(mktemp -d) || return 1
    mkdir -p "$stage/files"
    cp -rL -- "$B4H_ROOT" "$stage/b4h" && rm -rf -- "$stage/b4h/.git" "$stage/b4h/tools/b4h-tool/target" "$stage/b4h/tools/"*/target
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

  # One round trip: the host's history length (to bring back only this
  # session's lines), whether it knows this terminal, and whether its copy is
  # current (exit 0) or needs uploading (exit 3). Remote commands go through
  # sh -c so they work whatever the login shell is (csh on BSD).
  local term=${B4H_SSH_SESSION_TERM//[^A-Za-z0-9._+-]/}
  local up="d=\$HOME/.cache/bash4humans-ssh; h=\$d.history; n=0; [ -r \$h ] && n=\$(wc -l <\$h);
    t=0; if [ -n '$term' ] && ! infocmp '$term' >/dev/null 2>&1; then
      if command -v infocmp >/dev/null 2>&1 || ! ls /usr/share/terminfo/*/'$term' /lib/terminfo/*/'$term' >/dev/null 2>&1; then
        if command -v tic >/dev/null 2>&1; then t=1; else t=2; fi; fi; fi;
    [ -d \$d.terminfo ] && infocmp -A \$d.terminfo '$term' >/dev/null 2>&1 && t=3;
    echo \$n \$t; if [ \"\$(cat \$d/.sha 2>/dev/null)\" = $sha ]; then exit 0; fi; exit 3"
  out=$(command ssh "${ctl[@]}" "$@" "sh -c '${up//\'/\'\\\'\'}'"); rc=$?
  local nhist=0 tstate=0
  read -r nhist tstate <<<"$out"
  [[ $nhist =~ ^[0-9]+$ ]] || nhist=0
  case $rc in
    0) ;;
    3)
      local arch; arch=$(uname -m)
      local put="d=\$HOME/.cache/bash4humans-ssh; rm -rf \$d && mkdir -p \$d && tar -xzf - -C \$d &&
        for f in \$d/files/* \$d/files/.[!.]*; do [ -e \"\$f\" ] && { [ -e \"\$HOME/\${f##*/}\" ] || cp -a \"\$f\" \"\$HOME/\"; }; done;
        [ \"\$(uname -m)\" = $arch ] || rm -rf \$d/deps/fzf \$d/deps/bin; echo $sha > \$d/.sha"
      command ssh "${ctl[@]}" "$@" "sh -c '$put'" <"$bundle" || { echo 'b4h ssh: upload failed' >&2; return 1; }
      ;;
    *) return 1 ;;
  esac

  # The terminal: send its description when the host lacks it.
  local envs=
  if [[ $tstate == 1 ]] && command -v infocmp >/dev/null && infocmp -x "$term" >/dev/null 2>&1; then
    infocmp -x "$term" | command ssh "${ctl[@]}" "$@" \
      "sh -c 'd=\$HOME/.cache/bash4humans-ssh.terminfo; mkdir -p \$d && cat >\$d/src && tic -x -o \$d \$d/src >/dev/null 2>&1'" &&
      tstate=3
  fi
  [[ $term != "$TERM" ]] && envs="TERM=$term "
  [[ $tstate == 3 ]] && envs+='TERMINFO=$HOME/.cache/bash4humans-ssh.terminfo '
  [[ $tstate == 1 || $tstate == 2 ]] && envs='TERM=xterm-256color '

  # B4H_SSH_PRELUDE: commands for the host, run before bash4humans starts
  # (inside the single-quoted sh -c below: their quotes are escaped)
  local prelude=
  for p in "${B4H_SSH_PRELUDE[@]}"; do prelude+="$p; "; done
  prelude=${prelude//\'/\'\\\'\'}

  local launch="${prelude}if command -v bash >/dev/null; then ${envs}B4H_HOME=\$HOME/.cache/bash4humans-ssh HISTFILE=\$HOME/.cache/bash4humans-ssh.history exec bash --rcfile \$HOME/.cache/bash4humans-ssh/bashrc -i; else exec \$SHELL -l; fi"
  command ssh -t "${ctl[@]}" "$@" "sh -c '$launch'"; rc=$?

  # This session's history lines, appended to B4H_SSH_RETRIEVE_HISTORY.
  if [[ -n $B4H_SSH_RETRIEVE_HISTORY ]]; then
    local into=${B4H_SSH_RETRIEVE_HISTORY/#\~/$HOME}
    command ssh "${ctl[@]}" "$@" "sh -c 'tail -n +$((nhist + 1)) \$HOME/.cache/bash4humans-ssh.history 2>/dev/null'" >>"$into" ||
      echo 'b4h ssh: could not bring the history back' >&2
  fi
  # B4H_SSH_RETRIEVE_FILES: ~/path or /path, the same on both ends; a file
  # the host does not have is left alone here.
  local local_f remote_f
  for f in "${B4H_SSH_RETRIEVE_FILES[@]}"; do
    local_f=${f/#\~/$HOME}
    remote_f=$f
    # shellcheck disable=SC2088  # a literal ~/ in the setting's text, on purpose
    [[ $f == '~/'* ]] && remote_f="\$HOME/${f#\~/}"
    # ~/x written unquoted in ~/.bashrc arrives as this home's full path: the same file
    # under the host's home
    [[ $f == "$HOME"/* ]] && remote_f="\$HOME/${f#"$HOME"/}"
    remote_f=${remote_f//\'/\'\\\'\'}
    if command ssh "${ctl[@]}" "$@" "sh -c 'test -f \"$remote_f\" && cat \"$remote_f\"'" >"$local_f.b4h-tmp" 2>/dev/null; then
      mv -- "$local_f.b4h-tmp" "$local_f"
    else
      rm -f -- "$local_f.b4h-tmp"
    fi
  done
  return "$rc"
}

# ------------------------------------------- plain ssh, for B4H_SSH_HOSTS ---
# `ssh HOST` is `b4h ssh HOST` for hosts matching B4H_SSH_HOSTS, when it is an
# interactive login: a terminal on both ends, no remote command, none of
# -N -T -f -G -O -Q -V -W -s. Anything else runs ssh unchanged.
# ssh's arguments -> REPLY: the host (user@ and ssh://...:port removed);
# return 0 when they make an interactive login (no remote command, none of
# the flags that mean otherwise), else 1.
_b4h_ssh_parse() {
  local a dest= opt login=0
  REPLY=
  while (( $# )); do
    a=$1; shift
    if [[ -n $dest ]]; then login=1; break; fi        # a remote command follows the host
    case $a in
      --) dest=${1-}; shift ;;
      -*)
        opt=${a:1}
        # flags that mean "no interactive login"
        [[ $opt == *[NTfGVs]* && $opt != [BbcDEeFIiJLlmOopQRSWw]* ]] && login=1
        # options with an argument: -p 22, or -p22
        case ${opt:0:1} in
          O|Q|W) login=1 ;;
        esac
        case ${opt:0:1} in
          B|b|c|D|E|e|F|I|i|J|L|l|m|O|o|p|Q|R|S|W|w)
            [[ ${#opt} == 1 ]] && shift ;;
        esac ;;
      *) dest=$a ;;
    esac
  done
  [[ -n $dest ]] || return 1
  REPLY=${dest#ssh://}; REPLY=${REPLY##*@}; [[ $dest == ssh://* ]] && REPLY=${REPLY%%:*}
  return "$login"
}
_b4h_ssh_wants() {      # ARGS... -> 0: teleport
  local REPLY p
  (( ${#B4H_SSH_HOSTS[@]} )) && [[ -t 0 && -t 1 ]] || return 1
  _b4h_ssh_parse "$@" || return 1
  for p in "${B4H_SSH_HOSTS[@]}"; do
    # shellcheck disable=SC2053  # the pattern is a glob on purpose
    [[ $REPLY == $p ]] && return 0
  done
  return 1
}
if (( ${#B4H_SSH_HOSTS[@]} )) && ! declare -F ssh >/dev/null && ! alias ssh >/dev/null 2>&1; then
  ssh() {
    if _b4h_ssh_wants "$@"; then _b4h_ssh "$@"; else command ssh "$@"; fi
  }
fi
