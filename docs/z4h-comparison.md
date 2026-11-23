# zsh4humans and bash4humans: what each has

Compared 2026-11-22. zsh4humans: `romkatv/zsh4humans` branch `v5` (c0c29f9, 2026-05-01),
read in `~/src/zsh4humans` (main.zsh, fn/*, .zshrc, README.md, tips.md). bash4humans: this
repository, as integrated on 2026-11-22.

Status: **same** = equivalent behaviour; **partial** = present but less; **missing** = not in
b4h; **n/a** = specific to zsh/macOS/iTerm2, nothing to port; **b4h+** = b4h has more.

## 1. Components (what z4h installs by default)

| z4h | b4h | Status |
|---|---|---|
| zsh-autosuggestions | ble.sh suggestions (Right/Ctrl+F accept; `B4H_SUGGEST_ACCEPT` = z4h's `forward-char`) | same |
| zsh-syntax-highlighting | ble.sh highlighting | same |
| zsh-history-substring-search | ble.sh / readline `history-substring-search` on Up/Down | same |
| zsh-completions | bash-completion (system copy or pinned) | same in kind |
| fzf | fzf (system or pinned) | same |
| powerlevel10k | `lib/p10k` (port, checked against p10k) | same |
| systemd completions | come with systemd's bash completion | same |
| terminfo (ships terminfo entries, also to SSH hosts) | — | missing |
| tmux ("integrated tmux": screen contents for prompt-at-bottom, clear screen) | `B4H_START_TMUX` starts plain tmux only | partial |
| generated completions: bw, cargo, gh, helm, kitty, kubectl, oc, rustup | only what bash-completion / the tools provide | partial |

## 2. Plugins

| z4h | b4h | Status |
|---|---|---|
| `z4h install user/repo` (any GitHub repo, kept up to date) | `b4h install USER/REPO[@REF]`, `b4h load`, `b4h source`, `b4h uninstall`; `b4h update` updates them (`lib/repos.bash`) | same |
| `z4h load` / `z4h source` (Oh My Zsh plugins, any file) | `B4H_PLUGINS=()`, own `~/.config/bash4humans/plugins/*.plugin.bash` | partial |
| compatibility fixes for Oh My Zsh, forgit, fz, zsh-you-should-use | — | n/a (zsh plugins) |
| — | bundled: extract, colored-man-pages, zoxide, ssh-agent, git-aliases, cht; `b4h plugins list/search/enable/disable` | b4h+ |

## 3. Installation and maintenance

| z4h | b4h | Status |
|---|---|---|
| installer: keymap, tmux, rc backup, chsh; needs no git, zsh or sudo | `install.sh`: keymap, line editor, tmux, direnv, rc backup, chsh; needs git (or `B4H_SOURCE`) | partial (git) |
| vi keymap: installer refuses (manual `bindkey -v`) | `B4H_KEYMAP=vi` supported | b4h+ |
| auto-update ask / days; `z4h update` | `B4H_AUTO_UPDATE`, `B4H_AUTO_UPDATE_DAYS`; `b4h update` | same |
| `z4h compile`, orphan .zwc check | — | n/a (zsh) |
| try in Docker (one command) | — | missing (minor) |
| welcome message | — | missing (minor) |
| — | `b4h doctor`, `b4h version` | b4h+ |

## 4. Key bindings (z4h defaults, PC keyboard)

| Key | z4h | b4h | Status |
|---|---|---|---|
| Up/Down, Ctrl+P/N | history containing what is typed (this session first: "local") | substring search; local as z4h (other shells' new entries passed over: `B4H_HISTORY_LOCAL`, ble.sh); Enter runs the line found | same (ble.sh); readline: one list |
| Ctrl+Up/Down | global prefix history (all sessions) | prefix search (shared history) | same |
| Home/End, Ctrl+Home/End, Alt+Home/End | line / buffer start-end | ble.sh defaults | same |
| Ctrl+Left/Right, Alt+B/F | word left/right | same | same |
| Ctrl+Shift+Left/Right, Ctrl+Shift+Del | shell-word (zword) move/delete | same (ble.sh sword, readline shell-word) | same |
| Alt+D, Ctrl+Del, Alt+Del | delete word right | Ctrl+Del; Alt+D readline/ble default | same |
| Ctrl+W, Alt+BS, Ctrl+Alt+BS, Ctrl+BS, Ctrl+H | delete word left (Ctrl+Alt+BS: shell word) | same set | same |
| Alt+K | delete to line start | — (Ctrl+U does it) | partial |
| Alt+J | clear the whole buffer | same | same |
| Alt+O | stash the line into history, clear it (z4h-stash-buffer) | same | same |
| Alt+M | accept the whole suggestion | same (ble.sh) | same |
| Ctrl+/ , Shift+Tab / Alt+/ | undo / redo | same | same |
| Ctrl+Space | expand aliases, globs, parameters in place | alias, `~`, `$NAME`/`${NAME}`, glob; `$(...)` and other expansions are left alone (they would run code) | partial (on purpose) |
| Tab | fzf completion (Ctrl+Space multi-select, Ctrl+A all, `recurse-dirs`, `fzf-bindings`) | ble.sh menu; `B4H_TAB=fzf`: fzf with Ctrl+Space / Ctrl+A multi-select, Tab / Shift+Tab, Alt+J; no `recurse-dirs` (off in z4h's own template) | partial |
| Ctrl+R | fzf history (optional preview) | fzf history | same |
| Alt+H | run-help | manual page | same |
| Alt+Left/Right/Up/Down (Shift+ on macOS) | cd back / forward / up / pick subdirectory | same | same |
| Alt+R | fzf over persistent directory history | same (also `cdh`) | same |
| Ctrl+L / Ctrl+Alt+L | soft clear (scrollback kept) / hard clear, prompt at top or bottom | same: soft / hard clear, prompt at top or (`B4H_PROMPT_AT_BOTTOM=yes`) bottom; no tmux needed | same |
| macOS keyboard layout (`keyboard mac`) | — | n/a here |
| — | Alt+S toggle sudo, Ctrl+T files, Alt+C cd (fzf) | b4h+ |

## 5. Directories

| z4h | b4h | Status |
|---|---|---|
| persistent directory history (survives the shell; `cd -<Tab>`; `dir-history` max-size) | same: `$B4H_HOME/dir-history`, `B4H_DIR_HISTORY_SIZE`, `cd -<Tab>` (ble.sh menu, readline fzf); plus per-session back/forward stacks | same |
| auto_cd | `autocd` | same |
| `propagate-cwd` (new tmux pane / tab opens in the same directory) | OSC 7 (terminals); nothing for tmux | partial |
| OSC 9;9 for Windows Terminal (WSL) | — | missing |

## 6. History

| z4h | b4h | Status |
|---|---|---|
| unlimited, shared between shells | same (`HISTSIZE=-1`, history_share) | same |
| local (session) vs global history widgets | Up/Down local, Ctrl+Up/Down global (ble.sh; `lib/keys.bash`) | same (ble.sh) |
| `preserve-trailing-whitespace` | — | missing (minor) |
| — | timestamps, `histdel`, `b4h private` (no history) | b4h+ |

## 7. SSH ("teleportation")

| z4h | b4h | Status |
|---|---|---|
| automatic on plain `ssh HOST`, per host (`:z4h:ssh:HOST enable`) | `B4H_SSH_HOSTS` patterns; `b4h ssh HOST` for any host | same |
| works without zsh on the host (it brings zsh) | needs bash 5 on the host | partial |
| `send-extra-files` | `B4H_SSH_SEND_FILES` (+ rc file, prompt config) | same |
| `retrieve-history` / `retrieve-extra-files` (history back from the host, shared between hosts) | the session's history in the host's `~/.cache/bash4humans-ssh.history`; `B4H_SSH_RETRIEVE_HISTORY=FILE` appends each session's lines here; no extra files | partial |
| `configure` hook, `ssh-command`, `term` per host | — | missing |
| terminfo sent along | when the host lacks `$TERM`: compiled there into `~/.cache/bash4humans-ssh.terminfo` (TERMINFO), else TERM=xterm-256color | same |

## 8. Terminal integration and environment

| z4h | b4h | Status |
|---|---|---|
| `term-shell-integration` (OSC 133) | same (p10k's TERM_SHELL_INTEGRATION, on) | same |
| OSC 7 current directory | same | same |
| title: configurable, while idle and while a command runs (local / ssh) | same: `B4H_TITLE_IDLE`, `B4H_TITLE_RUNNING` (bash prompt escapes, `$B4H_COMMAND`), z4h's defaults | same |
| `prompt-at-bottom` | `B4H_PROMPT_AT_BOTTOM=yes`: at start (ESC[6n asks the terminal where the cursor is) and after Ctrl+L | same |
| `term-vresize` (redraw on vertical resize) | — | missing |
| clipboard: `x`, `c`, `v` | only planned (fn/notes.md), not in v5 | `x`, `c`, `v`: desktop tools, OSC 52 over SSH | b4h+ |
| `-z4h-fix-locale` (pick a UTF-8 locale when none is set) | `lib/locale.bash`: same order (C.UTF-8, en_US.UTF-8, first UTF-8); `B4H_FIX_LOCALE=no` off; `b4h doctor` says when it acted | same |
| WSL: `$z4h_win_home`, `~w` | — | missing (no named dirs in bash; a variable is possible) |
| macOS: Homebrew paths, iTerm2 integration | — | n/a here |
| LS_COLORS, LESS, TREE_COLORS | LS_COLORS (dircolors), LESS, PAGER | partial (TREE_COLORS) |
| GPG_TTY | same | same |
| ssh-agent (`:z4h:ssh-agent: start`) | `ssh-agent` plugin | same |
| direnv (+ `notify` on/off) | `B4H_DIRENV` | partial (no notify option) |
| command-not-found handler | same, plus "did you mean" and the package | b4h+ |
| `z4h sudo` (root shell with your config and TERM), `z4h docker`, `z4h tty-wait` | `sudo -Es` works by hand | missing |
| `zmv` | `zmv` (b4h-tool) | same |
| — | fish: `abbr`, `funced`/`funcsave`, `add_path`, `histdel`; zsh: `alias_suffix`; notification after long commands | b4h+ |

## 9. Gaps, roughly by value

Closed on 2026-11-22: persistent directory history with Alt+R and `cd -<Tab>`;
Alt+M, Alt+O, Alt+J, Ctrl+Space, Ctrl+Shift+Left/Right/Del, Ctrl+Up/Down; the
title while a command runs; `x` / `c` / `v` (checked by `tests/features.sh`).
What remains:

1. ~~Local vs global history~~ Done 2026-11-23 (ble.sh: Up/Down local, Ctrl+Up/Down global). Was: (Up/Down this session's commands first; needs a
   per-session list in bash).
2. ~~Locale fix-up (UTF-8 when none is set).~~ Done 2026-11-23 (`lib/locale.bash`).
3. ~~SSH: automatic per-host teleportation, history retrieval, terminfo.~~ Done 2026-11-23 (`B4H_SSH_HOSTS`, `B4H_SSH_RETRIEVE_HISTORY`, terminfo); still missing: retrieve-extra-files, a configure hook, `term` per host.
4. ~~Tab: fzf completion with multi-select~~ Done 2026-11-23 (`B4H_TAB=fzf`, `lib/completion.bash`); `recurse-dirs` left out.
5. ~~Plugins from any GitHub repository (`b4h install user/repo`).~~ Done 2026-11-23 (`lib/repos.bash`).
6. ~~prompt-at-bottom and soft/hard clear~~ Done 2026-11-23 (`lib/keys.bash`, `b4h.bash`; no tmux needed).
