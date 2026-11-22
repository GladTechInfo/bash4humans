#!/usr/bin/env bash
# Downloads MesloLGS NF - the font Powerlevel10k recommends - at a pinned commit of
# github.com/romkatv/powerlevel10k-media, and checks every file against its SHA-256.
#
#   docs/demo/fonts.sh [DIR]      (default ~/.cache/bash4humans-demo/fonts)
#
# Prints DIR. The font's licence (Apache-2.0) is downloaded with it.
set -euo pipefail
DIR=${1:-${XDG_CACHE_HOME:-$HOME/.cache}/bash4humans-demo/fonts}
COMMIT=145eb9fbc2f42ee408dacd9b22d8e6e0e553f83d
BASE=https://raw.githubusercontent.com/romkatv/powerlevel10k-media/$COMMIT

# name|sha256
FILES=(
  "MesloLGS NF Regular.ttf|d97946186e97f8d7c0139e8983abf40a1d2d086924f2c5dbf1c29bd8f2c6e57d"
  "MesloLGS NF Bold.ttf|b6c0199cf7c7483c8343ea020658925e6de0aeb318b89908152fcb4d19226003"
  "MesloLGS NF Italic.ttf|6f357bcbe2597704e157a915625928bca38364a89c22a4ac36e7a116dcd392ef"
  "MesloLGS NF Bold Italic.ttf|56b4131adecec052c4b324efb818dd326d586dbc316fc68f98f1cae2eb8d1220"
  "MesloLGS NF License.txt|0eb25f1a4e86320ceae5f650cb75e628117c3f575bc2e332bb13cd08c3be438e"
)

mkdir -p "$DIR"
for entry in "${FILES[@]}"; do
  name=${entry%|*} sum=${entry#*|}
  file=$DIR/$name
  if [[ ! -f $file ]] || ! echo "$sum  $file" | sha256sum -c --status; then
    curl -fsSL -o "$file.part" "$BASE/${name// /%20}"
    echo "$sum  $file.part" | sha256sum -c --status || { echo "checksum mismatch: $name" >&2; rm -f "$file.part"; exit 1; }
    mv "$file.part" "$file"
  fi
done
echo "$DIR"
