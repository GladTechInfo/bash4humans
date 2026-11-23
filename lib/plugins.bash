# =============================================================================
#  lib/plugins.bash - optional extras, switched on in ~/.bashrc:
#
#    B4H_PLUGINS=(extract git-aliases)
#
#    b4h plugins                 list them, [x] = on
#    b4h plugins enable NAME     switch on (edits B4H_PLUGINS in ~/.bashrc)
#    b4h plugins disable NAME    switch off (takes effect in a new shell)
#    b4h plugins search WORD
#
#  Bundled plugins live in plugins/; your own go in
#  ~/.config/bash4humans/plugins/NAME.plugin.bash (they win over bundled ones
#  of the same name). The first "# about:" line is the description.
# =============================================================================

[[ -v B4H_PLUGINS ]] || B4H_PLUGINS=()
_b4h_plugin_dirs=("${XDG_CONFIG_HOME:-$HOME/.config}/bash4humans/plugins" "$B4H_ROOT/plugins")

_b4h_plugin_file() {   # NAME -> path, or return 1
  local d
  for d in "${_b4h_plugin_dirs[@]}"; do
    [[ -r $d/$1.plugin.bash ]] && { printf '%s' "$d/$1.plugin.bash"; return 0; }
  done
  return 1
}

_b4h_plugins_load() {
  local p f
  for p in "${B4H_PLUGINS[@]}"; do
    if f=$(_b4h_plugin_file "$p"); then . "$f"
    else echo "bash4humans: plugin '$p' not found (b4h plugins)" >&2
    fi
  done
}

_b4h_plugins_cmd() {
  local sub=${1:-list} name
  shift 2>/dev/null
  case $sub in
    list|search)
      local -A seen=()
      local d f about mark
      for d in "${_b4h_plugin_dirs[@]}"; do
        for f in "$d"/*.plugin.bash; do
          [[ -r $f ]] || continue
          name=${f##*/}; name=${name%.plugin.bash}
          [[ -n ${seen[$name]-} ]] && continue; seen[$name]=1
          about=$(sed -n 's/^# about: //p' "$f" | head -1)
          [[ $sub == search && "$name $about" != *"${1-}"* ]] && continue
          mark=' '; [[ " ${B4H_PLUGINS[*]} " == *" $name "* ]] && mark=x
          printf '  [%s] %-18s %s\n' "$mark" "$name" "$about"
        done
      done | sort -t "]" -k2
      [[ $sub == list ]] && _b4h_repos_list
      ;;
    enable|disable)
      (( $# )) || { echo "usage: b4h plugins $sub NAME..." >&2; return 2; }
      local -a list=("${B4H_PLUGINS[@]}")
      for name; do
        if [[ $sub == enable ]]; then
          _b4h_plugin_file "$name" >/dev/null || { echo "b4h plugins: no plugin '$name'" >&2; return 1; }
          [[ " ${list[*]} " == *" $name "* ]] || list+=("$name")
        else
          local -a keep=() p
          for p in "${list[@]}"; do [[ $p == "$name" ]] || keep+=("$p"); done
          list=("${keep[@]}")
        fi
      done
      local line="B4H_PLUGINS=(${list[*]})"
      if grep -q '^B4H_PLUGINS=' "$B4H_RCFILE" 2>/dev/null; then
        sed -i "s/^B4H_PLUGINS=.*/$line/" "$B4H_RCFILE"
      else
        # put it with the settings, before bash4humans is loaded
        sed -i "0,/^# -* bootstrap ---/s//$line\n\n&/" "$B4H_RCFILE"
        grep -q '^B4H_PLUGINS=' "$B4H_RCFILE" || sed -i "1i $line" "$B4H_RCFILE"
      fi
      B4H_PLUGINS=("${list[@]}")
      if [[ $sub == enable ]]; then
        for name; do . "$(_b4h_plugin_file "$name")"; done
        echo "b4h plugins: $* on (saved in ${B4H_RCFILE/#$HOME/\~})"
      else
        echo "b4h plugins: $* off from the next shell (saved in ${B4H_RCFILE/#$HOME/\~})"
      fi
      ;;
    *) echo 'usage: b4h plugins [list | search WORD | enable NAME... | disable NAME...]' >&2; return 2 ;;
  esac
}
