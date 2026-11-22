#!/bin/bash
# tests/p10k/wizard.sh [FILTER] : `p10k configure` in bash against p10k's own
# wizard. Both are driven with the same keys; the screen after every key is
# compared cell by cell (character, foreground, background, bold), and so are
# the configurations they write: p10k's file with the bash wizard's p10k-form
# file (_P9K_WIZARD_KEEP_ZSH), first line (the date) aside.
# Both write to the same path, moved away after each run, so that the screens
# that show the path are the same. The bash side runs with B4H_VERSION set:
# the wizard then never offers to edit ~/.bashrc (as p10k inside zsh4humans).
T=${B4H_TEST_DIR:-/tmp/b4h-test}; W=$T/wizard; mkdir -p "$W/zdot" "$W/cfg" "$W/out"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
. "$root/tests/p10k/wizard-keys.sh"
cfg=$W/cfg/p10k.cfg
tool=$(type -P b4h-tool) || tool=$HOME/.cache/bash4humans/deps/bin/b4h-tool
pause=${WIZARD_PAUSE:-1.2}

# zsh: no automatic wizard; the rc file already sources the config and has
# the instant-prompt lines, so the wizard does not offer to edit it.
{ printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n'
  printf 'POWERLEVEL9K_CONFIG_FILE=%q\n' "$cfg"
  printf 'if false; then\n  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%%):-%%n}.zsh"\nfi\n'
  printf 'source %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme"
  printf '[[ ! -f $POWERLEVEL9K_CONFIG_FILE ]] || source $POWERLEVEL9K_CONFIG_FILE\n'; } >"$W/zdot/.zshrc"
# bash: the same (the port, as p10k, starts the wizard at the first prompt
# when no POWERLEVEL9K_* setting exists)
{ printf 'POWERLEVEL9K_DISABLE_CONFIGURATION_WIZARD=true\n'
  printf 'POWERLEVEL9K_CONFIG_FILE=%q\n' "$cfg"
  printf '. %q\np10k_init\n' "$root/lib/p10k/main.bash"; } >"$W/bashrc"
# the same under ble.sh (ble=1), set up as golden.sh does: no colouring or
# suggestions of the typed line (zsh here has neither)
ble=$HOME/.cache/bash4humans/deps/ble.sh/ble.sh
{ printf '. %q --attach=none --norc\n' "$ble"
  cat "$W/bashrc"
  echo 'bleopt highlight_syntax= highlight_filename= highlight_variable= complete_auto_complete='
  echo '[[ ${BLE_VERSION-} ]] && ble-attach'; } >"$W/bashrc.ble"

