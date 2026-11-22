# =============================================================================
#  lib/deps.bash - download, verify and build the pinned components into
#  $B4H_HOME/deps (see versions.conf). Nothing is installed system-wide.
#
#  Layout:  $B4H_HOME/deps/ble.sh/ble.sh
#           $B4H_HOME/deps/fzf/bin/fzf
#           $B4H_HOME/deps/bash-completion/bash_completion
#           $B4H_HOME/deps/bin/b4h-tool
#  Each directory holds a .b4h-version stamp; a component is fetched again
#  only when its stamp differs from versions.conf.
# =============================================================================

_b4h_say()  { printf '\e[33mbash4humans\e[0m: %s\n' "$*" >&2; }

_b4h_fetch() {   # _b4h_fetch URL OUTFILE
  if command -v curl >/dev/null; then curl -fsSL --retry 2 -o "$2" -- "$1"
  elif command -v wget >/dev/null; then wget -qO "$2" -- "$1"
  else _b4h_say 'need curl or wget'; return 1
  fi
}

_b4h_sha_ok() {   # _b4h_sha_ok FILE SHA256
  local got
  got=$(sha256sum -- "$1" 2>/dev/null) || return 1
  [[ ${got%% *} == "$2" ]] || { _b4h_say "checksum mismatch: ${1##*/}"; return 1; }
}

_b4h_arch() {     # prints amd64 / arm64, or nothing for an unsupported machine
  case $(uname -m) in
    x86_64|amd64)  echo amd64 ;;
    aarch64|arm64) echo arm64 ;;
  esac
}

_b4h_stamp_is() {   # _b4h_stamp_is DIR WANT - builtins only, as it runs at every start
  local v=
  { read -r v <"$1/.b4h-version"; } 2>/dev/null
  [[ $v == "$2" ]]
}
_b4h_stamp_set()  { printf '%s\n' "$2" >"$1/.b4h-version"; }

# ------------------------------------------------------------------ ble.sh ---
_b4h_dep_ble() {
  local dir=$B4H_HOME/deps/ble.sh want=$B4H_BLE_COMMIT
  _b4h_stamp_is "$dir" "$want" && [[ -r $dir/ble.sh ]] && return 0
  local tmp; tmp=$(mktemp -d) || return 1
  if command -v git >/dev/null && command -v make >/dev/null && command -v gawk >/dev/null; then
    _b4h_say "building ble.sh ${want:0:7}"
    if ( cd "$tmp" && git init -q src && cd src &&
         git remote add origin "$B4H_BLE_REPO" &&
         git fetch -q --depth 1 origin "$want" && git checkout -q FETCH_HEAD &&
         git submodule -q update --init --depth 1 &&
         make -s INSDIR="$tmp/out" install >/dev/null 2>&1 ) && [[ -r $tmp/out/ble.sh ]]; then
      rm -rf -- "$dir" && mv -- "$tmp/out" "$dir" && _b4h_stamp_set "$dir" "$want"
      rm -rf -- "$tmp"; return 0
    fi
    _b4h_say 'ble.sh build failed; trying the prebuilt nightly'
  fi
  # Fallback: prebuilt nightly (needs only tar + xz).
  if _b4h_fetch "$B4H_BLE_NIGHTLY" "$tmp/ble.tar.xz" && tar -xJf "$tmp/ble.tar.xz" -C "$tmp"; then
    local src; src=$(echo "$tmp"/ble-*/)
    if [[ -r $src/ble.sh ]]; then
      rm -rf -- "$dir" && mv -- "$src" "$dir" && _b4h_stamp_set "$dir" "nightly"
      rm -rf -- "$tmp"; return 0
    fi
  fi
  rm -rf -- "$tmp"; _b4h_say 'ble.sh unavailable; using plain readline'; return 1
}

# --------------------------------------------------------------------- fzf ---
_b4h_dep_fzf() {
  local dir=$B4H_HOME/deps/fzf want=$B4H_FZF_VERSION arch sha
  _b4h_stamp_is "$dir" "$want" && [[ -x $dir/bin/fzf ]] && return 0
  arch=$(_b4h_arch); [[ -n $arch ]] || return 1
  sha=B4H_FZF_SHA256_$arch
  local tmp; tmp=$(mktemp -d) || return 1
  _b4h_say "fetching fzf $want"
  if _b4h_fetch "https://github.com/junegunn/fzf/releases/download/v$want/fzf-$want-linux_$arch.tar.gz" "$tmp/fzf.tgz" &&
     _b4h_sha_ok "$tmp/fzf.tgz" "${!sha}" && tar -xzf "$tmp/fzf.tgz" -C "$tmp" fzf; then
    rm -rf -- "$dir" && mkdir -p -- "$dir/bin" && mv -- "$tmp/fzf" "$dir/bin/fzf" && _b4h_stamp_set "$dir" "$want"
    rm -rf -- "$tmp"; return 0
  fi
  rm -rf -- "$tmp"; return 1
}

