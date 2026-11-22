# =============================================================================
#  lib/p10k/segments-lang.bash - language and version-manager segments, part 1:
#  the helpers they share, the *env tools (pyenv goenv nodenv rbenv jenv
#  luaenv plenv phpenv scalaenv), virtualenv, anaconda, nodeenv, nvm, rvm,
#  chruby, perlbrew, fvm, haskell_stack. Ports of the same-named p10k code.
#
#  p10k caches file reads and command output by modification time; the
#  results are the same without the cache, so it is kept only for commands
#  (running `python --version` before every prompt would be slow).
# =============================================================================

# ------------------------------------------------------------ directories ---
# p10k: _p9k_fetch_cwd, run before each prompt.
#   _p9k__cwd        the logical current directory ($PWD)
#   _p9k__cwd_a      the same with symlinks resolved
#   _p9k__parent_dirs the directory and its parents, deepest first (index 1),
#                    stopping before / or, inside the home directory, before
#                    the directory that holds it (so ~ is the last one)
_p9k_fetch_cwd() {
  _p9k__cwd=$PWD
  _p9k__cwd_a=$(pwd -P 2>/dev/null) || _p9k__cwd_a=$PWD
  declare -ga _p9k__parent_dirs=('')   # index 0 unused: zsh arrays start at 1
  local parent rest
  case $_p9k__cwd in /|.) return 0 ;; esac
  if [[ $_p9k__cwd == "$HOME" || $_p9k__cwd == "$HOME"/* ]]; then
    parent=${HOME%/*}/                  # the directory that holds ~
  else
    parent=/
  fi
  rest=${_p9k__cwd#"$parent"}
  local -a parts=(); local IFS=/
  read -r -a parts <<<"$rest"; unset IFS
  # parts a b c -> parent/a/b/c, parent/a/b, parent/a
  local k j d
  for (( k = ${#parts[@]}; k >= 1; k-- )); do
    d=${parent%/}
    for (( j = 0; j < k; j++ )); do d+=/${parts[j]}; done
    _p9k__parent_dirs+=("$d")
  done
}

# p10k: _p9k_glob / _p9k_upglob PATTERN [QUALIFIER]. Returns the index in
# _p9k__parent_dirs of the first (deepest) directory with a matching entry,
# or 0. NB: like p10k, status 0 means "not found".
# PATTERN is a zsh pattern ("a|b", "*.(pl|pm)", "(|MY)META.yml"); it becomes
# a bash extended pattern. QUALIFIER: -. regular file, -/ directory (both
# after following symlinks), @ symbolic link, none: anything.
_p9k_upglob() {
  local pat=${1//(/@(} q=${2-} i f
  # a path such as .fvm/flutter_sdk is used as it is (an @(...) group cannot
  # contain "/"); other patterns may be alternatives: a|b
  [[ $pat == */* ]] || pat="@($pat)"
  local had_ext=0 had_null=0
  shopt -q extglob && had_ext=1; shopt -q nullglob && had_null=1
  shopt -s extglob nullglob
  local -a m
  for (( i = 1; i < ${#_p9k__parent_dirs[@]}; i++ )); do
    m=("${_p9k__parent_dirs[i]}"/$pat)
    for f in "${m[@]}"; do
      case $q in
        -.) [[ -f $f ]] || continue ;;
        -/) [[ -d $f ]] || continue ;;
        @) [[ -L $f ]] || continue ;;
      esac
      (( had_ext )) || shopt -u extglob; (( had_null )) || shopt -u nullglob
      return "$i"
    done
  done
  (( had_ext )) || shopt -u extglob; (( had_null )) || shopt -u nullglob
  return 0
}

# p10k: _p9k_read_word FILE -> first word of the first line; status: non-empty
_p9k_read_word() {
  local rest
  _p9k__ret=''
  { read -r _p9k__ret rest <"$1"; } 2>/dev/null
  _p9k__ret=${_p9k__ret%$'\r'}
  [[ -n $_p9k__ret ]]
}

