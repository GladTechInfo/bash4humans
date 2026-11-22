# =============================================================================
#  lib/keys.bash - key bindings (z4h's set, plus fish's Alt+S and Alt+H).
#
#    Right / Ctrl+F         accept the grey suggestion (ble.sh)
#    Up / Down              history entries containing what is typed
#    Ctrl+R                 fuzzy history (fzf)       Ctrl+T  files    Alt+C  cd
#    Ctrl+Backspace, Ctrl+H delete a word             Ctrl+Alt+Backspace  a shell word
#    Ctrl+/ , Shift+Tab     undo                      Alt+/   redo (ble.sh)
#    Ctrl+Left / Right      word left / right         Ctrl+Delete  delete word right
#    Alt+Left / Right       previous / next directory
#    Alt+Up / Down          parent directory / pick a subdirectory
#    Alt+S                  toggle sudo               Alt+H   manual page
# =============================================================================

# Directory keys: change directory, then redraw the prompt in place.
_b4h_key_back()    { _b4h_cd_back    && _b4h_prompt_refresh; return 0; }
_b4h_key_forward() { _b4h_cd_forward && _b4h_prompt_refresh; return 0; }
_b4h_key_up()      { _b4h_cd_up      && _b4h_prompt_refresh; return 0; }
_b4h_key_down()    { _b4h_cd_down    && _b4h_prompt_refresh; return 0; }

if (( _b4h_ble )); then
  # ble.sh: widgets run inside the editor, so the prompt can be redrawn
  # cleanly. Bindings go in once the emacs keymap has loaded.
  function ble/widget/b4h-back    { _b4h_key_back; }
  function ble/widget/b4h-forward { _b4h_key_forward; }
  function ble/widget/b4h-up      { _b4h_key_up; }

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
    ble-bind -f up       history-substring-search-backward
    ble-bind -f down     history-substring-search-forward
    ble-bind -f M-left   b4h-back
    ble-bind -f M-right  b4h-forward
    ble-bind -f M-up     b4h-up
    ble-bind -x M-down   _b4h_key_down
    ble-bind -x M-s      _b4h_key_sudo
    ble-bind -x M-h      _b4h_key_help
  }
  blehook/eval-after-load keymap_emacs _b4h_ble_keys

  if [[ $B4H_SUGGEST_ACCEPT == word ]]; then
    blehook/eval-after-load complete "ble-bind -m auto_complete -f right 'auto_complete/insert-word'"
  fi
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
  bind '"\e[A": history-substring-search-backward'
  bind '"\eOA": history-substring-search-backward'
  bind '"\e[B": history-substring-search-forward'
  bind '"\eOB": history-substring-search-forward'
  bind -x '"\e[1;3D": _b4h_key_back'
  bind -x '"\e[1;3C": _b4h_key_forward'
  bind -x '"\e[1;3A": _b4h_key_up'
  bind -x '"\e[1;3B": _b4h_key_down'
  bind -x '"\es": _b4h_key_sudo'
  bind -x '"\eh": _b4h_key_help'
fi