# NAME|OPTIONS (wizard-keys.sh)
cases=(
  "L1|style=lean time=2 lines=2 gap=3 frame=4 orn=1 spacing=2 icons=2 flow=2"
  "L2|style=lean lines=1 icons=1 flow=1 transient=y instant=2"
  "L3|style=lean colors=2 lines=2 gap=2 frame=2 orn=3 instant=3"
  "L4|style=lean charset=2 lines=2 gap=3"
  "L5|style=lean lines=2 gap=1 frame=3 orn=4 padding=n time=1"
  "C1|style=classic color=1 sep=1 head=3 tail=1 lines=2 gap=1 frame=1"
  "C2|style=classic color=2 sep=2 head=1 tail=2 lines=2 gap=2 frame=2 icons=2 flow=2"
  "C3|style=classic color=3 sep=3 head=4 tail=4 lines=1"
  "C4|style=classic color=4 sep=4 head=5 tail=5 lines=2 gap=3 frame=4 spacing=2 time=2"
  "C5|style=classic charset=2 lines=2 gap=3"
  "R1|style=rainbow sep=1 head=3 tail=1 lines=2 gap=1 frame=1 icons=2 flow=2"
  "R2|style=rainbow sep=3 head=4 tail=4 lines=1 icons=1"
  "R3|style=rainbow sep=4 head=5 tail=5 lines=2 gap=2 frame=2 orn=3"
  "R4|style=rainbow sep=2 head=2 tail=3 lines=2 gap=3 frame=3 orn=4 padding=n transient=y"
  "R5|style=rainbow charset=2 lines=1"
  "P1|style=pure rprompt=1 lines=2 spacing=2"
  "P2|style=pure rprompt=2 time=2 lines=1"
  "P3|style=pure rprompt=2 lines=2 time=1"
  "F1|arrow=n arrow2=y style=rainbow sep=3 head=4 tail=5 lines=2 gap=1 frame=4"
  "F2|arrow=n arrow2=n python=n style=classic lines=1 icons=2"
  "F3|diamond=n style=rainbow lines=2 gap=2 frame=2 orn=2 icons=2"
  "F4|lock=n lock2=y style=classic head=2 tail=2 lines=1"
  "F5|lock=n lock2=n style=rainbow lines=2 gap=3 frame=4"
  "F6|diamond=n lock=n lock2=n quotes=y style=lean lines=2 gap=2 frame=4"
  "F7|diamond=n lock=n lock2=n quotes=n style=classic lines=2 gap=2"
  "F8|width=2 arrow2=y style=lean lines=1"
  # true colour: Pure asks Original / Snazzy
  "T1|tc=1 style=pure colors=1 rprompt=1 lines=2"
  "T2|tc=1 style=pure colors=2 rprompt=2 time=2 lines=1 spacing=2"
  "T3|tc=1 style=rainbow lines=2 gap=2 frame=4 orn=2"
  # an existing config: Overwrite? y (and the backup line, its name random, aside)
  "O1|pre=cfg style=lean lines=1"
  # quit, and restart from the beginning
  "Q1|raw=yyq"
  "Q2|raw=yy1y11q"
  "Q3|raw=yyr|style=lean lines=1"
  # small terminals: widget passes drop previews ("not enough vertical space
  # to display this"), previews lose their indent or give up ("not enough
  # horizontal space"), text flows to the narrower width
  "S1|rows=24 cols=80 style=rainbow lines=2 gap=2 frame=4 orn=2"
  "S2|rows=14 cols=47 style=classic sep=3 head=4 tail=4 lines=2 gap=3 frame=4"
  # (70, not 60, columns: at 60 the typed `p10k configure` reaches the right
  # prompt; zsh then hides it, plain readline cannot — S7 is 60 under ble.sh)
  "S3|rows=20 cols=70 style=lean lines=2 gap=3 frame=4 time=2"
  "S4|rows=30 cols=50 style=pure rprompt=2 lines=2 time=1"
  # below the minimum (47 x 14): p10k configure refuses to start. (44, not
  # 46, columns: with 45 characters typed into 46 columns zle wraps the line
  # early, readline does not — the line editors differ, not the wizards)
  "S5|rows=13 cols=80 nokeys=1"
  "S6|rows=40 cols=44 nokeys=1"
  "S7|ble=1 rows=20 cols=60 style=lean lines=2 gap=3 frame=4 time=2"
  # 8 colours: lean_8colors without asking for a style or colours
  "E1|term=xterm lines=2 gap=2 frame=4 orn=3 time=2"
  "E2|term=xterm lines=1 charset=2"
  "E3|term=xterm diamond=n lock=n lock2=n quotes=y lines=2 gap=3 frame=2 orn=4"
  # bash under ble.sh: `p10k configure` typed into ble.sh, then its new prompt
  "B1|ble=1 style=rainbow lines=2 gap=2 frame=4 orn=2 transient=y"
  "B2|ble=1 style=lean lines=1 time=2"
)
# OPTIONS besides wizard-keys.sh's: tc=1 (COLORTERM=truecolor), pre=cfg (a
# config exists first), raw=KEYS (these keys first; then the options' keys,
# if a second |OPTIONS part follows, else nothing more), rows=N cols=N
# (terminal size, default 50 x 100), term=NAME (TERM; xterm has 8 colours),
# ble=1 (bash under ble.sh), nokeys=1 (no key at all: the wizard does not
# start, no config is written)

