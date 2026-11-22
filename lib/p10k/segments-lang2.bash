# =============================================================================
#  lib/p10k/segments-lang2.bash - language segments, part 2: asdf, the
#  *_version segments (node go rust java php dotnet swift laravel) and
#  package. Ports of the same-named p10k code; helpers in segments-lang.bash.
# =============================================================================

# ------------------------------------------------------- zsh key order ---
# _p9k_zsh_key_order KEY... (in insertion order) -> _p9k__keys, the order in
# which zsh lists the keys of an associative array (${(k)assoc}). p10k loops
# over asdf's plugins that way, so with several tools the segments appear in
# this order. zsh's table: hash h = h*33 + byte (32 bits), 17 buckets, a new
# key goes to the front of its bucket, and at 2 x size entries the table grows
# to 4 x size, re-inserting the old buckets in order.
_p9k_zsh_hash() {
  local k=$1 c; local -i h=0 j
  for (( j = 0; j < ${#k}; j++ )); do
    printf -v c '%d' "'${k:j:1}"
    h=$(( (h + (h << 5) + c) & 0xFFFFFFFF ))
  done
  _p9k__h=$h
}
_p9k_zsh_key_order() {
  local -i size=17 n=0 i b osize
  local -a buckets=() old
  local k s
  for k in "$@"; do
    for (( i = 0; i < size; i++ )); do
      [[ $'\n'${buckets[i]-}$'\n' == *$'\n'"$k"$'\n'* ]] && continue 2
    done
    _p9k_zsh_hash "$k"; i=$(( _p9k__h % size ))
    buckets[i]=$k${buckets[i]:+$'\n'${buckets[i]}}
    if (( ++n >= size * 2 )); then
      old=("${buckets[@]}") osize=size
      # ("${buckets[@]}" drops the gaps, so copy by index instead)
      old=(); for (( i = 0; i < osize; i++ )); do old[i]=${buckets[i]-}; done
      size=$(( size * 4 )); buckets=()
      for (( i = 0; i < osize; i++ )); do
        [[ -n ${old[i]} ]] || continue
        while IFS= read -r s; do
          _p9k_zsh_hash "$s"; b=$(( _p9k__h % size ))
          buckets[b]=$s${buckets[b]:+$'\n'${buckets[b]}}
        done <<<"${old[i]}"
      done
    fi
  done
  _p9k__keys=()
  for (( i = 0; i < size; i++ )); do
    [[ -n ${buckets[i]-} ]] || continue
    while IFS= read -r s; do _p9k__keys+=("$s"); done <<<"${buckets[i]}"
  done
}

# --------------------------------------------------------------------- asdf ---
# Plugins: directories in $ASDF_DATA_DIR/plugins. For each, the installed
# versions (plus "system") and, with legacy_version_file = yes in asdfrc,
# the legacy file names the plugin reads (.nvmrc, .ruby-version, ...).
# p10k caches this by modification times; it is rebuilt when they change.
declare -gA _p9k_asdf_plugins=() _p9k_asdf_file_info=()
declare -ga _p9k_asdf_plugin_order=()
_p9k__asdf_sig=''
_p9k_asdf_meta() {
  local cfg=${ASDF_CONFIG_FILE:-$HOME/.asdfrc} root=${ASDF_DATA_DIR:-$HOME/.asdf}
  local sig; sig=$cfg$'\1'$root$'\1'$(stat -c %Y -- "$cfg" "$root/plugins" "$root"/installs/* "$root"/plugins/*/bin 2>/dev/null | tr '\n' :)
  [[ $sig == "$_p9k__asdf_sig" ]] && return 0
  _p9k__asdf_sig=$sig
  _p9k_asdf_plugins=() _p9k_asdf_file_info=()
  local legacy=0 line
  if [[ -f $cfg && -r $cfg ]]; then
    # asdf's odd parser: exactly one legacy_version_file line, whose second
    # "="-separated field is "yes" (p10k does the same)
    local -a lines=()
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}
      [[ $line =~ ^[[:space:]]*legacy_version_file[[:space:]]*= ]] && lines+=("$line")
    done <"$cfg"
    if (( ${#lines[@]} == 1 )); then
      local -a f; IFS='=' read -r -a f <<<"${lines[0]}"
      [[ ${f[1]-} =~ ^[[:space:]]*yes[[:space:]]*$ ]] && legacy=1
    fi
  fi
  local -a names=()
  local p v
  if [[ -d $root/plugins ]]; then
    for p in "$root"/plugins/*/; do
      p=${p%/}; p=${p##*/}
      [[ -d $root/plugins/$p && $p != *[[:space:]]* ]] && names+=("$p")
    done
  fi
  for p in "${names[@]}"; do
    # installed versions, unique, as one "a|b|system" list for matching
    local inst=''
    for v in "$root"/installs/"$p"/*/; do
      v=${v%/}; v=${v##*/}
      [[ -d $root/installs/$p/$v && $v != *[[:space:]]* ]] && inst+=$v$'\n'
    done
    inst+=system
    _p9k_asdf_plugins[$p]=$inst
    (( legacy )) || continue
    local list=$root/plugins/$p/bin/list-legacy-filenames parse=$root/plugins/$p/bin/parse-legacy-file
    [[ -e $root/plugins/$p/bin && -x $list ]] || continue
    local has_parse=0; [[ -x $parse ]] && has_parse=1
    local n
    for n in $("$list" 2>/dev/null); do
      n=${n%$'\r'}
      [[ $n == */* || $n == .tool-versions ]] && continue
      _p9k_asdf_file_info[$n]+="$p $has_parse "
    done
  done
  _p9k_zsh_key_order "${names[@]}"
  _p9k_asdf_plugin_order=("${_p9k__keys[@]}")
}

# Is $2 one of the installed versions of plugin $1?
_p9k_asdf_installed() { [[ $'\n'${_p9k_asdf_plugins[$1]}$'\n' == *$'\n'"$2"$'\n'* ]]; }

# p10k: _p9k_asdf_parse_version_file FILE IS_LEGACY -> fills versions[] where
# still unset (deeper directories win)
_p9k_asdf_parse_version_file() {
  local file=$1 line p hp
  [[ -e $file ]] || return 1
  if (( $2 )); then
    local -a info; read -r -a info <<<"${_p9k_asdf_file_info[${file##*/}]-}"
    local k
    for (( k = 0; k + 1 < ${#info[@]}; k += 2 )); do
      p=${info[k]} hp=${info[k+1]}
      local -a v=()
      if (( hp )); then
        read -r -d '' -a v < <("${ASDF_DATA_DIR:-$HOME/.asdf}/plugins/$p/bin/parse-legacy-file" "$file" 2>/dev/null)
      else
        read -r -d '' -a v <"$file" 2>/dev/null
      fi
      local pick='' w
      for w in "${v[@]}"; do w=${w%$'\r'}; _p9k_asdf_installed "$p" "$w" && { pick=$w; break; }; done
      [[ -n $pick ]] || pick=${v[0]-}; pick=${pick%$'\r'}
      [[ -n $pick && -z ${versions[$p]+x} ]] && versions[$p]=$pick
    done
  else
    while IFS= read -r line || [[ -n $line ]]; do
      line=${line%$'\r'}; line=${line%%#*}
      local -a words; read -r -a words <<<"$line"
      (( ${#words[@]} > 1 )) || continue
      [[ -n ${_p9k_asdf_plugins[${words[0]}]+x} ]] || continue
      local pick='' w
      for w in "${words[@]:1}"; do _p9k_asdf_installed "${words[0]}" "$w" && { pick=$w; break; }; done
      [[ -n $pick ]] || pick=${words[1]}
      [[ -z ${versions[${words[0]}]+x} ]] && versions[${words[0]}]=$pick
    done <"$file"
  fi
  return 0
}

prompt_asdf() {
  _p9k_asdf_meta
  local -A versions=() local_versions=()
  local has_global=0 i d f
  local -a dirs=("${_p9k__parent_dirs[@]:1}")
  [[ ${dirs[-1]-} == "$HOME" ]] || dirs+=("$HOME")
  for d in "${dirs[@]}"; do
    local -a files=()
    [[ -e $d/.tool-versions ]] && files+=("$d/.tool-versions")
    for f in "${!_p9k_asdf_file_info[@]}"; do [[ -e $d/$f ]] && files+=("$d/$f"); done
    if (( ${#files[@]} )) && [[ ${files[0]%/*} == "$HOME" ]]; then
      # reaching ~: what was found so far is "local", ~ and below are global
      has_global=1
      local_versions=(); for f in "${!versions[@]}"; do local_versions[$f]=${versions[$f]}; done
      versions=()
    fi
    for f in "${files[@]}"; do
      if [[ $f == */.tool-versions ]]; then _p9k_asdf_parse_version_file "$f" 0 || return 0
      else _p9k_asdf_parse_version_file "$f" 1 || return 0
      fi
    done
  done
  if (( ! has_global )); then
    local_versions=(); for f in "${!versions[@]}"; do local_versions[$f]=${versions[$f]}; done
    versions=()
  fi
  if [[ -n ${ASDF_DEFAULT_TOOL_VERSIONS_FILENAME-} && -r $ASDF_DEFAULT_TOOL_VERSIONS_FILENAME ]]; then
    _p9k_asdf_parse_version_file "$ASDF_DEFAULT_TOOL_VERSIONS_FILENAME" 0 || return 0
  fi
  local plugin upper version
  for plugin in "${_p9k_asdf_plugin_order[@]}"; do
    upper=${plugin//-/_}; upper=${upper^^}
    local -a sources
    if _p9k_isset "_POWERLEVEL9K_ASDF_${upper}_SOURCES"; then
      local -n _src=_POWERLEVEL9K_ASDF_${upper}_SOURCES; sources=("${_src[@]}"); unset -n _src
    else
      sources=("${_POWERLEVEL9K_ASDF_SOURCES[@]}")
    fi
    local sl=" ${sources[*]} "
    local ev=ASDF_${upper}_VERSION
    version=${!ev-}
    if [[ -n $version ]]; then
      [[ $sl == *' shell '* ]] || continue
    else
      version=${local_versions[$plugin]-}
      if [[ -n $version ]]; then
        [[ $sl == *' local '* ]] || continue
      else
        version=${versions[$plugin]-}
        [[ -n $version ]] || continue
        [[ $sl == *' global '* ]] || continue
      fi
    fi
    if [[ $version == "${versions[$plugin]-}" ]]; then
      local pa=_POWERLEVEL9K_ASDF_${upper}_PROMPT_ALWAYS_SHOW
      if _p9k_isset "$pa"; then (( ${!pa} )) || continue
      else (( _POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW )) || continue
      fi
    fi
    if [[ $version == system ]]; then
      local ps=_POWERLEVEL9K_ASDF_${upper}_SHOW_SYSTEM
      if _p9k_isset "$ps"; then (( ${!ps} )) || continue
      else (( _POWERLEVEL9K_ASDF_SHOW_SYSTEM )) || continue
      fi
    fi
    _p9k_get_icon "prompt_asdf_$upper" "${upper}_ICON" "$plugin"
    _p9k_prompt_segment "prompt_asdf_$upper" green "$_p9k_color1" $'\1'"$_p9k__ret" 0 '' "${version//%/%%}"
  done
  return 0
}
_p9k_prompt_asdf_init() { _p9k_set_cond '@_p9k_have asdf'; }

# ------------------------------------------------------------- node_version ---
prompt_node_version() {
  _p9k_upglob package.json -.
  local idx=$?
  (( idx || ! _POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY )) || return 0
  _p9k_cached_cmd 0 '' node --version || return 0
  local v=$_p9k__ret
  [[ $v == v?* ]] || return 0
  v=${v#v}
  _p9k_prompt_segment "${FUNCNAME[0]}" green white NODE_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_node_version_init() { _p9k_set_cond '@_p9k_have_cmd node'; }

# --------------------------------------------------------------- go_version ---
prompt_go_version() {
  _p9k_cached_cmd 0 '' go version || return 0
  [[ $_p9k__ret =~ go([0-9.]+) ]] || return 0
  local v=${BASH_REMATCH[1]}
  if (( _POWERLEVEL9K_GO_VERSION_PROJECT_ONLY )); then
    local p=${GOPATH-}
    if [[ -z $p ]]; then
      if [[ -d $HOME/go ]]; then p=$HOME/go
      else p=$(go env GOPATH 2>/dev/null) && [[ -n $p ]] || return 0
      fi
    fi
    if [[ $_p9k__cwd/ != "$p"/* && $_p9k__cwd_a/ != "$p"/* ]]; then
      _p9k_upglob go.mod -. && return 0
    fi
  fi
  _p9k_prompt_segment "${FUNCNAME[0]}" green grey93 GO_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_go_version_init() { _p9k_set_cond '@_p9k_have_cmd go'; }

# ------------------------------------------------------------- rust_version ---
# `rustc --version` run in the current directory (rustup picks the toolchain
# per directory). p10k runs it in its worker; here before the segments.
prompt_rust_version() {
  _p9k_prompt_segment "${FUNCNAME[0]}" darkorange "$_p9k_color1" RUST_ICON 1 '${P9K_RUST_VERSION-}' '${P9K_RUST_VERSION//\%/%%}'
}
_p9k_prompt_rust_version_init() {
  _p9k_set_cond '@_p9k_have_cmd rustc'
  [[ " ${_p9k__precompute[*]} " == *' _p9k_rust_version_pre '* ]] || _p9k__precompute+=(_p9k_rust_version_pre)
}
_p9k_rust_version_pre() {
  local rustc
  if ! rustc=$(type -P rustc) || { (( _POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY )) && { _p9k_upglob Cargo.toml -.; (( ! $? )); }; }; then
    unset P9K_RUST_VERSION
    return 0
  fi
  local v; v=$("$rustc" --version 2>/dev/null) || v=''
  v=${v#rustc }; v=${v%% *}
  P9K_RUST_VERSION=$v
}

# ------------------------------------------------------------- java_version ---
prompt_java_version() {
  if (( _POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY )); then
    _p9k_upglob 'pom.xml|build.gradle.kts|build.sbt|deps.edn|project.clj|build.boot|*.(java|class|jar|gradle|clj|cljc)' -. && return 0
  fi
  # `java -fullversion` prints: openjdk full version "21.0.1+12-29"
  _p9k_cached_cmd 1 "${JAVA_HOME:+$JAVA_HOME/release}" java -fullversion || _p9k__ret=''
  local v=$_p9k__ret
  v=${v#*\"}; v=${v%\"*}
  (( _POWERLEVEL9K_JAVA_VERSION_FULL )) || v=${v%%-*}
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" red white JAVA_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_java_version_init() { _p9k_set_cond '@_p9k_have_cmd java'; }

# -------------------------------------------------------------- php_version ---
prompt_php_version() {
  if (( _POWERLEVEL9K_PHP_VERSION_PROJECT_ONLY )); then
    _p9k_upglob 'composer.json|*.php' -. && return 0
  fi
  _p9k_cached_cmd 0 '' php --version || return 0
  # the first line that starts with "PHP <digits>"
  local line v=''
  while IFS= read -r line; do
    [[ $line =~ ^PHP\ ([0-9.]+) ]] && { v=${BASH_REMATCH[1]}; break; }
  done <<<"$_p9k__ret"
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" fuchsia grey93 PHP_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_php_version_init() { _p9k_set_cond '@_p9k_have_cmd php'; }

# ----------------------------------------------------------- dotnet_version ---
prompt_dotnet_version() {
  if (( _POWERLEVEL9K_DOTNET_VERSION_PROJECT_ONLY )); then
    _p9k_upglob 'project.json|global.json|packet.dependencies|*.csproj|*.fsproj|*.xproj|*.sln' -. && return 0
  fi
  local cfg=''
  _p9k_upglob global.json -.; local i=$?
  (( i )) && cfg=${_p9k__parent_dirs[i]}/global.json
  _p9k_cached_cmd 0 "$cfg" dotnet --version || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" magenta white DOTNET_ICON 0 '' "$_p9k__ret"
}
_p9k_prompt_dotnet_version_init() { _p9k_set_cond '@_p9k_have_cmd dotnet'; }

# ------------------------------------------------------------ swift_version ---
prompt_swift_version() {
  _p9k_cached_cmd 0 '' swift --version || return 0
  [[ $_p9k__ret =~ ^[^0-9]*([0-9.]+) ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" magenta white SWIFT_ICON 0 '' "${BASH_REMATCH[1]//%/%%}"
}
_p9k_prompt_swift_version_init() { _p9k_set_cond '@_p9k_have_cmd swift'; }

# ---------------------------------------------------------- laravel_version ---
prompt_laravel_version() {
  _p9k_upglob artisan && return 0
  local dir=${_p9k__parent_dirs[$?]}
  local app=$dir/vendor/laravel/framework/src/Illuminate/Foundation/Application.php
  [[ -r $app ]] || return 0
  local v; v=$(php "$dir/artisan" --version 2>/dev/null)
  [[ $v == 'Laravel Framework '* ]] && v=${v#Laravel Framework } || v=''
  # some versions colour the output: one ESC[<n>m at each end
  [[ $v =~ ^$'\e'\[[0-9]+m(.*)$ ]] && v=${BASH_REMATCH[1]}
  [[ $v =~ ^(.*)$'\e'\[[0-9]+m$ ]] && v=${BASH_REMATCH[1]}
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" maroon white LARAVEL_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_laravel_version_init() { _p9k_set_cond '@_p9k_have_cmd php'; }

# ------------------------------------------------------------------ package ---
# name and version from the nearest package.json, read by p10k's small JSON
# scanner (top-level "name" and "version" strings only).
prompt_package() {
  unset P9K_PACKAGE_NAME P9K_PACKAGE_VERSION
  _p9k_upglob package.json -. && return 0
  local file=${_p9k__parent_dirs[$?]}/package.json data
  { data=$(<"$file"); } 2>/dev/null || return 0
  _p9k_package_scan "$data" || return 0
  P9K_PACKAGE_NAME=$_p9k__pkg_name P9K_PACKAGE_VERSION=$_p9k__pkg_version
  # zsh ${(V)...}: control characters shown visibly
  local v=$P9K_PACKAGE_VERSION
  _p9k_prompt_segment "${FUNCNAME[0]}" cyan "$_p9k_color1" PACKAGE_ICON 0 '' "${v//%/%%}"
}

_p9k_package_scan() {
  local data=${1//$'\r'/} field='' s tail
  local -A found=()
  data=${data#"${data%%[![:space:]]*}"}
  [[ $data == '{'* ]] || return 1
  data=${data:1}
  local depth=1
  while :; do
    data=${data#"${data%%[![:space:]]*}"}
    [[ -n $data ]] || return 1
    case ${data:0:1} in
      '{'|'[') data=${data:1}; (( ++depth )) ;;
      '}'|']') data=${data:1}; (( --depth > 0 )) || return 1 ;;
      ':') data=${data:1} ;;
      ',') data=${data:1}; field='' ;;
      [[:alnum:].]) data=${data#"${data%%[![:alnum:].]*}"} ;;
      '"')
        # the string up to the closing quote (backslash escapes skipped)
        local re='^"(([^"\\]|\\.)*)"'
        [[ $data =~ $re ]] || return 1
        s=${BASH_REMATCH[1]}; data=${data:${#BASH_REMATCH[0]}}
        (( depth == 1 )) || continue
        if [[ -z $field ]]; then
          field=${s:-x}
        elif [[ $field == name || $field == version ]]; then
          [[ -z ${found[$field]+x} ]] || return 1
          [[ -n $s ]] || return 1
          [[ $s != *$'\n'* && $s != *'\'* ]] || return 1
          found[$field]=$s
          (( ${#found[@]} == 2 )) && break
        fi ;;
      *) return 1 ;;
    esac
  done
  _p9k__pkg_name=${found[name]} _p9k__pkg_version=${found[version]}
}
