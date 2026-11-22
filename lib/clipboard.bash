# =============================================================================
#  lib/clipboard.bash - the clipboard from the command line.
#
#    ... | x        cut:  what comes in goes to the clipboard
#    ... | c        copy: to the clipboard, and passed on (c is a tee)
#    v              paste: the clipboard to the output   (v >file, v | less)
#    x TEXT..., c TEXT...   the arguments as text, instead of the input
#
#  zsh4humans planned these three (its notes.md, "clipboard-{cut,copy,paste}",
#  aliases x, c, v); they are not in a release. Here they work:
#    - on a desktop: wl-copy / wl-paste (Wayland), xclip or xsel (X11),
#      pbcopy / pbpaste (macOS), clip.exe / powershell.exe (WSL);
#    - otherwise (over SSH, a console): copying sends OSC 52, which asks the
#      terminal to put the text into the clipboard of the machine in front
#      of you (most terminals allow it; inside tmux it goes through tmux).
#      Terminals do not let programs read the clipboard back, so v there
#      pastes what x or c last copied on this machine ($B4H_HOME/clipboard).
#
#  B4H_CLIPBOARD_COMMANDS=no: none of the three. A name that is already a
#  command, function or alias is not taken; `b4h clipboard` says which tool
#  is used. The functions _b4h_clip_copy and _b4h_clip_paste stay available.
# =============================================================================

_b4h_clip_file=$B4H_HOME/clipboard

# Which tool reaches the clipboard here (checked on each use: DISPLAY can
# change, e.g. after `tmux attach` from another session).
_b4h_clip_tool() {
  if [[ -n ${WAYLAND_DISPLAY-} ]] && command -v wl-copy >/dev/null && command -v wl-paste >/dev/null; then
    REPLY=wayland
  elif [[ -n ${DISPLAY-} ]] && command -v xclip >/dev/null; then
    REPLY=xclip
  elif [[ -n ${DISPLAY-} ]] && command -v xsel >/dev/null; then
    REPLY=xsel
  elif [[ $OSTYPE == darwin* ]] && command -v pbcopy >/dev/null; then
    REPLY=macos
  elif [[ -n ${WSL_DISTRO_NAME-} ]] && command -v clip.exe >/dev/null; then
    REPLY=wsl
  else
    REPLY=osc52
  fi
}

# stdin → clipboard
_b4h_clip_copy() {
  local REPLY
  _b4h_clip_tool
  case $REPLY in
    wayland) wl-copy ;;
    xclip)   xclip -in -selection clipboard ;;
    xsel)    xsel --clipboard --input ;;
    macos)   pbcopy ;;
    wsl)     clip.exe ;;
    osc52)   _b4h_clip_osc52 ;;
  esac
}

# The terminal's clipboard (OSC 52), and a copy in a file for v.
_b4h_clip_osc52() {
  local data
  (umask 077; cat >"$_b4h_clip_file") || return 1
  # base64 on one line (GNU base64 wraps at 76 columns; busybox too)
  data=$(base64 <"$_b4h_clip_file" | tr -d '\n') || return 1
  if [[ -n ${TMUX-} ]] && tmux load-buffer -w - <"$_b4h_clip_file" 2>/dev/null; then
    return 0        # tmux 3.2+: its buffer, and OSC 52 to the outer terminal
  fi
  if [[ -n ${TMUX-} ]]; then
    # older tmux: pass the sequence through (needs allow-passthrough)
    printf '\ePtmux;\e\e]52;c;%s\a\e\\' "$data" >/dev/tty 2>/dev/null
  else
    printf '\e]52;c;%s\a' "$data" >/dev/tty 2>/dev/null
  fi
}

# clipboard → stdout
_b4h_clip_paste() {
  local REPLY
  _b4h_clip_tool
  case $REPLY in
    wayland) wl-paste --no-newline ;;
    xclip)   xclip -out -selection clipboard ;;
    xsel)    xsel --clipboard --output ;;
    macos)   pbpaste ;;
    wsl)     powershell.exe -NoProfile -Command Get-Clipboard | tr -d '\r' ;;
    osc52)   [[ -r $_b4h_clip_file ]] && cat -- "$_b4h_clip_file" ;;
  esac
}

# The text to copy: the arguments, else the input (not the keyboard).
_b4h_clip_in() {
  local name=$1; shift
  if (( $# )); then
    printf '%s' "$*"
  elif [[ -t 0 ]]; then
    echo "$name: give text, or pipe into it (... | $name)" >&2
    return 2
  else
    cat
  fi
}

_b4h_clip_x() {
  # (checked first: a pipeline would run the copy, emptying the clipboard)
  (( $# )) || [[ ! -t 0 ]] || { _b4h_clip_in x; return; }
  _b4h_clip_in x "$@" | _b4h_clip_copy
}
_b4h_clip_c() {
  # the input is passed on as it is copied
  local tmp
  tmp=$(mktemp) || return 1
  _b4h_clip_in c "$@" >"$tmp" || { rm -f -- "$tmp"; return 2; }
  _b4h_clip_copy <"$tmp"
  cat -- "$tmp"
  rm -f -- "$tmp"
}
_b4h_clip_v() { _b4h_clip_paste; }

# b4h clipboard: the tool in use, and which of x, c, v are ours.
_b4h_clipboard_info() {
  local REPLY n own=() other=()
  _b4h_clip_tool
  case $REPLY in
    wayland) echo 'clipboard: Wayland (wl-copy / wl-paste)' ;;
    xclip)   echo 'clipboard: X11 (xclip)' ;;
    xsel)    echo 'clipboard: X11 (xsel)' ;;
    macos)   echo 'clipboard: macOS (pbcopy / pbpaste)' ;;
    wsl)     echo 'clipboard: Windows (clip.exe / powershell.exe)' ;;
    osc52)   echo 'clipboard: the terminal'"'"'s, by OSC 52 (copy only); v pastes the last copy made here'
             [[ -n ${TMUX-} ]] && echo '           inside tmux: tmux 3.2+ passes it on (set-clipboard on)' ;;
  esac
  for n in x c v; do
    if [[ $(type -t "$n") == function ]] && declare -f "$n" | grep -q "_b4h_clip_$n"; then own+=("$n")
    else other+=("$n"); fi
  done
  (( ${#own[@]} ))   && echo "commands:  ${own[*]}"
  (( ${#other[@]} )) && echo "not ours:  ${other[*]} (taken by something else, or B4H_CLIPBOARD_COMMANDS=no)"
  return 0
}

if [[ $B4H_CLIPBOARD_COMMANDS == yes ]]; then
  for _b4h_f in x c v; do
    type -t "$_b4h_f" >/dev/null || eval "$_b4h_f() { _b4h_clip_$_b4h_f \"\$@\"; }"
  done
  unset _b4h_f
fi
