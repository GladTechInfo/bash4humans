// p10k.rs - convert a Powerlevel10k configuration (zsh) into bash.
//
//   b4h-tool p10k-config IN.zsh OUT.bash
//
// Used for p10k's own templates (at build time) and for a user's ~/.p10k.zsh
// (b4h configure --from-p10k). The result keeps every POWERLEVEL9K_* setting,
// every comment and the layout of the original file; only zsh-specific code is
// rewritten. bash understands most of a p10k config as it is: `typeset -g`
// exists in bash, arrays may contain comments, and bash brace-expands the
// arguments of typeset, so POWERLEVEL9K_{LEFT,RIGHT}_X= works unchanged.
//
// What cannot be translated is commented out with a "# b4h:" note and listed
// on stderr; the exit status is then 1. Nothing is guessed.

use regex::Regex;
use std::process::ExitCode;

pub fn run(args: &[String]) -> ExitCode {
    let [input, output] = args else {
        eprintln!("usage: b4h-tool p10k-config IN.zsh OUT.bash");
        return ExitCode::from(2);
    };
    let text = match std::fs::read_to_string(input) {
        Ok(t) => t,
        Err(e) => {
            eprintln!("p10k-config: {input}: {e}");
            return ExitCode::from(2);
        }
    };
    let (converted, problems) = convert(&text);
    if let Err(e) = std::fs::write(output, converted) {
        eprintln!("p10k-config: {output}: {e}");
        return ExitCode::from(2);
    }
    for p in &problems {
        eprintln!("p10k-config: {input}: {p}");
    }
    if problems.is_empty() { ExitCode::SUCCESS } else { ExitCode::from(1) }
}

/// Zsh-only values in p10k templates, and their bash forms. The bash forms use
/// p10k's own idiom ${$((f()))+...}: the engine calls f, then expands the rest.
/// The helper functions (_p9k_x_*) live in lib/p10k/expand.bash.
const VALUES: &[(&str, &str)] = &[
    (
        "'${${${${CONDA_PROMPT_MODIFIER#\\(}% }%\\)}:-${CONDA_PREFIX:t}}'",
        "'${$((_p9k_x_anaconda()))+${_p9k_x}}'",
    ),
    (
        "'${P9K_CONTENT}${${P9K_CONTENT:#$P9K_PYENV_PYTHON_VERSION(|/*)}:+ $P9K_PYENV_PYTHON_VERSION}'",
        "'${$((_p9k_x_pyenv()))+${_p9k_x}}'",
    ),
    (
        "'${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+…}'",
        "'${$((_p9k_x_timewarrior()))+${_p9k_x}}'",
    ),
    (
        // the same in ASCII configs (the wizard replaces … with ..)
        "'${P9K_CONTENT:0:24}${${P9K_CONTENT:24}:+..}'",
        "'${$((_p9k_x_timewarrior_ascii()))+${_p9k_x}}'",
    ),
    (
        "'${P9K_TOOLBOX_NAME:#fedora-toolbox-*}'",
        "'${$((_p9k_x_toolbox()))+${_p9k_x}}'",
    ),
    (
        "'${${${P9K_CONTENT/⇣* :⇡/⇣⇡}// }//:/ }'",
        "'${$((_p9k_x_pure_vcs()))+${_p9k_x}}'",
    ),
    (
        "'${${:-/$P9K_KUBECONTEXT_NAMESPACE}:#/default}'",
        "'${$((_p9k_x_kube_namespace()))+${_p9k_x}}'",
    ),
    (
        "'${(V)P9K_PACKAGE_NAME//\\%/%%}@${(V)P9K_PACKAGE_VERSION//\\%/%%}'",
        "'${P9K_PACKAGE_NAME//\\%/%%}@${P9K_PACKAGE_VERSION//\\%/%%}'",
    ),
    (
        "\"(${(j:|:)anchor_files})\"",
        "\"($(IFS='|'; printf '%s' \"${anchor_files[*]}\"))\"",
    ),
    (
        "${${(%):-%x}:a}",
        "$(realpath -- \"${BASH_SOURCE[0]}\")",
    ),
];

/// Lines (trimmed) that only manage zsh options or versions: dropped.
const DROP: &[&str] = &[
    "'builtin' 'local' '-a' 'p10k_config_opts'",
    "'builtin' 'setopt' 'no_aliases' 'no_sh_glob' 'brace_expand'",
    "emulate -L zsh -o extended_glob",
    "emulate -L zsh",
    "[[ $ZSH_VERSION == (5.<1->*|<6->.*) ]] || return",
    "(( ${#p10k_config_opts} )) && setopt ${p10k_config_opts[@]}",
    "'builtin' 'unset' 'p10k_config_opts'",
    "functions -M my_git_formatter 2>/dev/null",
];

