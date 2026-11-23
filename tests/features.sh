#!/bin/bash
# =============================================================================
#  tests/features.sh - the zsh4humans features of bash4humans, typed into a
#  real interactive bash4humans, under ble.sh and under plain readline:
#  Alt+J, Alt+O, Alt+M, Ctrl+Space, Ctrl+Shift+arrows/Delete, Ctrl+Up/Down,
#  Alt+R, cd -<Tab>, the persistent directory history, the window title
#  while a command runs, and x / c / v.
#
#    tests/features.sh [FILTER]      FILTER: run only cases whose name has it
#
#  Needs: tui-capture (screen checks), script (util-linux; raw output for
#  the title and OSC 52), jq, fzf, and ble.sh in ~/.cache/bash4humans/deps
#  (B4H_DEPS=DIR for another place). Everything else is made in a
#  temporary directory: B4H_HOME, the config, the history.
# =============================================================================
set -u
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
DEPS=${B4H_DEPS:-$HOME/.cache/bash4humans/deps}
FILTER=${1-}
T=$(mktemp -d /tmp/b4h-features.XXXXXX)
pass=0 fail=0 failed=()

for tool in tui-capture script jq; do
  command -v "$tool" >/dev/null || { echo "features.sh: $tool is missing" >&2; exit 2; }
done
[[ -r $DEPS/ble.sh/ble.sh ]] || { echo "features.sh: no ble.sh in $DEPS" >&2; exit 2; }

# ------------------------------------------------------------ the shells ---
# One rc file per editor; B4H_HOME shares the dependencies, nothing else.
mk_env() {    # $1: ble | readline
  local e=$1 d=$T/$1
  mkdir -p "$d/home" "$d/config/bash4humans" "$d/work/sub one" "$d/work/two" "$d/work/files"
  # the components, each linked; this home's own stamps and markers stay here
  mkdir -p "$d/home/deps"
  for c in "$DEPS"/*; do ln -s "$c" "$d/home/deps/${c##*/}"; done
  : >"$d/work/files/a1.txt"; : >"$d/work/files/a2.txt"; : >"$d/work/files/b 3.txt"
  # a small, plain prompt: the directory, then >
  {
    echo "POWERLEVEL9K_MODE=ascii"
    echo "POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir prompt_char)"
    echo "POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=()"
    echo "POWERLEVEL9K_INSTANT_PROMPT=off"
    echo "POWERLEVEL9K_PROMPT_ADD_NEWLINE=false"
    echo "POWERLEVEL9K_DISABLE_HOT_RELOAD=true"
  } >"$d/config/bash4humans/p10k.bash"
  {
    echo "B4H_HOME=$d/home"
    echo "XDG_CONFIG_HOME=$d/config"
    echo "HISTFILE=$d/hist"
    echo "B4H_LINE_EDITOR=$e"
    echo "B4H_GREETING="
    echo "B4H_WIZARD=no"
    echo "B4H_AUTO_UPDATE=no"
    echo "B4H_SHELL_INTEGRATION=no"
    echo "unset DISPLAY WAYLAND_DISPLAY TMUX SSH_CONNECTION"
    echo ". $ROOT/b4h.bash"
    echo "alias ll='ls -l'"
    echo "cd $d/work"
  } >"$d/rc"
  : >"$d/hist"
}

