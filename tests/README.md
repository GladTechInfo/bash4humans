# Tests

bash4humans itself needs bash only. The tests need more, because most of them
compare bash4humans with the real thing in zsh, or type into a real terminal.

| Test | What it checks | Needs |
|---|---|---|
| `unit-deps.sh` | the checksum check of the downloaded b4h-tool (pinned, `SHA256SUMS`, mismatch) | bash, sha256sum |
| `drive.sh RCFILE KEYS...` | helper: types KEYS into an interactive bash in a pseudo-terminal (used by CI) | `script` (util-linux) |
| `features.sh [FILTER]` | the zsh4humans keys and commands (Alt+R, Alt+O, Alt+J, Alt+M, Ctrl+Space, Ctrl+Shift+arrows, Ctrl+Up/Down, `cd -`+TAB, the window title, `x`/`c`/`v`), under ble.sh and under readline | tui-capture, jq, `script`, fzf and ble.sh in `~/.cache/bash4humans/deps` (an installed bash4humans) |
| `remote-install.sh HOST`, `remote-session.sh HOST` | install and use over SSH on a test machine (the source copied to `HOST:/tmp/bash4humans` first) | ssh |
| `p10k/all.sh` | the prompt against real Powerlevel10k, 14 suites (about 45 minutes) | zsh, Powerlevel10k, tui-capture, jq, git, b4h-tool |
| `p10k/wizard.sh` | `p10k configure` against p10k's own wizard, every screen and the written config (about an hour) | the same |

`cd tools/b4h-tool && cargo test` tests the Rust helper.

## What the comparisons need

- **zsh** (5.8 or later) and **Powerlevel10k v1.21.0** checked out at
  `~/src/powerlevel10k`:
  `git clone -b v1.21.0 --depth 1 https://github.com/romkatv/powerlevel10k ~/src/powerlevel10k`.
- **tui-capture** ([`tools/tui-capture`](../tools/tui-capture)): runs a
  program in a pseudo-terminal of a fixed size, sends keys on a schedule and
  saves the screen as JSON (cells with colours and attributes); the screens of
  both shells are compared cell by cell. `cargo install --path tools/tui-capture`
  puts it on `PATH`.
- **jq**, **git**, `script` (util-linux), and **b4h-tool** on `PATH` or in
  `~/.cache/bash4humans/deps/bin`.

Results and screens go to `$B4H_TEST_DIR` (default `/tmp/b4h-test`).

## Rules learnt the hard way

- Never edit a file under test, or a running test script, while a suite runs:
  bash reads scripts as it goes. To keep working meanwhile, copy the
  repository and run the copy (`B4H_TEST_DIR=/tmp/snap copy/tests/p10k/all.sh`;
  the scripts find the library relative to themselves).
- tui-capture passes its own environment on: give every variable that changes
  behaviour (`TERM`, `LANG`, `COLORTERM`, ...) explicitly in the spec.
- `wizard.sh` S2 (a 14×47 terminal) sometimes catches the bash wizard one
  screen late; run it again before suspecting a change.

## CI

`.github/workflows/ci.yml` runs everything that needs no zsh: `bash -n`,
shellcheck (`.shellcheckrc`; `lib/p10k` at error level), `cargo test`, the
static builds for amd64 and arm64, `unit-deps.sh`, an unattended install that
is then used as an interactive shell (`drive.sh`), and `features.sh` on it.
