# =============================================================================
#  lib/p10k/segments-misc.bash - battery, wifi, todo, timewarrior,
#  taskwarrior, per_directory_history, nordvpn, dropbox, openfoam,
#  rspec_stats, symfony2_tests, symfony2_version. Ports of p10k's code
#  (the Linux paths; p10k's macOS-only branches are not used by bash4humans).
# =============================================================================

_p9k_sysfs_power=/sys/class/power_supply   # tests point these at fixtures
_p9k_proc_wireless=/proc/net/wireless

# p10k: _p9k_read_file FILE -> first line; status: non-empty
_p9k_read_file() {
  _p9k__ret=''
  [[ -n $1 ]] && IFS='' read -r _p9k__ret <"$1" 2>/dev/null
  [[ -n $_p9k__ret ]]
}
# The first existing of the files, given in alphabetical order (zsh: the
# first match of dir/(a|b)(N), globs being sorted) -> _p9k__f
_p9k_first_file() {
  local d=$1 f; shift
  for f; do [[ -e $d/$f ]] && { _p9k__f=$d/$f; return 0; }; done
  return 1
}

# ------------------------------------------------------------------ battery ---
prompt_battery() {
  _p9k_prompt_battery_set_args
  (( ${#_p9k__battery_args[@]} )) && _p9k_prompt_segment "${_p9k__battery_args[@]}"
  return 0
}
_p9k_prompt_battery_init() {
  declare -ga _p9k__battery_args=()
  local d f ok=0
  for d in "$_p9k_sysfs_power"/*; do
    [[ ${d##*/} == CMB* || ${d##*/} == BAT* || ${d##*/} == *battery ]] || continue
    for f in energy_full charge_full charge_counter; do [[ -e $d/$f ]] && ok=1; done
  done
  (( ok )) || _p9k_cond_never
}

_p9k_prompt_battery_set_args() {
  _p9k__battery_args=()
  local -a bats=()
  local d
  for d in "$_p9k_sysfs_power"/*; do
    [[ ${d##*/} == CMB* || ${d##*/} == BAT* || ${d##*/} == *battery ]] && bats+=("$d")
  done
  (( ${#bats[@]} )) || return 0
  local -i energy_now=0 energy_full=0 power_now=0 is_full=1 is_calculating=0 is_charging=0 pow full
  local st state remain='' bat_status
  for d in "${bats[@]}"; do
    _p9k_read_file "$d/status" && bat_status=$_p9k__ret || continue
    [[ $bat_status == Unknown ]] && continue
    pow=0 full=0
    if _p9k_first_file "$d" charge_counter charge_full energy_full && _p9k_read_file "$_p9k__f"; then
      full=$_p9k__ret; (( energy_full += full ))
    fi
    if _p9k_first_file "$d" current_now power_now && _p9k_read_file "$_p9k__f" && (( ${#_p9k__ret} < 9 )); then
      pow=$_p9k__ret; (( power_now += pow ))
    fi
    if [[ -e $d/capacity ]] && _p9k_read_file "$d/capacity"; then
      # zsh: energy_now += capacity * full / 100. + 0.5, kept as an integer
      (( energy_now += (_p9k__ret * full + 50) / 100 ))
    elif _p9k_first_file "$d" charge_now energy_now && _p9k_read_file "$_p9k__f"; then
      (( energy_now += _p9k__ret ))
    fi
    [[ $bat_status != Full ]] && is_full=0
    [[ $bat_status == Charging ]] && is_charging=1
    [[ ( $bat_status == Charging || $bat_status == Discharging ) && $pow == 0 ]] && is_calculating=1
  done
  (( energy_full )) || return 0
  # zsh: 100. * now / full + 0.5, truncated
  local -i bat_percent=$(( (200 * energy_now + energy_full) / (2 * energy_full) ))
  (( bat_percent > 100 )) && bat_percent=100
  if (( is_full || (bat_percent == 100 && is_charging) )); then
    state=CHARGED
  else
    if (( is_charging )); then state=CHARGING
    elif (( bat_percent < _POWERLEVEL9K_BATTERY_LOW_THRESHOLD )); then state=LOW
    else state=DISCONNECTED
    fi
    if (( power_now > 0 )); then
      local -i e
      (( is_charging )) && e=$(( energy_full - energy_now )) || e=$energy_now
      local -i minutes=$(( 60 * e / power_now ))
      (( minutes > 0 )) && printf -v remain '%d:%02d' $(( minutes / 60 )) $(( minutes % 60 ))
    elif (( is_calculating )); then
      remain=...
    fi
  fi
  local hv=_POWERLEVEL9K_BATTERY_${state}_HIDE_ABOVE_THRESHOLD
  (( bat_percent >= ${!hv} )) && return 0
  local msg="$bat_percent%%"
  [[ $_POWERLEVEL9K_BATTERY_VERBOSE == 1 && -n $remain ]] && msg+=" ($remain)"
  # icon, background, foreground: stage number bat_percent * N / 100 + 1
  local icon=BATTERY_ICON bg=$_p9k_color1 fg idx
  case $state in LOW) fg=red ;; CHARGING) fg=yellow ;; CHARGED) fg=green ;; *) fg=$_p9k_color2 ;; esac
  local -n _st=_POWERLEVEL9K_BATTERY_${state}_STAGES
  if (( ${#_st[@]} )); then
    idx=${#_st[@]}; (( bat_percent < 100 )) && idx=$(( bat_percent * ${#_st[@]} / 100 + 1 ))
    icon=$'\1'${_st[idx-1]}
  fi
  local -n _bg=_POWERLEVEL9K_BATTERY_${state}_LEVEL_BACKGROUND
  if (( ${#_bg[@]} )); then
    idx=${#_bg[@]}; (( bat_percent < 100 )) && idx=$(( bat_percent * ${#_bg[@]} / 100 + 1 ))
    bg=${_bg[idx-1]}
  fi
  local -n _fg=_POWERLEVEL9K_BATTERY_${state}_LEVEL_FOREGROUND
  if (( ${#_fg[@]} )); then
    idx=${#_fg[@]}; (( bat_percent < 100 )) && idx=$(( bat_percent * ${#_fg[@]} / 100 + 1 ))
    fg=${_fg[idx-1]}
  fi
  _p9k__battery_args=("prompt_battery_$state" "$bg" "$fg" "$icon" 0 '' "$msg")
}

# --------------------------------------------------------------------- wifi ---
# From /proc/net/wireless (one interface, connected) and `iw dev IF link`;
# bars from the signal-to-noise margin.
prompt_wifi() {
  _p9k_prompt_segment "${FUNCNAME[0]}" green "$_p9k_color1" WIFI_ICON 1 '$_p9k__wifi_on' '$P9K_WIFI_LAST_TX_RATE Mbps'
}
_p9k_prompt_wifi_init() {
  if [[ -r $_p9k_proc_wireless ]] && type -P iw >/dev/null; then
    _p9k__wifi_on='' P9K_WIFI_LAST_TX_RATE='' P9K_WIFI_SSID='' P9K_WIFI_LINK_AUTH='' P9K_WIFI_RSSI='' P9K_WIFI_NOISE='' P9K_WIFI_BARS=''
    [[ " ${_p9k__precompute[*]} " == *' _p9k_wifi_compute '* ]] || _p9k__precompute+=(_p9k_wifi_compute)
  else
    _p9k_cond_never
  fi
}
_p9k_wifi_compute() {
  local last_tx_rate='' ssid='' link_auth='' rssi='' noise='' bars='' on='' iface state line
  _p9k_wifi_read && on=1
  if [[ -z $on ]]; then rssi='' noise='' ssid='' last_tx_rate='' bars='' link_auth=''; fi
  _p9k__wifi_on=$on P9K_WIFI_LAST_TX_RATE=$last_tx_rate P9K_WIFI_SSID=$ssid P9K_WIFI_LINK_AUTH=$link_auth
  P9K_WIFI_RSSI=$rssi P9K_WIFI_NOISE=$noise P9K_WIFI_BARS=$bars
}
_p9k_wifi_read() {
  local -a lines=() parts
  while IFS= read -r line; do [[ $line == *'|'* ]] || lines+=("$line"); done <"$_p9k_proc_wireless" 2>/dev/null
  (( ${#lines[@]} == 1 )) || return 1
  read -r -a parts <<<"${lines[0]}"
  iface=${parts[0]%:} state=${parts[1]} rssi=${parts[3]%.*} noise=${parts[4]%.*}
  [[ -n $iface && $state =~ ^0+$ && $rssi =~ ^(0|-[0-9]+)$ && $noise =~ ^(0|-[0-9]+)$ ]] || return 1
  local out; out=$(command iw dev "$iface" link) || return 1
  while IFS= read -r line; do
    if [[ $line =~ ^[[:space:]]*SSID:[[:space:]]+(.*)$ ]]; then
      ssid=${BASH_REMATCH[1]}
    elif [[ $line =~ ^[[:space:]]*'tx bitrate:'[[:space:]]+([^[:space:]]+)' MBit/s' ]]; then
      last_tx_rate=${BASH_REMATCH[1]}
      if [[ $last_tx_rate =~ ^[0-9]+\.[0-9]+$ ]]; then
        while [[ $last_tx_rate == *0 ]]; do last_tx_rate=${last_tx_rate%0}; done
        last_tx_rate=${last_tx_rate%.}
      fi
    fi
  done <<<"$out"
  [[ -n $ssid && -n $last_tx_rate ]] || return 1
  local -i snr=$(( rssi - noise ))
  if (( snr >= 40 )); then bars=4
  elif (( snr >= 25 )); then bars=3
  elif (( snr >= 15 )); then bars=2
  elif (( snr >= 10 )); then bars=1
  else bars=0
  fi
  return 0
}

# --------------------------------------------------------------------- todo ---
# todo.sh / todo-txt: "TODO: N of M tasks shown" from `todo.sh -p ls`.
prompt_todo() {
  unset P9K_TODO_TOTAL_TASK_COUNT P9K_TODO_FILTERED_TASK_COUNT
  [[ -r ${_p9k__todo_file-} && -x ${_p9k__todo_command-} ]] || return 0
  if ! _p9k_cache_stat_get prompt_todo "$_p9k__todo_file"; then
    local count; count=$("$_p9k__todo_command" -p ls | command tail -1)
    if [[ $count =~ ^'TODO: '([[:digit:]]+)' of '([[:digit:]]+)' ' ]]; then
      _p9k_cache_stat_set 1 "${BASH_REMATCH[1]}" "${BASH_REMATCH[2]}"
    else
      _p9k_cache_stat_set 0
    fi
  fi
  (( ${_p9k__cache_val[1]} )) || return 0
  P9K_TODO_FILTERED_TASK_COUNT=$(( 10#${_p9k__cache_val[2]} ))
  P9K_TODO_TOTAL_TASK_COUNT=$(( 10#${_p9k__cache_val[3]} ))
  if (( (P9K_TODO_TOTAL_TASK_COUNT || !_POWERLEVEL9K_TODO_HIDE_ZERO_TOTAL) &&
        (P9K_TODO_FILTERED_TASK_COUNT || !_POWERLEVEL9K_TODO_HIDE_ZERO_FILTERED) )); then
    local text
    if (( P9K_TODO_TOTAL_TASK_COUNT == P9K_TODO_FILTERED_TASK_COUNT )); then text=$P9K_TODO_TOTAL_TASK_COUNT
    else text="$P9K_TODO_FILTERED_TASK_COUNT/$P9K_TODO_TOTAL_TASK_COUNT"
    fi
    _p9k_prompt_segment "${FUNCNAME[0]}" grey50 "$_p9k_color1" TODO_ICON 0 '' "$text"
  fi
}
_p9k_prompt_todo_init() {
  # p10k: the TODO_FILE of todo.sh's configuration, found as todo.sh does
  local tg=''
  _p9k__todo_file=''
  if _p9k__todo_command=$(type -P todo.sh); then tg=/etc/todo/config
  elif _p9k__todo_command=$(type -P todo-txt); then tg=/etc/todo-txt/config
  else _p9k__todo_command=''
  fi
  if [[ -n $_p9k__todo_command ]]; then
    _p9k__todo_file=$(TODOTXT_P9K_DIR=${_p9k__todo_command%/*} TODOTXT_P9K_GLOBAL=$tg bash -c '
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=$HOME/.todo/config
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=$HOME/todo.cfg
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=$HOME/.todo.cfg
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=${XDG_CONFIG_HOME:-$HOME/.config}/todo/config
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=$TODOTXT_P9K_DIR/todo.cfg
      [ -e "$TODOTXT_CFG_FILE" ] || TODOTXT_CFG_FILE=${TODOTXT_GLOBAL_CFG_FILE:-$TODOTXT_P9K_GLOBAL}
      [ -r "$TODOTXT_CFG_FILE" ] || exit
      source "$TODOTXT_CFG_FILE"
      printf "%s" "$TODO_FILE" >&3' 3>&1 &>/dev/null)
  fi
  _p9k_set_cond '${_p9k__todo_file-}'
}

# -------------------------------------------------------------- timewarrior ---
# The tags of the open interval ("inc <start> # tags") in the newest
# YYYY-MM.data file of the timewarrior database.
prompt_timewarrior() {
  local dir=${TIMEWARRIORDB-}
  if [[ -z $dir ]]; then
    if [[ -d $HOME/.timewarrior ]]; then dir=$HOME/.timewarrior
    else dir=${XDG_DATA_HOME:-$HOME/.local/share}/timewarrior
    fi
  fi
  dir+=/data
  [[ -d $dir ]] || return 0
  local had_null=0; shopt -q nullglob && had_null=1; shopt -s nullglob
  local -a files=() f
  for f in "$dir"/*-*.data; do
    [[ ${f##*/} =~ ^[0-9]+-[0-9]+\.data$ && -f $f ]] && files+=("$f")
  done
  (( had_null )) || shopt -u nullglob
  (( ${#files[@]} )) || return 0
  # zsh ${(AO)files}[1]: the last in reverse alphabetical order... i.e. the
  # greatest name
  local newest=${files[0]}
  for f in "${files[@]}"; do [[ $f > $newest ]] && newest=$f; done
  local tail='' line
  while IFS= read -r line || [[ -n $line ]]; do [[ -n $line ]] && tail=$line; done <"$newest" 2>/dev/null
  if [[ $tail =~ ^'inc '[^\ ]+(\ *#(.*))?$ ]]; then
    local tags=${BASH_REMATCH[2]}
    tags=${tags#"${tags%%[! ]*}"}; tags=${tags%"${tags##*[! ]}"}
    _p9k_prompt_segment "${FUNCNAME[0]}" grey 255 TIMEWARRIOR_ICON 0 '' "${tags//%/%%}"
  fi
}
_p9k_prompt_timewarrior_init() { _p9k_set_cond '@_p9k_have_cmd timew'; }

# -------------------------------------------------------------- taskwarrior ---
# "!overdue/pending" from `task +OVERDUE count` and `task +PENDING count`;
# recomputed when the task data or ~/.taskrc change, or a due date passes.
prompt_taskwarrior() {
  unset P9K_TASKWARRIOR_PENDING_COUNT P9K_TASKWARRIOR_OVERDUE_COUNT
  local dir sig now=${EPOCHREALTIME%[.,]*}
  if [[ -z ${_p9k__tw_dir+x} || ${_p9k__tw_meta_key-} != "${TASKRC-}"$'\1'"${TASKDATA-}" ]]; then
    # p10k gives up (until the next reload) when `task` cannot tell where its data is
    [[ ${_p9k__tw_broken-} == "${TASKRC-}"$'\1'"${TASKDATA-}" ]] && return 0
    _p9k__tw_broken=${TASKRC-}$'\1'${TASKDATA-}
    local cfg; cfg=$(command task show data.location rc.color=0 rc._forcecolor=0 </dev/null 2>/dev/null) || return 0
    local -a lines=(); local l
    while IFS= read -r l; do [[ $l =~ ^data\.location[[:space:]]+[^[:space:]] ]] && lines+=("$l"); done <<<"$cfg"
    (( ${#lines[@]} == 1 )) || return 0
    _p9k__tw_broken=
    dir=${lines[0]#data.location}; dir=${dir#"${dir%%[! ]*}"}
    [[ $dir == '~'* ]] && dir=$HOME${dir#\~}
    _p9k__tw_dir=$dir _p9k__tw_meta_key=${TASKRC-}$'\1'${TASKDATA-}
  fi
  dir=$_p9k__tw_dir
  sig=$(stat -c %Y -- "$dir"/pending.data "$dir"/completed.data "$dir"/taskchampion.sqlite3 "${TASKRC:-$HOME/.taskrc}" 2>/dev/null | tr '\n' :)
  if [[ $sig != "${_p9k__tw_sig-}" ]] || (( ${_p9k__tw_next_due:-0} != 0 && _p9k__tw_next_due <= now )); then
    _p9k__tw_sig=$sig
    declare -gA _p9k__tw_counters=()
    local name val
    for name in PENDING OVERDUE; do
      val=$(command task +$name count rc.color=0 rc._forcecolor=0 </dev/null 2>/dev/null) || continue
      [[ $val =~ ^[0-9]+$ ]] && (( 10#$val >= 1 )) || continue
      _p9k__tw_counters[$name]=$val
    done
    _p9k__tw_next_due=0
    if (( ${_p9k__tw_counters[PENDING]:-0} > ${_p9k__tw_counters[OVERDUE]:-0} )); then
      local -a ts=()
      read -r -d '' -a ts < <(command task +PENDING -OVERDUE list rc.verbose=nothing rc.color=0 rc._forcecolor=0 \
        rc.report.list.labels= rc.report.list.columns=due.epoch </dev/null 2>/dev/null)
      local t ok=1 min=''
      for t in "${ts[@]}"; do [[ $t =~ ^-?[0-9]+(\.[0-9]+)?$ ]] || ok=0; done
      if (( ${#ts[@]} && ok )); then
        for t in "${ts[@]}"; do t=${t%.*}; [[ -z $min ]] || (( t < min )) && min=$t; done
        _p9k__tw_next_due=$min
        (( _p9k__tw_next_due > now )) || _p9k__tw_next_due=$(( now + 60 ))
      fi
    fi
  fi
  (( ${#_p9k__tw_counters[@]} )) || return 0
  local text='' c=${_p9k__tw_counters[OVERDUE]-}
  if [[ -n $c ]]; then P9K_TASKWARRIOR_OVERDUE_COUNT=$c; text+="!$c"; fi
  c=${_p9k__tw_counters[PENDING]-}
  if [[ -n $c ]]; then P9K_TASKWARRIOR_PENDING_COUNT=$c; [[ -n $text ]] && text+=/; text+=$c; fi
  [[ -n $text ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}" 6 "$_p9k_color1" TASKWARRIOR_ICON 0 '' "$text"
}
_p9k_prompt_taskwarrior_init() { _p9k_set_cond '@_p9k_have_cmd task'; }

# ---------------------------------------------------- per_directory_history ---
# For the zsh plugin of that name; in bash it shows when a compatible tool
# sets PER_DIRECTORY_HISTORY_TOGGLE and _per_directory_history_is_global.
prompt_per_directory_history() {
  if [[ ${_per_directory_history_is_global-} == true ]]; then
    _p9k_prompt_segment "${FUNCNAME[0]}_GLOBAL" 3 "$_p9k_color1" HISTORY_ICON 0 '' global
  else
    _p9k_prompt_segment "${FUNCNAME[0]}_LOCAL" 5 "$_p9k_color1" HISTORY_ICON 0 '' local
  fi
}
_p9k_prompt_per_directory_history_init() { _p9k_set_cond '${PER_DIRECTORY_HISTORY_TOGGLE-}'; }

# ------------------------------------------------------------------ nordvpn ---
# Disabled in p10k 1.21.0 ("broken, see romkatv/powerlevel10k#2860"): it
# never shows anything. Kept so configurations that list it work the same.
prompt_nordvpn() { return 0; }
_p9k_prompt_nordvpn_init() { _p9k_set_cond '@_p9k_have_cmd nordvpn'; }

# ------------------------------------------------------------------ dropbox ---
prompt_dropbox() {
  local st; st=$(dropbox-cli filestatus . | cut -d' ' -f2-)
  if [[ $st != unwatched && $st != "isn't running!" ]]; then
    [[ $st == *'up to date'* ]] && st=''
    _p9k_prompt_segment "${FUNCNAME[0]}" white blue DROPBOX_ICON 0 '' "${st//%/%%}"
  fi
}
_p9k_prompt_dropbox_init() { _p9k_set_cond '@_p9k_have_cmd dropbox-cli'; }

# ----------------------------------------------------------------- openfoam ---
prompt_openfoam() {
  local v=${WM_PROJECT_VERSION-}; v=${v%/}; v=${v##*/}
  if [[ -z ${WM_FORK-} ]]; then
    _p9k_prompt_segment "${FUNCNAME[0]}" yellow "$_p9k_color1" '' 0 '' "OF: ${v//%/%%}"
  else
    _p9k_prompt_segment "${FUNCNAME[0]}" yellow "$_p9k_color1" '' 0 '' "F-X: ${v//%/%%}"
  fi
}

# --------------------------------------------------------------- test ratios ---
# p10k: _p9k_build_test_stats NAME CODE TESTS HEADLINE ICON. The ratio is
# printed with two decimals (zsh local -F 2).
_p9k_build_test_stats() {
  local -i code=$2 tests=$3
  (( code > 0 )) || return 0
  # 100 * tests / code with 2 decimals, rounded half up (as printf would)
  local -i r=$(( (100000 * tests / code + 5) / 10 ))
  local ratio; printf -v ratio '%d.%02d' $(( r / 100 )) $(( r % 100 ))
  if (( r >= 7500 )); then _p9k_prompt_segment "${1}_GOOD" cyan "$_p9k_color1" "$5" 0 '' "$4: $ratio%%"
  elif (( r >= 5000 )); then _p9k_prompt_segment "${1}_AVG" yellow "$_p9k_color1" "$5" 0 '' "$4: $ratio%%"
  else _p9k_prompt_segment "${1}_BAD" red "$_p9k_color1" "$5" 0 '' "$4: $ratio%%"
  fi
}
# all *.rb files below app/ and spec/ (zsh app/**/*.rb: hidden dirs skipped)
_p9k_count_files() { _p9k__n=$(find "$1" -name '.*' -prune -o -name "$2" -print 2>/dev/null | grep -c .); }
prompt_rspec_stats() {
  [[ -d app && -d spec ]] || return 0
  _p9k_count_files app '*.rb'; local code=$_p9k__n
  (( code )) || return 0
  _p9k_count_files spec '*.rb'
  _p9k_build_test_stats "${FUNCNAME[0]}" "$code" "$_p9k__n" RSpec TEST_ICON
}
prompt_symfony2_tests() {
  [[ -d src && -d app && -f app/AppKernel.php ]] || return 0
  local all code
  all=$(find src -name '.*' -prune -o -name '*.php' -print 2>/dev/null | grep -c .)
  # p10k drops the paths that contain "Tests"
  code=$(find src -name '.*' -prune -o -name '*.php' -print 2>/dev/null | grep -vc Tests)
  (( code )) || return 0
  _p9k_build_test_stats "${FUNCNAME[0]}" "$code" $(( all - code )) SF2 TEST_ICON
}
prompt_symfony2_version() {
  [[ -r app/bootstrap.php.cache ]] || return 0
  local v; v=$(grep -F " VERSION " app/bootstrap.php.cache 2>/dev/null)
  v=${v//[!0-9.]/}
  _p9k_prompt_segment "${FUNCNAME[0]}" grey35 "$_p9k_color1" SYMFONY_ICON 0 '' "${v//%/%%}"
}
