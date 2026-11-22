# =============================================================================
#  lib/fish.bash - features borrowed from fish that neither bash nor zsh has.
#
#    abbr          abbreviations that expand as you type (fish syntax)
#    funced NAME   edit a function in $EDITOR; funcsave NAME keeps it for good
#    add_path DIR  add to PATH once, optionally for good (fish_add_path)
#    histdel TEXT  delete history entries containing TEXT
#    Alt+S         put sudo in front of the line (or the last command), or take it off
#    Alt+H         manual page for the command being typed
# =============================================================================

_b4h_conf=${XDG_CONFIG_HOME:-$HOME/.config}/bash4humans

# ------------------------------------------------------------------ abbr ---
# abbr -a NAME EXPANSION...             expand NAME where a command goes
# abbr -a --position anywhere NAME ...  expand NAME anywhere (like zsh's alias -g)
# abbr -e NAME                          erase;   abbr / abbr -l   list
#
# With ble.sh the expansion happens on Space or Enter and is visible, so the
# history holds the real command. With plain readline, command-position
# abbreviations become aliases (same effect, not visible).
declare -gA _b4h_abbr=() _b4h_abbr_pos=()

abbr() {
  local mode=add pos=command name
  while (( $# )); do
    case $1 in
      -a|--add)       mode=add ;;
      -e|--erase)     mode=erase ;;
      -l|--list|-s|--show) mode=list ;;
      -p|--position)  pos=$2; shift ;;
      --position=*)   pos=${1#*=} ;;
      -h|--help)      sed -n '/^# abbr -a NAME/,/^# history holds/p' "$B4H_ROOT/lib/fish.bash" | sed 's/^# \{0,1\}//'; return 0 ;;
      --) shift; break ;;
      -*) echo "abbr: unknown option $1" >&2; return 2 ;;
      *)  break ;;
    esac
    shift
  done
  if [[ $mode == add && $# -eq 0 ]]; then mode=list; fi

  case $mode in
    list)
      for name in "${!_b4h_abbr[@]}"; do
        if [[ ${_b4h_abbr_pos[$name]} == anywhere ]]; then
          printf 'abbr -a --position anywhere %s %q\n' "$name" "${_b4h_abbr[$name]}"
        else
          printf 'abbr -a %s %q\n' "$name" "${_b4h_abbr[$name]}"
        fi
      done | sort
      ;;
    erase)
      for name; do
        unset "_b4h_abbr[$name]" "_b4h_abbr_pos[$name]"
        if (( _b4h_ble )); then ble-sabbrev -r "$name" 2>/dev/null; else unalias "$name" 2>/dev/null; fi
      done
      ;;
    add)
      name=$1; shift
      (( $# )) || { echo "abbr: $name: missing expansion" >&2; return 2; }
      [[ $pos == command || $pos == anywhere ]] || { echo "abbr: --position is command or anywhere" >&2; return 2; }
      _b4h_abbr[$name]="$*"
      _b4h_abbr_pos[$name]=$pos
      if (( _b4h_ble )); then
        ble-sabbrev "$name=$*"     # position is enforced by _b4h_abbr_guard
      else
        alias "$name=$*"
        [[ $pos == anywhere ]] && echo "abbr: '$name' works in command position only without ble.sh" >&2
      fi
      ;;
  esac
}

# ble.sh expands its word abbreviations wherever the word stands. This
# wraps its expand function: a command-position abbreviation is declined
# unless the word starts the line or follows | ; & ( { or sudo.
_b4h_abbr_guard() {
  local before=${_ble_edit_str:0:_ble_edit_ind} word
  word=${before##*[[:space:]\;\|\&\(\{]}
  before=${before%"$word"}
  before=${before%"${before##*[![:space:]]}"}               # trim trailing spaces
  if [[ -n $word && ${_b4h_abbr_pos[$word]-} == command ]] &&
     ! [[ -z $before || $before == *[\|\;\&\(\{] || $before == sudo || $before == *[[:space:]\;\|\&]sudo ]]; then
    ADVICE_EXIT=1                                          # not here: leave the word alone
    return
  fi
  ble/function#advice/do
}
if (( _b4h_ble )); then
  blehook/eval-after-load complete 'ble/function#advice around ble/complete/sabbrev/expand _b4h_abbr_guard'
  bleopt edit_magic_accept=sabbrev:verify-syntax           # Enter expands too, as in fish
fi

# -------------------------------------------------------- funced/funcsave ---
# funced NAME: edit NAME (new or existing) in $EDITOR; it is loaded into
# this shell when the editor closes. funcsave NAME: keep it for every
# future shell (in ~/.config/bash4humans/functions). funcsave -e NAME: forget it.
funced() {
  local name=${1:?usage: funced NAME} tmp
  tmp=$(mktemp --suffix=.bash) || return
  if declare -F "$name" >/dev/null; then
    declare -f "$name" >"$tmp"
  elif [[ -r $_b4h_conf/functions/$name.bash ]]; then
    cat -- "$_b4h_conf/functions/$name.bash" >"$tmp"
  else
    printf '%s() {\n  \n}\n' "$name" >"$tmp"
  fi
  "${VISUAL:-${EDITOR:-nano}}" "$tmp"
  # Learner note for shell: `source` runs the file in *this* shell, so the
  # function it defines stays defined after funced returns.
  if bash -n "$tmp"; then
    source "$tmp"
    echo "funced: $name loaded; funcsave $name to keep it"
  else
    echo "funced: syntax error; nothing loaded (draft kept in $tmp)" >&2
    return 1
  fi
  rm -f -- "$tmp"
}

funcsave() {
  if [[ $1 == -e ]]; then
    shift
    rm -f -- "$_b4h_conf/functions/${1:?usage: funcsave -e NAME}.bash" && echo "funcsave: $1 removed"
    return
  fi
  local name
  for name; do
    declare -F "$name" >/dev/null || { echo "funcsave: $name: no such function" >&2; return 1; }
    mkdir -p -- "$_b4h_conf/functions"
    declare -f "$name" >"$_b4h_conf/functions/$name.bash"
    echo "funcsave: $name saved"
  done
}
complete -A function funced funcsave

# --------------------------------------------------------------- add_path ---
# add_path [-a] [-P] DIR...  -a: append instead of prepend; -P: also for
# every future shell (stored in ~/.config/bash4humans/path).
add_path() {
  local append=0 persist=0 d
  while [[ $1 == -* ]]; do
    case $1 in -a) append=1 ;; -P) persist=1 ;; *) echo "add_path: unknown option $1" >&2; return 2 ;; esac
    shift
  done
  for d; do
    d=$(realpath -m -- "$d")
    [[ -d $d ]] || { echo "add_path: $d: not a directory" >&2; continue; }
    if [[ ":$PATH:" != *":$d:"* ]]; then
      if (( append )); then PATH=$PATH:$d; else PATH=$d:$PATH; fi
    fi
    if (( persist )) && ! grep -qxF -- "$((append)) $d" "$_b4h_conf/path" 2>/dev/null; then
      mkdir -p -- "$_b4h_conf" && printf '%s %s\n' "$append" "$d" >>"$_b4h_conf/path"
    fi
  done
}
if [[ -r $_b4h_conf/path ]]; then
  while read -r _b4h_a _b4h_d; do
    [[ -d $_b4h_d && ":$PATH:" != *":$_b4h_d:"* ]] || continue
    if (( _b4h_a )); then PATH=$PATH:$_b4h_d; else PATH=$_b4h_d:$PATH; fi
  done <"$_b4h_conf/path"
  unset _b4h_a _b4h_d
fi
complete -d add_path

# ---------------------------------------------------------------- histdel ---
# histdel TEXT: list history entries containing TEXT, ask, then delete them
# from the history file and reload this shell's history from it. (Other
# open shells still hold their copy in memory until they are restarted.)
histdel() {
  local text=${1:?usage: histdel TEXT} answer count
  local file=${HISTFILE-}
  if [[ -z $file || $file == /dev/null ]]; then
    echo 'histdel: no history file in this shell (private mode?)' >&2
    return 1
  fi
  history -a                                   # pending entries into the file first
  count=$(grep -c -F -- "$text" "$file")
  # grep -c prints 0 and fails when nothing matches; the histdel line itself counts once
  if (( count <= 1 )) && grep -qF -- "histdel $text" "$file"; then count=0; fi
  (( count )) || { echo "histdel: nothing contains '$text'"; return 1; }
  grep -F -- "$text" "$file" | grep -v -F -- "histdel " | sed 's/^/  /'
  read -r -p 'Delete these entries? [y/N] ' answer
  [[ $answer == [yY]* ]] || return 1

  # An entry is an optional "#<time>" line plus the command's line(s);
  # drop the entries containing TEXT, and this histdel command too.
  local tmp; tmp=$(mktemp "$file.XXXXXX") || return 1
  # With timestamps, an entry runs from its "#<time>" line to the next one
  # (multi-line commands stay whole); without them, each line is an entry.
  awk -v text="$text" '
    function flush() { if (buf != "" && index(buf, text) == 0) printf "%s", buf; buf = ""; stamped = 0 }
    /^#[0-9]+$/ { flush(); buf = $0 "\n"; stamped = 1; next }
    { if (!stamped) flush(); buf = buf $0 "\n" }
    END { flush() }
  ' "$file" >"$tmp" && cat -- "$tmp" >"$file"     # cat keeps the file's owner and mode
  rm -f -- "$tmp"
  history -c
  history -r
  echo 'histdel: done'
}

# ------------------------------------------------------ line-editing keys ---
# These work on READLINE_LINE / READLINE_POINT, which both readline's
# `bind -x` and ble.sh's `ble-bind -x` provide. Bound in lib/keys.bash.

# Alt+S: toggle "sudo " at the start; on an empty line, use the last command.
_b4h_key_sudo() {
  if [[ -z $READLINE_LINE ]]; then
    READLINE_LINE=$(HISTTIMEFORMAT= history 1 | sed 's/^ *[0-9]* *//')
    READLINE_POINT=${#READLINE_LINE}
  fi
  if [[ $READLINE_LINE == 'sudo '* ]]; then
    READLINE_LINE=${READLINE_LINE#sudo }
    (( READLINE_POINT = READLINE_POINT > 5 ? READLINE_POINT - 5 : 0 ))
  else
    READLINE_LINE="sudo $READLINE_LINE"
    (( READLINE_POINT += 5 ))
  fi
}

# Alt+H: manual for the command on the line (skipping sudo, env, VAR=x).
_b4h_key_help() {
  local -a words
  read -r -a words <<<"$READLINE_LINE"
  local w
  for w in "${words[@]}"; do
    case $w in sudo|env|command|exec|time|nice|nohup|*=*|-*) continue ;; esac
    if [[ $(type -t "$w") == builtin || $(type -t "$w") == keyword ]]; then
      help "$w" | "${PAGER:-less}"
    elif man -w "$w" >/dev/null 2>&1; then
      man "$w"
    else
      "$w" --help 2>&1 | "${PAGER:-less}"
    fi
    return
  done
}
