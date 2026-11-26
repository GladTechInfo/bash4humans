#!/bin/bash
# tests/p10k/instant.sh [FILTER] : the instant prompt against p10k's. Both
# shells start with the instant-prompt preamble, load p10k and a template,
# then "load plugins" (sleep 2). A first session runs a few commands (the
# cache is written from the second prompt on); a second session in the
# same directory is captured during the sleep: that screen is the instant
# prompt, compared cell by cell (digits masked: the clock). Afterwards the
# real prompt is compared too.
T=${B4H_TEST_DIR:-/tmp/b4h-test}/instant; mkdir -p "$T"
root=$(cd "${BASH_SOURCE[0]%/*}/../.." && pwd)
# The prompt caches are disposable, but gitstatusd must be available offline.
export GITSTATUS_CACHE_DIR=${GITSTATUS_CACHE_DIR:-${XDG_CACHE_HOME:-$HOME/.cache}/gitstatus}
export GITSTATUS_AUTO_INSTALL=0
if ! "$HOME/src/powerlevel10k/gitstatus/install" -n -- sh -c 'test -x "$1"' sh; then
  echo "SETUP: cannot resolve an executable gitstatusd offline (cache: $GITSTATUS_CACHE_DIR)" >&2
  exit 2
fi
"$root/tests/p10k/make-git-fixtures.sh" "$T/git" >/dev/null

# NAME|TEMPLATE|DIRECTORY|EXTRA SETTINGS (both shells, separated by ;)
cases=(
  "lean-tmp|lean|/tmp|"
  "lean-git|lean|$T/git/dirty|"
  "classic|classic|/usr/share/doc|"
  "rainbow|rainbow|/usr/share/doc|"
  "rainbow-time|rainbow|/tmp|POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS+=(time)"
  "pure|pure|/tmp|"
  "lean8|lean-8colors|/usr/share|"
  "robbyrussell|robbyrussell|/tmp|"
  "lean-sparse-old|lean|/tmp|POWERLEVEL9K_PROMPT_ADD_NEWLINE=true;POWERLEVEL9K_NEW_TTY_MAX_AGE_SECONDS=0"
  "lean-1line|lean|/tmp|POWERLEVEL9K_LEFT_PROMPT_ELEMENTS=(dir prompt_char);POWERLEVEL9K_RIGHT_PROMPT_ELEMENTS=(status context time)"
)

