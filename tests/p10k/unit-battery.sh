#!/bin/bash
# tests/p10k/unit-battery.sh : the battery segment's computation, p10k's own
# _p9k_prompt_battery_set_args (taken from p10k.zsh, run in zsh with the
# sysfs directory pointed at a fixture) against the port, for several
# battery states. Compares the resulting segment arguments.
T=${B4H_TEST_DIR:-/tmp/b4h-test}/battery; rm -rf "$T"; mkdir -p "$T"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
P10K=$HOME/src/powerlevel10k/internal/p10k.zsh
ZSH=${ZSH_REF:-zsh}

bat() {  # bat CASE NAME key=value...
  local d=$T/$1/$2; mkdir -p "$d"; shift 2
  local kv; for kv; do printf '%s\n' "${kv#*=}" >"$d/${kv%%=*}"; done
}
bat discharging BAT0 status=Discharging energy_full=50000000 energy_now=20000000 power_now=10000000
bat charging    BAT0 status=Charging capacity=55 charge_full=4000000 current_now=1000000
bat full        BAT0 status=Full energy_full=50000000 energy_now=50000000
bat low         BAT0 status=Discharging capacity=5 energy_full=50000000 power_now=9000000
bat two         BAT0 status=Discharging energy_full=30000000 energy_now=10000000 power_now=5000000
bat two         BAT1 status=Discharging energy_full=20000000 energy_now=15000000 power_now=0
bat two         CMB1 status=Unknown energy_full=99 energy_now=99
bat calc        BAT0 status=Discharging energy_full=50000000 energy_now=33333333 power_now=0
bat counter     BAT0 status=Discharging charge_counter=1000 charge_full=4000 charge_now=777
bat ch100       BAT0 status=Charging capacity=100 energy_full=1000
bat bigpow      BAT0 status=Discharging energy_full=50000000 energy_now=20000000 power_now=123456789
bat round       BAT0 status=Discharging energy_full=3 energy_now=2 power_now=1
bat hidpp       hidpp_battery status=Discharging charge_counter=1000 charge_full=4000 charge_now=777 current_now=50

# settings: default, and with stages and level colours
settings=(
  'default|'
  'stages|POWERLEVEL9K_BATTERY_STAGES=(a b c d e) POWERLEVEL9K_BATTERY_LEVEL_BACKGROUND=(1 2 3 4) POWERLEVEL9K_BATTERY_CHARGING_LEVEL_FOREGROUND=(9 8) POWERLEVEL9K_BATTERY_VERBOSE=false'
  'hide|POWERLEVEL9K_BATTERY_DISCONNECTED_HIDE_ABOVE_THRESHOLD=40 POWERLEVEL9K_BATTERY_LOW_THRESHOLD=60'
)
fn=$(sed -n '/^_p9k_prompt_battery_set_args() {/,/^}/p; /^function _p9k_read_file() {/,/^}/p; /^function _p9k_declare() {/,/^}/p; /^_p9k_init_params() {/,/^}/p' "$P10K")
pass=0 fail=0
for c in "$T"/*/; do
  c=${c%/}; name=${c##*/}
  for s in "${settings[@]}"; do
    sid=${s%%|*} set=${s#*|}
    z=$("$ZSH" -fc '
      setopt extended_glob no_ksh_arrays
      '"$set"'
      _p9k_os=Linux _p9k_color1=0 _p9k_color2=7
      typeset -gA _p9k_battery_states=(LOW red CHARGING yellow CHARGED green DISCONNECTED 7)
      _p9k_segment_in_use() { true; }; _p9k_codeset_is_utf8() { true; }
      '"${fn//\/sys\/class\/power_supply/$c}"'
      _p9k_init_params >/dev/null 2>&1   # p10k'"'"'s own parameter defaults
      _p9k_prompt_battery_set_args
      print -r -- "${(j:|:)_p9k__battery_args}"' 2>&1)
    b=$(bash -c '
      . "'"$root"'/lib/p10k/main.bash"
      '"$set"'
      _p9k_init_params; _p9k_color1=0 _p9k_color2=7
      _p9k_sysfs_power='"$c"'
      _p9k_prompt_battery_set_args
      IFS="|"; echo "${_p9k__battery_args[*]}"' 2>&1)
    if [[ $z == "$b" ]]; then (( pass++ )); echo "SAME  $name/$sid   $z"
    else (( fail++ )); echo "DIFF  $name/$sid"; echo "   zsh:  $z"; echo "   bash: $b"
    fi
  done
done
echo "same: $pass   different: $fail"