/// Whole-line replacements (trimmed line -> bash), indentation kept.
const LINES: &[(&str, &str)] = &[
    (
        "unset -m '(POWERLEVEL9K_*|DEFAULT_USER)~POWERLEVEL9K_GITSTATUS_DIR'",
        "_p9k_unset_config  # unset POWERLEVEL9K_* and DEFAULT_USER, except POWERLEVEL9K_GITSTATUS_DIR",
    ),
    ("(( ! $+functions[p10k] )) || p10k reload", "! declare -F p10k >/dev/null || p10k reload"),
    (
        // robbyrussell template
        "my_git_format+=${${VCS_STATUS_LOCAL_BRANCH:-${VCS_STATUS_COMMIT[1,8]}}//\\%/%%}",
        "local where=${VCS_STATUS_LOCAL_BRANCH:-${VCS_STATUS_COMMIT:0:8}}; my_git_format+=${where//\\%/%%}",
    ),
    (
        "if [[ -n ${VCS_STATUS_REMOTE_BRANCH:#$VCS_STATUS_LOCAL_BRANCH} ]]; then",
        "if [[ -n $VCS_STATUS_REMOTE_BRANCH && $VCS_STATUS_REMOTE_BRANCH != \"$VCS_STATUS_LOCAL_BRANCH\" ]]; then",
    ),
    (
        "if [[ $VCS_STATUS_COMMIT_SUMMARY == (|*[^[:alnum:]])(wip|WIP)(|[^[:alnum:]]*) ]]; then",
        "if [[ $VCS_STATUS_COMMIT_SUMMARY == @(|*[^[:alnum:]])@(wip|WIP)@(|[^[:alnum:]]*) ]]; then",
    ),
];

// Learner note: a struct groups named fields. `Rules` holds the compiled
// regular expressions so they are built once, not for every line.
struct Rules {
    flag_v: Regex,      // ${(V)NAME...   -> ${NAME...   ((V) only makes control chars visible)
    flag_g: Regex,      // ${(g::)NAME}   -> ${NAME@E}   (expand backslash escapes)
    slice_1_8: Regex,   // ${NAME[1,8]}   -> ${NAME:0:8}
    trunc: Regex,       // (( $#x > 32 )) && x[13,-13]="…"
    leftover: Regex,    // anything zsh-only that is still there
}