# run SHELL ID KEYS: drive one wizard, one snapshot per key -> $W/out/ID.SHELL/
run() {
  local sh=$1 id=$2 keys=$3 i c steps cmd
  steps='[{"wait": 3}, {"keys": "p10k configure\r"}, {"wait": 2.5}, {"snap": "s00"}'
  local w
  for (( i = 0; i < ${#keys}; i++ )); do
    c=${keys:i:1}
    printf -v n '%02d' $(( i + 1 ))
    # after the last key: the config is written (and converted) and loaded
    w=$pause; (( i == ${#keys} - 1 )) && w=4
    steps+=', {"keys": "'$c'"}, {"wait": '$w'}, {"snap": "s'$n'"}'
  done
  steps+=', {"wait": 1}, {"snap": "end"}, {"keys": "exit\r"}, {"wait": 1}]'
  if [[ $sh == zsh ]]; then cmd='["zsh", "-i"]'
  else
    # an empty history, as zsh has here (the prompt shows the history number)
    : >"$W/bash_history"
    local rc=$W/bashrc; [[ -n ${BLE-} ]] && rc=$W/bashrc.ble
    cmd='["env", "B4H_VERSION=test", "HISTFILE='$W/bash_history'", "_P9K_WIZARD_KEEP_ZSH='$W/out/$id.port.zsh'", "bash", "--rcfile", "'$rc'", "-i"]'
  fi
  # COLORTERM always given: this environment's own would otherwise be inherited
  local ct=''; [[ -n ${TRUECOLOR-} ]] && ct=truecolor
  printf '{"cmd": %s, "rows": %d, "cols": %d, "env": {"TERM": "%s", "LANG": "en_GB.UTF-8", "ZDOTDIR": "%s", "COLORTERM": "%s"}, "steps": %s}\n' \
    "$cmd" "$ROWS" "$COLS" "$TERMV" "$W/zdot" "$ct" "$steps" >"$W/out/$id.$sh.json"
  rm -f -- "$cfg"
  [[ -n ${PRE_CFG-} ]] && printf '# an older config\n' >"$cfg"
  rm -rf "$W/out/$id.$sh"; (cd /tmp && tui-capture "$W/out/$id.$sh.json" "$W/out/$id.$sh" >/dev/null 2>&1)
  [[ -f $cfg ]] && mv -f -- "$cfg" "$W/out/$id.$sh.cfg"
}

cells() {  # screen.json -> one line per cell (rows naming a random backup file left out)
  local skip
  skip=$(jq -r '.grid | to_entries[] | select((.value | map(.[0]) | join("")) | test("Backup of the old config")) | .key' "$1" | tr '\n' ' ')
  jq -c --arg skip " $skip" '.grid | to_entries[] | .key as $r | select(($skip | contains(" \($r) ")) | not)
      | .value | to_entries[] | [$r, .key, .value[0], .value[1], .value[2], .value[3]]' "$1" |
    sed 's/^\(\[[0-9]*,[0-9]*,"\)[0-9]"/\1#"/'   # the clock in the final prompt
}

pass=0 fail=0
for c in "${cases[@]}"; do
  id=${c%%|*} opts=${c#*|}
  [[ -n ${1-} && $id != *$1* ]] && continue
  # this harness's own options
  TRUECOLOR='' PRE_CFG='' raw='' expect_cfg=1 rest='' nokeys=''
  ROWS=50 COLS=100 TERMV=xterm-256color BLE='' COLORS8=''
  more=''; [[ $opts == *'|'* ]] && { more=${opts#*|}; opts=${opts%%|*}; }
  for o in $opts; do
    case $o in
      tc=1) TRUECOLOR=1 ;;
      pre=cfg) PRE_CFG=1 ;;
      raw=*) raw=${o#raw=} ;;
      rows=*) ROWS=${o#rows=} ;;
      cols=*) COLS=${o#cols=} ;;
      term=*) TERMV=${o#term=} ;;
      ble=1) BLE=1 ;;
      nokeys=1) nokeys=1 ;;
      *) rest+=" $o" ;;
    esac
  done
  [[ $(TERM=$TERMV tput colors 2>/dev/null) -lt 256 ]] && COLORS8=1
  export TRUECOLOR COLORS8
  rm -f -- "$W/out/$id".*.cfg "$W/out/$id.port.zsh" "$W/out/$id.conv.bash"
  if [[ -n $nokeys ]]; then keys='' expect_cfg=0
  elif [[ -n $raw ]]; then
    keys=$raw
    if [[ -n $more ]]; then wizard_keys $more; keys+=$REPLY; else expect_cfg=0; fi
  else
    wizard_keys $rest; keys=$REPLY
    [[ -n $PRE_CFG ]] && keys+=y   # "Overwrite ...?" comes after the last question
  fi
  run zsh "$id" "$keys"
  run bash "$id" "$keys"
  bad=''
  for f in "$W/out/$id.zsh/"*.json; do
    s=${f##*/}
    if [[ ! -f $W/out/$id.bash/$s ]]; then bad+=" ${s%.json}(missing)"; continue; fi
    cmp -s <(cells "$f") <(cells "$W/out/$id.bash/$s") || bad+=" ${s%.json}"
  done
  # the configurations: p10k's and the bash wizard's p10k form, date line aside
  if (( ! expect_cfg )); then
    [[ $(cat "$W/out/$id.zsh.cfg" 2>/dev/null) == "$(cat "$W/out/$id.bash.cfg" 2>/dev/null)" ]] || bad+=" cfg(left behind)"
  elif [[ ! -f $W/out/$id.zsh.cfg ]]; then bad+=" cfg(zsh:none)"
  elif [[ ! -f $W/out/$id.port.zsh ]]; then bad+=" cfg(port:none)"
  elif ! cmp -s <(sed 1d "$W/out/$id.zsh.cfg") <(sed 1d "$W/out/$id.port.zsh"); then bad+=" cfg"
  fi
  (( ! expect_cfg )) || [[ -f $W/out/$id.bash.cfg ]] || bad+=" cfg(bash:none)"
  # the bash config, written without a converter, against p10k's config
  # converted by b4h-tool (the date line, the third, aside)
  if (( expect_cfg )) && [[ -f $W/out/$id.zsh.cfg && -f $W/out/$id.bash.cfg ]]; then
    "$tool" p10k-config "$W/out/$id.zsh.cfg" "$W/out/$id.conv.bash" >/dev/null 2>&1 || bad+=" cfg-bash(convert)"
    cmp -s <(sed 3d "$W/out/$id.conv.bash") <(sed 3d "$W/out/$id.bash.cfg") || bad+=" cfg-bash"
  fi
  if [[ -z $bad ]]; then (( pass++ )); echo "SAME  $id  keys=$keys"
  else (( fail++ )); echo "DIFF  $id  keys=$keys :$bad"
  fi
done
echo "same: $pass   different: $fail"
