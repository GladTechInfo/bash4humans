# Powerlevel10k: analysis for the bash port

Source: `romkatv/powerlevel10k` v1.21.0 (commit 50a35cc8, 2026-11-19), read in `~/src/powerlevel10k`.
Purpose: the reference that bash4humans' prompt is built from and checked against.

## 1. How p10k is put together

| Part | File | Lines | Role |
|---|---|---:|---|
| Engine | `internal/p10k.zsh` | 9548 | settings, segments, prompt assembly, instant/transient prompt, `p10k` command |
| Wizard | `internal/wizard.zsh` | 2265 | `p10k configure`: questions with previews, then writes `~/.p10k.zsh` |
| Icons | `internal/icons.zsh` | 1174 | every icon name × font mode (`nerdfont-v3`, `nerdfont-complete`, `awesome-*`, `flat`, `powerline`, `compatible`, `ascii`) |
| Templates | `config/p10k-{lean,lean-8colors,classic,rainbow,pure,robbyrussell}.zsh` | 111-1833 | complete configurations; rainbow alone sets 540 `POWERLEVEL9K_*` values and defines zsh functions (`my_git_formatter`, `prompt_example`) |
| git | `gitstatus/` | | gitstatusd + bindings (bash bindings exist upstream) |

**Key fact:** the wizard never draws a real prompt. It copies one template and edits
`POWERLEVEL9K_*` lines in it (`generate_config`: `sub`, `uncomment`, `rep`). Everything a user
sees is the engine interpreting those settings. A faithful port therefore needs (a) the same
settings with the same names and meanings, (b) the templates, (c) the wizard's edits, (d) an
engine that interprets the settings exactly as `p10k.zsh` does.

## 2. Wizard (`p10k configure`) — complete flow

Order and conditions, as in the main loop (wizard.zsh 2085-2230):

| # | Question | Asked when | Answers → effect |
|---|---|---|---|
| 0 | Install Meslo Nerd Font | only where p10k can install fonts (macOS iTerm2 etc.) | — |
| 1 | Diamond `` | UTF-8, TERM not dumb/linux | `cap_diamond` → powerline separators/heads; else separators empty, subsep `│` |
| 2 | Lock ``, then `` | not awesome-mapped | with 3-4 → `POWERLEVEL9K_MODE` |
| 3 | Upward arrow `\UF0737` / `ﰵ`, digit-width test | lock + diamond | `nerdfont-v3` / `nerdfont-complete` / `awesome-fontconfig` |
| 4 | Python logo, `❯❮` quotes | some awesome / no-lock paths | `awesome-patched`, `flat`, `powerline`, `compatible`, `ascii` |
| 5 | Icon padding ("fit between the crosses") | mode not powerline/compatible/ascii | `ICON_PADDING=none` (small icons) / `moderate` (large; slanted glyphs get a trailing space) |
| 6 | Style: Lean, Classic, Rainbow, Pure (Pure not in ascii) | <256 colours → lean_8colors without asking | lean: frames off; pure: empty line on |
| 7 | Character set: Unicode / ASCII | lean*/classic/rainbow, not ascii mode | ASCII: no separators, subsep `|`, `>` prompt char, no frames, mode ascii |
| 8 | Prompt colours | lean: 256 / 8 colours; pure (truecolor only): Original / Snazzy | |
| 9 | Prompt colour (Lightest/Light/Dark/Darkest) | classic only | bg 240/238/236/234, sep 248/246/244/242, prefix 250/248/246/244, frame 244/242/240/238 |
| 10 | Non-permanent content location: Left / Right | pure only | right: `command_execution_time virtualenv context` move to the right prompt |
| 11 | Show current time: No / 12h / 24h (keys n,1,2) | always | uncomments `time`; 12h sets `TIME_FORMAT='%D{%I:%M:%S %p}'` |
| 12 | Separators: Angled, Vertical, Slanted*, Round* | classic/rainbow with diamond (*nerdfont only) | `LEFT/RIGHT_(SUB)SEGMENT_SEPARATOR` |
| 13 | Heads: Flat, Blurred, Sharp, Slanted, Round | classic/rainbow, not ascii | `LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL`, `RIGHT_PROMPT_FIRST_SEGMENT_START_SYMBOL` |
| 14 | Tails: Flat, Blurred, Sharp, Slanted, Round | classic/rainbow, not ascii | `LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL`, `RIGHT_PROMPT_LAST_SEGMENT_END_SYMBOL` |
| 15 | Height: one / two lines | always | 1 line: removes `newline` and `Line #` lines from the template |
| 16 | Connection: Disconnected / Dotted `·` / Solid `─` | 2 lines, not pure | `MULTILINE_FIRST_PROMPT_GAP_CHAR` |
| 17 | Frame: No / Left / Right / Full | classic/rainbow/lean, 2 lines, not ascii | `MULTILINE_*_PROMPT_PREFIX/SUFFIX` `╭─ ├─ ╰─` / `─╮ ─┤ ─╯`; classic/rainbow without left frame: `STATUS_OK/ERROR=false` and `prompt_char` instead of `vi_mode` |
| 18 | Connection & frame colour (Lightest..Darkest) | rainbow/lean, 2 lines, gap or frame | `RULER_FOREGROUND`, `MULTILINE_FIRST_PROMPT_GAP_FOREGROUND`, frame colour |
| 19 | Spacing: Compact / Sparse | always | `PROMPT_ADD_NEWLINE` |
| 20 | Icons: Few / Many | not pure, not powerline/compatible/ascii | many: `os_icon` on, `VCS_BRANCH_ICON`; few: empties identifiers of vcs, execution time, time; `DIR_CLASSES` |
| 21 | Flow: Concise / Fluent | not pure | fluent: prefixes `on`, `took`, `with`, `at` (kubecontext, time), `in` (toolbox); lean `%f`, classic prefix colour |
| 22 | Transient prompt: Yes / No | always | `TRANSIENT_PROMPT=always` |
| 23 | Instant prompt: Verbose / Quiet / Off | zsh ≥ 5.4, not z4h | `INSTANT_PROMPT` |
| 24 | Overwrite existing config / edit `~/.zshrc` | | backup of the old config |

