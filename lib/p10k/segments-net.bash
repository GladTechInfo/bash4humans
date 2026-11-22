# =============================================================================
#  lib/p10k/segments-net.bash - network segments: ip, vpn_ip, public_ip.
#  Ports of p10k's prompt_ip, prompt_vpn_ip, prompt_public_ip and the shared
#  _p9k_prompt_net_iface_* functions.
#
#  p10k scans the interfaces in its background worker before each prompt;
#  here the scan runs in the prompt hook (one `ip -4 a show`). The values it
#  keeps between prompts (bytes and time) give the transfer rates, exactly as
#  in p10k: the first prompt, or a new address or interface, shows "0 B/s".
#  The public address needs the network, so it is fetched by a detached
#  background process and shown once it has arrived.
# =============================================================================

declare -ga _p9k__precompute=()   # functions the prompt hook runs before the segments

# ---------------------------------------------------------- interface scan ---
# p10k: _p9k_prompt_net_iface_init. Called by _p9k_init when ip, vpn_ip or
# public_ip (with a VPN interface) is in use.
_p9k_prompt_net_iface_init() {
  _p9k__public_ip_vpn='' _p9k__public_ip_not_vpn=''
  P9K_IP_IP='' P9K_IP_INTERFACE='' P9K_IP_TX_BYTES='' P9K_IP_RX_BYTES=''
  P9K_IP_TX_BYTES_DELTA='' P9K_IP_RX_BYTES_DELTA='' P9K_IP_TX_RATE='' P9K_IP_RX_RATE=''
  _p9k__ip_timestamp=''
  declare -ga _p9k__vpn_ip_ips=()
  [[ -z $_POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE ]] && _p9k__public_ip_not_vpn=1
  _p9k__precompute+=(_p9k_net_iface_compute)
}

# Interfaces that are up, with their first IPv4 address -> _p9k__iface2ip
# (pairs: name address name address ...). `ip` output looks like
#   2: eth0@if7: <BROADCAST,MULTICAST,UP,LOWER_UP> mtu 1500 ...
#       inet 192.0.2.10/24 ...
_p9k_net_iface_scan() {
  declare -ga _p9k__iface2ip=()
  local line iface=''
  local re_if='^[0-9]+:[[:space:]]+([^:]+):[[:space:]]+<([^>]*)>'
  local re_in='^[[:space:]]+inet[[:space:]]+([0-9.]+)'
  if command -v ip >/dev/null && { ! command -v ifconfig >/dev/null || [[ $OSTYPE == linux* ]]; }; then
    while IFS= read -r line; do
      if [[ $line =~ $re_if ]]; then
        [[ ,${BASH_REMATCH[2]}, == *,UP,* ]] && iface=${BASH_REMATCH[1]} || iface=''
      elif [[ -n $iface && $line =~ $re_in ]]; then
        _p9k__iface2ip+=("$iface" "${BASH_REMATCH[1]}"); iface=''
      fi
    done < <(command ip -4 a show 2>/dev/null)
  elif command -v ifconfig >/dev/null; then
    local re_fl='^([^[:space:]]+):[[:space:]]+flags=([[:xdigit:]]+)<'
    while IFS= read -r line; do
      if [[ $line =~ $re_fl ]]; then
        # the UP flag is bit 0 of the hexadecimal flags
        [[ ${BASH_REMATCH[2]} == *[13579bdfBDF] ]] && iface=${BASH_REMATCH[1]} || iface=''
      elif [[ -n $iface && $line =~ $re_in ]]; then
        _p9k__iface2ip+=("$iface" "${BASH_REMATCH[1]}"); iface=''
      fi
    done < <(command ifconfig 2>/dev/null)
  fi
}

