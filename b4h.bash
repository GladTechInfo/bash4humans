# =============================================================================
#  bash4humans - entry point, sourced from ~/.bashrc.
#
#  Only interactive shells are touched: scripts, `bash -c`, scp, rsync and
#  cron see plain bash. `B4H_DISABLE=1 bash` starts a plain bash on demand.
# =============================================================================

[[ $- == *i* ]] || return 0
[[ -z ${B4H_DISABLE-} ]] || return 0
[[ -z ${_b4h_loaded-} ]] || return 0          # once per shell
if (( BASH_VERSINFO[0] < 5 )); then
  printf 'bash4humans: needs bash 5 or later (this is %s); plain bash it is\n' "$BASH_VERSION" >&2
  return 0
fi
_b4h_loaded=1

B4H_ROOT=${BASH_SOURCE[0]%/*}
[[ $B4H_ROOT == /* ]] || B4H_ROOT=$PWD/$B4H_ROOT
B4H_VERSION=0.3.0

# B4H_PROFILE=1 bash : print how long each start-up step takes.
_b4h_t=${EPOCHREALTIME//[.,]/}
_b4h_mark() {
  [[ -n ${B4H_PROFILE-} ]] || return 0
  local now=${EPOCHREALTIME//[.,]/}
  printf "b4h profile: %-12s %4d ms\n" "$1" $(( (now - _b4h_t) / 1000 )) >&2
  _b4h_t=$now
}

. "$B4H_ROOT/lib/settings.bash"
. "$B4H_ROOT/lib/locale.bash"      # UTF-8 when the locale is not (before tmux and ble.sh)
. "$B4H_ROOT/lib/deps.bash"
_b4h_deps_at_start=1 _b4h_deps_ensure    # (downloads, but no cargo build at start)
_b4h_mark deps

# ------------------------------------------------------------------- tmux ---
if [[ $B4H_START_TMUX == yes && -z ${TMUX-} && $TERM != dumb ]] && command -v tmux >/dev/null; then
  exec tmux new-session -A -s main
fi

# --------------------------------------------------------------- greeting ---
[[ -n $B4H_GREETING ]] && eval "$B4H_GREETING"
_b4h_mark greeting

# --------------------------------------------------------- instant prompt ---
# Powerlevel10k's instant prompt: the last prompt seen in this directory
# appears now, while the rest loads; what loading prints is kept and shown
# afterwards (POWERLEVEL9K_INSTANT_PROMPT=verbose|quiet|off in the config).
# (shown below, once the terminal's size is settled). Kept in $B4H_HOME, like
# everything of bash4humans (`b4h ssh` leaves nothing elsewhere on a host).
_p9k_instant_dir=$B4H_HOME/instant-prompt
. "$B4H_ROOT/lib/p10k/instant-show.bash"

# ------------------------------------------------------------ line editor ---
# ble.sh replaces readline. It attaches just before the first prompt, so
# everything later in ~/.bashrc still runs first.
# A terminal that reports no size (serial consoles, some web consoles, ssh -tt
# without a terminal) stops ble.sh from attaching under bash 5.2: give it one.
if [[ $B4H_LINE_EDITOR == ble && $(stty size 2>/dev/null) == "0 0" ]]; then
  stty cols 80 rows 24 2>/dev/null
fi
_p9k_instant_prompt_show
_b4h_mark instant
_b4h_ble=0
if [[ $B4H_LINE_EDITOR == ble && $TERM != dumb && -r $B4H_HOME/deps/ble.sh/ble.sh ]]; then
  # ble.sh keeps a cache and state under XDG_CACHE_HOME / XDG_STATE_HOME,
  # read once while it loads. Point both into $B4H_HOME for that one
  # command, so everything of bash4humans lives in one directory (and
  # `b4h ssh` leaves nothing elsewhere on the host).
  mkdir -p -- "$B4H_HOME/ble-cache" "$B4H_HOME/ble-state"
  # ble.sh takes its terminal from the standard streams as it loads: give
  # it the real ones, not the instant prompt's capture
  _p9k_instant_prompt_pause
  XDG_CACHE_HOME=$B4H_HOME/ble-cache XDG_STATE_HOME=$B4H_HOME/ble-state \
    . "$B4H_HOME/deps/ble.sh/ble.sh" --attach=prompt && [[ -n ${BLE_VERSION-} ]] && _b4h_ble=1
  _p9k_instant_prompt_resume
fi
_b4h_mark ble.sh

# ---------------------------------------------------------------- modules ---
. "$B4H_ROOT/lib/options.bash"      # environment, shell options, history
_b4h_mark options
. "$B4H_ROOT/lib/completion.bash"   # bash-completion, fzf, completion behaviour
_b4h_mark completion
. "$B4H_ROOT/lib/prompt.bash"       # the prompt (Powerlevel10k for bash, lib/p10k), terminal integration
_b4h_prompt_apply
_b4h_mark prompt
. "$B4H_ROOT/lib/dirs.bash"         # directory history: back / forward / up / down, Alt+R, cdh
_b4h_mark dirs
. "$B4H_ROOT/lib/fish.bash"         # abbr, funced/funcsave, add_path, histdel, sudo toggle, help key
_b4h_mark fish
. "$B4H_ROOT/lib/cnf.bash"          # unknown commands: suffix aliases, did-you-mean, packages; zmv
_b4h_mark cnf
. "$B4H_ROOT/lib/clipboard.bash"    # x, c, v: cut, copy, paste
_b4h_mark clipboard
. "$B4H_ROOT/lib/keys.bash"         # key bindings
_b4h_mark keys
. "$B4H_ROOT/lib/cmd.bash"          # the `b4h` command
. "$B4H_ROOT/lib/plugins.bash"      # B4H_PLUGINS, b4h plugins
_b4h_plugins_load
_b4h_mark plugins
_b4h_mark cmd

# Functions saved with funcsave.
for _b4h_f in "${XDG_CONFIG_HOME:-$HOME/.config}"/bash4humans/functions/*.bash; do
  [[ -r $_b4h_f ]] && . "$_b4h_f"
done
unset _b4h_f

# The instant prompt ends here: the terminal is the shell's again, and what
# start-up printed appears (the rest of ~/.bashrc runs normally).
_p9k_clear_instant_prompt
_b4h_cfg_first_run      # an existing ~/.p10k.zsh? (else p10k's wizard comes with the first prompt)
_b4h_auto_update_check