ASCII mode also substitutes: status identifiers `ok`/`err`, `BATTERY_STAGES=('battery')`, prompt
chars `> < V ^`, `⭐→*`, `…→..`, `⇣→<`, `⇡→>`, `⇠→<-`, `⇢→->`, `─→-`.
The header written to the config records "Wizard options: …" exactly as in `~/.p10k.zsh`.

Previews (`lean_left`, `classic_left`, `rainbow_left`, `pure_left` … in wizard.zsh 50-120) are
fixed sample strings: `~/src`, `master`, `5s`, time `16:23:42` / `04:23:42 PM`, indented 2, at
most 88 columns wide.

## 3. Engine semantics

### 3.1 Settings lookup (`_p9k_param`)
For segment `S` in state `T` and attribute `A`: `POWERLEVEL9K_S_T_A`, then `POWERLEVEL9K_S_A`,
then `POWERLEVEL9K_A`, then the built-in default. 190 named settings exist (`_p9k_declare`), plus
these per-segment attributes: `FOREGROUND`, `BACKGROUND`, `VISUAL_IDENTIFIER_EXPANSION`,
`VISUAL_IDENTIFIER_COLOR`, `CONTENT_EXPANSION`, `PREFIX`, `SUFFIX`, `ICON_BEFORE_CONTENT`,
`SELF_JOINED`, `SHOW_ON_UPGLOB`, `SHOW_ON_COMMAND`, `DISABLED_DIR_PATTERN`, separators,
whitespace (`LEFT_LEFT_WHITESPACE`, `LEFT_RIGHT_WHITESPACE`, `LEFT_MIDDLE_WHITESPACE`, right
equivalents, `WHITESPACE_BETWEEN_*`).

### 3.2 Colours (`_p9k_translate_color`)
Decimal (`255`), hex (`#ffffff`), or names from `__p9k_colors` (with `bg-`/`fg-`/`br` prefixes stripped).
Values in templates also use zsh prompt escapes inside strings: `%F{n}`, `%NF`, `%K{n}`, `%f`, `%k`,
`%B`/`%b`, `%U`/`%u`, `%{…%}`, `%%`, `%n`, `%m`, `%~`, `%D{fmt}` — the port needs an interpreter
for these.