fn rules() -> Rules {
    Rules {
        flag_v: Regex::new(r"\$\{\(V\)").unwrap(),
        flag_g: Regex::new(r"\$\{\(g::\)([A-Za-z_][A-Za-z0-9_]*)\}").unwrap(),
        slice_1_8: Regex::new(r"\$\{([A-Za-z_][A-Za-z0-9_]*)\[1,8\]\}").unwrap(),
        trunc: Regex::new(r#"\(\( \$#(\w+) > 32 \)\) && (\w+)\[13,-13\]="(…|\.\.)""#).unwrap(),
        leftover: Regex::new(
            r#"\$\{\(|\$\+|\(\(\s*\$\+|:t\}|\$#[A-Za-z_]|\w\[\d+,-?\d+\]|\bsetopt\b|\bemulate\b|\bfunctions -M\b|\$\{\$\{"#,
        )
        .unwrap(),
    }
}

/// Convert the whole text. Returns the bash text and a list of problems.
fn convert(text: &str) -> (String, Vec<String>) {
    let r = rules();
    let mut out = String::new();
    let mut problems = Vec::new();
    let mut in_body = false; // inside the top-level "() {" ... "}"

    out.push_str("# Converted from zsh by b4h-tool p10k-config (bash4humans). Settings and\n");
    out.push_str("# comments are Powerlevel10k's; zsh-only code has been rewritten for bash.\n");

    // Learner note: .lines() splits on newlines; .enumerate() adds the index.
    for (n, raw) in text.lines().enumerate() {
        let lineno = n + 1;
        let indent_len = raw.len() - raw.trim_start().len();
        let indent = &raw[..indent_len];
        let trimmed = raw.trim();

        // The anonymous function that wraps p10k's settings.
        if raw == "() {" {
            out.push_str("_p9k_config_body() {\n");
            in_body = true;
            continue;
        }
        if in_body && raw == "}" {
            out.push_str("}\n_p9k_config_body\nunset -f _p9k_config_body\n");
            in_body = false;
            continue;
        }
        if DROP.contains(&trimmed)
            || (trimmed.starts_with("[[ ! -o '") && trimmed.contains("p10k_config_opts"))
        {
            out.push('\n');
            continue;
        }
        if let Some((_, bash)) = LINES.iter().find(|(z, _)| *z == trimmed) {
            out.push_str(indent);
            out.push_str(bash);
            out.push('\n');
            continue;
        }

        // Comments are kept as they are (they may show zsh examples).
        if trimmed.starts_with('#') && !trimmed.starts_with("# typeset -g") {
            out.push_str(raw);
            out.push('\n');
            continue;
        }

        let mut line = raw.to_string();
        for (zsh, bash) in VALUES {
            if line.contains(zsh) {
                line = line.replace(zsh, bash);
            }
        }
        // Learner note: replace_all returns a Cow (borrowed or owned text);
        // .into_owned() turns it into a plain String.
        line = r.flag_v.replace_all(&line, "${").into_owned();
        line = r.flag_g.replace_all(&line, "$${${1}@E}").into_owned();
        line = r.slice_1_8.replace_all(&line, "$${${1}:0:8}").into_owned();
        line = r
            .trunc
            .replace_all(&line, r#"(( $${#${1}} > 32 )) && ${2}="$${${2}:0:12}${3}$${${2}: -12}""#)
            .into_owned();

        // Anything zsh-only left? Comment it out and report it (commented-out
        // settings in the original are only reported if they are not comments).
        let code = line.trim_start();
        if r.leftover.is_match(code) {
            if code.starts_with('#') {
                problems.push(format!("line {lineno}: commented example left as zsh: {}", code.trim()));
            } else {
                problems.push(format!("line {lineno}: not converted: {}", code.trim()));
                line = format!("{indent}# b4h: not converted from zsh: {}", code.trim());
            }
        }
        out.push_str(&line);
        out.push('\n');
    }
    (fill_empty_branches(&out), problems)
}

/// zsh accepts an if/elif/else branch that holds only comments; bash does
/// not. Put a `:` (do nothing) into each such branch.
fn fill_empty_branches(text: &str) -> String {
    let lines: Vec<&str> = text.lines().collect();
    let mut out = String::new();
    for (i, line) in lines.iter().enumerate() {
        out.push_str(line);
        out.push('\n');
        let t = line.trim();
        let opens = t.ends_with("; then") || t == "then" || t == "else";
        if !opens {
            continue;
        }
        // Look ahead: only comments/blank lines until the branch ends?
        let mut j = i + 1;
        while j < lines.len() {
            let u = lines[j].trim();
            if u.is_empty() || u.starts_with('#') {
                j += 1;
                continue;
            }
            break;
        }
        let next = lines.get(j).map(|l| l.trim()).unwrap_or("");
        if next == "fi" || next.starts_with("elif ") || next == "else" {
            let indent_len = line.len() - line.trim_start().len();
            out.push_str(&line[..indent_len]);
            out.push_str("  :  # b4h: empty branch (bash needs a command here)\n");
        }
    }
    out
}

#[cfg(test)]
mod tests {
    use super::convert;

    #[test]
    fn wrapper_and_values() {
        let zsh = "() {\n  emulate -L zsh -o extended_glob\n  typeset -g POWERLEVEL9K_TOOLBOX_CONTENT_EXPANSION='${P9K_TOOLBOX_NAME:#fedora-toolbox-*}'\n}\n";
        let (bash, problems) = convert(zsh);
        assert!(problems.is_empty(), "{problems:?}");
        assert!(bash.contains("_p9k_config_body() {"));
        assert!(bash.contains("'${$((_p9k_x_toolbox()))+${_p9k_x}}'"));
        assert!(!bash.contains("emulate"));
    }

    #[test]
    fn git_formatter_lines() {
        let zsh = "      local branch=${(V)VCS_STATUS_LOCAL_BRANCH}\n      (( $#branch > 32 )) && branch[13,-13]=\"…\"  # <-- this line\n      res+=\"${clean}${(g::)POWERLEVEL9K_VCS_BRANCH_ICON}${branch//\\%/%%}\"\n      res+=\"${meta}@${clean}${VCS_STATUS_COMMIT[1,8]}\"\n";
        let (bash, problems) = convert(zsh);
        assert!(problems.is_empty(), "{problems:?}");
        assert!(bash.contains("local branch=${VCS_STATUS_LOCAL_BRANCH}"));
        assert!(bash.contains("(( ${#branch} > 32 )) && branch=\"${branch:0:12}…${branch: -12}\""));
        assert!(bash.contains("${POWERLEVEL9K_VCS_BRANCH_ICON@E}"));
        assert!(bash.contains("${VCS_STATUS_COMMIT:0:8}"));
    }

    #[test]
    fn unknown_zsh_is_reported() {
        let (bash, problems) = convert("  typeset -g X=${(%):-%n}\n");
        assert_eq!(problems.len(), 1);
        assert!(bash.contains("# b4h: not converted"));
    }
}