normalise_snapshot() {
  jq -ce '
    if (.cursor | type) != "array" or (.cursor_visible | type) != "boolean" then
      error("capture lacks cursor information")
    else
      {cursor, cursor_visible, grid: (.grid | map(map(.[0:4] | .[0] |= sub("^[0-9]$"; "#"))))}
    end' "$1"
}
pass=0 fail=0
for c in "${cases[@]}"; do
  IFS='|' read -r id tpl dir extra <<<"$c"
  [[ -n ${1-} && $id != *$1* ]] && continue
  d=$T/$id; rm -rf "$d"; mkdir -p "$d/zdot" "$d/cache"
  zcfg=$HOME/src/powerlevel10k/config/p10k-$tpl.zsh bcfg=$root/p10k/config/p10k-$tpl.bash
  { printf '%s\n' 'if [[ -r "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh" ]]; then' \
      '  source "${XDG_CACHE_HOME:-$HOME/.cache}/p10k-instant-prompt-${(%):-%n}.zsh"' 'fi'
    printf 'source %q\nsource %q\n' "$HOME/src/powerlevel10k/powerlevel10k.zsh-theme" "$zcfg"
    IFS=";" read -ra kvs <<<"$extra"; for kv in "${kvs[@]}"; do printf "%s\n" "$kv"; done
    printf 'sleep 2\n'; } >"$d/zdot/.zshrc"
  { printf '. %q\n_p9k_instant_prompt_show\n' "$root/lib/p10k/instant-show.bash"
    printf '. %q\n. %q\n' "$root/lib/p10k/main.bash" "$bcfg"
    IFS=";" read -ra kvs <<<"$extra"; for kv in "${kvs[@]}"; do printf "%s\n" "$kv"; done
    printf 'p10k_init\nsleep 2\n_p9k_clear_instant_prompt\n'; } >"$d/bashrc"
  bad=''
  for sh in zsh bash; do
    if [[ $sh == zsh ]]; then cmd='["zsh", "-i"]'
    else : >"$d/hist"; cmd='["env", "HISTFILE='$d/hist'", "bash", "--rcfile", "'$d/bashrc'", "-i"]'
    fi
    env='{"TERM": "xterm-256color", "LANG": "en_GB.UTF-8", "COLORTERM": "", "ZDOTDIR": "'$d/zdot'", "XDG_CACHE_HOME": "'$d/cache.$sh'"}'
    mkdir -p "$d/cache.$sh"
    # first session: commands (the cache is written), then the second one
    printf '{"cmd": %s, "rows": 10, "cols": 100, "env": %s, "steps": [{"wait": 4}, {"keys": "true\\r"}, {"wait": 2}, {"keys": "true\\r"}, {"wait": 2}, {"keys": "exit\\r"}, {"wait": 1}]}\n' \
      "$cmd" "$env" >"$d/$sh.1.json"
    printf '{"cmd": %s, "rows": 10, "cols": 100, "env": %s, "steps": [{"wait": 1}, {"snap": "instant"}, {"wait": 3}, {"snap": "real"}, {"keys": "exit\\r"}, {"wait": 1}]}\n' \
      "$cmd" "$env" >"$d/$sh.2.json"
    if ! (cd "$dir" && tui-capture "$d/$sh.1.json" "$d/$sh.1" >"$d/$sh.1.log" 2>&1); then
      bad="$sh warm-up capture failed (see $d/$sh.1.log)"
      break
    fi
    cache="$d/cache.$sh"
    if [[ $sh == zsh ]]; then
      prompt_cache="$cache/p10k-$(id -un)/prompt-${#dir}"
      if [[ ! -s $cache/p10k-instant-prompt-$(id -un).zsh ]]; then
        bad="$sh warm-up produced no instant-prompt preamble"
        break
      fi
    else
      prompt_cache="$cache/p10k-bash-${USER:-$EUID}/prompt-${#dir}"
    fi
    if [[ ! -s $prompt_cache ]]; then
      bad="$sh warm-up produced no prompt cache for $dir"
      break
    fi
    if ! (cd "$dir" && tui-capture "$d/$sh.2.json" "$d/$sh.2" >"$d/$sh.2.log" 2>&1); then
      bad="$sh prompt capture failed (see $d/$sh.2.log)"
      break
    fi
  done
  if [[ -n $bad ]]; then
    (( fail++ ))
    echo "SETUP  $id : $bad"
    continue
  fi
  for s in instant real; do
    if [[ ! -f $d/zsh.2/$s.json || ! -f $d/bash.2/$s.json ]]; then bad+=" $s(missing)"
    elif ! normalise_snapshot "$d/zsh.2/$s.json" >"$d/zsh.2/$s.normalised" ||
         ! normalise_snapshot "$d/bash.2/$s.json" >"$d/bash.2/$s.normalised"; then bad+=" $s(invalid capture)"
    elif ! cmp -s "$d/zsh.2/$s.normalised" "$d/bash.2/$s.normalised"; then bad+=" $s"
    fi
  done
  # an instant prompt at all? (the screen during the sleep is not empty)
  [[ -n $(jq -r '.grid[] | map(.[0]) | join("")' "$d/zsh.2/instant.json" 2>/dev/null | tr -d ' \n') ]] || bad+=" zsh-shows-none"
  if [[ -z $bad ]]; then (( pass++ )); echo "SAME  $id"
  else (( fail++ )); echo "DIFF  $id :$bad"
  fi
done
echo "same: $pass   different: $fail"
(( fail == 0 ))
