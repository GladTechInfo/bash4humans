#!/bin/bash
# tests/unit-deps.sh - lib/deps.bash: the checksum check of the downloaded
# b4h-tool (pinned in versions.conf, else the release's SHA256SUMS), against
# a fake release served by file:// URLs. Prints ok/FAIL per case.
set -u
ROOT=$(cd "${BASH_SOURCE[0]%/*}/.." && pwd)
R=$(mktemp -d); H=$(mktemp -d)
printf 'binary-v1\n' >"$R/b4h-tool-linux-amd64"
good=$(sha256sum "$R/b4h-tool-linux-amd64" | cut -d' ' -f1)
B4H_ROOT=/nonexistent B4H_HOME=$H
. "$ROOT/lib/deps.bash"
B4H_TOOL_VERSION=t B4H_TOOL_URL=file://$R
_b4h_arch() { echo amd64; }
# shellcheck disable=SC2329  # (called by _b4h_dep_tool)
cargo() { return 1; }       # never build in this test
run() {   # run NAME EXPECT(0/1)
  rm -rf "$H/deps"; mkdir -p "$H/deps"
  _b4h_dep_tool 2>/dev/null; local st=$?
  [[ $st == "$2" ]] && echo "ok    $1" || echo "FAIL  $1 (status $st)"
}
B4H_TOOL_SHA256_amd64=$good;            run 'pinned, matches'        0
B4H_TOOL_SHA256_amd64=${good//[0-9]/0}; run 'pinned, differs'        1
B4H_TOOL_SHA256_amd64=
echo "$good  b4h-tool-linux-amd64" >"$R/SHA256SUMS";       run 'SHA256SUMS, matches' 0
echo "${good//[a-f]/0}  b4h-tool-linux-amd64" >"$R/SHA256SUMS"; run 'SHA256SUMS, differs' 1
echo "$good  b4h-tool-linux-arm64" >"$R/SHA256SUMS";       run 'SHA256SUMS, no line'   1
rm "$R/SHA256SUMS";                                          run 'no pin, no SHA256SUMS' 1
# no release: the installer and b4h update build with cargo, a shell start
# never does (a source tree with a Cargo.toml, a cargo that only records)
mkdir -p "$R/src/tools/b4h-tool"; : >"$R/src/tools/b4h-tool/Cargo.toml"
# (cargo runs in a subshell there: it leaves a file, not a variable)
B4H_ROOT=$R/src
# shellcheck disable=SC2329  # (called by _b4h_dep_tool)
cargo() { : >"$R/built"; return 1; }
_b4h_deps_at_start=1 run 'at start, no release' 1
[[ ! -e $R/built ]] && echo 'ok    at start: cargo not run' || echo 'FAIL  at start: cargo was run'
run 'install / update, no release' 1
[[ -e $R/built ]] && echo 'ok    install / update: cargo run' || echo 'FAIL  install / update: cargo not run'
rm -rf "$R" "$H"