# p10k: _p9k_prompt_net_iface_match REGEX -> _p9k__ifaces, _p9k__ips; status 0 if any
_p9k_net_iface_match() {
  local re="^($1)\$" i
  _p9k__ifaces=() _p9k__ips=()
  for (( i = 0; i < ${#_p9k__iface2ip[@]}; i += 2 )); do
    [[ ${_p9k__iface2ip[i]} =~ $re ]] || continue
    _p9k__ifaces+=("${_p9k__iface2ip[i]}") _p9k__ips+=("${_p9k__iface2ip[i+1]}")
  done
  (( ${#_p9k__ips[@]} ))
}

# "1.5K" -> "1.5 KiB/s", "12B" -> "12 B/s" (p10k's rate text)
_p9k_net_rate_text() {
  if [[ $_p9k__ret == *B ]]; then _p9k__ret="${_p9k__ret%?} B/s"
  else _p9k__ret="${_p9k__ret%?} ${_p9k__ret: -1}iB/s"
  fi
}

# p10k: _p9k_prompt_net_iface_async (+ _sync), run before each prompt.
_p9k_net_iface_compute() {
  _p9k_net_iface_scan
  local -a _p9k__ifaces _p9k__ips
  local public_ip_vpn public_ip_not_vpn
  if _p9k_net_iface_match "$_POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE"; then public_ip_vpn=1 public_ip_not_vpn=''
  else public_ip_vpn='' public_ip_not_vpn=1
  fi
  local ip_ip='' ip_interface='' ip_timestamp='' ip_tx_bytes='' ip_rx_bytes='' ip_tx_rate='' ip_rx_rate=''
  if _p9k_net_iface_match "$_POWERLEVEL9K_IP_INTERFACE"; then
    ip_ip=${_p9k__ips[0]} ip_interface=${_p9k__ifaces[0]} ip_timestamp=${EPOCHREALTIME/,/.}
    local st=/sys/class/net/${_p9k__ifaces[0]}/statistics
    if [[ -r $st/tx_bytes && -r $st/rx_bytes ]]; then
      ip_tx_bytes=$(<"$st/tx_bytes") ip_rx_bytes=$(<"$st/rx_bytes")
      [[ $ip_tx_bytes =~ ^[0-9]+$ && $ip_rx_bytes =~ ^[0-9]+$ ]] || ip_tx_bytes='' ip_rx_bytes=''
    fi
    if [[ -n $ip_rx_bytes ]]; then
      if [[ $ip_ip == "$P9K_IP_IP" && ${_p9k__ifaces[0]} == "$P9K_IP_INTERFACE" ]]; then
        # elapsed time in microseconds; rate = delta bytes / seconds, with
        # 6 decimals (zsh computes it in floating point)
        local us=$(( ${ip_timestamp/./} - ${_p9k__ip_timestamp/./} ))
        if (( us <= 0 )); then
          ip_tx_rate=${P9K_IP_TX_RATE:-0 B/s} ip_rx_rate=${P9K_IP_RX_RATE:-0 B/s}
        else
          local dv
          dv=$(( ip_tx_bytes - P9K_IP_TX_BYTES ))
          _p9k_net_rate "$dv" "$us"; _p9k_human_readable_bytes "$_p9k__ret"; _p9k_net_rate_text; ip_tx_rate=$_p9k__ret
          dv=$(( ip_rx_bytes - P9K_IP_RX_BYTES ))
          _p9k_net_rate "$dv" "$us"; _p9k_human_readable_bytes "$_p9k__ret"; _p9k_net_rate_text; ip_rx_rate=$_p9k__ret
        fi
      else
        ip_tx_rate='0 B/s' ip_rx_rate='0 B/s'
      fi
    fi
  fi
  local -a vpn_ip_ips=()
  if _p9k_net_iface_match "$_POWERLEVEL9K_VPN_IP_INTERFACE"; then
    if (( _POWERLEVEL9K_VPN_IP_SHOW_ALL )); then vpn_ip_ips=("${_p9k__ips[@]}"); else vpn_ip_ips=("${_p9k__ips[0]}"); fi
  fi
  _p9k__public_ip_vpn=$public_ip_vpn _p9k__public_ip_not_vpn=$public_ip_not_vpn
  P9K_IP_IP=$ip_ip P9K_IP_INTERFACE=$ip_interface
  if [[ -n $ip_tx_bytes && -n $P9K_IP_TX_BYTES ]]; then P9K_IP_TX_BYTES_DELTA=$(( ip_tx_bytes - P9K_IP_TX_BYTES )); else P9K_IP_TX_BYTES_DELTA=''; fi
  if [[ -n $ip_rx_bytes && -n $P9K_IP_RX_BYTES ]]; then P9K_IP_RX_BYTES_DELTA=$(( ip_rx_bytes - P9K_IP_RX_BYTES )); else P9K_IP_RX_BYTES_DELTA=''; fi
  P9K_IP_TX_BYTES=$ip_tx_bytes P9K_IP_RX_BYTES=$ip_rx_bytes
  P9K_IP_TX_RATE=$ip_tx_rate P9K_IP_RX_RATE=$ip_rx_rate
  _p9k__ip_timestamp=$ip_timestamp
  _p9k__vpn_ip_ips=("${vpn_ip_ips[@]}")
}

# BYTES / (MICROSECONDS / 1e6) as a decimal with 6 places -> _p9k__ret
_p9k_net_rate() {
  local -i b=$1 us=$2 neg=0
  (( b < 0 )) && { neg=1; b=$(( -b )); }
  local whole=$(( b * 1000000 / us )) rem=$(( b * 1000000 % us ))
  printf -v _p9k__ret '%d.%06d' "$whole" $(( rem * 1000000 / us ))
  (( neg )) && _p9k__ret=-$_p9k__ret
}

# ----------------------------------------------------------------------- ip ---
prompt_ip() {
  _p9k_prompt_segment "${FUNCNAME[0]}" cyan "$_p9k_color1" NETWORK_ICON 1 '$P9K_IP_IP' '$P9K_IP_IP'
}

# ------------------------------------------------------------------- vpn_ip ---
# One segment per address (VPN_IP_SHOW_ALL=true) or for the first one.
prompt_vpn_ip() {
  local ip
  for ip in "${_p9k__vpn_ip_ips[@]}"; do
    [[ -n $ip ]] && _p9k_prompt_segment prompt_vpn_ip cyan "$_p9k_color1" VPN_ICON 0 '' "$ip"
  done
  return 0
}

# ---------------------------------------------------------------- public_ip ---
# PUBLIC_IP_METHODS (dig, curl, wget) are tried in order, twice; a result is
# kept for PUBLIC_IP_TIMEOUT seconds, a failure is retried after 5 seconds.
# With PUBLIC_IP_VPN_INTERFACE set, the icon is VPN_ICON while such an
# interface is up.
prompt_public_ip() {
  local ip='${_p9k__public_ip:-$_POWERLEVEL9K_PUBLIC_IP_NONE}'
  if [[ -n $_POWERLEVEL9K_PUBLIC_IP_VPN_INTERFACE ]]; then
    _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" "$_p9k_color2" PUBLIC_IP_ICON 1 '${_p9k__public_ip_not_vpn:+'"$ip"'}' "$ip"
    _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" "$_p9k_color2" VPN_ICON 1 '${_p9k__public_ip_vpn:+'"$ip"'}' "$ip"
  else
    _p9k_prompt_segment "${FUNCNAME[0]}" "$_p9k_color1" "$_p9k_color2" PUBLIC_IP_ICON 1 "$ip" "$ip"
  fi
}
_p9k_prompt_public_ip_init() {
  _p9k__public_ip='' _p9k__public_ip_next=0
  _p9k__public_ip_file=${XDG_RUNTIME_DIR:-/tmp}/p9k-public-ip.$UID.$$
  rm -f -- "$_p9k__public_ip_file"
  _p9k__precompute+=(_p9k_public_ip_compute)
}

# Before each prompt: take a finished result, start a fetch when one is due.
_p9k_public_ip_compute() {
  _p9k_public_ip_take
  (( ${_p9k__public_ip_busy:-0} )) && return 0
  local now=${EPOCHREALTIME%[.,]*}
  (( now >= _p9k__public_ip_next )) || return 0
  _p9k__public_ip_busy=1
  # ( ... & ) runs the fetch detached: no job-control messages, not counted
  # by background_jobs.
  ( _p9k_public_ip_fetch "$_p9k__public_ip_file" "$now" >/dev/null 2>&1 </dev/null & )
  # ble.sh: redraw the prompt on the screen when the result comes (p10k does
  # this through its worker); plain bash shows it at the next prompt.
  if (( ${_p9k_ble:-0} && ! ${_p9k__public_ip_watch:-0} )); then
    _p9k__public_ip_watch=1
    ble/util/idle.push -F "$_p9k__public_ip_file" _p9k_public_ip_idle
  fi
}

# A finished result -> _p9k__public_ip; status 1 if there is none.
_p9k_public_ip_take() {
  local f=$_p9k__public_ip_file line
  [[ -s $f ]] || return 1
  # the file holds: NEXT_TIME IP   (written in one go by the fetcher)
  read -r line <"$f" && rm -f -- "$f"
  _p9k__public_ip_next=${line%% *}
  local ip=${line#* }; [[ $line == *' '* ]] || ip=''
  _p9k__public_ip=$ip
  _p9k__public_ip_busy=0
}

# ble.sh idle task (the file has content): take it and redraw if it changed.
_p9k_public_ip_idle() {
  _p9k__public_ip_watch=0
  local old=$_p9k__public_ip
  _p9k_public_ip_take || return 0
  [[ $_p9k__public_ip == "$old" ]] || _p9k_replay_render
}

_p9k_public_ip_fetch() {
  local f=$1 start=$2 ip='' method next=$(( $2 + 5 ))
  for method in "${_POWERLEVEL9K_PUBLIC_IP_METHODS[@]}" "${_POWERLEVEL9K_PUBLIC_IP_METHODS[@]}"; do
    case $method in
      dig)
        if command -v dig >/dev/null; then
          ip=$(dig +tries=1 +short -4 A myip.opendns.com @resolver1.opendns.com 2>/dev/null)
          [[ $ip == ';'* ]] && ip=''
          if [[ -z $ip ]]; then
            ip=$(dig +tries=1 +short -6 AAAA myip.opendns.com @resolver1.opendns.com 2>/dev/null)
            [[ $ip == ';'* ]] && ip=''
          fi
        fi ;;
      curl) command -v curl >/dev/null && ip=$(curl --max-time 5 -w '\n' "$_POWERLEVEL9K_PUBLIC_IP_HOST" 2>/dev/null) ;;
      wget) command -v wget >/dev/null && ip=$(wget -T 5 -qO- "$_POWERLEVEL9K_PUBLIC_IP_HOST" 2>/dev/null) ;;
    esac
    [[ $ip =~ ^[0-9a-f.:]+$ ]] || ip=''
    if [[ -n $ip ]]; then
      next=$(( start + ${_POWERLEVEL9K_PUBLIC_IP_TIMEOUT%%.*} ))
      break
    fi
  done
  printf '%s %s\n' "$next" "$ip" >"$f.tmp" && mv -f -- "$f.tmp" "$f"
}
