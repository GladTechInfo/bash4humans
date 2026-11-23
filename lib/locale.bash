# =============================================================================
#  lib/locale.bash - UTF-8 when the locale is not (zsh4humans' -z4h-fix-locale)
# =============================================================================
#  With no UTF-8 locale in effect - LANG unset, C or POSIX, or a UTF-8 name
#  that is not installed on this machine - line editing, the prompt's glyphs
#  and every non-ASCII file name go wrong. zsh4humans then sets LC_ALL to
#  C.UTF-8, else en_US.UTF-8, else the first UTF-8 locale the system has;
#  bash4humans does the same, as the shell starts, before ble.sh and tmux.
#  Nothing changes when no UTF-8 locale exists. B4H_FIX_LOCALE=no: off.

# Is the locale bash is using UTF-8? The two bytes of "é" are one character
# in UTF-8 and two in any other locale. ${#v} counts characters by bash's
# own locale, so this starts no process.
_b4h_locale_is_utf8() {
  local e=$'\xc3\xa9'
  (( ${#e} == 1 ))
}

_b4h_fix_locale() {
  [[ $B4H_FIX_LOCALE == yes ]] || return 0
  _b4h_locale_is_utf8 && return 0
  local had=${LC_ALL+1} old=${LC_ALL-} loc
  # zsh4humans' order: C.UTF-8, en_US.UTF-8, then the first UTF-8 locale.
  # glibc lists them as C.utf8 and en_US.utf8; both spellings are tried.
  local -a try=(C.UTF-8 C.utf8 en_US.UTF-8 en_US.utf8)
  if command -v locale >/dev/null; then
    local -a all
    mapfile -t all < <(locale -a 2>/dev/null)
    for loc in "${all[@]}"; do
      [[ $loc == *.[Uu][Tt][Ff]8 || $loc == *.[Uu][Tt][Ff]-8 ]] && try+=("$loc")
    done
  fi
  # bash changes its own locale as soon as LC_ALL is assigned; one that does
  # not exist only earns a warning (hidden here), so each try is checked.
  for loc in "${try[@]}"; do
    { LC_ALL=$loc; } 2>/dev/null
    if _b4h_locale_is_utf8; then
      export LC_ALL
      _b4h_locale_fixed=$loc       # b4h doctor says so
      return 0
    fi
  done
  # none works: put back what was there
  if [[ -n $had ]]; then { LC_ALL=$old; } 2>/dev/null; else unset LC_ALL; fi
  return 0
}
_b4h_fix_locale
