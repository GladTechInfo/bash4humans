# =============================================================================
#  lib/p10k/core.bash - Powerlevel10k for bash: settings, lookups, colours,
#  icons and the prompt-escape interpreter.
#
#  A port of romkatv/powerlevel10k internal/p10k.zsh (v1.21.0). Function and
#  variable names are p10k's own (_p9k_*, _POWERLEVEL9K_*) so each piece can
#  be compared with the original; where bash needs a different technique the
#  comment says which p10k function it stands for.
# =============================================================================

# ------------------------------------------------------------ declarations ---
# Is the variable set? (p10k: $+parameters[NAME]). Unlike [[ -v ]], an empty
# array counts as set - templates use NAME=() to switch things off.
_p9k_isset() { declare -p "$1" &>/dev/null; }

# zsh's %D{FMT} (ztrftime) -> _p9k__ret. Day/month names and AM/PM are
# zsh's own English ones whatever the locale, i.e. the C locale's; zsh adds
#   %f day of month, %K hour 0-23, %L hour 1-12 (all without padding),
#   %N nanoseconds, %. or %1. .. %9. fraction of a second with N digits;
# and %P is empty (zsh does not pass it on). The rest is C strftime.
_p9k_strftime() {
  local f=$1 out='' c now=${EPOCHREALTIME/,/.}
  local sec=${now%.*} us=${now#*.}000
  while [[ -n $f ]]; do
    if [[ $f != %* ]]; then out+=${f%%%*}; f=${f#"${f%%%*}"}; continue; fi
    c=${f:1:1}
    if [[ $c == [1-9] && ${f:2:1} == . ]]; then out+=${us:0:c}; f=${f:3}; continue; fi
    case $c in
      f) out+=%-d ;;
      K) out+=%-H ;;
      L) out+=%-I ;;
      N) out+=${us:0:9} ;;
      .) out+=${us:0:3} ;;
      P) ;;
      %) out+=%% ;;
      '') out+=%%; f=%x ;;
      *) out+=%$c ;;
    esac
    f=${f:2}
  done
  LC_ALL=C printf -v _p9k__ret "%($out)T" "$sec"
}

# p10k: _p9k_declare. Copies POWERLEVEL9K_X into _POWERLEVEL9K_X with a type,
# or sets the default when POWERLEVEL9K_X is not set.
#   -b bool (only the string "true" is true)   -i integer   -F float
#   -s string   -e string with backslash escapes expanded   -a array (-- DEFAULTS...)
_p9k_declare() {
  local type=$1 name=$2 set=0
  _p9k_isset "$name" && set=1
  (( $# > 2 || set )) || return 0
  case $type in
    -b)
      if (( set )); then
        [[ ${!name} == true ]] && declare -gi "_$name=1" || declare -gi "_$name=0"
      else
        declare -gi "_$name=$3"
      fi ;;
    -a)
      if (( set )); then
        eval "declare -ga _$name=(\"\${$name[@]}\")"
      else
        shift 3
        eval "declare -ga _$name=(\"\$@\")"
      fi ;;
    -i)
      if (( set )); then declare -gi "_$name=${!name}"; else declare -gi "_$name=${3:-0}"; fi ;;
    -F)
      # bash has no floating point type: keep the text; users of these compare with _p9k_fcmp.
      if (( set )); then declare -g "_$name=${!name}"; else declare -g "_$name=${3:-0}"; fi ;;
    -s)
      if (( set )); then declare -g "_$name=${!name}"; else declare -g "_$name=${3-}"; fi ;;
    -e)
      local v
      if (( set )); then v=${!name}; else v=${3-}; fi
      declare -g "_$name=${v@E}" ;;
  esac
}

_p9k_codeset_is_utf8() {
  [[ ${LC_ALL:-${LC_CTYPE:-${LANG-}}} == *[Uu][Tt][Ff]?(-)8* ]]
}

# p10k: _p9k_segment_in_use - is NAME (or NAME_joined) in either prompt?
_p9k_segment_in_use() {
  local s
  for s in "${_POWERLEVEL9K_LEFT_PROMPT_ELEMENTS[@]}" "${_POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS[@]}"; do
    [[ ${s%_joined} == "$1" ]] && return 0
  done
  return 1
}