### 3.3 Icons (`_p9k_get_icon`)
`POWERLEVEL9K_<NAME>` overrides the table `icons[<NAME>]` for the current `MODE`;
`ICON_PADDING` affects width handling.

### 3.4 Drawing a left segment (`_p9k_left_prompt_segment`)
A segment is shown only if its icon or its content is non-empty. Style is `%b` + background + foreground.
Opening, by the previous segment on the line:
1. none (first on the line): `LEFT_PROMPT_FIRST_SEGMENT_START_SYMBOL` in fg = this bg on no bg, then style, `LEFT_LEFT_WHITESPACE`;
2. joined (`name_joined` in the list and the previous segment was shown): style only;
3. same background: `LEFT_SUBSEGMENT_SEPARATOR` (fg switched to a contrasting colour if fg == bg), style, left whitespace;
4. different background: `LEFT_SEGMENT_SEPARATOR` with fg = previous bg on this bg, style, left whitespace.

Then: `PREFIX`, icon (`VISUAL_IDENTIFIER_COLOR`, default the fg), `LEFT_MIDDLE_WHITESPACE`
only if both icon and content exist, content, `SUFFIX`, `LEFT_RIGHT_WHITESPACE`.
`ICON_BEFORE_CONTENT=false` swaps icon and content. The line's last segment ends with
`LEFT_PROMPT_LAST_SEGMENT_END_SYMBOL` (default: the separator) in fg = its bg.
Right segments mirror this (`_p9k_right_prompt_segment`).

### 3.5 Lines (`_p9k_set_prompt`, `_p9k_init_lines`)
`newline` in `LEFT/RIGHT_PROMPT_ELEMENTS` splits lines; line *n* of the left list pairs with
line *n* of the right list. Each line: `MULTILINE_{FIRST,NEWLINE,LAST}_PROMPT_PREFIX` + left +
gap + right + `…_SUFFIX`. The gap uses `MULTILINE_{FIRST,NEWLINE}_PROMPT_GAP_CHAR` and
`…_GAP_FOREGROUND`/`BACKGROUND`. The right part of the last line is `RPROMPT`. Also:
`PROMPT_ADD_NEWLINE(_COUNT)`, `SHOW_RULER`/`RULER_CHAR`/`RULER_FOREGROUND`,
`DISABLE_RPROMPT`, `RPROMPT_ON_NEWLINE`, `PROMPT_ON_NEWLINE`.

### 3.6 Directory
Dynamic truncation at display time to the room left (`DIR_MAX_LENGTH`, `DIR_MIN_COMMAND_COLUMNS(_PCT)`),
strategies `truncate_to_unique` (default in templates), `truncate_to_first_and_last`,
`truncate_from_left/right/middle`, `truncate_to_last`, `truncate_with_folder_marker`,
`truncate_with_package_name`; anchors (`DIR_ANCHOR_*`, `SHORTEN_FOLDER_MARKER` files list);
three colours (anchor / regular / shortened); `DIR_CLASSES` (per-path classes with own icon/colour);
states `NOT_WRITABLE`, `NON_EXISTENT`; `DIR_HYPERLINK`.

### 3.7 Other mechanisms
- **Transient prompt** `TRANSIENT_PROMPT=off|always|same-dir`: the accepted line is redrawn as just the prompt character + command.
- **Instant prompt**: prints a cached prompt at the very start of `~/.zshrc`, before plugins load.
- **Show on command** `*_SHOW_ON_COMMAND`: segment appears only while the typed command matches.
- **Show on upglob** `*_SHOW_ON_UPGLOB`: only when a file pattern exists in the directory or a parent.
- **Hot reload**, caches, async workers (`worker.zsh`) for slow segments.
- `p10k` command: `configure`, `reload`, `segment` (custom segment API: `-s -b -f -i -c -t -r -e`), `display` (show/hide parts at run time), `help`, `finalize`.

## 4. Segments (87)

