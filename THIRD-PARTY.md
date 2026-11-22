# Third-party code and components

bash4humans is licensed under the GNU General Public License, version 3 or
(at your option) any later version ([`LICENSE`](LICENSE)). This file lists what
comes from elsewhere: code in this repository derived from other projects
(whose notices are kept here), components the installer downloads, and crates
inside the released `b4h-tool` binaries. All of them are compatible with the
GPL-3.0-or-later.

## In this repository

### Powerlevel10k (MIT)

<https://github.com/romkatv/powerlevel10k>, v1.21.0.

- `lib/p10k/` is a port of Powerlevel10k from zsh to bash: its settings,
  segments, wizard, instant and transient prompt, rewritten in bash.
- `lib/p10k/data.bash` is generated from Powerlevel10k's icon and colour
  tables by `tools/gen/p10k-data.zsh`.
- `p10k/templates/` holds Powerlevel10k's configuration templates unchanged;
  `p10k/config/` holds the same templates converted to bash (comments and
  settings are Powerlevel10k's).

Copyright (c) 2009-2014 Robby Russell and contributors,
Copyright (c) 2014-2017 Ben Hilburn,
Copyright (c) 2019 Roman Perepelitsa and contributors.
Their MIT licence text is in
[`p10k/templates/LICENSE.powerlevel10k`](p10k/templates/LICENSE.powerlevel10k);
its copyright and permission notice apply to all of the above, which is
distributed here as part of bash4humans under the GPL-3.0-or-later.

### gitstatus (GPL-3.0-or-later)

<https://github.com/romkatv/gitstatus>, Copyright 2019 Roman Perepelitsa.
The gitstatusd client in `lib/p10k/segments-vcs.bash` (`_p9k_gs_query`,
`_p9k_gs_response` and their helpers) is a bash port of gitstatus's
`gitstatus.plugin.zsh`, which is licensed under the GNU GPL, version 3 or any
later version, the licence of bash4humans.

### zsh4humans (MIT)

<https://github.com/romkatv/zsh4humans>, Copyright (c) 2020 Roman Perepelitsa.
bash4humans follows its design, key bindings and defaults; no zsh4humans code
is included.

## Downloaded by the installer (not in this repository)

Fetched at pinned versions into `~/.cache/bash4humans/deps`, each checked
against a SHA-256 or built from a pinned commit (`versions.conf`), and used
unmodified under its own licence:

| Component | Licence | Use |
|---|---|---|
| [ble.sh](https://github.com/akinomyoga/ble.sh) | BSD-3-Clause | the line editor (suggestions, highlighting, menus) |
| [fzf](https://github.com/junegunn/fzf) | MIT | fuzzy finder |
| [bash-completion](https://github.com/scop/bash-completion) | GPL-2.0-or-later | completions for many commands |
| [gitstatus](https://github.com/romkatv/gitstatus) | GPL-3.0-or-later | git status for the prompt (gitstatusd and its bash plugin) |

## Inside the b4h-tool release binaries

The static binaries on the releases page contain these Rust crates, each used
under its MIT option; their licence texts are in `THIRD-PARTY-LICENSES.txt`
next to the binaries (made by `tools/third-party-licenses.sh`):
regex, regex-automata, regex-syntax (MIT OR Apache-2.0), aho-corasick and
memchr (Unlicense OR MIT). Building from source fetches the same crates.
