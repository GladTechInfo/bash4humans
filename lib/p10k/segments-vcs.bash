# =============================================================================
#  lib/p10k/segments-vcs.bash - the vcs segment (git), after p10k's
#  prompt_vcs, _p9k_vcs_render, _p9k_vcs_style, _p9k_vcs_icon and _p9k_init_vcs.
#  Status comes from gitstatusd (Powerlevel10k's engine, bash bindings); if it
#  is unavailable, the same VCS_STATUS_* variables are filled from git itself.
# =============================================================================

declare -gA __p9k_vcs_states=([CLEAN]=2 [MODIFIED]=3 [UNTRACKED]=2 [LOADING]=8 [CONFLICTED]=3)
_p9k__vcs_mode=sync                 # async: drawn from _p9k_vcs_precmd's request (ble.sh)
_p9k__prompt_idx=0                  # prompts shown so far (p10k: _p9k__prompt_idx)

_p9k_init_vcs() {
  _p9k_segment_in_use vcs || return 0
  (( ${#_POWERLEVEL9K_VCS_BACKENDS[@]} )) || return 0
  (( _POWERLEVEL9K_DISABLE_GITSTATUS )) && return 0
  local b has_git=0
  for b in "${_POWERLEVEL9K_VCS_BACKENDS[@]}"; do [[ $b == git ]] && has_git=1; done
  (( has_git )) || return 0
  [[ -n ${GITSTATUS_DAEMON_PID-} ]] && return 0
  local dir=${_POWERLEVEL9K_GITSTATUS_DIR:-${B4H_HOME:-$HOME/.cache/bash4humans}/deps/gitstatus}
  [[ -r $dir/gitstatus.plugin.sh ]] || return 0
  [[ -n ${GITSTATUS_CACHE_DIR-} ]] || export GITSTATUS_CACHE_DIR=$dir/bin
  . "$dir/gitstatus.plugin.sh" || return 0
  local -a opt=(-s "$_POWERLEVEL9K_VCS_STAGED_MAX_NUM" -u "$_POWERLEVEL9K_VCS_UNSTAGED_MAX_NUM"
                -d "$_POWERLEVEL9K_VCS_UNTRACKED_MAX_NUM" -c "$_POWERLEVEL9K_VCS_CONFLICTED_MAX_NUM"
                -m "$_POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY" -t "$_POWERLEVEL9K_GITSTATUS_INIT_TIMEOUT_SEC")
  (( _POWERLEVEL9K_VCS_RECURSE_UNTRACKED_DIRS )) && opt+=(-e)
  gitstatus_start "${opt[@]}" 2>/dev/null || true
}

# p10k: _p9k_vcs_icon - icon for the remote URL
_p9k_vcs_icon() {
  local i
  for (( i = 0; i + 1 < ${#_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[@]}; i += 2 )); do
    if (( ${_p9k_git_remote_icons_regex:-0} )); then
      [[ $1 =~ ${_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[i]} ]] && { _p9k__ret=${_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[i+1]}; return; }
    else
      # user-supplied zsh patterns: treat as shell globs
      [[ $1 == ${_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[i]} ]] && { _p9k__ret=${_POWERLEVEL9K_VCS_GIT_REMOTE_ICONS[i+1]}; return; }
    fi
  done
  _p9k__ret=
}

# p10k: _p9k_vcs_style STATE PART -> _p9k__ret
_p9k_vcs_style() {
  local key="vs$1"$'\1'"$2"
  if [[ -v _p9k_cache[$key] ]]; then _p9k__ret=${_p9k_cache[$key]}; return; fi
  local style=%b
  _p9k_color prompt_vcs_$1 BACKGROUND "${__p9k_vcs_states[$1]}"; _p9k_background "$_p9k__ret"; style+=$_p9k__ret
  local var=_POWERLEVEL9K_VCS_${1}_${2}FORMAT_FOREGROUND
  if _p9k_isset $var; then _p9k_translate_color "${!var}"
  else
    var=_POWERLEVEL9K_VCS_${2}FORMAT_FOREGROUND
    if _p9k_isset $var; then _p9k_translate_color "${!var}"
    else _p9k_color prompt_vcs_$1 FOREGROUND "$_p9k_color1"
    fi
  fi
  _p9k_foreground "$_p9k__ret"
  _p9k__ret=$style$_p9k__ret
  _p9k_cache[$key]=$_p9k__ret
}

# ------------------------------------------------------ gitstatusd client ---
# p10k talks to gitstatusd through gitstatus.plugin.zsh (gitstatus_query with
# a callback, gitstatus_process_results). The bash plugin's gitstatus_query
# can only wait, so this is a port of the zsh client that uses the pipes the
# bash plugin's gitstatus_start opened (_GITSTATUS_REQ_FD, _GITSTATUS_RESP_FD).
#   request:  "ID CALLBACK" \x1f DIR \x1f NO_DIFF \x1e
#   answer:   "ID CALLBACK" \x1f 1|0 \x1f 27 fields (as _p9k_gs_fields) \x1e
# An answer to an earlier request that is no longer awaited is "async": its
# callback (the text after the ID) is run with VCS_STATUS_RESULT=*-async.
_p9k_gs_fields=(VCS_STATUS_WORKDIR VCS_STATUS_COMMIT VCS_STATUS_LOCAL_BRANCH VCS_STATUS_REMOTE_BRANCH
  VCS_STATUS_REMOTE_NAME VCS_STATUS_REMOTE_URL VCS_STATUS_ACTION VCS_STATUS_INDEX_SIZE
  VCS_STATUS_NUM_STAGED VCS_STATUS_NUM_UNSTAGED VCS_STATUS_NUM_CONFLICTED VCS_STATUS_NUM_UNTRACKED
  VCS_STATUS_COMMITS_AHEAD VCS_STATUS_COMMITS_BEHIND VCS_STATUS_STASHES VCS_STATUS_TAG
  VCS_STATUS_NUM_UNSTAGED_DELETED VCS_STATUS_NUM_STAGED_NEW VCS_STATUS_NUM_STAGED_DELETED
  VCS_STATUS_PUSH_REMOTE_NAME VCS_STATUS_PUSH_REMOTE_URL VCS_STATUS_PUSH_COMMITS_AHEAD
  VCS_STATUS_PUSH_COMMITS_BEHIND VCS_STATUS_NUM_SKIP_WORKTREE VCS_STATUS_NUM_ASSUME_UNCHANGED
  VCS_STATUS_COMMIT_ENCODING VCS_STATUS_COMMIT_SUMMARY)
# the fields zsh declares as integers (an empty value becomes 0)
_p9k_gs_int=' INDEX_SIZE NUM_STAGED NUM_UNSTAGED NUM_CONFLICTED NUM_UNTRACKED COMMITS_AHEAD
  COMMITS_BEHIND STASHES NUM_UNSTAGED_DELETED NUM_STAGED_NEW NUM_STAGED_DELETED PUSH_COMMITS_AHEAD
  PUSH_COMMITS_BEHIND NUM_SKIP_WORKTREE NUM_ASSUME_UNCHANGED '
_p9k__gs_inflight=0   # requests sent and not answered yet
_p9k__gs_n=0          # makes request IDs unique

# gitstatus.plugin.zsh: _gitstatus_clear
_p9k_gs_clear() {
  unset "${_p9k_gs_fields[@]}" VCS_STATUS_HAS_STAGED VCS_STATUS_HAS_UNSTAGED \
        VCS_STATUS_HAS_CONFLICTED VCS_STATUS_HAS_UNTRACKED
}

# The daemon broke: stop it, as the zsh client does.
_p9k_gs_stop() {
  declare -F gitstatus_stop >/dev/null && gitstatus_stop
  unset GITSTATUS_DAEMON_PID
  _p9k__gs_inflight=0
}

# _p9k_gs_query DIR TIMEOUT NO_DIFF [CALLBACK]   (gitstatus_query -d -t -p -c)
# TIMEOUT -1 waits for the answer; 0 only sends the request (result "tout").
# Status 0 when VCS_STATUS_RESULT is set (ok-sync, norepo-sync, or tout with
# a callback that will receive the answer later); 1 otherwise.
_p9k_gs_query() {
  unset VCS_STATUS_RESULT
  [[ -n ${GITSTATUS_DAEMON_PID-} && -n ${_GITSTATUS_REQ_FD-} ]] || return 1
  local dir=$1 timeout=$2 cb=${4-}
  if [[ -z ${GIT_DIR-} ]]; then
    [[ $dir == /* ]] || dir=$PWD/$dir
  elif [[ $GIT_DIR == /* ]]; then
    dir=:$GIT_DIR
  else
    dir=:$PWD/$GIT_DIR
  fi
  # \x1e and \x1f separate the protocol's parts: such a name is "no repository"
  if [[ ( $dir != /* && $dir != :/* ) || $dir == *[$'\x1e\x1f']* ]]; then
    VCS_STATUS_RESULT=norepo-sync
    _p9k_gs_clear
    return 0
  fi
  local id=${EPOCHREALTIME/,/.}.$(( ++_p9k__gs_n ))
  printf '%s\x1f%s\x1f%s\x1e' "$id $cb" "$dir" "$3" >&"$_GITSTATUS_REQ_FD" 2>/dev/null || { _p9k_gs_stop; return 1; }
  (( _p9k__gs_inflight++ ))
  if [[ $timeout == 0 ]]; then
    VCS_STATUS_RESULT=tout
    _p9k_gs_clear
  else
    while true; do
      _p9k_gs_response "$timeout" "$id" || return 1
      [[ $VCS_STATUS_RESULT == *-async ]] || break
    done
  fi
  [[ $VCS_STATUS_RESULT != tout || -n $cb ]]
}

# gitstatus_process_results -t TIMEOUT: handle answers still to come.
_p9k_gs_process() {
  [[ -n ${GITSTATUS_DAEMON_PID-} ]] || return 1
  while (( _p9k__gs_inflight )); do
    _p9k_gs_response "$1" '' || return 1
    [[ ${VCS_STATUS_RESULT-} == *-async ]] || break
  done
  return 0
}

# _p9k_gs_response TIMEOUT ID : read one answer (gitstatus.plugin.zsh:
# _gitstatus_process_response). Waiting must not lose half an answer, so the
# first character is awaited with the timeout and the rest is read in full.
_p9k_gs_response() {
  local timeout=$1 id=$2 fd=${_GITSTATUS_RESP_FD-} c='' st
  [[ -n $fd ]] || return 1
  if [[ $timeout == 0 ]]; then
    read -t 0 -u "$fd" || st=142     # read -t 0 only tests for input
  elif [[ $timeout != -* ]]; then
    IFS= read -r -t "$timeout" -N 1 -u "$fd" c; st=$?
    (( st == 0 )) || (( st > 128 )) || { _p9k_gs_stop; return 1; }
  fi
  if (( ${st:-0} > 128 )); then      # nothing came in time
    if [[ -n $id ]]; then VCS_STATUS_RESULT=tout; _p9k_gs_clear; fi
    return 0
  fi
  local -a resp
  IFS=$'\x1f' read -r -d $'\x1e' -a resp -u "$fd" || { _p9k_gs_stop; return 1; }
  resp[0]=$c${resp[0]}
  local sync=0
  [[ -n $id && ${resp[0]} == "$id "* ]] && sync=1
  if (( ${resp[1]:-0} )); then
    if (( sync )); then VCS_STATUS_RESULT=ok-sync; else VCS_STATUS_RESULT=ok-async; fi
    local i v
    for (( i = 0; i < ${#_p9k_gs_fields[@]}; i++ )); do
      v=${resp[i+2]-}
      [[ $_p9k_gs_int == *" ${_p9k_gs_fields[i]#VCS_STATUS_}"[$' \n']* ]] && v=${v:-0}
      printf -v "${_p9k_gs_fields[i]}" '%s' "$v"
    done
    VCS_STATUS_HAS_STAGED=$(( VCS_STATUS_NUM_STAGED > 0 ))
    if (( _POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY >= 0 && VCS_STATUS_INDEX_SIZE > _POWERLEVEL9K_VCS_MAX_INDEX_SIZE_DIRTY )); then
      VCS_STATUS_HAS_UNSTAGED=-1 VCS_STATUS_HAS_CONFLICTED=-1 VCS_STATUS_HAS_UNTRACKED=-1
    else
      VCS_STATUS_HAS_UNSTAGED=$(( VCS_STATUS_NUM_UNSTAGED > 0 ))
      VCS_STATUS_HAS_CONFLICTED=$(( VCS_STATUS_NUM_CONFLICTED > 0 ))
      VCS_STATUS_HAS_UNTRACKED=$(( VCS_STATUS_NUM_UNTRACKED > 0 ))
    fi
  else
    if (( sync )); then VCS_STATUS_RESULT=norepo-sync; else VCS_STATUS_RESULT=norepo-async; fi
    _p9k_gs_clear
  fi
  (( _p9k__gs_inflight > 0 && _p9k__gs_inflight-- ))
  # an answer nobody waits for any more: run its callback
  if [[ $VCS_STATUS_RESULT == *-async && ${resp[0]} == *' '?* ]]; then
    eval "${resp[0]#* }"
  fi
  return 0
}

# ------------------------------------------------- status cache per repo ---
# p10k: _p9k_vcs_status_save / _restore / _for_dir / _purge. The last status
# of each repository (key: its work tree, or GIT_DIR:dir), shown greyed as
# the LOADING state while a fresh one is computed. p10k joins the fields with
# NUL, which a bash string cannot hold; \1 does the same job here.
declare -gA _p9k__gitstatus_last=() _p9k_git_slow=()
_p9k_vcs_saved_vars=(VCS_STATUS_COMMIT VCS_STATUS_LOCAL_BRANCH VCS_STATUS_REMOTE_BRANCH VCS_STATUS_REMOTE_NAME
  VCS_STATUS_REMOTE_URL VCS_STATUS_ACTION VCS_STATUS_INDEX_SIZE VCS_STATUS_NUM_STAGED
  VCS_STATUS_NUM_UNSTAGED VCS_STATUS_NUM_CONFLICTED VCS_STATUS_NUM_UNTRACKED
  VCS_STATUS_HAS_STAGED VCS_STATUS_HAS_UNSTAGED VCS_STATUS_HAS_CONFLICTED
  VCS_STATUS_HAS_UNTRACKED VCS_STATUS_COMMITS_AHEAD VCS_STATUS_COMMITS_BEHIND
  VCS_STATUS_STASHES VCS_STATUS_TAG VCS_STATUS_NUM_UNSTAGED_DELETED VCS_STATUS_NUM_STAGED_NEW
  VCS_STATUS_NUM_STAGED_DELETED VCS_STATUS_PUSH_REMOTE_NAME VCS_STATUS_PUSH_REMOTE_URL
  VCS_STATUS_PUSH_COMMITS_AHEAD VCS_STATUS_PUSH_COMMITS_BEHIND VCS_STATUS_NUM_SKIP_WORKTREE
  VCS_STATUS_NUM_ASSUME_UNCHANGED)
_p9k_vcs_key() {   # -> _p9k__ret
  if [[ -n ${_p9k__git_dir-} ]]; then _p9k__ret=GIT_DIR:$_p9k__git_dir; else _p9k__ret=${VCS_STATUS_WORKDIR-}; fi
}
_p9k_vcs_status_save() {
  local v s='' first=1
  for v in "${_p9k_vcs_saved_vars[@]}"; do
    (( first )) || s+=$'\1'
    first=0 s+=${!v-}
  done
  _p9k_vcs_key
  _p9k__gitstatus_last[$_p9k__ret]=$s
}
_p9k_vcs_status_restore() {   # VALUE (as saved)
  local s=$1$'\1' v
  for v in "${_p9k_vcs_saved_vars[@]}"; do
    printf -v "$v" '%s' "${s%%$'\1'*}"
    s=${s#*$'\1'}
  done
}
_p9k_vcs_status_for_dir() {   # -> _p9k__ret (the saved status), status 1 if none
  if [[ -n ${GIT_DIR-} ]]; then
    _p9k__ret=${_p9k__gitstatus_last[GIT_DIR:$GIT_DIR]-}
    [[ -n $_p9k__ret ]]
    return
  fi
  local dir=${_p9k__cwd_a:-$PWD}
  while true; do
    _p9k__ret=${_p9k__gitstatus_last[$dir]-}
    [[ -n $_p9k__ret ]] && return 0
    [[ $dir == / || $dir == . ]] && return 1
    _p9k_dirname "$dir"; dir=$_p9k__ret
  done
}
_p9k_vcs_status_purge() {   # DIR
  if [[ -n ${_p9k__git_dir-} ]]; then
    _p9k__gitstatus_last[GIT_DIR:$_p9k__git_dir]=''
    return
  fi
  local dir=$1
  while true; do
    _p9k__gitstatus_last[$dir]='' _p9k_git_slow[$dir]=''
    [[ $dir == / || $dir == . ]] && break
    _p9k_dirname "$dir"; dir=$_p9k__ret
  done
}
# zsh ${dir:h} -> _p9k__ret
_p9k_dirname() {
  case $1 in
    */*) _p9k__ret=${1%/*}; [[ -n $_p9k__ret ]] || _p9k__ret=/ ;;
    *) _p9k__ret=. ;;
  esac
}

# ------------------------------------------- asynchronous status (ble.sh) ---
# With ble.sh the prompt can be redrawn, so vcs works as in p10k: the status
# is requested at the start of the prompt hook; if gitstatusd has not answered
# within VCS_MAX_SYNC_LATENCY_SECONDS the segment shows the LOADING state, and
# the answer, when it comes, redraws the prompt (a ble.sh idle task watches
# the answer pipe). Without ble.sh the hook waits instead (prompt_vcs).

# p10k: the vcs part of _p9k_precmd_impl. Sets _p9k__vcs_mode=async when the
# segment will be drawn from these results.
_p9k_vcs_precmd() {
  _p9k__vcs_mode=sync
  unset _p9k__vcs_timeout
  (( ${_p9k_ble:-0} )) && [[ -n ${GITSTATUS_DAEMON_PID-} ]] || return 0
  _p9k_segment_in_use vcs || return 0
  local b has_git=0
  for b in "${_POWERLEVEL9K_VCS_BACKENDS[@]}"; do [[ $b == git ]] && has_git=1; done
  (( has_git )) || return 0
  local pat=${_POWERLEVEL9K_VCS_DISABLED_DIR_PATTERN-}
  if [[ -n $pat ]]; then
    pat=${pat/#\~/$HOME}
    # shellcheck disable=SC2053
    [[ $_p9k__cwd == $pat ]] && return 0
  fi
  _p9k__vcs_mode=async
  _p9k__vcs_start_us=${EPOCHREALTIME//[.,]/}
  _p9k_vcs_gitstatus
  return 0
}

# seconds (decimal) -> microseconds (integer) -> _p9k__ret
_p9k_secs_us() {
  local s=$1 i f
  i=${s%%.*}; [[ $s == *.* ]] && f=${s#*.} || f=
  f=${f}000000
  _p9k__ret=$(( 10#${i:-0} * 1000000 + 10#${f:0:6} ))
}

# p10k: _p9k_vcs_gitstatus (the request at the start of a prompt)
_p9k_vcs_gitstatus() {
  if [[ -v _p9k__gitstatus_next_dir ]]; then
    # an answer is still awaited: ask for this directory when it comes
    _p9k__gitstatus_next_dir=$_p9k__cwd_a
    return 0
  fi
  local timeout=$_POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS
  if ! _p9k_vcs_status_for_dir; then
    # never seen: first a quick answer without the index (-p)
    _p9k__git_dir=${GIT_DIR-}
    _p9k_gs_query "$_p9k__cwd_a" "$timeout" 1 '_p9k_vcs_resume 0' || return 1
    _p9k_maybe_ignore_git_repo
    case $VCS_STATUS_RESULT in
      tout) _p9k__gitstatus_next_dir='' _p9k__gitstatus_start_us=${EPOCHREALTIME//[.,]/}; return 0 ;;
      norepo-sync) return 0 ;;
      ok-sync) _p9k_vcs_status_save ;;
    esac
  else
    # a repository known to be slow is not waited for at all
    if [[ -n ${GIT_DIR-} ]]; then
      [[ ${_p9k_git_slow[GIT_DIR:$GIT_DIR]-} == 1 ]] && timeout=0
    else
      local dir=$_p9k__cwd_a
      while true; do
        case ${_p9k_git_slow[$dir]-} in
          '') [[ $dir == / || $dir == . ]] && break; _p9k_dirname "$dir"; dir=$_p9k__ret ;;
          0) break ;;
          1) timeout=0; break ;;
        esac
      done
    fi
  fi
  (( _p9k__prompt_idx == 1 )) && timeout=0
  _p9k__git_dir=${GIT_DIR-}
  if ! _p9k_gs_query "$_p9k__cwd_a" 0 0 '_p9k_vcs_resume 1'; then
    unset VCS_STATUS_RESULT
    return 1
  fi
  _p9k__vcs_timeout=$timeout
  _p9k__gitstatus_next_dir=''
  _p9k__gitstatus_start_us=${EPOCHREALTIME//[.,]/}
  return 0
}

# p10k: _p9k_vcs_resume 0|1 - the callback of an answer that came late
# (0: the quick one without the index, 1: the full one).
_p9k_vcs_resume() {
  _p9k_maybe_ignore_git_repo
  if [[ $VCS_STATUS_RESULT == ok-async ]]; then
    local now=${EPOCHREALTIME//[.,]/} max
    _p9k_secs_us "$_POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS"; max=$_p9k__ret
    local latency=$(( now - ${_p9k__gitstatus_start_us:-now} ))
    _p9k_vcs_key
    if (( latency > max )); then
      _p9k_git_slow[$_p9k__ret]=1
    elif (( $1 && latency * 10 < 8 * max )); then   # 0.8: no flip-flopping
      _p9k_git_slow[$_p9k__ret]=0
    fi
    _p9k_vcs_status_save
  fi

  if [[ -z ${_p9k__gitstatus_next_dir-} ]]; then
    unset _p9k__gitstatus_next_dir
    case $VCS_STATUS_RESULT in
      norepo-async) (( $1 )) && _p9k_vcs_status_purge "$_p9k__cwd_a" ;;
      ok-async) (( $1 )) || _p9k__gitstatus_next_dir=$_p9k__cwd_a ;;
    esac
  fi

  if [[ -n ${_p9k__gitstatus_next_dir-} ]]; then
    _p9k__git_dir=${GIT_DIR-}
    if ! _p9k_gs_query "$_p9k__gitstatus_next_dir" 0 0 '_p9k_vcs_resume 1'; then
      unset _p9k__gitstatus_next_dir VCS_STATUS_RESULT
    else
      _p9k_maybe_ignore_git_repo
      case $VCS_STATUS_RESULT in
        tout) _p9k__gitstatus_next_dir='' _p9k__gitstatus_start_us=${EPOCHREALTIME//[.,]/} ;;
        norepo-sync) _p9k_vcs_status_purge "$_p9k__gitstatus_next_dir"; unset _p9k__gitstatus_next_dir ;;
        ok-sync) _p9k_vcs_status_save; unset _p9k__gitstatus_next_dir ;;
      esac
    fi
  fi
  # During the prompt hook prompt_vcs draws the segment itself; later the
  # prompt on the screen is redrawn (p10k: _p9k_reset_prompt).
  (( ${_p9k__in_precmd:-0} )) || _p9k_vcs_refresh
}

# The vcs segment drawn from the current results (p10k: the start of _p9k_vcs_render).
_p9k_vcs_render_async() {
  local state=''
  if [[ -v _p9k__gitstatus_next_dir ]]; then
    if _p9k_vcs_status_for_dir; then
      _p9k_vcs_status_restore "$_p9k__ret"
      state=LOADING
    else
      _p9k_prompt_segment prompt_vcs_LOADING "${__p9k_vcs_states[LOADING]}" "$_p9k_color1" VCS_LOADING_ICON 0 '' "$_POWERLEVEL9K_VCS_LOADING_TEXT"
      return 0
    fi
  elif [[ ${VCS_STATUS_RESULT-} != ok-* ]]; then
    return 1
  fi
  _p9k_vcs_render "$state"
}

# Redraw after a late answer: draw vcs again at each place it appears (its
# recorded calls are replaced), then rebuild the prompt from the recordings.
_p9k_vcs_refresh() {
  (( ${_p9k__initialized:-0} )) && [[ $_p9k__vcs_mode == async ]] || return 0
  _p9k_vcs_rerecord
  # the replay draws (vi_mode and prompt_char are run again and drawn there)
  _p9k_replay_render
}
_p9k_vcs_rerecord() {
  local _p9k__prompt_side _p9k__segment_index _p9k__segment_name=vcs line elem
  local _p9k__record_only=1
  for _p9k__prompt_side in left right; do
    local -n _p9k_ls=_p9k_line_segments_$_p9k__prompt_side
    _p9k__segment_index=1
    for line in "${_p9k_ls[@]}"; do
      for elem in $line; do
        if [[ ${elem%_joined} == vcs ]]; then
          _p9k__rec[$_p9k__prompt_side$_p9k__segment_index]=''
          _p9k_vcs_render_async
        fi
        (( _p9k__segment_index++ ))
      done
    done
    unset -n _p9k_ls
  done
}

# ble.sh idle task: runs when an answer can be read, while the line is edited.
_p9k_gs_ready() { [[ -n ${_GITSTATUS_RESP_FD-} ]] && read -t 0 -u "$_GITSTATUS_RESP_FD"; }
_p9k_gs_watch() {
  (( ${_p9k__gs_watching:-0} )) && return 0
  _p9k__gs_watching=1
  ble/util/idle.push -C '_p9k_gs_ready' _p9k_gs_idle
}
_p9k_gs_idle() {
  _p9k_gs_process 0
  if (( _p9k__gs_inflight )) && [[ -n ${GITSTATUS_DAEMON_PID-} ]]; then
    ble/util/idle.wait-condition '_p9k_gs_ready'   # keep watching
  else
    _p9k__gs_watching=0
  fi
}

# Without gitstatusd: compute the same variables with git.
_p9k_vcs_from_git() {
  local out line top
  top=$(git rev-parse --show-toplevel 2>/dev/null) || { VCS_STATUS_RESULT=norepo-sync; return; }
  out=$(GIT_OPTIONAL_LOCKS=0 git status --porcelain=v2 --branch --show-stash 2>/dev/null) || { VCS_STATUS_RESULT=norepo-sync; return; }
  VCS_STATUS_RESULT=ok-sync VCS_STATUS_WORKDIR=$top VCS_STATUS_COMMIT='' VCS_STATUS_LOCAL_BRANCH=''
  VCS_STATUS_REMOTE_BRANCH='' VCS_STATUS_REMOTE_NAME='' VCS_STATUS_REMOTE_URL='' VCS_STATUS_ACTION=''
  VCS_STATUS_NUM_STAGED=0 VCS_STATUS_NUM_UNSTAGED=0 VCS_STATUS_NUM_CONFLICTED=0 VCS_STATUS_NUM_UNTRACKED=0
  VCS_STATUS_COMMITS_AHEAD=0 VCS_STATUS_COMMITS_BEHIND=0 VCS_STATUS_STASHES=0 VCS_STATUS_TAG=''
  VCS_STATUS_NUM_UNSTAGED_DELETED=0 VCS_STATUS_PUSH_COMMITS_AHEAD=0 VCS_STATUS_PUSH_COMMITS_BEHIND=0
  VCS_STATUS_COMMIT_SUMMARY=''
  while IFS= read -r line; do
    case $line in
      '# branch.oid '*) VCS_STATUS_COMMIT=${line#\# branch.oid }; [[ $VCS_STATUS_COMMIT == '(initial)' ]] && VCS_STATUS_COMMIT='' ;;
      '# branch.head '*) VCS_STATUS_LOCAL_BRANCH=${line#\# branch.head }; [[ $VCS_STATUS_LOCAL_BRANCH == '(detached)' ]] && VCS_STATUS_LOCAL_BRANCH='' ;;
      '# branch.upstream '*) line=${line#\# branch.upstream }; VCS_STATUS_REMOTE_NAME=${line%%/*}; VCS_STATUS_REMOTE_BRANCH=${line#*/} ;;
      '# branch.ab '*) line=${line#\# branch.ab +}; VCS_STATUS_COMMITS_AHEAD=${line%% *}; VCS_STATUS_COMMITS_BEHIND=${line##*-} ;;
      '# stash '*) VCS_STATUS_STASHES=${line#\# stash } ;;
      'u '*) (( VCS_STATUS_NUM_CONFLICTED++ )) ;;
      '? '*) (( VCS_STATUS_NUM_UNTRACKED++ )) ;;
      [12]' '*) [[ ${line:2:1} != . ]] && (( VCS_STATUS_NUM_STAGED++ ))
                [[ ${line:3:1} != . ]] && (( VCS_STATUS_NUM_UNSTAGED++ ))
                [[ ${line:3:1} == D ]] && (( VCS_STATUS_NUM_UNSTAGED_DELETED++ )) ;;
    esac
  done <<<"$out"
  [[ -n $VCS_STATUS_REMOTE_NAME ]] && VCS_STATUS_REMOTE_URL=$(git config --get "remote.$VCS_STATUS_REMOTE_NAME.url" 2>/dev/null)
  [[ -n $VCS_STATUS_COMMIT ]] && {
    VCS_STATUS_TAG=$(git describe --tags --exact-match HEAD 2>/dev/null)
    VCS_STATUS_COMMIT_SUMMARY=$(git log -1 --format=%s 2>/dev/null)
  }
  local gd; gd=$(git rev-parse --git-dir 2>/dev/null)
  if [[ -d $gd/rebase-merge || -d $gd/rebase-apply ]]; then VCS_STATUS_ACTION=rebase
  elif [[ -f $gd/MERGE_HEAD ]]; then VCS_STATUS_ACTION=merge
  elif [[ -f $gd/CHERRY_PICK_HEAD ]]; then VCS_STATUS_ACTION=cherry-pick
  elif [[ -f $gd/REVERT_HEAD ]]; then VCS_STATUS_ACTION=revert
  elif [[ -f $gd/BISECT_LOG ]]; then VCS_STATUS_ACTION=bisect
  fi
  VCS_STATUS_HAS_STAGED=$(( VCS_STATUS_NUM_STAGED > 0 )) VCS_STATUS_HAS_UNSTAGED=$(( VCS_STATUS_NUM_UNSTAGED > 0 ))
  VCS_STATUS_HAS_CONFLICTED=$(( VCS_STATUS_NUM_CONFLICTED > 0 )) VCS_STATUS_HAS_UNTRACKED=$(( VCS_STATUS_NUM_UNTRACKED > 0 ))
}

_p9k_maybe_ignore_git_repo() {
  if [[ $VCS_STATUS_RESULT == ok-* && -n $_POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN ]]; then
    local pat=${_POWERLEVEL9K_VCS_DISABLED_WORKDIR_PATTERN/#\~/$HOME}
    _p9k_zglob_match "$VCS_STATUS_WORKDIR" "$pat" && VCS_STATUS_RESULT=norepo${VCS_STATUS_RESULT#ok}
  fi
}

prompt_vcs() {
  local b has_git=0
  for b in "${_POWERLEVEL9K_VCS_BACKENDS[@]}"; do [[ $b == git ]] && has_git=1; done
  (( has_git )) || return 0
  local state=''
  if [[ ${_p9k__vcs_mode-} == async ]]; then
    # ble.sh: requested in _p9k_vcs_precmd. Wait for the rest of the latency
    # budget once (p10k: gitstatus_process_results in _p9k_precmd_impl).
    if [[ -v _p9k__vcs_timeout ]]; then
      local t_us now=${EPOCHREALTIME//[.,]/} rem
      _p9k_secs_us "$_p9k__vcs_timeout"; t_us=$_p9k__ret
      unset _p9k__vcs_timeout
      rem=$(( t_us + _p9k__vcs_start_us - now ))
      (( rem < 0 )) && rem=0
      printf -v rem '%d.%06d' $(( rem / 1000000 )) $(( rem % 1000000 ))
      [[ $rem == 0.000000 ]] && rem=0
      _p9k_gs_process "$rem"
    fi
    _p9k_vcs_render_async
    return 0
  fi
  if [[ -n ${GITSTATUS_DAEMON_PID-} ]]; then
    # bash cannot redraw the prompt when a late answer arrives (p10k does), so
    # without ble.sh wait up to 1 s rather than show "loading" for good.
    local t=$_POWERLEVEL9K_VCS_MAX_SYNC_LATENCY_SECONDS
    _p9k_fcmp "$t" "<" 1 && t=1
    _p9k__git_dir=${GIT_DIR-}
    if _p9k_gs_query "${_p9k__cwd_a:-$PWD}" "$t" 0; then
      _p9k_maybe_ignore_git_repo
      [[ $VCS_STATUS_RESULT == ok-sync ]] || return 0
      _p9k_vcs_status_save
    else
      [[ ${VCS_STATUS_RESULT-} == tout ]] || return 0   # gitstatusd failed
      # Not answered in time: the last known status, greyed (p10k's LOADING state).
      if _p9k_vcs_status_for_dir; then
        _p9k_vcs_status_restore "$_p9k__ret"
        state=LOADING
      else
        # Is this a repository at all? (cheap walk up for .git)
        local d=$PWD; while [[ -n $d && ! -e $d/.git ]]; do d=${d%/*}; done
        [[ -e $d/.git ]] || return 0
        _p9k_prompt_segment prompt_vcs_LOADING "${__p9k_vcs_states[LOADING]}" "$_p9k_color1" VCS_LOADING_ICON 0 '' "$_POWERLEVEL9K_VCS_LOADING_TEXT"
        return 0
      fi
    fi
  else
    command -v git >/dev/null || return 0
    _p9k_vcs_from_git
    _p9k_maybe_ignore_git_repo
    [[ $VCS_STATUS_RESULT == ok-* ]] || return 0
  fi
  _p9k_vcs_render "$state"
}

# p10k: _p9k_vcs_render
_p9k_vcs_render() {
  local state=$1 me=prompt_vcs
  local -a hooks=("${_POWERLEVEL9K_VCS_GIT_HOOKS[@]}")
  _p9k_hook() { local h; for h in "${hooks[@]}"; do [[ $h == "$1" ]] && return 0; done; return 1; }

  if (( _POWERLEVEL9K_VCS_DISABLE_GITSTATUS_FORMATTING )); then
    if [[ -z $state ]]; then
      if [[ $VCS_STATUS_HAS_CONFLICTED == 1 && $_POWERLEVEL9K_VCS_CONFLICTED_STATE == 1 ]]; then state=CONFLICTED
      elif [[ $VCS_STATUS_HAS_STAGED != 0 || $VCS_STATUS_HAS_UNSTAGED != 0 ]]; then state=MODIFIED
      elif [[ $VCS_STATUS_HAS_UNTRACKED != 0 ]]; then state=UNTRACKED
      else state=CLEAN
      fi
    fi
    _p9k_vcs_icon "$VCS_STATUS_REMOTE_URL"
    _p9k_prompt_segment "${me}_$state" "${__p9k_vcs_states[$state]}" "$_p9k_color1" "$_p9k__ret" 0 '' ''
    return 0
  fi

  _p9k_hook git-untracked   || VCS_STATUS_HAS_UNTRACKED=0
  _p9k_hook git-aheadbehind || { VCS_STATUS_COMMITS_AHEAD=0; VCS_STATUS_COMMITS_BEHIND=0; }
  _p9k_hook git-stash       || VCS_STATUS_STASHES=0
  _p9k_hook git-remotebranch || VCS_STATUS_REMOTE_BRANCH=''
  _p9k_hook git-tagname     || VCS_STATUS_TAG=''
  (( _POWERLEVEL9K_VCS_COMMITS_AHEAD_MAX_NUM >= 0 && VCS_STATUS_COMMITS_AHEAD > _POWERLEVEL9K_VCS_COMMITS_AHEAD_MAX_NUM )) &&
    VCS_STATUS_COMMITS_AHEAD=$_POWERLEVEL9K_VCS_COMMITS_AHEAD_MAX_NUM
  (( _POWERLEVEL9K_VCS_COMMITS_BEHIND_MAX_NUM >= 0 && VCS_STATUS_COMMITS_BEHIND > _POWERLEVEL9K_VCS_COMMITS_BEHIND_MAX_NUM )) &&
    VCS_STATUS_COMMITS_BEHIND=$_POWERLEVEL9K_VCS_COMMITS_BEHIND_MAX_NUM

  local icon='' content=''
  if _p9k_hook vcs-detect-changes; then
    if [[ -z $state ]]; then
      if [[ $VCS_STATUS_HAS_CONFLICTED == 1 && $_POWERLEVEL9K_VCS_CONFLICTED_STATE == 1 ]]; then state=CONFLICTED
      elif [[ $VCS_STATUS_HAS_STAGED != 0 || $VCS_STATUS_HAS_UNSTAGED != 0 ]]; then state=MODIFIED
      elif [[ $VCS_STATUS_HAS_UNTRACKED != 0 ]]; then state=UNTRACKED
      fi
    fi
    _p9k_vcs_icon "$VCS_STATUS_REMOTE_URL"; icon=$_p9k__ret
  fi
  : "${state:=CLEAN}"
  _fmt() { _p9k_vcs_style "$state" "$1"; content+="$_p9k__ret$2"; }

  local ws=''
  if [[ $_POWERLEVEL9K_SHOW_CHANGESET == 1 || -z $VCS_STATUS_LOCAL_BRANCH ]]; then
    _p9k_get_icon "${me}_$state" VCS_COMMIT_ICON
    local c=${VCS_STATUS_COMMIT:0:$_POWERLEVEL9K_CHANGESET_HASH_LENGTH}
    _fmt COMMIT "$_p9k__ret${c:-HEAD}"
    ws=' '
  fi
  if [[ -n $VCS_STATUS_LOCAL_BRANCH ]]; then
    local branch=$ws
    if (( !_POWERLEVEL9K_HIDE_BRANCH_ICON )); then _p9k_get_icon "${me}_$state" VCS_BRANCH_ICON; branch+=$_p9k__ret; fi
    local L=${#VCS_STATUS_LOCAL_BRANCH}
    if _p9k_isset _POWERLEVEL9K_VCS_SHORTEN_LENGTH && _p9k_isset _POWERLEVEL9K_VCS_SHORTEN_MIN_LENGTH &&
       (( L > _POWERLEVEL9K_VCS_SHORTEN_MIN_LENGTH && L > _POWERLEVEL9K_VCS_SHORTEN_LENGTH )) &&
       [[ $_POWERLEVEL9K_VCS_SHORTEN_STRATEGY == truncate_middle || $_POWERLEVEL9K_VCS_SHORTEN_STRATEGY == truncate_from_right ]]; then
      local x=${VCS_STATUS_LOCAL_BRANCH:0:_POWERLEVEL9K_VCS_SHORTEN_LENGTH}
      branch+=${x//\%/%%}$_POWERLEVEL9K_VCS_SHORTEN_DELIMITER
      if [[ $_POWERLEVEL9K_VCS_SHORTEN_STRATEGY == truncate_middle ]]; then
        _p9k_vcs_style "$state" BRANCH
        x=${VCS_STATUS_LOCAL_BRANCH: -_POWERLEVEL9K_VCS_SHORTEN_LENGTH}
        branch+=$_p9k__ret${x//\%/%%}
      fi
    else
      branch+=${VCS_STATUS_LOCAL_BRANCH//\%/%%}
    fi
    _fmt BRANCH "$branch"
  fi
  if [[ $_POWERLEVEL9K_VCS_HIDE_TAGS == 0 && -n $VCS_STATUS_TAG ]]; then
    _p9k_get_icon "${me}_$state" VCS_TAG_ICON; _fmt TAG " $_p9k__ret${VCS_STATUS_TAG//\%/%%}"
  fi
  if [[ -n $VCS_STATUS_ACTION ]]; then
    _fmt ACTION " | ${VCS_STATUS_ACTION//\%/%%}"
  else
    if [[ -n $VCS_STATUS_REMOTE_BRANCH && $VCS_STATUS_LOCAL_BRANCH != "$VCS_STATUS_REMOTE_BRANCH" ]]; then
      _p9k_get_icon "${me}_$state" VCS_REMOTE_BRANCH_ICON; _fmt REMOTE_BRANCH " $_p9k__ret${VCS_STATUS_REMOTE_BRANCH//\%/%%}"
    fi
    if [[ $VCS_STATUS_HAS_STAGED == 1 || $VCS_STATUS_HAS_UNSTAGED == 1 || $VCS_STATUS_HAS_UNTRACKED == 1 ]]; then
      _p9k_get_icon "${me}_$state" VCS_DIRTY_ICON; _fmt DIRTY "$_p9k__ret"
      if [[ $VCS_STATUS_HAS_STAGED == 1 ]]; then
        _p9k_get_icon "${me}_$state" VCS_STAGED_ICON
        (( _POWERLEVEL9K_VCS_STAGED_MAX_NUM != 1 )) && _p9k__ret+=$VCS_STATUS_NUM_STAGED
        _fmt STAGED " $_p9k__ret"
      fi
      if [[ $VCS_STATUS_HAS_UNSTAGED == 1 ]]; then
        _p9k_get_icon "${me}_$state" VCS_UNSTAGED_ICON
        (( _POWERLEVEL9K_VCS_UNSTAGED_MAX_NUM != 1 )) && _p9k__ret+=$VCS_STATUS_NUM_UNSTAGED
        _fmt UNSTAGED " $_p9k__ret"
      fi
      if [[ $VCS_STATUS_HAS_UNTRACKED == 1 ]]; then
        _p9k_get_icon "${me}_$state" VCS_UNTRACKED_ICON
        (( _POWERLEVEL9K_VCS_UNTRACKED_MAX_NUM != 1 )) && _p9k__ret+=$VCS_STATUS_NUM_UNTRACKED
        _fmt UNTRACKED " $_p9k__ret"
      fi
    fi
    if (( VCS_STATUS_COMMITS_BEHIND > 0 )); then
      _p9k_get_icon "${me}_$state" VCS_INCOMING_CHANGES_ICON
      (( _POWERLEVEL9K_VCS_COMMITS_BEHIND_MAX_NUM != 1 )) && _p9k__ret+=$VCS_STATUS_COMMITS_BEHIND
      _fmt INCOMING_CHANGES " $_p9k__ret"
    fi
    if (( VCS_STATUS_COMMITS_AHEAD > 0 )); then
      _p9k_get_icon "${me}_$state" VCS_OUTGOING_CHANGES_ICON
      (( _POWERLEVEL9K_VCS_COMMITS_AHEAD_MAX_NUM != 1 )) && _p9k__ret+=$VCS_STATUS_COMMITS_AHEAD
      _fmt OUTGOING_CHANGES " $_p9k__ret"
    fi
    if (( VCS_STATUS_STASHES > 0 )); then
      _p9k_get_icon "${me}_$state" VCS_STASH_ICON; _fmt STASH " $_p9k__ret$VCS_STATUS_STASHES"
    fi
  fi
  _p9k_prompt_segment "${me}_$state" "${__p9k_vcs_states[$state]}" "$_p9k_color1" "$icon" 0 '' "$content"
}
