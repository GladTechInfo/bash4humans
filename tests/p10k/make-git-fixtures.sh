#!/bin/bash
# tests/p10k/make-git-fixtures.sh DIR : git repositories in known states for golden tests.
set -e
D=${1:?DIR}; rm -rf "$D"; mkdir -p "$D"; cd "$D"
export GIT_AUTHOR_NAME=t GIT_AUTHOR_EMAIL=t@t GIT_COMMITTER_NAME=t GIT_COMMITTER_EMAIL=t@t
export GIT_AUTHOR_DATE='2026-01-01T00:00:00Z' GIT_COMMITTER_DATE='2026-01-01T00:00:00Z'
g() { git -c init.defaultBranch=main -c advice.detachedHead=false "$@" >/dev/null 2>&1; }
mk() { g init -q "$1"; (cd "$1" && echo a >a && g add a && g commit -qm init); }

mk clean
mk dirty;  (cd dirty && echo b >>a && echo s >s && g add s && echo u >u && echo u2 >u2)
g init -q --bare remote.git
mk ahead;  (cd ahead && g remote add origin "$D/remote.git" && g push -q origin main && g branch -u origin/main &&
            echo c >>a && g commit -qam two && echo d >>a && g commit -qam three &&
            git config remote.origin.url https://github.com/someone/project.git)
mk behind; (cd behind && g remote add origin "$D/remote.git" && g fetch -q origin && g reset -q --hard origin/main &&
            g branch -u origin/main && g fetch -q "$D/ahead" +main:refs/remotes/origin/main)
mk stash;  (cd stash && echo x >>a && g stash && echo y >>a && g stash)
mk tag;    (cd tag && g tag v1.2.3 && g checkout -q v1.2.3)
mk detached; (cd detached && echo e >>a && g commit -qam e && g checkout -q HEAD~1)
mk long;   (cd long && g checkout -q -b feature/a-really-long-branch-name-that-goes-on-and-on)
mk wip;    (cd wip && echo w >>a && g commit -qam 'wip: half done')
mk merge;  (cd merge && g checkout -q -b other && echo o >a && g commit -qam o && g checkout -q main &&
            echo m >a && g commit -qam m && g merge other || true)
mk gitlab; (cd gitlab && git config remote.origin.url git@gitlab.com:x/y.git && g remote add up "$D/remote.git" 2>/dev/null; true)
ls "$D"
