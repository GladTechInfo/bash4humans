#!/usr/bin/env bash
# Makes the README's pictures from the real bash4humans in a throwaway demo HOME.
#
#   docs/demo/shots.sh [NAME...]        NAME: a file in docs/demo/shots/ without .json (default: all)
#
# For each shot: setup.sh builds the demo HOME in the shot's style, the shot's "prep" commands
# run in ~/projects/webapp, tui-capture types the shot's keys into `bash -i` (started with
# `env -i` and only the variables in env.json), and term-render draws the screens: a PNG for a
# shot with a "snap" step, a GIF for one with "record". Images go to docs/images/; the raw
# captures stay in $B4H_SHOTS (default /tmp/b4h-shots).
#
# Before anything is written to docs/images/, the text of every captured screen - every frame
# of every GIF - is searched for this machine's user and host names, home paths and private
# addresses; any match stops the script.
#
# Needs: jq, cargo (builds tools/tui-capture and tools/term-render), curl (docs/demo/fonts.sh).
set -euo pipefail

HERE=$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)
REPO=$(cd "$HERE/../.." && pwd)
OUT=${B4H_SHOTS:-/tmp/b4h-shots}
IMAGES=$REPO/docs/images
DEMO=/tmp/b4h-demo
mkdir -p "$OUT" "$IMAGES"

# ---- tools ----------------------------------------------------------------
for t in tui-capture term-render; do
  [[ -x $REPO/tools/$t/target/release/$t ]] || (cd "$REPO/tools/$t" && cargo build --release -q)
done
CAPTURE=$REPO/tools/tui-capture/target/release/tui-capture
RENDER=$REPO/tools/term-render/target/release/term-render
FONTS=$("$HERE/fonts.sh")

# `env -i` plus env.json: the shell sees nothing of this machine's environment.
CMD=$(jq -c '["env", "-i"] + (to_entries | map("\(.key)=\(.value)")) + ["bash", "-i"]' "$HERE/env.json")

# What must never appear in a picture (worked out here, so no name is written in the repository).
FORBIDDEN="$(id -un)|$(hostname -s)|$(hostname)|/home/|/root|192\.168\.|10\.[0-9]+\.[0-9]+\.[0-9]+|172\.(1[6-9]|2[0-9]|3[01])\."

# ---- one shot -------------------------------------------------------------
# shoot NAME STYLE: capture docs/demo/shots/NAME.json in STYLE into $OUT/OUTNAME.
shoot() {
  local spec=$HERE/shots/$1.json style=$2 outname=$3
  local dir=$OUT/$outname
  rm -rf "$dir"; mkdir -p "$dir"

  "$HERE/setup.sh" "$style" >/dev/null
  local conf=$DEMO/home/.config/bash4humans/p10k.bash line name
  while IFS= read -r line; do
    [[ -n $line ]] || continue
    name=${line#typeset -g }; name=${name%%=*}
    grep -q "typeset -g $name=" "$conf" || { echo "$1: $name is not in the configuration" >&2; exit 1; }
    sed -i "s|typeset -g $name=.*|$line|" "$conf"
  done < <(jq -r '.settings[]?' "$spec")
  local W=$DEMO/home/projects/webapp
  while IFS= read -r line; do
    [[ -n $line ]] && (cd "$W" && GIT_CONFIG_GLOBAL=/dev/null GIT_CONFIG_NOSYSTEM=1 bash -c "$line")
  done < <(jq -r '.prep[]?' "$spec")

  # The wizard step becomes one key per question (the keys come from the tests' helper).
  local wkeys='' wizard
  wizard=$(jq -r '[.steps[] | .wizard? // empty | .[]] | join(" ")' "$spec")
  if [[ -n $wizard ]]; then
    # shellcheck disable=SC1091
    wkeys=$(source "$REPO/tests/p10k/wizard-keys.sh"; read -ra args <<<"$wizard"; wizard_keys "${args[@]}"; printf '%s' "$REPLY")
  fi
  jq --argjson cmd "$CMD" --arg wkeys "$wkeys" '
    {cmd: $cmd, rows, cols,
     steps: [.steps[] | if has("wizard")
                         then .every as $e | ($wkeys | split("")[] | {keys: ., after: $e})
                         else . end]}' "$spec" > "$dir/spec.json"

  local cwd
  cwd=$DEMO/home/$(jq -r '.cwd // "."' "$spec")
  # A first start in a new HOME builds ble.sh's caches (slow, and it says so on the screen):
  # one start with nothing typed first, so the shot shows a shell as it is every other day.
  jq -n --argjson cmd "$CMD" --slurpfile s "$dir/spec.json" \
    '{cmd: $cmd, rows: $s[0].rows, cols: $s[0].cols, steps: [{wait: 12}]}' > "$dir/warmup.json"
  (cd "$cwd" && "$CAPTURE" "$dir/warmup.json" "$dir/warmup" 2>/dev/null)
  rm -rf "$dir/warmup" "$dir/warmup.json"

  (cd "$cwd" && "$CAPTURE" "$dir/spec.json" "$dir" 2>/dev/null)

  # Every screen's text, searched before any image is made.
  local text
  text=$(if [[ -d $dir/frames ]]; then "$RENDER" text "$dir/frames"; fi
         for f in "$dir"/*.json; do [[ $f == */spec.json ]] || "$RENDER" text "$f"; done)
  printf '%s\n' "$text" > "$dir/text.txt"
  if grep -En "$FORBIDDEN" "$dir/text.txt" >&2; then
    echo "$outname: the lines above must not appear in a picture; nothing written" >&2
    exit 1
  fi

  if [[ -d $dir/frames ]]; then
    "$RENDER" gif "$dir/frames" "$IMAGES/$outname.gif" --fonts "$FONTS" --scale 2 ${GIF_OPTS:-}
  fi
  if [[ -f $dir/screen.json ]]; then
    "$RENDER" png "$dir/screen.json" "$IMAGES/$outname.png" --fonts "$FONTS" --scale 2 --cursor none ${PNG_OPTS:-}
  fi
}

# ---- all shots ------------------------------------------------------------
names=("$@")
if (( ! ${#names[@]} )); then
  for f in "$HERE"/shots/*.json; do names+=("$(basename "$f" .json)"); done
fi
for n in "${names[@]}"; do
  [[ -f $HERE/shots/$n.json ]] || { echo "no shot $n" >&2; exit 1; }
  style=$(jq -r .style "$HERE/shots/$n.json")
  if [[ $style == each ]]; then
    for s in lean classic rainbow pure; do echo "== $n-$s"; shoot "$n" "$s" "$n-$s"; done
  else
    echo "== $n"; shoot "$n" "$style" "$n"
  fi
done
