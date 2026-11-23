# tui-capture

The screen-capture tool of bash4humans' tests. It runs a program in a
pseudo-terminal of a fixed size, types keys on a schedule, and saves the
screen at named moments as JSON: every cell with its character, colours,
bold and reverse. `tests/p10k/` runs bash4humans and real Powerlevel10k in
zsh through it and compares the two screens cell by cell;
`tests/features.sh` checks bash4humans' own keys the same way.

    cargo install --path tools/tui-capture     # puts tui-capture on PATH
    tui-capture SPEC.json OUTDIR

    SPEC: {"cmd": ["bash", "-i"], "rows": 24, "cols": 80, "env": {"TERM": "xterm-256color"},
           "steps": [{"wait": 3}, {"keys": "ls\r"}, {"snap": "screen"}, ...]}

`"answer_cpr": true` makes it answer the cursor-position query `ESC[6n` as a
terminal does (off by default).

Steps: `wait` reads the program's output for N seconds; `keys` types text
or one named key (`<up> <down> <left> <right> <home> <end> <enter> <tab> <bs>
<esc> <del>`, with modifiers `<S-up>`, `<A-left>`, `<C-right>`, `<S-tab>`, or
one character `<C-r>`, `<A-r>`), then reads for `after` seconds (0.4); `type`
types text one character every `delay` seconds (0.12); `sh` starts a shell
command in the background; `snap` saves `OUTDIR/<name>.json`; `record: DIR`
saves a frame every `interval` seconds (0.1) as `OUTDIR/DIR/00001.json` ...
(each with `t`, the seconds since recording began) until `{"stop": true}`.
At the end `q` is sent and the program is stopped after a second.

The JSON is pyte's format (`{"grid": [[[char, fg, bg, bold, reverse, italic,
underline], ...], ...], "cursor": [row, col], "cursor_visible": true}`): pyte's
five fields first, then two more. Colours are `default`, the 16 basic colours by
pyte's names (`brown` for yellow, `brightblack`, ...), others six hex digits.
`tools/term-render` turns snaps and recordings into PNG and GIF images.

The program inherits tui-capture's environment: give every variable that
changes its behaviour (`TERM`, `LANG`, `COLORTERM`, ...) in `env`.

Crates: portable-pty (the pseudo-terminal, from WezTerm), vt100 (the terminal
emulator), serde_json. The source has learner notes for each new idea.

Licence: GPL-3.0-or-later, as bash4humans.
