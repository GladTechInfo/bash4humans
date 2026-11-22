#!/usr/bin/env bash
# =============================================================================
#  tools/third-party-licenses.sh - the licences of the Rust crates built into
#  the static b4h-tool binary, for the release (THIRD-PARTY-LICENSES.txt).
#  Each crate is used under its MIT option; its MIT licence text (with its
#  copyright line) is copied from cargo's source of that crate.
#
#    tools/third-party-licenses.sh >THIRD-PARTY-LICENSES.txt
#
#  Needs cargo and jq; run after a build (the sources are then downloaded).
#  Fails if a crate has no MIT option or no MIT licence file.
# =============================================================================
set -euo pipefail
cd "$(dirname "$0")/b4h-tool"

printf 'b4h-tool is licensed under the GNU GPL, version 3 or later (see LICENSE in\n'
printf 'the bash4humans repository).\n'
printf 'It contains the following crates, each used under the MIT licence.\n'

# name, version, licence expression, directory of each dependency
cargo metadata --format-version 1 --locked |
  jq -r '.packages[] | select(.name != "b4h-tool")
         | [.name, .version, .license, (.manifest_path | sub("/Cargo.toml$"; ""))] | @tsv' |
  sort |
  while IFS=$'\t' read -r name version licence dir; do
    [[ $licence == *MIT* ]] || { echo "third-party-licenses: $name ($licence) has no MIT option" >&2; exit 1; }
    file=''
    for f in LICENSE-MIT LICENSE-MIT.md LICENSE.MIT COPYING LICENSE; do
      [[ -r $dir/$f ]] && grep -q 'Permission is hereby granted' "$dir/$f" && { file=$dir/$f; break; }
    done
    [[ -n $file ]] || { echo "third-party-licenses: no MIT licence text found for $name in $dir" >&2; exit 1; }
    printf '\n%s\n%s %s (%s)\n%s\n\n' '==============================================================================' \
      "$name" "$version" "$licence" '=============================================================================='
    cat -- "$file"
  done