anaconda asdf aws aws_eb_env azure background_jobs battery chezmoi_shell chruby
command_execution_time context cpu_arch date detect_virt dir direnv dir_writable disk_usage
docker_machine dotnet_version dropbox fvm gcloud goenv google_app_cred go_version
haskell_stack history host ip java_version jenv kubecontext laravel_version lf load luaenv
midnight_commander nix_shell nnn nodeenv nodenv node_version nordvpn nvm openfoam os_icon
package per_directory_history perlbrew phpenv php_version plenv prompt_char proxy public_ip
pyenv ram ranger rbenv root_indicator rspec_stats rust_version rvm scalaenv ssh status swap
swift_version symfony2_tests symfony2_version taskwarrior terraform terraform_version time
timewarrior todo toolbox user vcs vi_mode vim_shell virtualenv vpn_ip wifi xplr yazi
(plus `newline`, `custom_*`, and template-defined `example`).

Templates enable by default — left: `os_icon` (many icons), `dir`, `vcs`, `newline`,
`prompt_char` (lean, pure, or classic/rainbow without left frame); right: `status`,
`command_execution_time`, `background_jobs`, `direnv`, `asdf`, `virtualenv`, `anaconda`, `pyenv`,
`goenv`, `nodenv`, `nvm`, `nodeenv`, `rbenv`, `rvm`, `fvm`, `luaenv`, `jenv`, `plenv`, `perlbrew`,
`phpenv`, `scalaenv`, `haskell_stack`, `kubecontext`, `terraform`, `aws`, `aws_eb_env`, `azure`,
`gcloud`, `google_app_cred`, `toolbox`, `context`, `nordvpn`, `ranger`, `yazi`, `nnn`, `lf`, `xplr`,
`vim_shell`, `midnight_commander`, `nix_shell`, `chezmoi_shell`, `todo`, `timewarrior`,
`taskwarrior`, `per_directory_history`, `vi_mode`/`time` per wizard; the rest are commented out.

## 5. What the first b4h prompt got wrong (against this analysis)

- Its own settings (`B4H_P_*`) instead of p10k's; none of the 540 template settings honoured.
- Wizard: an invented "layout" question; missing font modes, icon-padding, Pure's
  right/left question, classic's colour-drives-frame rule, few/many icons semantics,
  instant prompt; colour questions applied to the wrong styles.
- Segment drawing: no separate whitespace/prefix/suffix/identifier-colour rules, no joined
  segments, simplified subsegment rule, no states (`STATUS_OK/ERROR/…`, `CONTEXT_ROOT/REMOTE/SUDO`, `VCS_CLEAN/MODIFIED/UNTRACKED/LOADING`, `DIR_NOT_WRITABLE`…).
- git: one colour for the whole segment instead of the template formatter's per-part colours;
  no tracking branch, `wip`, `─`, tag/commit rules.
- Directory: crude middle-letter shortening instead of `truncate_to_unique` with classes and anchors.
- No ruler, no `├─ ─┤` middle lines, no show-on-command, no custom-segment API, ~20 segments of 87.

## 6. Port design

1. **Same settings.** The engine reads `POWERLEVEL9K_*` with p10k's names, defaults and lookup order.
2. **Templates and user configs converted, not rewritten by hand:** a converter turns a p10k
   zsh config (a template, or the user's own `~/.p10k.zsh`) into bash: `typeset -g` lines into
   assignments, arrays kept, and the few zsh-only constructs (`my_git_formatter`, `$((…))` math
   calls, `${(g::)…}`, anonymous functions) replaced by known bash equivalents; anything unknown
   is reported, never guessed. Rust (runs once at configure time).
3. **Engine** in bash: lookup, colours, icon table per mode (generated from `icons.zsh`),
   prompt-escape interpreter, segment drawing per 3.4, lines/gap/frame/ruler per 3.5, dynamic dir
   truncation, transient prompt and show-on-command via ble.sh, an instant-prompt equivalent.
4. **Wizard** in bash: the same screens, questions, conditions, previews and `generate_config` edits.
5. **Verification against real p10k:** the same config rendered by zsh+p10k and by bash+b4h in
   `tui-capture` (fixed terminal size, same fixture directory and git repository), screens compared
   cell by cell (character, foreground, background, bold). Wizard: drive both with the same keys,
   compare each screen and the resulting configuration.
