#!/bin/bash
# tests/p10k/unit-wifi.sh : the wifi segment's computation, p10k's own
# _p9k_prompt_wifi_async (from p10k.zsh; /proc/net/wireless pointed at a
# fixture, a fake `iw` on PATH) against the port. Compares P9K_WIFI_*.
T=${B4H_TEST_DIR:-/tmp/b4h-test}/wifi; rm -rf "$T"; mkdir -p "$T/bin"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
P10K=$HOME/src/powerlevel10k/internal/p10k.zsh
H='Inter-| sta-|   Quality        |   Discarded packets               | Missed | WE
 face | tus | link level noise |  nwid  crypt   frag  retry   misc | beacon | 22'
wl() { printf '%s\n%s\n' "$H" "$2" >"$T/$1.wireless"; printf '%s\n' "$3" >"$T/$1.iw"; }
IW=$'Connected to 74:83:c2:be:76:da (on wlp3s0)\n\tSSID: Daily Grind\n\tfreq: 5745\n\tsignal: -52 dBm\n\ttx bitrate: 240.0 MBit/s VHT-MCS 5'
wl good   'wlp3s0: 0000   58.  -52.  -256        0      0      0      0     76        0' "$IW"
wl snr30  'wlp3s0: 0000   58.  -60.  -90        0      0      0      0     76        0' "${IW/240.0/86.70}"
wl snr12  'wlp3s0: 0000   58.  -80.  -92        0      0      0      0     76        0' "${IW/240.0/6}"
wl down   'wlp3s0: 0001   58.  -52.  -256        0      0      0      0     76        0' "$IW"
wl nossid 'wlp3s0: 0000   58.  -52.  -256        0      0      0      0     76        0' $'\ttx bitrate: 240.0 MBit/s'
wl two    $'wlp3s0: 0000   58.  -52.  -256 0 0 0 0 76 0\nwlan1: 0000   58.  -52.  -256 0 0 0 0 76 0' "$IW"
printf '#!/bin/sh\ncat "$IW_OUT"\n' >"$T/bin/iw"; chmod +x "$T/bin/iw"
fn=$(sed -n '/^_p9k_prompt_wifi_async() {/,/^}/p' "$P10K")
pass=0 fail=0
for f in "$T"/*.wireless; do
  n=${f##*/}; n=${n%.wireless}
  vars='_p9k__wifi_on P9K_WIFI_LAST_TX_RATE P9K_WIFI_SSID P9K_WIFI_LINK_AUTH P9K_WIFI_RSSI P9K_WIFI_NOISE P9K_WIFI_BARS'
  z=$(IW_OUT=$T/$n.iw PATH=$T/bin:$PATH zsh -fc 'setopt extended_glob no_ksh_arrays
    _p9k_print_params() { :; }
    '"${fn//\/proc\/net\/wireless/$f}"'
    _p9k_prompt_wifi_async >/dev/null
    for v in '"$vars"'; do print -rn -- "${(P)v}|"; done' 2>&1)
  b=$(IW_OUT=$T/$n.iw PATH=$T/bin:$PATH bash -c '. "'"$root"'/lib/p10k/main.bash"
    _p9k_proc_wireless='"$f"'
    _p9k_wifi_compute
    for v in '"$vars"'; do printf "%s|" "${!v}"; done' 2>&1)
  if [[ $z == "$b" ]]; then (( pass++ )); echo "SAME  $n   $z"; else (( fail++ )); echo "DIFF  $n"; echo "   zsh:  $z"; echo "   bash: $b"; fi
done
echo "same: $pass   different: $fail"