# p10k: _p9k_read_pyenv_like_version_file FILE PREFIX -> the first word of
# every line not starting with #, PREFIX removed, joined with ":".
_p9k_read_pyenv_like_version_file() {
  local content='' line w out='' rest
  { IFS= read -r -N 1024 content <"$1"; } 2>/dev/null
  while IFS= read -r line; do
    read -r w rest <<<"$line"
    [[ -z $w || $w == '#'* ]] && continue
    w=${w#"$2"}
    [[ -n $w ]] && out+=${out:+:}$w
  done <<<"$content"
  _p9k__ret=$out
  [[ -n $_p9k__ret ]]
}

# "@_p9k_have NAME": NAME is a command on PATH or a shell function
# (p10k: ${commands[NAME]:-${${+functions[NAME]}:#0}}).
_p9k_have() { type -P "$1" >/dev/null || declare -F "$1" >/dev/null; }
_p9k_have_cmd() { type -P "$1" >/dev/null; }

# p10k: _p9k_cached_cmd STDERR DEP CMD ARGS... -> output of CMD (with stderr
# when STDERR=1). Cached until CMD or the file DEP changes.
declare -gA _p9k__cmd_cache=()
_p9k_cached_cmd() {
  local cmd; cmd=$(type -P "$3") || return 1
  local key="$*" stamp out st
  stamp=$(stat -L -c %Y -- "$cmd" ${2:+"$2"} 2>/dev/null | tr '\n' :)
  local c=${_p9k__cmd_cache[$key]-}
  if [[ -n $c && ${c%%$'\x1f'*} == "$stamp" ]]; then
    c=${c#*$'\x1f'}; st=${c%%$'\x1f'*}; out=${c#*$'\x1f'}
  else
    if (( $1 )); then out=$("$cmd" "${@:4}" 2>&1); else out=$("$cmd" "${@:4}" 2>/dev/null); fi
    st=$(( ! $? ))
    _p9k__cmd_cache[$key]=$stamp$'\x1f'$st$'\x1f'$out
  fi
  (( st )) || return 1
  _p9k__ret=$out
}

# ------------------------------------------------------------ the *env tools ---
# One function for p10k's eight copies (prompt_rbenv and its siblings).
#   $1 tool (rbenv)  $2 version file (.ruby-version)  $3 prefix to strip
#   ("" = read the first word; else pyenv-like file, e.g. "go-")
#   $4 background  $5 foreground  $6 icon  [$7 = node: nodenv's name transform]
# Result: the segment, or nothing.
_p9k_xenv_prompt() {
  local tool=$1 vfile=$2 pfx=$3 T=${1^^}
  local -n srcs=_POWERLEVEL9K_${T}_SOURCES
  local always_v=_POWERLEVEL9K_${T}_PROMPT_ALWAYS_SHOW system_v=_POWERLEVEL9K_${T}_SHOW_SYSTEM
  local env_ver=${T}_VERSION env_dir=${T}_DIR v
  local has_shell=0 has_local=0 has_global=0 s
  for s in "${srcs[@]}"; do
    case $s in shell) has_shell=1 ;; local) has_local=1 ;; global) has_global=1 ;; esac
  done
  _p9k_xenv_read() { if [[ -n $pfx ]]; then _p9k_read_pyenv_like_version_file "$1" "$pfx"; else _p9k_read_word "$1"; fi; }

  if [[ -n $pfx ]]; then
    # goenv: GOENV_VERSION split on ":", prefix removed from each part
    local -a parts=(); local IFS=:
    read -r -a parts <<<"${!env_ver-}"; unset IFS
    v=''; for s in "${parts[@]}"; do v+=${v:+:}${s#"$pfx"}; done
  else
    v=${!env_ver-}
  fi
  if [[ -n $v ]]; then
    (( has_shell )) || return 0
  else
    (( has_local || has_global )) || return 0
    _p9k__ret=''
    local ed=${!env_dir-}
    if [[ -n $ed && $ed != . ]]; then
      local dir; [[ $ed == /* ]] && dir=$ed || dir=$_p9k__cwd_a/$ed
      dir=$(realpath -m -- "$dir" 2>/dev/null) || dir=''
      if [[ -n $dir && $dir != "$_p9k__cwd_a" ]]; then
        while :; do
          if _p9k_xenv_read "$dir/$vfile"; then
            (( has_local )) || return 0
            break
          fi
          [[ $dir == / || $dir == . ]] && break
          dir=${dir%/*}; [[ -n $dir ]] || dir=/
        done
      fi
    fi
    if [[ -z $_p9k__ret ]]; then
      _p9k_upglob "$vfile" -.
      local idx=$?
      if (( idx )) && _p9k_xenv_read "${_p9k__parent_dirs[idx]}/$vfile"; then
        (( has_local )) || return 0
      else
        _p9k__ret=''
      fi
    fi
    if [[ -z $_p9k__ret ]]; then
      (( ${!always_v} )) || return 0
      (( has_global )) || return 0
      "_p9k_${tool}_global_version"
    fi
    v=$_p9k__ret
    if [[ ${7-} == node ]]; then _p9k_nodeenv_version_transform "$_p9k__ret" || return 0; v=$_p9k__ret; fi
  fi
  if (( ! ${!always_v} )); then
    "_p9k_${tool}_global_version"
    if [[ ${7-} == node ]]; then
      _p9k_nodeenv_version_transform "$_p9k__ret" && [[ $v == "$_p9k__ret" ]] && return 0
    else
      [[ $v == "$_p9k__ret" ]] && return 0
    fi
  fi
  if (( ! ${!system_v} )); then
    [[ $v == system ]] && return 0
  fi
  _p9k_prompt_segment "prompt_$tool" "$4" "$5" "$6" 0 '' "${v//%/%%}"
}

# Global versions (TOOL_ROOT/version, "system" when missing).
_p9k_rbenv_global_version()    { _p9k_read_word "${RBENV_ROOT:-$HOME/.rbenv}/version" || _p9k__ret=system; }
_p9k_goenv_global_version()    { _p9k_read_pyenv_like_version_file "${GOENV_ROOT:-$HOME/.goenv}/version" go- || _p9k__ret=system; }
_p9k_nodenv_global_version()   { _p9k_read_word "${NODENV_ROOT:-$HOME/.nodenv}/version" || _p9k__ret=system; }
_p9k_jenv_global_version()     { _p9k_read_word "${JENV_ROOT:-$HOME/.jenv}/version" || _p9k__ret=system; }
_p9k_luaenv_global_version()   { _p9k_read_word "${LUAENV_ROOT:-$HOME/.luaenv}/version" || _p9k__ret=system; }
_p9k_plenv_global_version()    { _p9k_read_word "${PLENV_ROOT:-$HOME/.plenv}/version" || _p9k__ret=system; }
_p9k_phpenv_global_version()   { _p9k_read_word "${PHPENV_ROOT:-$HOME/.phpenv}/version" || _p9k__ret=system; }
_p9k_scalaenv_global_version() { _p9k_read_word "${SCALAENV_ROOT:-$HOME/.scalaenv}/version" || _p9k__ret=system; }
_p9k_pyenv_global_version()    { _p9k_read_pyenv_like_version_file "${PYENV_ROOT:-$HOME/.pyenv}/version" python- || _p9k__ret=system; }

# nodenv accepts "v18.1.0", "node-18.1.0" and "node-v18.1.0" for an
# installed "18.1.0" (p10k: _p9k_nodeenv_version_transform).
_p9k_nodeenv_version_transform() {
  local dir=${NODENV_ROOT:-$HOME/.nodenv}/versions
  [[ -z $1 || $1 == system ]] && { _p9k__ret=$1; return 0; }
  [[ -d $dir/$1 ]] && { _p9k__ret=$1; return 0; }
  [[ -d $dir/${1/v} ]] && { _p9k__ret=${1/v}; return 0; }
  [[ -d $dir/${1#node-} ]] && { _p9k__ret=${1#node-}; return 0; }
  [[ -d $dir/${1#node-v} ]] && { _p9k__ret=${1#node-v}; return 0; }
  return 1
}

prompt_rbenv()    { _p9k_xenv_prompt rbenv    .ruby-version  ''  red     "$_p9k_color1" RUBY_ICON; }
prompt_goenv()    { _p9k_xenv_prompt goenv    .go-version    go- blue    "$_p9k_color1" GO_ICON; }
prompt_nodenv()   { _p9k_xenv_prompt nodenv   .node-version  ''  black   green          NODE_ICON node; }
prompt_jenv()     { _p9k_xenv_prompt jenv     .java-version  ''  white   red            JAVA_ICON; }
prompt_luaenv()   { _p9k_xenv_prompt luaenv   .lua-version   ''  blue    "$_p9k_color1" LUA_ICON; }
prompt_plenv()    { _p9k_xenv_prompt plenv    .perl-version  ''  blue    "$_p9k_color1" PERL_ICON; }
prompt_phpenv()   { _p9k_xenv_prompt phpenv   .php-version   ''  magenta "$_p9k_color1" PHP_ICON; }
prompt_scalaenv() { _p9k_xenv_prompt scalaenv .scala-version ''  red     "$_p9k_color1" SCALA_ICON; }
for _p9k_f in rbenv goenv nodenv jenv luaenv plenv phpenv scalaenv pyenv nvm; do
  eval "_p9k_prompt_${_p9k_f}_init() { _p9k_set_cond '@_p9k_have $_p9k_f'; }"
done
unset _p9k_f

# -------------------------------------------------------------------- pyenv ---
# p10k: _p9k_pyenv_compute -> _p9k__pyenv_version, P9K_PYENV_PYTHON_VERSION
_p9k_pyenv_compute() {
  unset P9K_PYENV_PYTHON_VERSION _p9k__pyenv_version
  local has_shell=0 has_local=0 has_global=0 s v=''
  for s in "${_POWERLEVEL9K_PYENV_SOURCES[@]}"; do
    case $s in shell) has_shell=1 ;; local) has_local=1 ;; global) has_global=1 ;; esac
  done
  local -a parts=(); local IFS=:
  read -r -a parts <<<"${PYENV_VERSION-}"; unset IFS
  for s in "${parts[@]}"; do v+=${v:+:}${s#python-}; done
  if [[ -n $v ]]; then
    (( has_shell )) || return 1
  else
    (( has_local || has_global )) || return 1
    _p9k__ret=''
    local ed=${PYENV_DIR-}
    if [[ -n $ed && $ed != . ]]; then
      local dir; [[ $ed == /* ]] && dir=$ed || dir=$_p9k__cwd_a/$ed
      dir=$(realpath -m -- "$dir" 2>/dev/null) || dir=''
      if [[ -n $dir && $dir != "$_p9k__cwd_a" ]]; then
        while :; do
          if _p9k_read_pyenv_like_version_file "$dir/.python-version" python-; then
            (( has_local )) || return 1
            break
          fi
          [[ $dir == / || $dir == . ]] && break
          dir=${dir%/*}; [[ -n $dir ]] || dir=/
        done
      fi
    fi
    if [[ -z $_p9k__ret ]]; then
      _p9k_upglob .python-version -.
      local idx=$?
      if (( idx )) && _p9k_read_pyenv_like_version_file "${_p9k__parent_dirs[idx]}/.python-version" python-; then
        (( has_local )) || return 1
      else
        _p9k__ret=''
      fi
    fi
    if [[ -z $_p9k__ret ]]; then
      (( _POWERLEVEL9K_PYENV_PROMPT_ALWAYS_SHOW )) || return 1
      (( has_global )) || return 1
      _p9k_pyenv_global_version
    fi
    v=$_p9k__ret
  fi
  if (( ! _POWERLEVEL9K_PYENV_PROMPT_ALWAYS_SHOW )); then
    _p9k_pyenv_global_version
    [[ $v == "$_p9k__ret" ]] && return 1
  fi
  if (( ! _POWERLEVEL9K_PYENV_SHOW_SYSTEM )); then
    [[ $v == system ]] && return 1
  fi
  # P9K_PYENV_PYTHON_VERSION: the first of the versions that is an installed
  # directory (after resolving symlinks), named as under versions/.
  local versions; versions=$(realpath -m -- "${PYENV_ROOT:-$HOME/.pyenv}/versions" 2>/dev/null)
  local name version
  local IFS=:
  for name in $v; do
    version=$(realpath -m -- "$versions/$name" 2>/dev/null)
    if [[ -d $version && $version == "$versions"/?* ]]; then
      s=${version#"$versions"/}; P9K_PYENV_PYTHON_VERSION=${s%%/*}
      break
    fi
  done
  unset IFS
  _p9k__pyenv_version=$v
}
prompt_pyenv() {
  _p9k_pyenv_compute || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PYTHON_ICON 0 '' "${_p9k__pyenv_version//%/%%}"
}

# p10k: _p9k_python_version -> _p9k__ret (e.g. 3.12.1)
_p9k_python_version() {
  local py; py=$(type -P python) || return 1
  if [[ $py == "${PYENV_ROOT:-$HOME/.pyenv}/shims/python" ]]; then
    local P9K_PYENV_PYTHON_VERSION _p9k__pyenv_version
    local _POWERLEVEL9K_PYENV_PROMPT_ALWAYS_SHOW=1 _POWERLEVEL9K_PYENV_SHOW_SYSTEM=1
    local -a _POWERLEVEL9K_PYENV_SOURCES=(shell local global)
    if _p9k_pyenv_compute && [[ ${P9K_PYENV_PYTHON_VERSION-} =~ ^[0-9.]+ ]]; then
      _p9k__ret=$P9K_PYENV_PYTHON_VERSION
      return 0
    fi
  fi
  _p9k_cached_cmd 1 '' python --version || return 1
  [[ $_p9k__ret =~ ^Python\ ([0-9.]+) ]] && _p9k__ret=${BASH_REMATCH[1]}
  return 0
}

# --------------------------------------------------------------- virtualenv ---
# p10k: _p9k_parse_virtualenv_cfg - "prompt = ..." from pyvenv.cfg
# -> _p9k__vcfg_ok (0/1) and _p9k__vcfg_val
_p9k_parse_virtualenv_cfg() {
  _p9k__vcfg_ok=0 _p9k__vcfg_val=''
  [[ -f $1 && -r $1 ]] || return 0
  local line res=''
  local found=0
  while IFS= read -r line || [[ -n $line ]]; do
    if [[ $line =~ ^prompt[\ $'\t']*=(.*)$ ]]; then res=${BASH_REMATCH[1]}; found=1; break; fi
  done <"$1"
  (( found )) || return 0
  res=${res#"${res%%[! $'\t']*}"}; res=${res%"${res##*[! $'\t']}"}
  if [[ $res == \"*\" || $res == \'*\' ]]; then
    # p10k: ${(Vg:e:)${res[2,-2]}} - echo-style escapes, then control
    # characters shown visibly (^X)
    res=${res:1:${#res}-2}
    printf -v res '%b' "$res"
    local out='' i ch o
    for (( i = 0; i < ${#res}; i++ )); do
      ch=${res:i:1}; printf -v o '%d' "'$ch"
      if (( o < 32 )); then printf -v ch '^%b' "\\x$(printf %x $(( o + 64 )))"
      elif (( o == 127 )); then ch='^?'
      fi
      out+=$ch
    done
    res=$out
  fi
  _p9k__vcfg_ok=1 _p9k__vcfg_val=$res
}

prompt_virtualenv() {
  local msg=''
  if (( _POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION )) && _p9k_python_version; then
    msg="${_p9k__ret//%/%%} "
  fi
  _p9k_parse_virtualenv_cfg "$VIRTUAL_ENV/pyvenv.cfg"
  local v
  if (( _p9k__vcfg_ok )); then
    v=$_p9k__vcfg_val
  else
    v=${VIRTUAL_ENV%/}; v=${v##*/}
    local vp=${VIRTUAL_ENV_PROMPT-}
    if [[ $vp == '('?*') ' && $vp != "($v) " ]]; then
      v=${vp:1:${#vp}-3}
    elif [[ $v == @($_POWERLEVEL9K_VIRTUALENV_GENERIC_NAMES_PAT) ]]; then
      v=${VIRTUAL_ENV%/*}; v=${v##*/}
    fi
  fi
  msg+="$_POWERLEVEL9K_VIRTUALENV_LEFT_DELIMITER${v//%/%%}$_POWERLEVEL9K_VIRTUALENV_RIGHT_DELIMITER"
  case $_POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV in
    false)
      # only while pyenv shows no version (p10k: ${(M)${#P9K_PYENV_PYTHON_VERSION}:#0});
      # "1" from offset ${#var}: "1" when the variable is empty, else nothing
      _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PYTHON_ICON 0 '${_p9k__one:${#P9K_PYENV_PYTHON_VERSION}}' "$msg" ;;
    if-different)
      # only when the name differs from pyenv's version
      _p9k__venv_name=$v
      _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PYTHON_ICON 0 '${$((_p9k_venv_differs()))+$_p9k__venv_differs}' "$msg" ;;
    *)
      _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PYTHON_ICON 0 '' "$msg" ;;
  esac
}
_p9k__one=1
_p9k_venv_differs() {
  _p9k__venv_differs=''
  [[ $_p9k__venv_name == "${_p9k__pyenv_version-}" ]] || _p9k__venv_differs=$_p9k__venv_name
}
# p10k evaluates these conditions after every segment has run, so pyenv's
# result is known even though pyenv comes after virtualenv in the templates.
# Here pyenv's part is computed before the segments (as prompt_pyenv would).
_p9k_pyenv_pre() {
  unset P9K_PYENV_PYTHON_VERSION _p9k__pyenv_version
  _p9k_segment_in_use pyenv && _p9k_have pyenv && _p9k_pyenv_compute
  return 0
}
_p9k_prompt_virtualenv_init() {
  _p9k_set_cond '${VIRTUAL_ENV-}'
  [[ " ${_p9k__precompute[*]} " == *' _p9k_pyenv_pre '* ]] || _p9k__precompute+=(_p9k_pyenv_pre)
}