# run_screen NAME EDITOR STEP... : run the keys (each STEP one string;
# RC=FILE: another rc file; CPR=1: the terminal answers ESC[6n;
# "@N" waits N tenths of a second; "!CMD" runs CMD beside the shell, as
# another terminal would), keep the screen as text.
run_screen() {
  local name=$1 e=$2; shift 2
  local d=$T/$e out=$T/out/$name-$e steps k
  mkdir -p "$T/out"
  steps='[{"wait": 4}'
  for k in "$@"; do
    if [[ $k == @* ]]; then
      steps+=', {"wait": '"$(( ${k#@} / 10 )).$(( ${k#@} % 10 ))"'}'
    elif [[ $k == !* ]]; then
      steps+=', {"sh": '"$(jq -Rn --arg c "${k#!}" '$c')"'}, {"wait": 1}'
    elif [[ $k == '\x00' ]]; then
      # Ctrl+Space: a NUL byte, which a bash variable cannot hold
      steps+=', {"keys": "\u0000"}, {"wait": 0.6}'
    else
      steps+=', {"keys": '"$(jq -Rn --arg k "$(printf '%b' "$k")" '$k')"'}, {"wait": 0.6}'
    fi
  done
  steps+=', {"wait": 1}, {"snap": "screen"}, {"keys": "\u0003exit\r"}, {"wait": 1}]'
  printf '{"cmd": ["bash", "--rcfile", "%s", "-i"], "rows": 30, "cols": 100, "answer_cpr": %s, "env": {"TERM": "xterm-256color", "LANG": "C.UTF-8", "COLORTERM": "", "HOME": "%s"}, "steps": %s}\n' \
    "${RC:-$d/rc}" "$([[ -n ${CPR-} ]] && echo true || echo false)" "$HOME" "$steps" >"$out.json"
  rm -rf "$out"
  tui-capture "$out.json" "$out" >/dev/null 2>&1
  jq -r '.grid[] | map(.[0]) | join("") | sub(" +$"; "")' "$out/screen.json" >"$out.txt" 2>/dev/null
  SCREEN=$(<"$out.txt")
}

# run_raw NAME EDITOR KEYS... : the same in `script`, the raw output kept
run_raw() {
  local name=$1 e=$2; shift 2
  local d=$T/$e out=$T/out/$name-$e.raw k
  mkdir -p "$T/out"
  {
    sleep 4
    for k in "$@"; do
      if [[ $k == @* ]]; then sleep "$(( ${k#@} / 10 )).$(( ${k#@} % 10 ))"
      else printf '%b' "$k"; sleep 0.6; fi
    done
    sleep 1; printf 'exit\r'; sleep 1
  } | env TERM=xterm-256color LANG=C.UTF-8 \
      script -qfec "stty cols 100 rows 30; bash --rcfile $d/rc -i" "$out" >/dev/null 2>&1
  RAW=$(<"$out")
}

check() {     # check NAME CONDITION-RESULT(0/1) WHAT
  if (( $2 == 0 )); then pass=$((pass + 1)); printf '  ok    %s\n' "$1"
  else fail=$((fail + 1)); failed+=("$1"); printf '  FAIL  %s: %s\n' "$1" "$3"; fi
}
has()    { [[ $SCREEN == *"$1"* ]]; }
hasnot() { [[ $SCREEN != *"$1"* ]]; }
want()   { [[ -z $FILTER || $1 == *"$FILTER"* ]]; }

# --------------------------------------------------------------- the cases ---
for e in ble readline; do
  mk_env "$e"
  d=$T/$e
  echo "== $e"

  if want alt-j; then
    run_screen alt-j "$e" 'echo gone-1' '\ej' 'echo kept-1\r'
    has 'kept-1' && ! grep -qx 'gone-1' <<<"$SCREEN"; check "alt-j $e" $? 'line not cleared'
  fi

  if want alt-o; then
    # stash, the line is empty, run another command, Up Up brings it back
    run_screen alt-o "$e" 'echo stashed-2' '\eo' 'echo other-2\r' '\e[A' '\e[A' '\r'
    grep -qx 'other-2' <<<"$SCREEN" && grep -qx 'stashed-2' <<<"$SCREEN"
    check "alt-o $e" $? 'stashed line not back with Up'
  fi

  if want ctrl-space && [[ $e == ble || $e == readline ]]; then
    run_screen ctrl-space-glob "$e" 'cd files\r' 'echo a*' '\x00' '\r'
    has 'echo a1.txt a2.txt' && grep -qx 'a1.txt a2.txt' <<<"$SCREEN"
    check "ctrl-space glob $e" $? 'glob not expanded'
    run_screen ctrl-space-quote "$e" 'cd files\r' 'ls b*' '\x00'
    has 'ls b\ 3.txt'; check "ctrl-space quoting $e" $? 'match not quoted'
    run_screen ctrl-space-var "$e" 'echo $HOME/x' '\x00'
    has "echo $HOME/x"; check "ctrl-space \$HOME $e" $? 'variable not expanded'
    run_screen ctrl-space-tilde "$e" 'echo ~/y' '\x00'
    has "echo $HOME/y"; check "ctrl-space ~ $e" $? 'tilde not expanded'
    run_screen ctrl-space-alias "$e" 'll' '\x00'
    has '❯  ls -l'; check "ctrl-space alias $e" $? 'alias not expanded'
    run_screen ctrl-space-subst "$e" 'echo $(date)' '\x00'
    has 'echo $(date)'; check "ctrl-space leaves \$(...) $e" $? 'command substitution touched'
  fi

  if want shell-word; then
    run_screen shell-word-left "$e" 'echo /usr/local/bin' '\e[1;6D' 'X'
    has 'echo X/usr/local/bin'; check "ctrl-shift-left $e" $? 'not a whole shell word'
    run_screen shell-word-del "$e" 'echo aa/bb cc' '\x01' '\e[1;6C' '\e[3;6~'
    has '❯  echo cc'; check "ctrl-shift-right + delete $e" $? 'shell word not deleted'
  fi

  if want ctrl-up; then
    # prefix search: "true echo two-5" contains "echo" but does not start with it
    run_screen ctrl-up "$e" 'echo one-5\r' 'true echo two-5\r' 'echo' '\e[1;5A'
    has '❯  echo one-5'; check "ctrl-up prefix $e" $? 'not the entry starting with echo'
  fi

  if want alt-m && [[ $e == ble ]]; then
    run_screen alt-m "$e" 'echo suggested-6-long\r' 'echo sugg' '\em' '\r'
    [[ $(grep -cx 'suggested-6-long' <<<"$SCREEN") == 2 ]]; check "alt-m $e" $? 'suggestion not taken'
  fi

  if want dirhist; then
    : >"$d/home/dir-history"
    run_screen dirhist "$e" 'cd "sub one"\r' 'cd ../two\r' 'cd ..\r' 'pwd\r'
    mapfile -t l <"$d/home/dir-history"
    [[ ${l[0]-} == "$d/work" && ${l[1]-} == "$d/work/two" && ${l[2]-} == "$d/work/sub one" ]]
    check "dir-history file $e" $? "got: ${l[*]:0:3}"
    run_screen alt-r "$e" '\er' '@10' 'sub one' '@5' '\r' 'pwd\r'
    grep -qx "$d/work/sub one" <<<"$SCREEN"; check "alt-r $e" $? 'did not change directory'
    if [[ $e == ble ]]; then
      # ble.sh: a menu of the directories
      run_screen cd-dash-tab "$e" 'cd -\t' '@10' '\t' '@5'
      has "work/sub\\ one" && has "work/two"; check "cd -<Tab> $e" $? 'no history menu'
    else
      # readline: fzf picks one, the line gets it, Enter goes there
      run_screen cd-dash-tab "$e" 'cd -\t' '@10' 'sub one' '@5' '\r' '@5' '\r' 'pwd\r'
      grep -qx "$d/work/sub one" <<<"$SCREEN"; check "cd -<Tab> $e" $? 'did not go there'
    fi
  fi

  if want title; then
    run_raw title "$e" 'sleep 0.3\r' '@5'
    [[ $RAW == *$'\e]0;sleep 0.3\a'* ]]; check "title running $e" $? 'no title with the command'
    [[ $RAW == *$'\e]0;'"${d/#"$HOME"/\~}"/work$'\a'* ]]; check "title idle $e" $? 'no title with the directory'
    # a line starting with a space: ble.sh still names it; readline cannot
    # (it is not in the history), so the title stays (nothing older shown)
    run_raw title-space "$e" 'echo older-8\r' ' sleep 0.3\r' '@5'
    if [[ $e == ble ]]; then
      [[ $RAW == *$'\e]0;sleep 0.3\a'* ]]
    else
      [[ $RAW != *$'\e]0;sleep 0.3\a'* && $RAW == *$'\e]0;echo older-8\a'* &&
         $(grep -ao $'\e]0;echo older-8\a' <<<"$RAW" | wc -l) == 1 ]]
    fi
    check "title, command not in the history $e" $? 'wrong command in the title'
  fi

  if want clipboard; then
    rm -f "$d/home/clipboard"
    run_raw clipboard "$e" 'echo hi | x\r' '@3'
    [[ $RAW == *$'\e]52;c;aGkK\a'* && $(<"$d/home/clipboard") == hi ]]
    check "x (OSC 52 + file) $e" $? 'no OSC 52 or file'
    run_screen clipboard-v "$e" 'echo pasted-7 | c\r' 'v | tr a-z A-Z\r'
    grep -qx 'pasted-7' <<<"$SCREEN" && grep -qx 'PASTED-7' <<<"$SCREEN"
    check "c, v $e" $? 'copy/paste round trip'
  fi

  if want local-history && [[ $e == ble ]]; then
    # One entry at start; "another shell" adds one while this one runs; this
    # shell runs its own. Up: own, then the start-up one (the other shell's
    # passed over). Ctrl+Up: own, then the other shell's.
    printf '#1700000000\necho start-9\n' >"$d/hist"
    run_screen local-history "$e" '@10' "!printf '#1700000100\\necho foreign-9\\n' >> $d/hist" \
      'echo own-9\r' '@10' '\e[A' '\e[A'
    last=$(grep '❯' <<<"$SCREEN" | tail -1)
    ok=1; [[ $last == *'echo start-9'* ]] && ok=0
    check "local history: Up skips other shells $e" "$ok" "$last"
    printf '#1700000000\necho start-9\n' >"$d/hist"
    run_screen global-history "$e" '@10' "!printf '#1700000100\\necho foreign-9\\n' >> $d/hist" \
      'echo own-9\r' '@10' '\e[1;5A' '\e[1;5A'
    last=$(grep '❯' <<<"$SCREEN" | tail -1)
    ok=1; [[ $last == *'echo foreign-9'* ]] && ok=0
    check "global history: Ctrl+Up has all $e" "$ok" "$last"
  fi

  if want repos && [[ $e == readline ]]; then
    # b4h install/load/source/update/uninstall against a local git
    # repository standing in for GitHub (B4H_GIT_BASE=file://...).
    g=$T/git/demo/hello
    git init -q -b main "$g"
    mkdir -p "$g/bin" "$g/lib"
    printf 'hello_b4h() { echo hello-v1; }\n' >"$g/hello.plugin.bash"
    printf '#!/bin/sh\necho greet-ok\n' >"$g/bin/greet"; chmod +x "$g/bin/greet"
    printf 'extra_b4h=sourced-ok\n' >"$g/lib/extra.bash"
    git -C "$g" add -A && git -C "$g" -c user.name=t -c user.email=t@t commit -qm v1
    repo_run() { env -i HOME="$HOME" PATH="$PATH" TERM=xterm B4H_GIT_BASE="file://$T/git" \
                   bash --rcfile "$d/rc" -i -c "$1" 2>&1 </dev/null; }
    r=$(repo_run 'b4h install demo/hello >/dev/null && b4h load demo/hello && hello_b4h && greet && b4h source demo/hello/lib/extra.bash && echo "$extra_b4h"')
    ok=1; [[ $r == *hello-v1*greet-ok*sourced-ok* ]] && ok=0
    check "b4h install, load, bin/, source $e" "$ok" "$r"
    printf 'hello_b4h() { echo hello-v2; }\n' >"$g/hello.plugin.bash"
    git -C "$g" -c user.name=t -c user.email=t@t commit -qam v2
    r=$(repo_run 'b4h install demo/hello; b4h update 2>/dev/null | grep demo/hello; b4h load demo/hello && hello_b4h')
    ok=1; [[ $r == *'demo/hello '*' -> '*hello-v2* ]] && ok=0
    check "b4h update follows the branch $e" "$ok" "$r"
    r=$(repo_run 'b4h install demo/missing; echo "rc=$?"; b4h install demo/missing; echo "rc=$?"')
    ok=1; [[ $r == *'could not be downloaded'*'rc=1'*'rc=1' && $(grep -c 'could not' <<<"$r") == 1 ]] && ok=0
    check "b4h install: a failed download is remembered $e" "$ok" "$r"
    r=$(repo_run 'b4h uninstall demo/hello >/dev/null; b4h load demo/hello')
    ok=1; [[ $r == *'not installed'* && ! -d $d/home/repos/demo/hello ]] && ok=0
    check "b4h uninstall $e" "$ok" "$r"
  fi

  if want ssh && [[ $e == ble ]]; then
    # A stand-in for ssh runs the "remote" commands here with HOME=$T/remote
    # (CI has no ssh server): plain `ssh other` passes through; `ssh -p 2222
    # box.lab` (B4H_SSH_HOSTS) teleports, keeps the session's history in the
    # host's bash4humans-ssh.history and brings it back afterwards.
    mkdir -p "$T/fakebin" "$T/remote"
    cat >"$T/fakebin/ssh" <<'FAKE'
#!/bin/bash
# stand-in for ssh: options skipped, then HOST, then the remote command
while [[ $1 == -* ]]; do
  case $1 in -[BbcDEeFIiJLlmOopQRSWw]) shift ;; esac
  shift