# Compare two decimal numbers: _p9k_fcmp A OP B, OP one of < <= > >= ==.
_p9k_fcmp() {
  local a=$1 op=$2 b=$3
  # scale both to 6 decimal places as integers
  local ai af bi bf
  ai=${a%%.*} af=${a#*.}; [[ $a == *.* ]] || af=
  bi=${b%%.*} bf=${b#*.}; [[ $b == *.* ]] || bf=
  af=${af}000000 bf=${bf}000000
  local x=$(( 10#${ai:-0} * 1000000 + 10#${af:0:6} )) y=$(( 10#${bi:-0} * 1000000 + 10#${bf:0:6} ))
  [[ ${a:0:1} == - ]] && x=$(( 10#${ai#-} * -1000000 - 10#${af:0:6} ))
  [[ ${b:0:1} == - ]] && y=$(( 10#${bi#-} * -1000000 - 10#${bf:0:6} ))
  (( x $op y ))
}

# ---------------------------------------------------------------- params ---
# p10k: _p9k_init_params. Declaration by declaration, in p10k's order.
_p9k_init_params() {
  _p9k_declare -F POWERLEVEL9K_GCLOUD_REFRESH_PROJECT_NAME_SECONDS 60

  _p9k_declare -s POWERLEVEL9K_INSTANT_PROMPT  # verbose, quiet, off
  if [[ ${_POWERLEVEL9K_INSTANT_PROMPT-} == off ]]; then
    declare -gi _POWERLEVEL9K_DISABLE_INSTANT_PROMPT=1
  else
    _p9k_declare -b POWERLEVEL9K_DISABLE_INSTANT_PROMPT 0
    if (( _POWERLEVEL9K_DISABLE_INSTANT_PROMPT )); then
      _POWERLEVEL9K_INSTANT_PROMPT=off
    elif [[ ${_POWERLEVEL9K_INSTANT_PROMPT-} != quiet ]]; then
      _POWERLEVEL9K_INSTANT_PROMPT=verbose
    fi
  fi

  _p9k_declare -s POWERLEVEL9K_TRANSIENT_PROMPT off
  [[ $_POWERLEVEL9K_TRANSIENT_PROMPT == @(off|always|same-dir) ]] || _POWERLEVEL9K_TRANSIENT_PROMPT=off

  _p9k_declare -b POWERLEVEL9K_TERM_SHELL_INTEGRATION 0

  _p9k_declare -s POWERLEVEL9K_WORKER_LOG_LEVEL
  _p9k_declare -i POWERLEVEL9K_COMMANDS_MAX_TOKEN_COUNT 64
  _p9k_declare -a POWERLEVEL9K_HOOK_WIDGETS --
  _p9k_declare -b POWERLEVEL9K_TODO_HIDE_ZERO_TOTAL 0
  _p9k_declare -b POWERLEVEL9K_TODO_HIDE_ZERO_FILTERED 0
  _p9k_declare -b POWERLEVEL9K_DISABLE_HOT_RELOAD 0
  _p9k_declare -F POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS 5
  _p9k_declare -i POWERLEVEL9K_INSTANT_PROMPT_COMMAND_LINES
  _p9k_declare -a POWERLEVEL9K_LEFT_PROMPT_ELEMENTS -- context dir vcs
  _p9k_declare -a POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS -- status root_indicator background_jobs history time
  _p9k_declare -b POWERLEVEL9K_DISABLE_RPROMPT 0
  _p9k_declare -b POWERLEVEL9K_PROMPT_ADD_NEWLINE 0
  _p9k_declare -b POWERLEVEL9K_PROMPT_ON_NEWLINE 0
  _p9k_declare -b POWERLEVEL9K_RPROMPT_ON_NEWLINE 0
  _p9k_declare -b POWERLEVEL9K_SHOW_RULER 0
  _p9k_declare -i POWERLEVEL9K_PROMPT_ADD_NEWLINE_COUNT 1
  _p9k_declare -s POWERLEVEL9K_COLOR_SCHEME dark
  _p9k_declare -s POWERLEVEL9K_GITSTATUS_DIR ""
  _p9k_declare -s POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN
  _p9k_declare -b POWERLEVEL9K_VCS_SHOW_SUBMODULE_DIRTY 0
  _p9k_declare -i POWERLEVEL9K_VCS_SHORTEN_LENGTH
  _p9k_declare -i POWERLEVEL9K_VCS_SHORTEN_MIN_LENGTH
  _p9k_declare -s POWERLEVEL9K_VCS_SHORTEN_STRATEGY
  if _p9k_codeset_is_utf8; then
    _p9k_declare -e POWERLEVEL9K_VCS_SHORTEN_DELIMITER '…'
  else
    _p9k_declare -e POWERLEVEL9K_VCS_SHORTEN_DELIMITER '..'
  fi
  _p9k_declare -b POWERLEVEL9K_VCS_CONFLICTED_STATE 0
  _p9k_declare -b POWERLEVEL9K_HIDE_BRANCH_ICON 0
  _p9k_declare -b POWERLEVEL9K_VCS_HIDE_TAGS 0
  _p9k_declare -a POWERLEVEL9K_VCS_GIT_REMOTE_ICONS
  if _p9k_isset _POWERLEVEL9K_VCS_GIT_REMOTE_ICONS; then
    (( ${#_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[@]} & 1 )) && _POWERLEVEL9K_VCS_GIT_REMOTE_ICONS+=('')
  else
    # p10k builds zsh glob patterns; here: extended regular expressions on the remote URL.
    local -a domain2icon=(
      'archlinux.org'                  VCS_GIT_ARCHLINUX_ICON
      'dev.azure.com|visualstudio.com' VCS_GIT_AZURE_ICON
      'bitbucket.org'                  VCS_GIT_BITBUCKET_ICON
      'codeberg.org'                   VCS_GIT_CODEBERG_ICON
      'debian.org'                     VCS_GIT_DEBIAN_ICON
      'freebsd.org'                    VCS_GIT_FREEBSD_ICON
      'freedesktop.org'                VCS_GIT_FREEDESKTOP_ICON
      'gitea.com|gitea.io'             VCS_GIT_GITEA_ICON
      'github.com'                     VCS_GIT_GITHUB_ICON
      'gitlab.com'                     VCS_GIT_GITLAB_ICON
      'gnome.org'                      VCS_GIT_GNOME_ICON
      'gnu.org'                        VCS_GIT_GNU_ICON
      'kde.org'                        VCS_GIT_KDE_ICON
      'kernel.org'                     VCS_GIT_LINUX_ICON
      'sr.ht'                          VCS_GIT_SOURCEHUT_ICON
    )
    declare -ga _POWERLEVEL9K_VCS_GIT_REMOTE_ICONS=()
    _p9k_git_remote_icons_regex=1
    local i domain
    for (( i = 0; i < ${#domain2icon[@]}; i += 2 )); do
      domain=${domain2icon[i]//./\\.}
      _POWERLEVEL9K_VCS_GIT_REMOTE_ICONS+=(
        "^([A-Za-z0-9][A-Za-z0-9+.-]*://)?([^:/?#]*[.@])?($domain)([/:?#].*)?\$" "${domain2icon[i+1]}")
    done
    _POWERLEVEL9K_VCS_GIT_REMOTE_ICONS+=('.*' VCS_GIT_ICON)
  fi
  _p9k_declare -i POWERLEVEL9K_CHANGESET_HASH_LENGTH 8
  _p9k_declare -i POWERLEVEL9K_MAX_CACHE_SIZE 10000
  _p9k_declare -e POWERLEVEL9K_ANACONDA_LEFT_DELIMITER "("
  _p9k_declare -e POWERLEVEL9K_ANACONDA_RIGHT_DELIMITER ")"
  _p9k_declare -b POWERLEVEL9K_ANACONDA_SHOW_PYTHON_VERSION 1
  _p9k_declare -b POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE 1
  _p9k_declare -b POWERLEVEL9K_BACKGROUND_JOBS_VERBOSE_ALWAYS 0
  _p9k_declare -b POWERLEVEL9K_DISK_USAGE_ONLY_WARNING 0
  _p9k_declare -i POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL 90
  _p9k_declare -i POWERLEVEL9K_DISK_USAGE_CRITICAL_LEVEL 95
  _p9k_declare -i POWERLEVEL9K_BATTERY_LOW_THRESHOLD 10
  _p9k_declare -i POWERLEVEL9K_BATTERY_HIDE_ABOVE_THRESHOLD 999
  _p9k_declare -b POWERLEVEL9K_BATTERY_VERBOSE 1
  _p9k_declare -a POWERLEVEL9K_BATTERY_LEVEL_BACKGROUND --
  _p9k_declare -a POWERLEVEL9K_BATTERY_LEVEL_FOREGROUND --
  _p9k_stages_from POWERLEVEL9K_BATTERY_STAGES _POWERLEVEL9K_BATTERY_STAGES
  local state var
  for state in CHARGED CHARGING LOW DISCONNECTED; do
    _p9k_declare -i POWERLEVEL9K_BATTERY_${state}_HIDE_ABOVE_THRESHOLD $_POWERLEVEL9K_BATTERY_HIDE_ABOVE_THRESHOLD
    var=POWERLEVEL9K_BATTERY_${state}_STAGES
    if _p9k_isset $var; then _p9k_stages_from $var _$var
    else eval "declare -ga _$var=(\"\${_POWERLEVEL9K_BATTERY_STAGES[@]}\")"
    fi
    var=POWERLEVEL9K_BATTERY_${state}_LEVEL_BACKGROUND
    if [[ $(declare -p $var 2>/dev/null) == "declare -a"* ]]; then eval "declare -ga _$var=(\"\${$var[@]}\")"
    else eval "declare -ga _$var=(\"\${_POWERLEVEL9K_BATTERY_LEVEL_BACKGROUND[@]}\")"
    fi
    var=POWERLEVEL9K_BATTERY_${state}_LEVEL_FOREGROUND
    if [[ $(declare -p $var 2>/dev/null) == "declare -a"* ]]; then eval "declare -ga _$var=(\"\${$var[@]}\")"
    else eval "declare -ga _$var=(\"\${_POWERLEVEL9K_BATTERY_LEVEL_FOREGROUND[@]}\")"
    fi
  done
  _p9k_declare -F POWERLEVEL9K_PUBLIC_IP_TIMEOUT 300
  _p9k_declare -a POWERLEVEL9K_PUBLIC_IP_METHODS -- dig curl wget
  _p9k_declare -e POWERLEVEL9K_PUBLIC_IP_NONE ""
  _p9k_declare -s POWERLEVEL9K_PUBLIC_IP_HOST "https://v4.ident.me/"
  _p9k_declare -s POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE ""
  _p9k_segment_in_use public_ip || _POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE=
  _p9k_declare -b POWERLEVEL9K_ALWAYS_SHOW_CONTEXT 0
  _p9k_declare -b POWERLEVEL9K_ALWAYS_SHOW_USER 0
  _p9k_declare -e POWERLEVEL9K_CONTEXT_TEMPLATE "%n@%m"
  _p9k_declare -e POWERLEVEL9K_USER_TEMPLATE "%n"
  _p9k_declare -e POWERLEVEL9K_HOST_TEMPLATE "%m"
  _p9k_declare -F POWERLEVEL9K_COMMAND_EXECUTION_TIME_THRESHOLD 3
  _p9k_declare -i POWERLEVEL9K_COMMAND_EXECUTION_TIME_PRECISION 2
  _p9k_declare -s POWERLEVEL9K_COMMAND_EXECUTION_TIME_FORMAT "H:M:S"
  _p9k_declare -e POWERLEVEL9K_HOME_FOLDER_ABBREVIATION "~"
  _p9k_declare -b POWERLEVEL9K_DIR_PATH_ABSOLUTE 0
  _p9k_declare -s POWERLEVEL9K_DIR_SHOW_WRITABLE ''
  case $_POWERLEVEL9K_DIR_SHOW_WRITABLE in
    true) _POWERLEVEL9K_DIR_SHOW_WRITABLE=1 ;;
    v2)   _POWERLEVEL9K_DIR_SHOW_WRITABLE=2 ;;
    v3)   _POWERLEVEL9K_DIR_SHOW_WRITABLE=3 ;;
    *)    _POWERLEVEL9K_DIR_SHOW_WRITABLE=0 ;;
  esac
  _p9k_declare -b POWERLEVEL9K_DIR_OMIT_FIRST_CHARACTER 0
  _p9k_declare -b POWERLEVEL9K_DIR_HYPERLINK 0
  _p9k_declare -s POWERLEVEL9K_SHORTEN_STRATEGY ""
  local -a markers=(.bzr .citc .git .hg .node-version .python-version .ruby-version
                    .shorten_folder_marker .svn .terraform CVS Cargo.toml composer.json go.mod package.json)
  local IFS='|'
  _p9k_declare -s POWERLEVEL9K_SHORTEN_FOLDER_MARKER "(${markers[*]})"
  unset IFS
  _p9k_declare -s POWERLEVEL9K_DIR_MAX_LENGTH 0
  _p9k_declare -a POWERLEVEL9K_DIR_PACKAGE_FILES -- package.json composer.json
  _p9k_declare -i POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS 40
  _p9k_declare -F POWERLEVEL9K_DIR_MIN_COMMAND_COLUMNS_PCT 50
  _p9k_declare -a POWERLEVEL9K_DIR_CLASSES
  _p9k_declare -i POWERLEVEL9K_SHORTEN_DELIMITER_LENGTH
  _p9k_declare -e POWERLEVEL9K_SHORTEN_DELIMITER
  _p9k_declare -s POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER ''
  if [[ $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER == first || $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER == last ]]; then
    _POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER+=:0
  elif [[ ! $_POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER =~ ^(first|last):-?[0-9]+$ ]]; then
    _POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=
  fi
  [[ -z $_POWERLEVEL9K_SHORTEN_FOLDER_MARKER ]] && _POWERLEVEL9K_DIR_TRUNCATE_BEFORE_MARKER=
  _p9k_declare -i POWERLEVEL9K_SHORTEN_DIR_LENGTH
  _p9k_declare -s POWERLEVEL9K_IP_INTERFACE ""
  : "${_POWERLEVEL9K_IP_INTERFACE:=.*}"
  _p9k_segment_in_use ip || _POWERLEVEL9K_IP_INTERFACE=
  _p9k_declare -s POWERLEVEL9K_VPN_IP_INTERFACE "(gpd|wg|(.*tun)|tailscale)[0-9]*|(zt.*)"
  : "${_POWERLEVEL9K_VPN_IP_INTERFACE:=.*}"
  _p9k_segment_in_use vpn_ip || _POWERLEVEL9K_VPN_IP_INTERFACE=
  _p9k_declare -b POWERLEVEL9K_VPN_IP_SHOW_ALL 0
  _p9k_declare -i POWERLEVEL9K_LOAD_WHICH 5
  case $_POWERLEVEL9K_LOAD_WHICH in
    1)  _POWERLEVEL9K_LOAD_WHICH=1 ;;
    15) _POWERLEVEL9K_LOAD_WHICH=3 ;;
    *)  _POWERLEVEL9K_LOAD_WHICH=2 ;;
  esac
  _p9k_declare -F POWERLEVEL9K_LOAD_WARNING_PCT 50
  _p9k_declare -F POWERLEVEL9K_LOAD_CRITICAL_PCT 70
  _p9k_declare -b POWERLEVEL9K_NODE_VERSION_PROJECT_ONLY 0
  _p9k_declare -b POWERLEVEL9K_PHP_VERSION_PROJECT_ONLY 0
  _p9k_declare -b POWERLEVEL9K_DOTNET_VERSION_PROJECT_ONLY 1
  _p9k_declare -b POWERLEVEL9K_GO_VERSION_PROJECT_ONLY 1
  _p9k_declare -b POWERLEVEL9K_RUST_VERSION_PROJECT_ONLY 1
  _p9k_declare -b POWERLEVEL9K_PERLBREW_PROJECT_ONLY 1
  _p9k_declare -b POWERLEVEL9K_PERLBREW_SHOW_PREFIX 0
  _p9k_declare -b POWERLEVEL9K_JAVA_VERSION_PROJECT_ONLY 0
  local tool
  for tool in NODENV RBENV SCALAENV PHPENV LUAENV JENV PLENV PYENV GOENV; do
    _p9k_declare -b POWERLEVEL9K_${tool}_PROMPT_ALWAYS_SHOW 0
    _p9k_declare -a POWERLEVEL9K_${tool}_SOURCES -- shell local global
    _p9k_declare -b POWERLEVEL9K_${tool}_SHOW_SYSTEM 1
  done
  _p9k_declare -b POWERLEVEL9K_NVM_PROMPT_ALWAYS_SHOW 0
  _p9k_declare -b POWERLEVEL9K_NVM_SHOW_SYSTEM 1
  _p9k_declare -b POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW 0
  _p9k_declare -b POWERLEVEL9K_ASDF_SHOW_SYSTEM 1
  _p9k_declare -a POWERLEVEL9K_ASDF_SOURCES -- shell local global
  for var in $(compgen -v POWERLEVEL9K_ASDF_); do
    case $var in
      *_PROMPT_ALWAYS_SHOW) _p9k_declare -b $var $_POWERLEVEL9K_ASDF_PROMPT_ALWAYS_SHOW ;;
      *_SHOW_SYSTEM)        _p9k_declare -b $var $_POWERLEVEL9K_ASDF_SHOW_SYSTEM ;;
      *_SOURCES)            _p9k_declare -a $var -- "${_POWERLEVEL9K_ASDF_SOURCES[@]}" ;;
    esac
  done
  _p9k_declare -b POWERLEVEL9K_HASKELL_STACK_PROMPT_ALWAYS_SHOW 1
  _p9k_declare -a POWERLEVEL9K_HASKELL_STACK_SOURCES -- shell local
  _p9k_declare -b POWERLEVEL9K_RVM_SHOW_GEMSET 0
  _p9k_declare -b POWERLEVEL9K_RVM_SHOW_PREFIX 0
  _p9k_declare -b POWERLEVEL9K_CHRUBY_SHOW_VERSION 1
  _p9k_declare -b POWERLEVEL9K_CHRUBY_SHOW_ENGINE 1
  _p9k_declare -s POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN
  if (( _POWERLEVEL9K_CHRUBY_SHOW_ENGINE )); then
    [[ -v _POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN ]] || _POWERLEVEL9K_CHRUBY_SHOW_ENGINE_PATTERN='*'
  fi
  _p9k_declare -b POWERLEVEL9K_STATUS_CROSS 0
  _p9k_declare -b POWERLEVEL9K_STATUS_OK 1
  _p9k_declare -b POWERLEVEL9K_STATUS_OK_PIPE 1
  _p9k_declare -b POWERLEVEL9K_STATUS_ERROR 1
  _p9k_declare -b POWERLEVEL9K_STATUS_ERROR_PIPE 1
  _p9k_declare -b POWERLEVEL9K_STATUS_ERROR_SIGNAL 1
  _p9k_declare -b POWERLEVEL9K_STATUS_SHOW_PIPESTATUS 1
  _p9k_declare -b POWERLEVEL9K_STATUS_HIDE_SIGNAME 0
  _p9k_declare -b POWERLEVEL9K_STATUS_VERBOSE_SIGNAME 1
  _p9k_declare -b POWERLEVEL9K_STATUS_EXTENDED_STATES 0
  _p9k_declare -b POWERLEVEL9K_STATUS_VERBOSE 1
  _p9k_declare -b POWERLEVEL9K_STATUS_OK_IN_NON_VERBOSE 0
  _p9k_declare -e POWERLEVEL9K_DATE_FORMAT "%D{%d.%m.%y}"
  _p9k_declare -s POWERLEVEL9K_VCS_ACTIONFORMAT_FOREGROUND 1
  _p9k_declare -b POWERLEVEL9K_SHOW_CHANGESET 0
  _p9k_declare -e POWERLEVEL9K_VCS_LOADING_TEXT loading
  _p9k_declare -a POWERLEVEL9K_VCS_GIT_HOOKS -- vcs-detect-changes git-untracked git-aheadbehind git-stash git-remotebranch git-tagname
  _p9k_declare -a POWERLEVEL9K_VCS_HG_HOOKS -- vcs-detect-changes
  _p9k_declare -a POWERLEVEL9K_VCS_SVN_HOOKS -- vcs-detect-changes svn-detect-changes
  _p9k_declare -F POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS 0.01
  _p9k_declare -a POWERLEVEL9K_VCS_BACKENDS -- git
  if ! command -v git >/dev/null; then
    local -a keep=(); local b
    for b in "${_POWERLEVEL9K_VCS_BACKENDS[@]}"; do [[ $b == git ]] || keep+=("$b"); done
    _POWERLEVEL9K_VCS_BACKENDS=("${keep[@]}")
  fi
  _p9k_declare -b POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING 0
  _p9k_declare -i POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY -1
  _p9k_declare -i POWERLEVEL9K_VCS_STAGED_MAX_NUM 1
  _p9k_declare -i POWERLEVEL9K_VCS_UNSTAGED_MAX_NUM 1
  _p9k_declare -i POWERLEVEL9K_VCS_UNTRACKED_MAX_NUM 1
  _p9k_declare -i POWERLEVEL9K_VCS_CONFLICTED_MAX_NUM 1
  _p9k_declare -i POWERLEVEL9K_VCS_COMMITS_AHEAD_MAX_NUM -1
  _p9k_declare -i POWERLEVEL9K_VCS_COMMITS_BEHIND_MAX_NUM -1
  _p9k_declare -b POWERLEVEL9K_VCS_RECURSE_UNTRACKED_DIRS 0
  _p9k_declare -F POWERLEVEL9K_GITSTATUS_INIT_TIMEOUT_SEC 10
  _p9k_declare -b POWERLEVEL9K_DISABLE_GITSTATUS 0
  _p9k_declare -e POWERLEVEL9K_VI_INSERT_MODE_STRING "INSERT"
  _p9k_declare -e POWERLEVEL9K_VI_COMMAND_MODE_STRING "NORMAL"
  _p9k_declare -e POWERLEVEL9K_VI_VISUAL_MODE_STRING
  _p9k_declare -e POWERLEVEL9K_VI_OVERWRITE_MODE_STRING
  _p9k_declare -s POWERLEVEL9K_VIRTUALENV_SHOW_WITH_PYENV true
  _p9k_declare -b POWERLEVEL9K_VIRTUALENV_SHOW_PYTHON_VERSION 1
  _p9k_declare -e POWERLEVEL9K_VIRTUALENV_LEFT_DELIMITER "("
  _p9k_declare -e POWERLEVEL9K_VIRTUALENV_RIGHT_DELIMITER ")"
  _p9k_declare -a POWERLEVEL9K_VIRTUALENV_GENERIC_NAMES -- virtualenv venv .venv env
  IFS='|'; _POWERLEVEL9K_VIRTUALENV_GENERIC_NAMES_PAT="${_POWERLEVEL9K_VIRTUALENV_GENERIC_NAMES[*]}"; unset IFS
  _p9k_declare -b POWERLEVEL9K_NODEENV_SHOW_NODE_VERSION 1
  _p9k_declare -e POWERLEVEL9K_NODEENV_LEFT_DELIMITER "["
  _p9k_declare -e POWERLEVEL9K_NODEENV_RIGHT_DELIMITER "]"
  _p9k_declare -b POWERLEVEL9K_KUBECONTEXT_SHOW_DEFAULT_NAMESPACE 1
  _p9k_declare -a POWERLEVEL9K_KUBECONTEXT_SHORTEN --
  _p9k_declare -a POWERLEVEL9K_KUBECONTEXT_CLASSES --
  _p9k_declare -a POWERLEVEL9K_AWS_CLASSES --
  _p9k_declare -a POWERLEVEL9K_AZURE_CLASSES --
  _p9k_declare -a POWERLEVEL9K_TERRAFORM_CLASSES --
  _p9k_declare -b POWERLEVEL9K_TERRAFORM_SHOW_DEFAULT 0
  _p9k_declare -a POWERLEVEL9K_GOOGLE_APP_CRED_CLASSES -- 'service_account:*' SERVICE_ACCOUNT
  _p9k_declare -b POWERLEVEL9K_JAVA_VERSION_FULL 1
  _p9k_declare -b POWERLEVEL9K_PROMPT_CHAR_OVERWRITE_STATE 0
  _p9k_declare -e POWERLEVEL9K_TIME_FORMAT "%D{%H:%M:%S}"
  _p9k_declare -b POWERLEVEL9K_TIME_UPDATE_ON_COMMAND 0
  _p9k_declare -b POWERLEVEL9K_EXPERIMENTAL_TIME_REALTIME 0
  _p9k_declare -F POWERLEVEL9K_EXPERIMENTAL_TIME_REALTIME_INTERVAL_SEC 1
  _p9k_declare -b POWERLEVEL9K_NIX_SHELL_INFER_FROM_PATH 0

  # Segments switched off with POWERLEVEL9K_<SEG>_[LEFT_|RIGHT_]DISABLED=true.
  local side seg u i
  for side in LEFT RIGHT; do
    eval "local -a els=(\"\${_POWERLEVEL9K_${side}_PROMPT_ELEMENTS[@]}\")"
    local -a keep=()
    for seg in "${els[@]}"; do
      u=${seg^^}
      var=POWERLEVEL9K_${u}_${side}_DISABLED
      [[ -v $var ]] || var=POWERLEVEL9K_${u}_DISABLED
      [[ ${!var-} == true ]] || keep+=("$seg")
    done
    eval "_POWERLEVEL9K_${side}_PROMPT_ELEMENTS=(\"\${keep[@]}\")"
  done

  # Every other POWERLEVEL9K_* is copied as it is.
  for var in "${!POWERLEVEL9K_@}"; do
    _p9k_isset _$var && continue
    if [[ $(declare -p "$var" 2>/dev/null) == "declare -a"* ]]; then
      eval "declare -ga _$var=(\"\${$var[@]}\")"
    else
      declare -g "_$var=${!var}"
    fi
  done
}

# BATTERY_STAGES may be a string (one stage per character) or an array.
_p9k_stages_from() {   # SOURCE DEST
  local src=$1 dst=$2
  if [[ $(declare -p "$src" 2>/dev/null) == "declare -a"* ]]; then
    eval "local -a v=(\"\${$src[@]}\")"
    local -a out=() x
    for x in "${v[@]}"; do out+=("${x@E}"); done
    eval "declare -ga $dst=(\"\${out[@]}\")"
  elif _p9k_isset "$src"; then
    local s=${!src}; s=${s@E}
    local -a out=() i
    for (( i = 0; i < ${#s}; i++ )); do out+=("${s:i:1}"); done
    eval "declare -ga $dst=(\"\${out[@]}\")"
  else
    eval "declare -ga $dst=()"
  fi
}

# Unset the configuration (p10k: unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR').
_p9k_unset_config() {
  local v
  for v in "${!POWERLEVEL9K_@}"; do
    [[ $v == POWERLEVEL9K_GITSTATUS_DIR ]] || unset "$v"
  done
  unset DEFAULT_USER
}

# ----------------------------------------------------------------- lookups ---
declare -gA _p9k_cache=()

# p10k: _p9k_param SEGMENT_STATE NAME DEFAULT -> _p9k__ret
# prompt_vcs_CLEAN FOREGROUND: _POWERLEVEL9K_VCS_CLEAN_FOREGROUND, then
# _POWERLEVEL9K_VCS_FOREGROUND, then _POWERLEVEL9K_FOREGROUND, then DEFAULT.
_p9k_param() {
  local key="p$1"$'\1'"$2"$'\1'"${3-}"
  if [[ -v _p9k_cache[$key] ]]; then _p9k__ret=${_p9k_cache[$key]}; return; fi
  local s=${1//-/_} var
  if [[ $s =~ ^prompt_([a-z0-9_]*)(.*)$ ]]; then
    local m1=${BASH_REMATCH[1]} m2=${BASH_REMATCH[2]}
    var=_POWERLEVEL9K_${m1^^}${m2}_$2
    if [[ -v $var ]]; then _p9k__ret=${!var}
    else
      var=_POWERLEVEL9K_${m1%_}; var=${var^^}_$2
      if [[ -v $var ]]; then _p9k__ret=${!var}
      else
        var=_POWERLEVEL9K_$2
        if [[ -v $var ]]; then _p9k__ret=${!var}; else _p9k__ret=${3-}; fi
      fi
    fi
  else
    var=_POWERLEVEL9K_$2
    if [[ -v $var ]]; then _p9k__ret=${!var}; else _p9k__ret=${3-}; fi
  fi
  _p9k_cache[$key]=$_p9k__ret
}

# p10k: _p9k_get_icon SEGMENT NAME [DEFAULT] -> _p9k__ret (escapes expanded)
_p9k_get_icon() {
  local key="i$1"$'\1'"$2"$'\1'"${3-}"
  if [[ -v _p9k_cache[$key] ]]; then _p9k__ret=${_p9k_cache[$key]}; return; fi
  if [[ $2 == $'\1'* ]]; then
    _p9k__ret=${2:1}
  else
    if [[ -v icons[$2] ]]; then _p9k_param "$1" "$2" "${icons[$2]}"
    else _p9k_param "$1" "$2" $'\1'"${3-}"
    fi
    if [[ $_p9k__ret == $'\1'* ]]; then
      _p9k__ret=${_p9k__ret:1}
    else
      _p9k__ret=${_p9k__ret@E}
    fi
  fi
  _p9k_cache[$key]=$_p9k__ret
}

# p10k: _p9k_translate_color -> _p9k__ret: 3-digit number, #hex, or '' (default)
_p9k_translate_color() {
  local c=$1
  if [[ $c =~ ^[0-9]+$ ]]; then
    printf -v _p9k__ret '%03d' "$((10#$c))"
  elif [[ $c =~ ^#[0-9A-Fa-f]+$ ]]; then
    _p9k__ret=${c,,}
  else
    c=${c#bg-}; c=${c#fg-}; c=${c#br}
    if [[ -n $c ]]; then _p9k__ret=${_p9k_colors[$c]-}; else _p9k__ret=; fi
  fi
}

# p10k: _p9k_color SEGMENT NAME DEFAULT -> _p9k__ret (translated colour)
_p9k_color() {
  local key="c$1"$'\1'"$2"$'\1'"${3-}"
  if [[ -v _p9k_cache[$key] ]]; then _p9k__ret=${_p9k_cache[$key]}; return; fi
  _p9k_param "$@"
  _p9k_translate_color "$_p9k__ret"
  _p9k_cache[$key]=$_p9k__ret
}

_p9k_background() { if [[ -n $1 ]]; then _p9k__ret="%K{$1}"; else _p9k__ret='%k'; fi; }
_p9k_foreground() { if [[ -n $1 ]]; then _p9k__ret="%F{$1}"; else _p9k__ret='%f'; fi; }

# ------------------------------------------------- prompt-escape interpreter ---
# zsh prompt sequences -> terminal codes, plus the visible width.
#   _p9k_pe STRING  -> _p9k__pe (with \001..\002 around codes when
#                      _p9k__pe_mark=1, for readline) and _p9k__pw (columns)
# Handles: %% %F{c} %NF %f %K{c} %NK %k %B %b %U %u %S %s %{..%} %G %n %m %M
#          %~ %/ %d %# %D{fmt} %* %T %t %h %! %?
_p9k__pe_mark=0
_p9k__pe_cont=0   # 1: carry colour/attribute state over from the previous call

# zsh's colour and attribute state while it prints a prompt, reproduced
# because it shows on screen. zsh re-applies the current colours after %B,
# %b (which is ESC[0m), %u and %s. A colour given as #rrggbb sets a "24-bit"
# flag that a later palette colour does not clear (only %f/%k/default do),
# so colour N is then re-applied as the 24-bit value N, i.e. #0000NN - a zsh
# quirk (5.8 and 5.9) that p10k users see, e.g. Pure's Snazzy colours.
#   _p9k__pes_fg/bg: '' (default) or the SGR parameters last used
#   _p9k__pes_fgn/bgn: the colour as a number (palette index or 0xRRGGBB)
#   _p9k__pes_fgt/bgt: the 24-bit flag   _p9k__pes_u/s: underline/standout on
_p9k_pe_reset() {
  _p9k__pes_fg='' _p9k__pes_bg='' _p9k__pes_fgn=0 _p9k__pes_bgn=0
  _p9k__pes_fgt=0 _p9k__pes_bgt=0 _p9k__pes_u=0 _p9k__pes_s=0 _p9k__pes_b=0
}
_p9k_pe_reset

# Record a colour change. $1 = 38 or 48, $2 = SGR parameters -> state updated.
# $3, if given: the palette colour these parameters stand for. A terminal
# without setaf gets 3N / 4N, so 39 / 49 can be colour 9, not the default.
_p9k_pe_setcol() {
  local k=fg; [[ $1 == 48 ]] && k=bg
  local p=$2 n=0 t=-1
  case ${3:+raw}$p in
    raw*) n=$3 ;;
    39|49) p='' t=0 ;;
    3[0-7]|4[0-7]) n=${p:1} ;;
    9[0-7]) n=$(( ${p:1} + 8 )) ;;
    10[0-7]) n=$(( ${p:2} + 8 )) ;;
    [34]8\;5\;*) n=${p##*;} ;;
    [34]8\;2\;*) local r=${p#*;2;}; local IFS=';'; local -a c=($r); n=$(( c[0] << 16 | c[1] << 8 | c[2] )); t=1 ;;
  esac
  printf -v "_p9k__pes_$k" '%s' "$p"
  printf -v "_p9k__pes_${k}n" '%s' "$n"
  (( t >= 0 )) && printf -v "_p9k__pes_${k}t" '%s' "$t"
  return 0
}

# Codes zsh prints to re-apply the current colours -> _p9k__ret
_p9k_pe_recol() {
  local o=$1 e=$2 n
  _p9k__ret=''
  if [[ -n $_p9k__pes_fg ]]; then
    if (( _p9k__pes_fgt )); then n=$_p9k__pes_fgn; _p9k__ret+="$o"$'\e[38;2;'"$(( n >> 16 & 255 ));$(( n >> 8 & 255 ));$(( n & 255 ))m$e"
    else _p9k__ret+="$o"$'\e['"${_p9k__pes_fg}m$e"; fi
  fi
  if [[ -n $_p9k__pes_bg ]]; then
    if (( _p9k__pes_bgt )); then n=$_p9k__pes_bgn; _p9k__ret+="$o"$'\e[48;2;'"$(( n >> 16 & 255 ));$(( n >> 8 & 255 ));$(( n & 255 ))m$e"
    else _p9k__ret+="$o"$'\e['"${_p9k__pes_bg}m$e"; fi
  fi
}

# ncurses (tinfo/trim_sgr0.c), which zsh asks for termcap's `me`: sgr0,
# unless the terminal's sgr with all attributes off says the same more
# simply - then that, without the part that leaves the alternate character
# set (rmacs) or the SGR 10 that does the same. (tput has already dropped
# padding such as $<2>, so ncurses' delay handling is not needed.)
#   _p9k_nc_trim_sgr0 SGR0 SGR(0..0) SGR(0..0,1) SMACS RMACS -> _p9k__ret
_p9k_nc_is_csi() {   # STRING -> _p9k__ret: 1 (CSI byte), 2 (ESC [) or 0
  if [[ ${1:0:1} == $'\x9b' ]]; then _p9k__ret=1
  elif [[ ${1:0:2} == $'\e[' ]]; then _p9k__ret=2
  else _p9k__ret=0
  fi
}
_p9k_nc_skip_zero() {   # STRING -> _p9k__ret: without a leading "0;" or "0" before a letter
  local s=$1
  if [[ ${s:0:1} == 0 ]]; then
    if [[ ${s:1:1} == ';' ]]; then s=${s:2}
    elif [[ ${s:1:1} == [[:alpha:]] ]]; then s=${s:1}
    fi
  fi
  _p9k__ret=$s
}
_p9k_nc_rewrite_sgr() {   # STRING ATTR -> _p9k__ret: ATTR moved from the front to the end
  local s=$1 a=$2
  [[ -n $a && ${#s} -gt ${#a} && ${s:0:${#a}} == "$a" ]] && s=${s:${#a}}$a
  _p9k__ret=$s
}
_p9k_nc_similar_sgr() {   # A B -> status 0 if one starts with the other (after CSI, 0)
  local a=$1 b=$2 ca cb
  _p9k_nc_is_csi "$a"; ca=$_p9k__ret
  _p9k_nc_is_csi "$b"; cb=$_p9k__ret
  if (( ca && cb && ca == cb )); then
    a=${a:ca} b=${b:cb}
    if [[ ${a:0:1} != "${b:0:1}" ]]; then
      _p9k_nc_skip_zero "$a"; a=$_p9k__ret
      _p9k_nc_skip_zero "$b"; b=$_p9k__ret
    fi
  fi
  [[ -n $a && -n $b ]] || return 1
  if (( ${#a} > ${#b} )); then [[ ${a:0:${#b}} == "$b" ]]; else [[ ${b:0:${#a}} == "$a" ]]; fi
}
_p9k_nc_trim_sgr0() {
  local sgr0=$1 off=$2 on=$3 smacs=$4 rmacs=$5 end found=0 i j k tmp
  _p9k__ret=$sgr0
  [[ -n $sgr0 && -n $off && -n $on ]] || return 0
  _p9k_nc_rewrite_sgr "$on" "$smacs"; on=$_p9k__ret
  _p9k_nc_rewrite_sgr "$off" "$rmacs"; off=$_p9k__ret
  _p9k_nc_rewrite_sgr "$sgr0" "$rmacs"; end=$_p9k__ret
  if ! _p9k_nc_similar_sgr "$off" "$end" || _p9k_nc_similar_sgr "$off" "$on"; then
    _p9k__ret=$sgr0; return 0
  fi
  local result=$off
  # rmacs inside sgr(0): cut it out (the first place it occurs)
  if [[ -n $rmacs ]]; then
    j=${#off} k=${#rmacs}
    if (( j > k )); then
      for (( i = 0; i <= j - k; i++ )); do
        if [[ ${off:i:k} == "$rmacs" ]]; then
          off=${off:0:i}${off:i+k}; result=$off found=1; break
        fi
      done
    fi
  fi
  # else an SGR 10 (normal font) inside CSI ... m: cut it out
  if (( ! found )); then
    _p9k_nc_is_csi "$off"; i=$_p9k__ret
    if (( i )) && [[ ${off: -1} == m ]]; then
      _p9k_nc_skip_zero "${off:i}"; tmp=$_p9k__ret
      local p=$(( ${#off} - ${#tmp} ))   # where tmp starts in off
      _p9k_nc_skip_zero "${tmp:1}"
      if [[ ${tmp:0:1} == 1 && $_p9k__ret != "${tmp:1}" ]]; then
        j=$(( ${#off} - ${#_p9k__ret} ))
        i=$p; [[ ${off:i-1:1} == ';' ]] && (( i-- ))
        off=${off:0:i}${off:j}; result=$off found=1
      fi
    fi
  fi
  # else sgr(0) inside sgr0 (as rewritten): sgr0 without it
  if (( ! found )) && [[ $end == *"$off"* && $end != "$off" ]]; then
    tmp=${end%%"$off"*}
    result=$tmp${end:${#tmp}+${#off}}
  fi
  _p9k__ret=$result
}

# The terminal's colours, as zsh uses them (it reads terminfo for TERM):
# _p9k__tc_colors = terminfo's colour count (-1: none given), and for the
# colours 8 .. count-1 (at most 255) the SGR parameters of terminfo's
# setaf / setab, in _p9k__tc_fg[N] / _p9k__tc_bg[N]. Read once per TERM
# (one tput call each for the count and the sequences). Without tput the
# common xterm-256color sequences are assumed.
#
# Also the attribute codes zsh prints for %B %b %U %u %S %s: the termcap
# strings md me us ue so se, in _p9k__tc_md ... _p9k__tc_se ('' where the
# terminal has none: zsh then prints nothing). zsh asks ncurses by termcap
# name; ncurses answers with terminfo's bold sgr0 smul rmul smso rmso, but
# trims sgr0 for `me` (_p9k_nc_trim_sgr0 below). A terminal that cannot
# move the cursor up (no cuu1, e.g. dumb) gets no attributes at all.
_p9k_term_colors_init() {
  _p9k__tc_term=${TERM-}
  declare -ga _p9k__tc_fg=() _p9k__tc_bg=()
  if ! command -v tput >/dev/null 2>&1; then
    _p9k__tc_colors=256 _p9k__tc_std=1 _p9k__tc_cap=1
    _p9k__tc_md=$'\e[1m' _p9k__tc_me=$'\e[0m' _p9k__tc_us=$'\e[4m' _p9k__tc_ue=$'\e[24m'
    _p9k__tc_so=$'\e[7m' _p9k__tc_se=$'\e[27m'
    return 0
  fi
  # the attributes: one tput call; cr separates the answers (a missing
  # capability answers nothing). sgr comes last: tput stops at a missing
  # capability that takes parameters, so a short answer means "no sgr".
  local -a a=()
  local caps=$'cuu1\ncr\nbold\ncr\nsgr0\ncr\nsmul\ncr\nrmul\ncr\nsmso\ncr\nrmso\ncr\nsmacs\ncr\nrmacs\ncr'
  caps+=$'\nsgr 0 0 0 0 0 0 0 0 0\ncr\nsgr 0 0 0 0 0 0 0 0 1\ncr'
  local attrs; attrs=$(tput -S <<<"$caps" 2>/dev/null)
  IFS=$'\r' read -r -d '' -a a <<<"$attrs"
  a[-1]=${a[-1]%$'\n'}   # (read keeps the here-string's final newline)
  if [[ -z ${a[0]-} ]]; then
    _p9k__tc_md='' _p9k__tc_me='' _p9k__tc_us='' _p9k__tc_ue='' _p9k__tc_so='' _p9k__tc_se=''
  else
    _p9k__tc_md=${a[1]-} _p9k__tc_us=${a[3]-} _p9k__tc_ue=${a[4]-}
    _p9k__tc_so=${a[5]-} _p9k__tc_se=${a[6]-}
    _p9k_nc_trim_sgr0 "${a[2]-}" "${a[9]-}" "${a[10]-}" "${a[7]-}" "${a[8]-}"
    _p9k__tc_me=$_p9k__ret
  fi
  local c; c=$(tput colors 2>/dev/null)
  [[ $c =~ ^-?[0-9]+$ ]] || c=-1
  _p9k__tc_colors=$c _p9k__tc_std=0 _p9k__tc_cap=1
  # no setaf at all (dumb, vt100): zsh writes 3N / 4N itself
  tput setaf 1 >/dev/null 2>&1 || { _p9k__tc_cap=0; return 0; }
  (( c < 0 || c > 256 )) && c=256   # no count: zsh asks terminfo for any N
  (( c > 8 )) || return 0
  # setaf N, then cr (a carriage return) as a separator, so that an empty
  # answer cannot shift the list; then the same for setab
  local n req='' out
  for (( n = 8; n < c; n++ )); do req+="setaf $n"$'\n'cr$'\n'"setab $n"$'\n'cr$'\n'; done
  out=$(tput -S <<<"$req" 2>/dev/null)
  # (read, not an unquoted expansion, which would also glob: ESC[38;5;9m
  # holds a bracket expression. \r is not white space to IFS: an empty answer
  # stays an empty element. The here-string's newline makes one more.)
  local -a seq=()
  IFS=$'\r' read -r -d '' -a seq <<<"$out"
  # if tput stopped early, fall back to the standard sequences
  if (( ${#seq[@]} != 2 * (c - 8) + 1 )); then _p9k__tc_std=1; return 0; fi
  local i s
  for (( n = 8, i = 0; n < c; n++, i += 2 )); do
    # keep "PARAMS" of ESC [ PARAMS m; anything else: the default colour
    s=${seq[i]}; [[ $s == $'\e['*m ]] && s=${s:2:-1} || s=39; _p9k__tc_fg[n]=$s
    s=${seq[i+1]}; [[ $s == $'\e['*m ]] && s=${s:2:-1} || s=49; _p9k__tc_bg[n]=$s
  done
}

# zsh's rule for colour N (prompt.c match_colour, set_colour_attribute):
# 0-7 are ANSI codes 3N / 4N; 8 and above come from terminfo (setaf /
# setab) when the terminal has more than N colours (or gives no count), else
# the default colour; a terminal without setaf gets 3N / 4N for any N; 256
# and above, the default colour.
# (%NK, a background as a numeric argument, follows zsh 5.9: zsh 5.8 makes
# it colour 0, a bug. p10k never writes %NK.)
_p9k_sgr_color() {   # 38|48 COLOR -> _p9k__sgr
  local base=$1 c=$2 n
  if [[ $c =~ ^[0-9]+$ ]]; then
    n=$((10#$c))
    [[ ${_p9k__tc_term-unset} == "${TERM-}" ]] || _p9k_term_colors_init
    if (( n < 8 )); then _p9k__sgr=$(( base == 38 ? 30 + n : 40 + n ))
    elif (( n >= 256 )); then _p9k__sgr=$(( base == 38 ? 39 : 49 ))
    elif (( ! _p9k__tc_cap )); then _p9k__sgr=$(( base == 38 ? 3 : 4 ))$n _p9k__sgr_n=$n
    elif (( _p9k__tc_colors >= 0 && n >= _p9k__tc_colors )); then _p9k__sgr=$(( base == 38 ? 39 : 49 ))
    elif (( ! _p9k__tc_std )); then
      if (( base == 38 )); then _p9k__sgr=${_p9k__tc_fg[n]}; else _p9k__sgr=${_p9k__tc_bg[n]}; fi
    elif (( n < 16 )); then _p9k__sgr=$(( base == 38 ? 90 + n - 8 : 100 + n - 8 ))
    else _p9k__sgr="$base;5;$n"
    fi
  elif [[ $c =~ ^#([0-9a-fA-F]{6})$ ]]; then
    local h=${BASH_REMATCH[1]}
    _p9k__sgr="$base;2;$((16#${h:0:2}));$((16#${h:2:2}));$((16#${h:4:2}))"
  elif [[ $c =~ ^#([0-9a-fA-F]{3})$ ]]; then
    local h=${BASH_REMATCH[1]}
    _p9k__sgr="$base;2;$((16#${h:0:1}${h:0:1}));$((16#${h:1:1}${h:1:1}));$((16#${h:2:1}${h:2:1}))"
  elif [[ -n $c && -n ${_p9k_colors[${c,,}]-} ]]; then
    _p9k_sgr_color "$base" "${_p9k_colors[${c,,}]}"
  elif [[ $c == default ]]; then
    _p9k__sgr=$(( base == 38 ? 39 : 49 ))
  else
    _p9k__sgr=''
  fi
}

# zsh's tsetcap for _p9k_pe (uses its out, o, e): CODE DIRTY [B] -> out.
# Nothing at all when the terminal lacks CODE. DIRTY: then bold (unless
# CODE is bold itself, B), standout, underline and the colours again.
_p9k_pe_cap() {
  [[ -n $1 ]] || return 0
  out+="$o$1$e"
  (( $2 )) || return 0
  (( _p9k__pes_b )) && [[ -z ${3-} && -n $_p9k__tc_md ]] && out+="$o$_p9k__tc_md$e"
  (( _p9k__pes_s )) && [[ -n $_p9k__tc_so ]] && out+="$o$_p9k__tc_so$e"
  (( _p9k__pes_u )) && [[ -n $_p9k__tc_us ]] && out+="$o$_p9k__tc_us$e"
  _p9k_pe_recol "$o" "$e"; out+=$_p9k__ret
}

_p9k_pe() {
  local s=$1 out='' w=0 c rest arg o=$'\001' e=$'\002'
  (( _p9k__pe_mark )) || o='' e=''
  [[ ${_p9k__tc_term-unset} == "${TERM-}" ]] || _p9k_term_colors_init
  (( _p9k__pe_cont )) || _p9k_pe_reset
  while [[ -n $s ]]; do
    # plain text up to the next %
    rest=${s%%\%*}
    if [[ -n $rest ]]; then
      out+=$rest; w=$(( w + ${#rest} ))
      s=${s:${#rest}}
      continue
    fi
    # s starts with %
    c=${s:1:1}
    case $c in
      %) out+=%; (( w++ )); s=${s:2} ;;
      [FK])
        if [[ ${s:2:1} == '{' ]]; then arg=${s:3}; arg=${arg%%\}*}; s=${s:$(( 4 + ${#arg} ))}
        else arg=''; s=${s:2}
        fi
        local base=48; [[ $c == F ]] && base=38
        # zsh: an empty or blank colour is number 0 (black), spaces before a
        # number are skipped, an unknown name gives the default colour.
        arg=${arg#"${arg%%[! ]*}"}; [[ -z $arg ]] && arg=0
        _p9k__sgr_n=''
        _p9k_sgr_color "$base" "${arg% }"
        [[ -n $_p9k__sgr ]] || _p9k__sgr=$(( base == 38 ? 39 : 49 ))
        _p9k_pe_setcol "$base" "$_p9k__sgr" "$_p9k__sgr_n"
        out+="$o"$'\e['"${_p9k__sgr}m$e" ;;
      f) out+="$o"$'\e[39m'"$e"; _p9k_pe_setcol 38 39; s=${s:2} ;;
      k) out+="$o"$'\e[49m'"$e"; _p9k_pe_setcol 48 49; s=${s:2} ;;
      # zsh (prompt.c tsetcap): the terminal's code, if it has one; after
      # %B %b %u %s ("dirty") also the attributes and colours still on
      B) _p9k__pes_b=1; _p9k_pe_cap "$_p9k__tc_md" 1 B; s=${s:2} ;;
      b) _p9k__pes_b=0; _p9k_pe_cap "$_p9k__tc_me" 1; s=${s:2} ;;
      U) _p9k__pes_u=1; _p9k_pe_cap "$_p9k__tc_us" 0; s=${s:2} ;;
      u) _p9k__pes_u=0; _p9k_pe_cap "$_p9k__tc_ue" 1; s=${s:2} ;;
      S) _p9k__pes_s=1; _p9k_pe_cap "$_p9k__tc_so" 0; s=${s:2} ;;
      s) _p9k__pes_s=0; _p9k_pe_cap "$_p9k__tc_se" 1; s=${s:2} ;;
      '{')
        # literal escape sequence up to %}; %G inside counts one column each
        arg=${s:2}; arg=${arg%%%\}*}
        s=${s:$(( 4 + ${#arg} ))}
        local noG=${arg//%G/} gl
        gl=$(( (${#arg} - ${#noG}) / 2 ))
        out+="$o${arg//%G/}$e"; w=$(( w + gl )) ;;
      n) out+=$USER; w=$(( w + ${#USER} )); s=${s:2} ;;
      m) arg=${HOSTNAME%%.*}; out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      M) out+=$HOSTNAME; w=$(( w + ${#HOSTNAME} )); s=${s:2} ;;
      '~') arg=$PWD; [[ $arg == "$HOME" || $arg == "$HOME"/* ]] && arg="~${arg#"$HOME"}"
           out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      /|d) out+=$PWD; w=$(( w + ${#PWD} )); s=${s:2} ;;
      '#') if (( EUID == 0 )); then out+='#'; else out+='%'; fi; (( w++ )); s=${s:2} ;;
      h|'!') arg=${_p9k__histno:-1}; out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      '?') out+=${_p9k__status:-0}; arg=${_p9k__status:-0}; w=$(( w + ${#arg} )); s=${s:2} ;;
      D)
        if [[ ${s:2:1} == '{' ]]; then
          arg=${s:3}; arg=${arg%%\}*}; s=${s:$(( 4 + ${#arg} ))}
          _p9k_strftime "$arg"; arg=$_p9k__ret
        else
          _p9k_strftime '%y-%m-%d'; arg=$_p9k__ret; s=${s:2}
        fi
        out+=$arg; w=$(( w + ${#arg} )) ;;
      '*') _p9k_strftime '%K:%M:%S'; arg=$_p9k__ret; out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      T) _p9k_strftime '%K:%M'; arg=$_p9k__ret; out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      t) _p9k_strftime '%L:%M%p'; arg=$_p9k__ret; out+=$arg; w=$(( w + ${#arg} )); s=${s:2} ;;
      G) s=${s:2} ;;
      '') out+=%; (( w++ )); s='' ;;
      *)
        # %NF / %NK : colour given as a number before the letter
        # %N{...%} : a literal sequence that takes N columns
        if [[ $s =~ ^%([0-9]+)\{ ]]; then
          local num=${BASH_REMATCH[1]}
          arg=${s:$(( 2 + ${#num} ))}; arg=${arg%%%\}*}
          s=${s:$(( 4 + ${#num} + ${#arg} ))}
          out+="$o$arg$e"; w=$(( w + 10#$num ))
        elif [[ $s =~ ^%([0-9]+)([FK]) ]]; then
          local base=48 num=${BASH_REMATCH[1]}; [[ ${BASH_REMATCH[2]} == F ]] && base=38
          _p9k_sgr_color "$base" "$num"
          [[ -n $_p9k__sgr ]] || _p9k__sgr=$(( base == 38 ? 39 : 49 ))
          _p9k_pe_setcol "$base" "$_p9k__sgr"
          out+="$o"$'\e['"${_p9k__sgr}m$e"
          s=${s:$(( 2 + ${#num} ))}
        else
          out+=%; (( w++ )); s=${s:1}
        fi ;;
    esac
  done
  _p9k__pe=$out _p9k__pw=$w
}
