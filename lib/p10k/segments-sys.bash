# =============================================================================
#  lib/p10k/segments-sys.bash - system segments: load, ram, swap, disk_usage,
#  cpu_arch, detect_virt. Ports of p10k's prompt_* functions (Linux path).
#
#  p10k computes load (on macOS/BSD), ram, swap and disk_usage in a background
#  worker and redraws the prompt when the value arrives; the settled prompt
#  is the same as computing them here directly, which costs one read of
#  /proc or one `df`.
# =============================================================================

# p10k: _p9k_human_readable_bytes N -> _p9k__ret, e.g. 1536 -> 1.5K, 120M ->
# "120M". Divide by 1024 until below 1024, then 0, 1 or 2 decimals (for >=100,
# >=10, <10), trailing zeros and point removed. N may have a fraction (rates).
# bash has no floating point arithmetic, but its printf rounds a decimal
# string: the quotient is written out with 9 decimals by integer arithmetic.
_p9k_human_readable_bytes() {
  local -i b=${1%%.*} d=1 k=0
  local f=000000; [[ $1 == *.* ]] && { f=${1#*.}000000; f=${f:0:6}; }
  local -a suf=(B K M G T P E Z Y)
  while (( b / d >= 1024 && k < 8 )); do d=$(( d * 1024 )); (( k++ )); done
  local q=$(( b / d )) r=$(( b % d )) frac
  # (r + f/1e6) / d as 9 decimals. For units above G, d is scaled down first
  # (the lost digits are far below the 2 that are shown).
  local dd=$d rr=$r ff=$(( 10#$f ))
  while (( dd > 1000000000 )); do dd=$(( dd / 1024 )); rr=$(( rr / 1024 )); ff=0; done
  printf -v frac '%09d' $(( (rr * 1000000 + ff) * 1000 / dd ))
  local n=$q.$frac
  if (( q >= 100 )); then printf -v _p9k__ret '%.0f.' "$n"
  elif (( q >= 10 )); then printf -v _p9k__ret '%.1f' "$n"
  else printf -v _p9k__ret '%.2f' "$n"
  fi
  # zsh ${${x%%0#}%.}: remove trailing zeros, then a trailing point
  while [[ $_p9k__ret == *0 ]]; do _p9k__ret=${_p9k__ret%0}; done
  _p9k__ret=${_p9k__ret%.}${suf[k]}
}

# --------------------------------------------------------------------- load ---
# Load average (1, 5 or 15 minutes: LOAD_WHICH) against the number of CPUs.
prompt_load() {
  [[ -r /proc/loadavg ]] || return 0
  local -a f; read -r -a f </proc/loadavg || return 0
  local load=${f[_POWERLEVEL9K_LOAD_WHICH - 1]//,/.}
  # pct = 100 * load / cpus, compared as fixed point (6 decimals)
  local li=${load%%.*} lf=${load#*.}000000; [[ $load == *.* ]] || lf=000000
  local pct6=$(( (10#$li * 1000000 + 10#${lf:0:6}) * 100 / _p9k_num_cpus )) pct
  printf -v pct '%d.%06d' $(( pct6 / 1000000 )) $(( pct6 % 1000000 ))
  local me=${FUNCNAME[0]}
  if _p9k_fcmp "$pct" '>' "$_POWERLEVEL9K_LOAD_CRITICAL_PCT"; then
    _p9k_prompt_segment "${me}_CRITICAL" red "$_p9k_color1" LOAD_ICON 0 '' "$load"
  elif _p9k_fcmp "$pct" '>' "$_POWERLEVEL9K_LOAD_WARNING_PCT"; then
    _p9k_prompt_segment "${me}_WARNING" yellow "$_p9k_color1" LOAD_ICON 0 '' "$load"
  else
    _p9k_prompt_segment "${me}_NORMAL" green "$_p9k_color1" LOAD_ICON 0 '' "$load"
  fi
}
_p9k_prompt_load_init() { [[ -r /proc/loadavg ]] || _p9k_cond_never; }

# ---------------------------------------------------------------------- ram ---
# Available memory: MemAvailable (MemFree on old kernels) from /proc/meminfo.
# (p10k's pattern takes whichever of the two comes last; MemAvailable does.)
prompt_ram() {
  local k v u kb=''
  while read -r k v u; do
    [[ $k == MemFree: || $k == MemAvailable: ]] && kb=$v
  done </proc/meminfo
  [[ -n $kb ]] || return 0
  _p9k_human_readable_bytes $(( kb * 1024 ))
  _p9k_prompt_segment "${FUNCNAME[0]}" yellow "$_p9k_color1" RAM_ICON 0 '' "$_p9k__ret"
}
_p9k_prompt_ram_init() { [[ -r /proc/meminfo ]] || _p9k_cond_never; }

# --------------------------------------------------------------------- swap ---
# Used swap: SwapTotal - SwapFree (never below 0).
prompt_swap() {
  local k v u t='' f=''
  while read -r k v u; do
    case $k in SwapTotal:) t=$v ;; SwapFree:) f=$v ;; esac
  done </proc/meminfo
  [[ -n $t && -n $f ]] || return 0
  local used=$(( (t - f) * 1024 )); (( used >= 0 )) || used=0
  _p9k_human_readable_bytes "$used"
  _p9k_prompt_segment "${FUNCNAME[0]}" yellow "$_p9k_color1" SWAP_ICON 0 '' "$_p9k__ret"
}
_p9k_prompt_swap_init() { [[ -r /proc/meminfo ]] || _p9k_cond_never; }

# --------------------------------------------------------------- disk_usage ---
# Use% of the file system holding the current directory (df -P, 5th field).
prompt_disk_usage() {
  command -v df >/dev/null || return 0
  local -a l; local line n=0 pct=''
  while IFS= read -r line; do
    (( ++n == 2 )) && { read -r -a l <<<"$line"; pct=${l[4]%%%*}; }
  done < <(df -P -- "$PWD" 2>/dev/null)
  [[ $pct =~ ^[0-9]+$ ]] && (( 10#$pct <= 100 )) || return 0
  pct=$(( 10#$pct ))
  local me=${FUNCNAME[0]}
  if (( pct >= _POWERLEVEL9K_DISK_USAGE_CRITICAL_LEVEL )); then
    _p9k_prompt_segment "${me}_CRITICAL" red white DISK_ICON 0 '' "$pct%%"
  elif (( pct >= _POWERLEVEL9K_DISK_USAGE_WARNING_LEVEL )); then
    _p9k_prompt_segment "${me}_WARNING" yellow "$_p9k_color1" DISK_ICON 0 '' "$pct%%"
  elif (( ! _POWERLEVEL9K_DISK_USAGE_ONLY_WARNING )); then
    _p9k_prompt_segment "${me}_NORMAL" "$_p9k_color1" yellow DISK_ICON 0 '' "$pct%%"
  fi
}

# ----------------------------------------------------------------- cpu_arch ---
# Shown only where a `machine` or `arch` command exists (as in p10k), with
# the state _<ARCH>, e.g. prompt_cpu_arch_X86_64. Cached for the session.
prompt_cpu_arch() {
  if [[ -z ${_p9k__cpu_arch_text+x} ]]; then
    local text=''
    if [[ -r /proc/sys/kernel/arch ]]; then
      text=$(</proc/sys/kernel/arch)
    else
      local cmd
      for cmd in machine arch; do
        command -v "$cmd" >/dev/null || continue
        if text=$(command -- "$cmd" 2>/dev/null) && [[ $text =~ ^[a-zA-Z][a-zA-Z0-9_]*$ ]]; then break; else text=''; fi
      done
    fi
    _p9k__cpu_arch_text=$text
  fi
  [[ -n $_p9k__cpu_arch_text ]] || return 0
  _p9k_prompt_segment "${FUNCNAME[0]}_${_p9k__cpu_arch_text^^}" yellow "$_p9k_color1" ARCH_ICON 0 '' "$_p9k__cpu_arch_text"
}
_p9k_prompt_cpu_arch_init() { command -v machine >/dev/null || command -v arch >/dev/null || _p9k_cond_never; }

# -------------------------------------------------------------- detect_virt ---
# systemd-detect-virt's answer; "none" becomes "chroot" when / is not inode 2.
prompt_detect_virt() {
  local virt; virt=$(systemd-detect-virt 2>/dev/null)
  if [[ $virt == none ]]; then
    local ino; ino=$(stat -c %i / 2>/dev/null)
    [[ -n $ino && $ino != 2 ]] && virt=chroot
  fi
  [[ -n $virt ]] && _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" yellow '' 0 '' "${virt//%/%%}"
  return 0
}
_p9k_prompt_detect_virt_init() { command -v systemd-detect-virt >/dev/null || _p9k_cond_never; }