done
host=$1; shift
if (( ! $# )); then echo "PLAIN-SSH $host"; exit 0; fi
HOME=$FAKE_REMOTE exec sh -c "$*"
FAKE
    chmod +x "$T/fakebin/ssh"
    # As the real ~/.bashrc: bash4humans from $B4H_HOME/b4h, so the host runs
    # the uploaded copy, not this checkout
    ln -sfn "$ROOT" "$d/home/b4h"
    sed -e "s|^B4H_HOME=.*|B4H_HOME=\${B4H_HOME:-$d/home}|" -e "s|^HISTFILE=.*|HISTFILE=\${HISTFILE:-$d/hist}|" \
        -e "s|^\. $ROOT/b4h.bash\$|. \"\\\$B4H_HOME/b4h/b4h.bash\"|" "$d/rc" >"$d/rc-ssh"
    sed -i "1i B4H_SSH_HOSTS=('*.lab'); B4H_SSH_RETRIEVE_HISTORY=$d/remote-hist; B4H_RCFILE=$d/rc-ssh; PATH=$T/fakebin:\$PATH; export FAKE_REMOTE=$T/remote" "$d/rc-ssh"
    # Per host: TERM, a file brought back, a configure hook with a prelude.
    # The shell's own HOME is a directory of its own here, so ~/notes.txt is
    # $d/localhome/notes.txt here and $T/remote/notes.txt on the "host".
    mkdir -p "$d/localhome"
    {
      echo "HOME=$d/localhome"
      echo "B4H_SSH_TERM=('*.lab=screen-256color')"
      echo "B4H_SSH_RETRIEVE_FILES=('~/notes.txt')"
      echo 'b4h_ssh_configure() { B4H_SSH_PRELUDE+=("export HOOK_HOST=$1"); }'
    } >>"$d/rc-ssh"
    rm -f "$d/remote-hist" "$d/localhome/notes.txt" "$T/remote/notes.txt"
    RC=$d/rc-ssh run_screen ssh "$e" 'ssh other\r' '@10' 'ssh -p 2222 box.lab\r' '@80' \
      'echo "remote=$B4H_HOME hist=$HISTFILE"\r' '@10' 'echo marker-77\r' '@10' \
      'echo "term=$TERM hook=$HOOK_HOST"; echo note-55 >~/notes.txt\r' '@10' 'exit\r' '@30'
    has 'PLAIN-SSH other'; check "ssh: other hosts unchanged $e" $? 'no plain ssh'
    # (the line is longer than the screen: compare with the wrapped rows joined)
    ok=1; [[ ${SCREEN//$'\n'/} == *"remote=$T/remote/.cache/bash4humans-ssh hist=$T/remote/.cache/bash4humans-ssh.history"* ]] && ok=0
    check "ssh: a B4H_SSH_HOSTS host teleports $e" "$ok" 'no bash4humans on the host'
    ok=1; grep -qx 'echo marker-77' "$d/remote-hist" 2>/dev/null && ! grep -q marker-77 "$d/hist" && ok=0
    check "ssh: the session's history comes back $e" "$ok" "$(cat "$d/remote-hist" 2>&1)"
    has 'term=screen-256color hook=box.lab'; check "ssh: B4H_SSH_TERM and the configure hook $e" $? 'TERM or prelude not set there'
    ok=1; [[ $(cat "$d/localhome/notes.txt" 2>/dev/null) == note-55 ]] && ok=0
    check "ssh: B4H_SSH_RETRIEVE_FILES brings ~/notes.txt back $e" "$ok" "$(ls "$d/localhome" 2>&1)"
  fi

  if want fzf-tab && [[ $e == ble ]]; then
    # B4H_TAB=fzf: Ctrl+A marks every file, Enter inserts them all, quoted;
    # a single Enter inserts the entry under the cursor (ble.sh's own way).
    { echo 'B4H_TAB=fzf'; cat "$d/rc"; } >"$d/rc-fzf"
    RC=$d/rc-fzf run_screen fzf-tab-all "$e" 'cd files\r' 'ls ' '\t' '@20' '\x01' '\r' '@10'
    last=$(grep '❯' <<<"$SCREEN" | tail -1)
    ok=1; [[ $last == *'ls a1.txt a2.txt b\ 3.txt'* ]] && ok=0
    check "fzf Tab: Ctrl+A inserts every pick $e" "$ok" "$last"
    RC=$d/rc-fzf run_screen fzf-tab-one "$e" 'cd files\r' 'ls ' '\t' '@20' '\r' '@10'
    last=$(grep '❯' <<<"$SCREEN" | tail -1)
    ok=1; [[ $last =~ ls\ (a1|a2)\.txt\ *$|ls\ b\\\ 3\.txt\ *$ ]] && ok=0
    check "fzf Tab: Enter inserts one $e" "$ok" "$last"
  fi

  if want clear; then
    # Ctrl+L: the screen is cleared, the line kept; the prompt on the first
    # row, or with B4H_PROMPT_AT_BOTTOM=yes on the last (also at start, when
    # the terminal says where the cursor is).
    run_screen clear-top "$e" 'seq 1 60\r' '@5' 'typed-8' '\x0c' '@5'
    ok=1; [[ $(head -1 <<<"$SCREEN") == *'typed-8'* && $SCREEN != *$'\n'58$'\n'* ]] && ok=0
    check "Ctrl+L: prompt on top $e" "$ok" "$(head -1 <<<"$SCREEN")"
    { echo 'B4H_PROMPT_AT_BOTTOM=yes'; cat "$d/rc"; } >"$d/rc-bottom"
    RC=$d/rc-bottom CPR=1 run_screen bottom-start "$e" '@5'
    ok=1; [[ $(sed -n 30p "$T/out/bottom-start-$e.txt") == *'❯'* ]] && ok=0
    check "prompt at bottom: at start $e" "$ok" "$(grep -n '❯' "$T/out/bottom-start-$e.txt" | tail -1)"
    RC=$d/rc-bottom CPR=1 run_screen bottom-clear "$e" 'echo top-9\r' '@5' 'typed-9' '\x0c' '@5'
    ok=1; [[ $(sed -n 30p "$T/out/bottom-clear-$e.txt") == *'typed-9'* && $SCREEN != *top-9$'\n'* ]] && ok=0
    check "prompt at bottom: Ctrl+L $e" "$ok" "$(grep -n 'typed-9' "$T/out/bottom-clear-$e.txt")"
  fi

  if want locale; then
    # The shell started with a clean environment (no terminal needed: the fix
    # runs before the line editor); "é" is one character only in UTF-8.
    probe='x=$'"'"'\xc3\xa9'"'"'; echo "chars=${#x} lc_all=${LC_ALL-unset} fixed=${_b4h_locale_fixed-}"'
    locale_run() { env -i HOME="$HOME" PATH="$PATH" TERM=xterm "$@" bash --rcfile "$d/rc" -i -c "$probe" 2>/dev/null </dev/null | tail -1; }
    r=$(locale_run)
    ok=1; [[ $r == "chars=1 "* && $r != *fixed= ]] && ok=0
    check "locale: none set -> UTF-8 $e" "$ok" "$r"
    r=$(locale_run LANG=C.UTF-8)
    ok=1; [[ $r == "chars=1 lc_all=unset fixed=" ]] && ok=0
    check "locale: UTF-8 left alone $e" "$ok" "$r"
    r=$(locale_run LANG=C B4H_FIX_LOCALE=no)
    ok=1; [[ $r == "chars=2 lc_all=unset fixed=" ]] && ok=0
    check "locale: B4H_FIX_LOCALE=no $e" "$ok" "$r"
  fi
done

echo
echo "features: $pass passed, $fail failed${failed:+ (${failed[*]})}   (screens in $T/out)"
(( fail == 0 ))