# --------------------------------------------------------- bash-completion ---
_b4h_dep_bashcomp() {
  local dir=$B4H_HOME/deps/bash-completion want=$B4H_BASHCOMP_VERSION
  _b4h_stamp_is "$dir" "$want" && [[ -r $dir/bash_completion ]] && return 0
  local tmp; tmp=$(mktemp -d) || return 1
  _b4h_say "fetching bash-completion $want"
  if _b4h_fetch "https://github.com/scop/bash-completion/releases/download/$want/bash-completion-$want.tar.xz" "$tmp/bc.tar.xz" &&
     _b4h_sha_ok "$tmp/bc.tar.xz" "$B4H_BASHCOMP_SHA256" && tar -xJf "$tmp/bc.tar.xz" -C "$tmp"; then
    rm -rf -- "$dir" && mv -- "$tmp/bash-completion-$want" "$dir" && _b4h_stamp_set "$dir" "$want"
    rm -rf -- "$tmp"; return 0
  fi
  rm -rf -- "$tmp"; return 1
}

# ---------------------------------------------------------------- b4h-tool ---
# Prefer the released static binary; build from tools/b4h-tool with cargo
# when there is no release for this version or machine.
_b4h_dep_tool() {
  local dir=$B4H_HOME/deps/bin want=$B4H_TOOL_VERSION arch src=$B4H_ROOT/tools/b4h-tool
  _b4h_stamp_is "$dir" "$want" && [[ -x $dir/b4h-tool ]] && return 0
  mkdir -p -- "$dir"
  arch=$(_b4h_arch)
  local tmp; tmp=$(mktemp -d) || return 1
  if [[ -n $arch ]] && _b4h_fetch "$B4H_TOOL_URL/b4h-tool-linux-$arch" "$tmp/b4h-tool" 2>/dev/null; then
    chmod +x "$tmp/b4h-tool" && mv -- "$tmp/b4h-tool" "$dir/b4h-tool" && _b4h_stamp_set "$dir" "$want"
    rm -rf -- "$tmp"; return 0
  fi
  rm -rf -- "$tmp"
  if command -v cargo >/dev/null && [[ -r $src/Cargo.toml ]]; then
    _b4h_say 'building b4h-tool with cargo'
    local target=() out=$src/target/release/b4h-tool
    if rustup target list --installed 2>/dev/null | grep -qx "$(uname -m)-unknown-linux-musl"; then
      target=(--target "$(uname -m)-unknown-linux-musl")
      out=$src/target/$(uname -m)-unknown-linux-musl/release/b4h-tool
    fi
    if ( cd "$src" && cargo build -q --release "${target[@]}" ) && [[ -x $out ]]; then
      cp -- "$out" "$dir/b4h-tool" && _b4h_stamp_set "$dir" "$want"; return 0
    fi
  fi
  return 1   # optional: zmv and "did you mean" are simply absent
}

# --------------------------------------------------------------- gitstatus ---
# Source tarball (checksum pinned here), then its own installer downloads
# gitstatusd into deps/gitstatus/bin, checking the checksum it ships with.
_b4h_dep_gitstatus() {
  local dir=$B4H_HOME/deps/gitstatus want=$B4H_GITSTATUS_VERSION
  _b4h_stamp_is "$dir" "$want" && [[ -r $dir/gitstatus.plugin.sh ]] && return 0
  local tmp; tmp=$(mktemp -d) || return 1
  _b4h_say "fetching gitstatus $want"
  if _b4h_fetch "https://github.com/romkatv/gitstatus/archive/refs/tags/v$want.tar.gz" "$tmp/gs.tgz" &&
     _b4h_sha_ok "$tmp/gs.tgz" "$B4H_GITSTATUS_SHA256" && tar -xzf "$tmp/gs.tgz" -C "$tmp" &&
     GITSTATUS_CACHE_DIR=$tmp/gitstatus-$want/bin sh "$tmp/gitstatus-$want/install" -f >/dev/null 2>&1; then
    rm -rf -- "$dir" && mv -- "$tmp/gitstatus-$want" "$dir" && _b4h_stamp_set "$dir" "$want"
    rm -rf -- "$tmp"; return 0
  fi
  rm -rf -- "$tmp"; return 1   # the git segment falls back to `git status`
}

# Fetch whatever is missing or out of date. Failures are not fatal: each
# feature checks for its component and falls back.
_b4h_deps_ensure() {
  . "$B4H_ROOT/versions.conf"
  mkdir -p -- "$B4H_HOME/deps"
  [[ $B4H_LINE_EDITOR == ble ]] && _b4h_dep_ble
  _b4h_dep_fzf
  _b4h_dep_bashcomp
  _b4h_dep_gitstatus
  _b4h_dep_tool
  return 0
}
