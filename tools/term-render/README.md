# term-render

Turns screens captured by `tools/tui-capture` (JSON) into images: a PNG from
one screen, an animated GIF from a recording. It makes the pictures in the
bash4humans README; `docs/demo/shots.sh` runs it.

    cargo build --release
    term-render png  SNAP.json OUT.png  [options]
    term-render gif  FRAMEDIR  OUT.gif  [options]
    term-render text SNAP.json|FRAMEDIR          the text of every screen

Options: `--fonts DIR` (MesloLGS NF, as `docs/demo/fonts.sh` downloads it),
`--fallback FILE`, `--size PX` (14), `--scale N` (1), `--crop R0,C0,R1,C1`,
`--cursor block|bar|none`, `--pad PX` (12), and for GIFs `--hold S` (3, the
last frame), `--max-delay S` (2), `--speed F` (1).

The font is MesloLGS NF, the one Powerlevel10k recommends (Apache-2.0,
downloaded at a pinned commit, checked by SHA-256; not kept in the repository).
Box-drawing characters, block elements, shades and the powerline separators
are drawn as shapes, as terminals draw them, so frames and segments meet
without gaps. Characters no font has are listed at the end, never silently
left out.

A GIF stores one palette when its frames use 256 colours or fewer (glyph edges
are rounded to eighths, so they usually do), and each frame only the rectangle
that changed. Consecutive equal screens become one frame.

Crates: ab_glyph (font outlines to pixels), png, gif, serde_json. The source
has learner notes for each new idea.

Licence: GPL-3.0-or-later, as bash4humans.