# ----------------------------------------------------------------- anaconda ---
prompt_anaconda() {
  local msg=''
  if _p9k_python_version; then
    P9K_ANACONDA_PYTHON_VERSION=$_p9k__ret
    (( _POWERLEVEL9K_ANACONDA_SHOW_PYTHON_VERSION )) && msg="${P9K_ANACONDA_PYTHON_VERSION//%/%%} "
  else
    unset P9K_ANACONDA_PYTHON_VERSION
  fi
  local p=${CONDA_PREFIX:-${CONDA_ENV_PATH-}}
  p=${p%/}; p=${p##*/}
  msg+="$_POWERLEVEL9K_ANACONDA_LEFT_DELIMITER${p//%/%%}$_POWERLEVEL9K_ANACONDA_RIGHT_DELIMITER"
  _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PYTHON_ICON 0 '' "$msg"
}
_p9k_prompt_anaconda_init() { _p9k_set_cond '${CONDA_PREFIX:-${CONDA_ENV_PATH-}}'; }

# ------------------------------------------------------------------ nodeenv ---
prompt_nodeenv() {
  local msg=''
  if (( _POWERLEVEL9K_NODEENV_SHOW_NODE_VERSION )) && _p9k_cached_cmd 0 '' node --version; then
    msg="${_p9k__ret//%/%%} "
  fi
  local n=${NODE_VIRTUAL_ENV%/}; n=${n##*/}
  msg+="$_POWERLEVEL9K_NODEENV_LEFT_DELIMITER${n//%/%%}$_POWERLEVEL9K_NODEENV_RIGHT_DELIMITER"
  _p9k_prompt_segment "${FUNCNAME[0]}" black green NODE_ICON 0 '' "$msg"
}
_p9k_prompt_nodeenv_init() { _p9k_set_cond '${NODE_VIRTUAL_ENV-}'; }

# ---------------------------------------------------------------------- nvm ---
# p10k: _p9k_nvm_ls_current - the version of the node on PATH
_p9k_nvm_ls_current() {
  local node; node=$(type -P node) || return 1
  node=$(realpath -- "$node" 2>/dev/null) || return 1
  local nvm_dir; nvm_dir=$(realpath -m -- "$NVM_DIR" 2>/dev/null)
  if [[ -n $nvm_dir && $node == "$nvm_dir"/versions/io.js/* ]]; then
    _p9k_cached_cmd 0 '' iojs --version || return 1
    _p9k__ret=iojs-v${_p9k__ret#v}
  elif [[ -n $nvm_dir && $node == "$nvm_dir"/* ]]; then
    _p9k_cached_cmd 0 '' node --version || return 1
    _p9k__ret=v${_p9k__ret#v}
  else
    _p9k__ret=system
  fi
}

# p10k: _p9k_nvm_ls_default - what `nvm alias default` resolves to
_p9k_nvm_ls_default() {
  local v=default target
  local -a seen=("$v")
  while [[ -r $NVM_DIR/alias/$v ]]; do
    target=''
    IFS='' read -r target <"$NVM_DIR/alias/$v"
    target=${target%$'\r'}
    [[ -z $target ]] && break
    local x; for x in "${seen[@]}"; do [[ $x == "$target" ]] && return 1; done
    seen+=("$target")
    v=$target
  done
  case $v in
    default|N/A) return 1 ;;
    system|v) _p9k__ret=system; return 0 ;;
    iojs-[0-9]*) v=iojs-v${v#iojs-} ;;
    [0-9]*) v=v$v ;;
  esac
  if [[ $v == v*.*.* ]]; then
    if [[ -x $NVM_DIR/versions/node/$v/bin/node || -x $NVM_DIR/$v/bin/node ]]; then
      _p9k__ret=$v; return 0
    elif [[ -x $NVM_DIR/versions/io.js/$v/bin/node ]]; then
      _p9k__ret=iojs-$v; return 0
    else
      return 1
    fi
  fi
  local -a dirs=()
  local pat
  case $v in
    node|node-|stable) dirs=("$NVM_DIR/versions/node" "$NVM_DIR"); pat='@(v[1-9]*|v0.*[02468].*)' ;;
    unstable) dirs=("$NVM_DIR/versions/node" "$NVM_DIR"); pat='v0.*[13579].*' ;;
    iojs*) dirs=("$NVM_DIR/versions/io.js"); v=${v#iojs}; v=${v#-}; pat="v${v#v}*" ;;
    *) dirs=("$NVM_DIR/versions/node" "$NVM_DIR" "$NVM_DIR/versions/io.js"); pat="v${v#v}*" ;;
  esac
  local had_ext=0 had_null=0 d p
  shopt -q extglob && had_ext=1; shopt -q nullglob && had_null=1
  shopt -s extglob nullglob
  local -a matches=()
  for d in "${dirs[@]}"; do for p in "$d"/$pat/; do matches+=("${p%/}"); done; done
  (( had_ext )) || shopt -u extglob; (( had_null )) || shopt -u nullglob
  (( ${#matches[@]} )) || return 1
  # the highest version: v(A).(B).(C), each part padded to 6 digits and
  # compared as text, as p10k does; (Oa) = examined last to first
  local max='' key name i a b c
  for (( i = ${#matches[@]} - 1; i >= 0; i-- )); do
    p=${matches[i]}; name=${p##*/}
    [[ $name =~ ^v(.*)\.(.*)\.(.*)$ ]] || continue
    printf -v a '%6s' "${BASH_REMATCH[1]}"; printf -v b '%6s' "${BASH_REMATCH[2]}"; printf -v c '%6s' "${BASH_REMATCH[3]}"
    key=${a// /0}${b// /0}${c// /0}
    [[ $key > $max ]] || continue
    max=$key _p9k__ret=$name
    d=${p%/*}; [[ ${d##*/} != io.js ]] || _p9k__ret=iojs-$_p9k__ret
  done
  [[ -n $max ]]
}

prompt_nvm() {
  [[ -n ${NVM_DIR-} ]] && _p9k_nvm_ls_current || return 0
  local current=$_p9k__ret
  (( _POWERLEVEL9K_NVM_SHOW_SYSTEM )) || [[ $current != system ]] || return 0
  (( _POWERLEVEL9K_NVM_PROMPT_ALWAYS_SHOW )) || ! _p9k_nvm_ls_default || [[ $_p9k__ret != "$current" ]] || return 0
  current=${current#v}
  _p9k_prompt_segment "${FUNCNAME[0]}" magenta black NODE_ICON 0 '' "${current//%/%%}"
}

# ---------------------------------------------------------------------- rvm ---
prompt_rvm() {
  [[ ${GEM_HOME-} == *rvm* && ${ruby_string-} != "${rvm_path-}/bin/ruby" ]] || return 0
  local v=${GEM_HOME%/}; v=${v##*/}
  (( _POWERLEVEL9K_RVM_SHOW_GEMSET )) || v=${v%%"${rvm_gemset_separator:-@}"*}
  (( _POWERLEVEL9K_RVM_SHOW_PREFIX )) || v=${v#*-}
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" 240 "$_p9k_color1" RUBY_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_rvm_init() { _p9k_set_cond '@_p9k_have rvm-prompt'; }

# ------------------------------------------------------------------- chruby ---
prompt_chruby() {
  local v=''
  # the engine is shown when it matches CHRUBY_SHOW_ENGINE_PATTERN (zsh pattern)
  [[ -n ${RUBY_ENGINE-} && $RUBY_ENGINE == @($_POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN_BASH) ]] && v=$RUBY_ENGINE
  [[ $_POWERLEVEL9K_CHRUBY_SHOW_VERSION == 1 && -n ${RUBY_VERSION-} ]] && v+=${v:+ }$RUBY_VERSION
  _p9k_prompt_segment "${FUNCNAME[0]}" red "$_p9k_color1" RUBY_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_chruby_init() {
  # zsh pattern -> bash extended pattern: (a|b) -> @(a|b)
  _POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN_BASH=${_POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN//(/@(}
  _p9k_set_cond '${RUBY_ENGINE-}'
}

# ----------------------------------------------------------------- perlbrew ---
prompt_perlbrew() {
  if (( _POWERLEVEL9K_PERLBREW_PROJECT_ONLY )); then
    _p9k_upglob 'cpanfile|.perltidyrc|(|MY)META.(yml|json)|(Makefile|Build).PL|*.(pl|pm|t|pod)' -. && return 0
  fi
  local v=${PERLBREW_PERL-}
  (( _POWERLEVEL9K_PERLBREW_SHOW_PREFIX )) || v=${v#*-}
  [[ -n $v ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" blue "$_p9k_color1" PERL_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_perlbrew_init() { _p9k_set_cond '${PERLBREW_PERL-}'; }

# ---------------------------------------------------------------------- fvm ---
# Flutter version: .fvm/flutter_sdk (new) or fvm (old) symlink in a parent.
prompt_fvm() {
  local link re
  _p9k_upglob .fvm/flutter_sdk @
  local i=$?
  if (( i )); then
    link=$(realpath -m -- "${_p9k__parent_dirs[i]}/.fvm/flutter_sdk" 2>/dev/null)
    re='/versions/([^/]+)$'
    if [[ $link =~ $re ]]; then
      _p9k_prompt_segment prompt_fvm blue "$_p9k_color1" FLUTTER_ICON 0 '' "${BASH_REMATCH[1]//%/%%}"
      return 0
    fi
  fi
  _p9k_upglob fvm @
  i=$?
  (( i )) || return 0
  link=$(realpath -m -- "${_p9k__parent_dirs[i]}/fvm" 2>/dev/null)
  re='/versions/([^/]+)/bin/flutter$'
  [[ $link =~ $re ]] && _p9k_prompt_segment prompt_fvm blue "$_p9k_color1" FLUTTER_ICON 0 '' "${BASH_REMATCH[1]//%/%%}"
  return 0
}
_p9k_prompt_fvm_init() { _p9k_set_cond '@_p9k_have_cmd fvm'; }

# ------------------------------------------------------------ haskell_stack ---
_p9k_haskell_stack_version() {
  _p9k__ret=$(STACK_YAML=$1 stack --silent --no-install-ghc --skip-ghc-check --no-terminal \
    --color=never --lock-file=read-only query compiler actual 2>/dev/null) || _p9k__ret=''
}
prompt_haskell_stack() {
  local has_shell=0 has_local=0 has_global=0 s
  for s in "${_POWERLEVEL9K_HASKELL_STACK_SOURCES[@]}"; do
    case $s in shell) has_shell=1 ;; local) has_local=1 ;; global) has_global=1 ;; esac
  done
  local groot=${STACK_ROOT:-$HOME/.stack}/global-project/stack.yaml
  if [[ -n ${STACK_YAML-} ]]; then
    (( has_shell )) || return 0
    _p9k_haskell_stack_version "$STACK_YAML"
  else
    (( has_local || has_global )) || return 0
    _p9k_upglob stack.yaml -.
    local idx=$?
    if (( ! idx )); then
      (( _POWERLEVEL9K_HASKELL_STACK_PROMPT_ALWAYS_SHOW )) || return 0
      (( has_global )) || return 0
      _p9k_haskell_stack_version "$groot"
    else
      (( has_local )) || return 0
      _p9k_haskell_stack_version "${_p9k__parent_dirs[idx]}/stack.yaml"
    fi
  fi
  [[ -n $_p9k__ret ]] || return 0
  local v=$_p9k__ret
  if (( ! _POWERLEVEL9K_HASKELL_STACK_PROMPT_ALWAYS_SHOW )); then
    _p9k_haskell_stack_version "$groot"
    [[ $v == "$_p9k__ret" ]] && return 0
  fi
  _p9k_prompt_segment "${FUNCNAME[0]}" yellow "$_p9k_color1" HASKELL_ICON 0 '' "${v//%/%%}"
}
_p9k_prompt_haskell_stack_init() { _p9k_set_cond '@_p9k_have_cmd stack'; }
