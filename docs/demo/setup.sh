#!/usr/bin/env bash
# Builds the demo environment the README images are captured in.
#
#   docs/demo/setup.sh [STYLE]      STYLE: lean | classic | rainbow | pure (default rainbow)
#
# Everything lives under $B4H_DEMO (default /tmp/b4h-demo): a throwaway HOME with
# bash4humans (this checkout), a chosen history, and ~/projects/webapp - a git
# repository whose remote is github.com/example/webapp. Nothing from the machine
# running it (user, host, paths, history) is meant to reach a frame; run.sh starts
# the shell with `env -i` and only the variables listed there.
set -euo pipefail

STYLE=${1:-rainbow}
REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
D=${B4H_DEMO:-/tmp/b4h-demo}
H=$D/home

# ---- a fresh HOME --------------------------------------------------------
[[ $D == /tmp/* ]] || { echo "B4H_DEMO must be under /tmp" >&2; exit 1; }
rm -rf -- "$D"
mkdir -p "$H/.cache/bash4humans" "$H/.config/bash4humans" "$H/projects"

# bash4humans itself: this checkout; components copied from the local install
# (so nothing is downloaded), or fetched on the first start if there is none.
ln -s "$REPO" "$H/.cache/bash4humans/b4h"
SRC_DEPS=${B4H_DEMO_DEPS:-$HOME/.cache/bash4humans/deps}
[[ -d $SRC_DEPS ]] && cp -a "$SRC_DEPS" "$H/.cache/bash4humans/deps"

sed -e 's/^B4H_AUTO_UPDATE=ask /B4H_AUTO_UPDATE=no  /' \
    -e 's/^B4H_SSH_SEND_FILES=.*/B4H_SSH_SEND_FILES=()/' \
    "$REPO/bashrc.template" > "$H/.bashrc"
echo 'B4H_WIZARD=no' | cat - "$H/.bashrc" > "$H/.bashrc.new" && mv "$H/.bashrc.new" "$H/.bashrc"
cp "$REPO/p10k/config/p10k-$STYLE.bash" "$H/.config/bash4humans/p10k.bash"

# ---- history -------------------------------------------------------------
# Newest last: a grey suggestion is the newest entry that starts with what is typed.
# Each entry has its time stamp line (#EPOCH), as bash4humans writes history.
t=1793520000   # 2026-11-01
while IFS= read -r line; do
  printf '#%d\n%s\n' "$t" "$line"
  t=$((t + 3600))
done > "$H/.bash_history" <<'EOF'
ls -la
git status
git log --oneline --graph
docker compose up -d
kubectl get pods -A
make test
git push origin main
git commit -am "Fix the login form"
cargo build --release
git add README.md
git commit -m "Update the README"
EOF

# ---- the demo repository -------------------------------------------------
W=$H/projects/webapp
mkdir -p "$W/src" "$W/docs" "$W/tests"
g() { git -C "$W" -c user.name=Demo -c user.email=demo@example.com \
        -c init.defaultBranch=main -c commit.gpgsign=false "$@"; }
export GIT_AUTHOR_DATE='2026-11-01T10:00:00Z' GIT_COMMITTER_DATE='2026-11-01T10:00:00Z'
export GIT_CONFIG_NOSYSTEM=1 GIT_CONFIG_GLOBAL=/dev/null
g init -q
printf '# webapp\n\nA small demo web application.\n' > "$W/README.md"
printf 'fn main() {\n    println!("Hello");\n}\n' > "$W/src/main.rs"
printf '[package]\nname = "webapp"\nversion = "0.1.0"\nedition = "2021"\n' > "$W/Cargo.toml"
printf 'target/\n' > "$W/.gitignore"
g add -A && g commit -qm "Initial commit"
printf 'pub fn login() {}\n' > "$W/src/login.rs"
g add -A && g commit -qm "Add the login form"
g remote add origin https://github.com/example/webapp.git
# The remote branch is made locally: nothing is fetched or pushed.
g update-ref refs/remotes/origin/main HEAD
g config branch.main.remote origin
g config branch.main.merge refs/heads/main
g config user.name Demo
g config user.email demo@example.com
echo "demo ready: $H ($STYLE)"
