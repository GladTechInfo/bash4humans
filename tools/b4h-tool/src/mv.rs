// mv.rs - bulk rename with patterns, after zsh's zmv.
//
//   zmv '(*).txt' '$1.md'           a.txt -> a.md        (parentheses capture: $1, $2 ...)
//   zmv '(**/)(*).jpeg' '$1$2.jpg'  recursive: **/ matches any directories
//   zmv -W '*.txt' '*.md'           -W: each wildcard is captured; the
//                                   target's wildcards are filled in order
//
// Patterns: *  ?  [abc] [!abc]  **/  (a|b)  and \ to escape.  $f or $0 in
// the target is the whole source path.
//
// Safety: every pair is worked out and checked first - no matches, two
// sources with one target, an existing target (without -f) - and nothing is
// touched if any check fails. Deeper paths are handled first, so renaming a
// directory never invalidates the paths inside it that are being renamed.

use regex::Regex;
use std::collections::HashMap;
use std::fs;
use std::io::{BufRead, Write};
use std::path::Path;
use std::process::ExitCode;

// Learner note: `#[derive(Default)]` makes Options::default() build a value
// with every bool false - handy for "all options off" before parsing.
#[derive(Default)]
struct Options {
    dry_run: bool,     // -n  show what would happen
    force: bool,       // -f  allow overwriting existing targets
    interactive: bool, // -i  ask before each one
    verbose: bool,     // -v  print each action
    parents: bool,     // -p  create missing target directories
    copy: bool,        // -C  copy instead of move
    wildcard: bool,    // -W  implicit captures (see top of file)
    dotglob: bool,     // --dotglob  wildcards match names starting with "."
}

pub fn run(args: &[String]) -> ExitCode {
    // Learner note: `match f() { Ok(v) => v, Err(e) => ... }` unpacks a
    // Result: use the value on success, otherwise handle the error.
    let (opts, src_pat, dst_pat) = match parse_args(args) {
        Ok(parsed) => parsed,
        Err(msg) => {
            eprintln!("zmv: {msg}");
            eprintln!("usage: zmv [-n] [-f] [-i] [-v] [-p] [-C] [-W] 'SOURCE-PATTERN' 'TARGET'");
            return ExitCode::from(2);
        }
    };

    let (body, _groups) = match glob_to_regex(&src_pat, opts.wildcard) {
        Ok(r) => r,
        Err(msg) => {
            eprintln!("zmv: {msg}");
            return ExitCode::from(2);
        }
    };
    // ^ and $ anchor the regex: the whole path must match, not just part.
    let re = match Regex::new(&format!("^{body}$")) {
        Ok(re) => re,
        Err(e) => {
            eprintln!("zmv: bad pattern: {e}");
            return ExitCode::from(2);
        }
    };

    // 1. Work out every (source, target) pair.
    let mut pairs: Vec<(String, String)> = Vec::new();
    for path in candidates(&src_pat, opts.dotglob) {
        // Learner note: `let Some(caps) = ... else { continue }` skips
        // paths the regex does not match.
        let Some(caps) = re.captures(&path) else { continue };
        match expand_target(&dst_pat, &caps, &path, opts.wildcard) {
            Ok(target) if target == path => {} // unchanged: nothing to do
            Ok(target) => pairs.push((path, target)),
            Err(msg) => {
                eprintln!("zmv: {msg}");
                return ExitCode::from(2);
            }
        }
    }
    if pairs.is_empty() {
        eprintln!("zmv: no matches for '{src_pat}'");
        return ExitCode::from(1);
    }

    // 2. Check all of them before touching anything.
    if !check(&pairs, opts.force) {
        eprintln!("zmv: nothing done");
        return ExitCode::from(1);
    }

    // 3. Deepest first, then alphabetical.
    // Learner note: sort_by takes a closure comparing two items; `.then_with`
    // breaks ties with a second comparison. `b ... cmp(a)` sorts descending.
    pairs.sort_by(|a, b| {
        depth(&b.0).cmp(&depth(&a.0)).then_with(|| a.0.cmp(&b.0))
    });

    // 4. Do it.
    let verb = if opts.copy { "cp" } else { "mv" };
    let mut failed = false;
    for (src, dst) in &pairs {
        if opts.dry_run {
            println!("{verb} -- {} {}", quote(src), quote(dst));
            continue;
        }
        if opts.interactive && !ask(&format!("{verb} {} -> {}? [y/N] ", quote(src), quote(dst))) {
            continue;
        }
        if let Err(e) = apply(src, dst, &opts) {
            eprintln!("zmv: {src} -> {dst}: {e}");
            failed = true;
            continue;
        }
        if opts.verbose {
            println!("{src} -> {dst}");
        }
    }
    if failed { ExitCode::from(1) } else { ExitCode::SUCCESS }
}

/// Split the arguments into options and the two patterns.
// Learner note: the return type `Result<(Options, String, String), String>`
// means "either the three parsed values, or an error message".
fn parse_args(args: &[String]) -> Result<(Options, String, String), String> {
    let mut opts = Options::default();
    let mut words: Vec<String> = Vec::new();
    let mut options_done = false;
    for arg in args {
        if options_done || !arg.starts_with('-') || arg == "-" {
            words.push(arg.clone());
        } else if arg == "--" {
            options_done = true;
        } else if arg == "--dotglob" {
            opts.dotglob = true;
        } else {
            // "-nv" is "-n -v": look at each letter after the dash.
            for flag in arg.chars().skip(1) {
                match flag {
                    'n' => opts.dry_run = true,
                    'f' => opts.force = true,
                    'i' => opts.interactive = true,
                    'v' => opts.verbose = true,
                    'p' => opts.parents = true,
                    'C' => opts.copy = true,
                    'W' => opts.wildcard = true,
                    other => return Err(format!("unknown option -{other}")),
                }
            }
        }
    }
    if words.len() != 2 {
        return Err("need exactly a source pattern and a target".into());
    }
    // Learner note: `words.remove(0)` takes the first item out of the Vec,
    // giving us ownership of the String without copying it.
    let src = words.remove(0);
    let dst = words.remove(0);
    Ok((opts, src, dst))
}

/// Translate a glob into regex text. Returns the text and the number of
/// capture groups.
fn glob_to_regex(pat: &str, wildcard: bool) -> Result<(String, usize), String> {
    let chars: Vec<char> = pat.chars().collect();
    let mut out = String::new();
    let mut groups = 0;
    let mut open = 0; // parentheses currently open
    let mut i = 0;

    // Learner note: a closure is a small unnamed function stored in a
    // variable. This one reads `wildcard` from the surrounding function and
    // is handed `out` and `groups` as arguments, so it can change them. It
    // adds a piece of regex, wrapped as a capture group in -W mode.
    let push_wild = |piece: &str, out: &mut String, groups: &mut usize| {
        if wildcard {
            out.push('(');
            out.push_str(piece);
            out.push(')');
            *groups += 1;
        } else {
            out.push_str(piece);
        }
    };

    while i < chars.len() {
        let c = chars[i];
        match c {
            '\\' => {
                i += 1;
                if i < chars.len() {
                    out.push_str(&regex::escape(&chars[i].to_string()));
                }
            }
            '*' => {
                let double = i + 1 < chars.len() && chars[i + 1] == '*';
                if double && i + 2 < chars.len() && chars[i + 2] == '/' {
                    push_wild("(?:[^/]*/)*", &mut out, &mut groups); // **/ : any directories
                    i += 2;
                } else {
                    push_wild("[^/]*", &mut out, &mut groups);
                    if double {
                        i += 1; // a lone ** is the same as *
                    }
                }
            }
            '?' => push_wild("[^/]", &mut out, &mut groups),
            '[' => {
                // Character class: find the closing ]. A ] straight after
                // [ or [! is a literal member.
                let mut j = i + 1;
                let negate = j < chars.len() && (chars[j] == '!' || chars[j] == '^');
                if negate {
                    j += 1;
                }
                let mut class = String::new();
                if j < chars.len() && chars[j] == ']' {
                    class.push_str("\\]");
                    j += 1;
                }
                while j < chars.len() && chars[j] != ']' {
                    let ch = chars[j];
                    // These have special meaning inside a regex class.
                    if matches!(ch, '\\' | '[' | '&' | '~' | '^') {
                        class.push('\\');
                    }
                    class.push(ch);
                    j += 1;
                }
                if j >= chars.len() {
                    out.push_str("\\["); // no closing ]: a literal [
                } else {
                    let piece = if negate { format!("[^/{class}]") } else { format!("[{class}]") };
                    push_wild(&piece, &mut out, &mut groups);
                    i = j;
                }
            }
            '(' if !wildcard => {
                out.push('(');
                groups += 1;
                open += 1;
            }
            ')' if !wildcard && open > 0 => {
                out.push(')');
                open -= 1;
            }
            '|' if !wildcard && open > 0 => out.push('|'),
            _ => out.push_str(&regex::escape(&c.to_string())),
        }
        i += 1;
    }
    if open != 0 {
        return Err("unbalanced parentheses in the pattern".into());
    }
    Ok((out, groups))
}

/// List the paths a pattern could match: walk from the pattern's literal
/// leading directories, as deep as the pattern reaches.
fn candidates(pat: &str, dotglob: bool) -> Vec<String> {
    let is_special = |s: &str| s.contains(['*', '?', '[', '(', ')', '|', '\\']);
    let comps: Vec<&str> = pat.split('/').collect();

    // Leading components without wildcards are a fixed starting directory.
    let mut fixed = 0;
    while fixed + 1 < comps.len() && !is_special(comps[fixed]) {
        fixed += 1;
    }
    let mut base = comps[..fixed].join("/");
    if pat.starts_with('/') && base.is_empty() {
        base = "/".into();
    }
    let rest = &comps[fixed..];

    let max_depth = if rest.iter().any(|c| c.contains("**")) { usize::MAX } else { rest.len() };
    // Names starting with "." are included with --dotglob, or when the
    // pattern itself asks for them.
    let hidden = dotglob || rest.iter().any(|c| c.starts_with('.') || c.starts_with("(."));

    let (start, prefix) = if base.is_empty() {
        (".".to_string(), String::new())
    } else if base.ends_with('/') {
        (base.clone(), base.clone())
    } else {
        (base.clone(), format!("{base}/"))
    };

    let mut out = Vec::new();
    walk(Path::new(&start), &prefix, 1, max_depth, hidden, &mut out);
    out
}

// Learner note: `&mut Vec<String>` lets walk() add to the caller's list
// instead of building and returning a new one at each level.
fn walk(dir: &Path, prefix: &str, depth: usize, max_depth: usize, hidden: bool, out: &mut Vec<String>) {
    let Ok(entries) = fs::read_dir(dir) else { return };
    let mut names: Vec<String> = entries
        .flatten()
        .filter_map(|e| e.file_name().into_string().ok())
        .collect();
    names.sort();
    for name in names {
        if !hidden && name.starts_with('.') {
            continue;
        }
        let rel = format!("{prefix}{name}");
        let full = dir.join(&name);
        out.push(rel.clone());
        // symlink_metadata does not follow links, so a link to a directory
        // is renamed as itself, never walked into (no loops).
        let is_dir = fs::symlink_metadata(&full).map(|m| m.is_dir()).unwrap_or(false);
        if is_dir && depth < max_depth {
            walk(&full, &format!("{rel}/"), depth + 1, max_depth, hidden, out);
        }
    }
}

/// Build the target name from the target pattern and the captures.
fn expand_target(dst: &str, caps: &regex::Captures, whole: &str, wildcard: bool) -> Result<String, String> {
    let chars: Vec<char> = dst.chars().collect();
    let mut out = String::new();
    let mut next_group = 1; // -W: next capture to use
    let mut i = 0;

    // Learner note: `caps.get(n)` is None for a group that took part in no
    // match (one side of an alternation); `.map_or("", ...)` gives "" then.
    let group = |n: usize| -> Result<String, String> {
        if n >= caps.len() {
            return Err(format!("the target uses ${n}, but the pattern has only {} group(s)", caps.len() - 1));
        }
        Ok(caps.get(n).map_or("", |m| m.as_str()).to_string())
    };

    while i < chars.len() {
        let c = chars[i];
        if c == '\\' && i + 1 < chars.len() {
            out.push(chars[i + 1]);
            i += 2;
            continue;
        }
        if wildcard && (c == '*' || c == '?') {
            out.push_str(&group(next_group)?);
            next_group += 1;
            // "**/" in the target takes one capture, like in the source.
            if c == '*' && i + 2 < chars.len() && chars[i + 1] == '*' && chars[i + 2] == '/' {
                i += 3;
            } else {
                i += 1;
            }
            continue;
        }
        if c == '$' && i + 1 < chars.len() {
            let n = chars[i + 1];
            if n == 'f' {
                out.push_str(whole);
                i += 2;
                continue;
            }
            // ${12} or $1
            let (digits, used) = if n == '{' {
                let end = chars[i + 2..].iter().position(|&ch| ch == '}').ok_or("unclosed ${ in the target")?;
                (chars[i + 2..i + 2 + end].iter().collect::<String>(), end + 3)
            } else {
                let len = chars[i + 1..].iter().take_while(|ch| ch.is_ascii_digit()).count();
                (chars[i + 1..i + 1 + len].iter().collect::<String>(), len + 1)
            };
            // Learner note: `str::parse::<usize>()` converts text to a number
            // and returns a Result; `if let Ok(n)` uses it only if valid.
            if let Ok(n) = digits.parse::<usize>() {
                out.push_str(&if n == 0 { whole.to_string() } else { group(n)? });
                i += used;
                continue;
            }
        }
        out.push(c);
        i += 1;
    }
    if out.is_empty() {
        return Err(format!("'{whole}' would get an empty name"));
    }
    Ok(out)
}

/// Return false (after printing every problem) if the plan is unsafe.
fn check(pairs: &[(String, String)], force: bool) -> bool {
    let mut ok = true;
    // Learner note: a HashMap maps keys to values - here target -> source,
    // to spot two sources heading for the same target.
    let mut seen: HashMap<&str, &str> = HashMap::new();
    for (src, dst) in pairs {
        if let Some(other) = seen.insert(dst, src) {
            eprintln!("zmv: both '{other}' and '{src}' would become '{dst}'");
            ok = false;
            continue; // the "already exists" line was printed for the first one
        }
        if !force && fs::symlink_metadata(dst).is_ok() {
            eprintln!("zmv: '{dst}' already exists (use -f to overwrite)");
            ok = false;
        }
    }
    ok
}

/// Move or copy one path, creating parents with -p.
fn apply(src: &str, dst: &str, opts: &Options) -> std::io::Result<()> {
    if opts.parents {
        if let Some(parent) = Path::new(dst).parent() {
            if !parent.as_os_str().is_empty() {
                fs::create_dir_all(parent)?;
            }
        }
    }
    if opts.copy {
        return copy_any(Path::new(src), Path::new(dst));
    }
    // Learner note: the `?` operator returns early with the error if the
    // call failed; here we inspect the error instead, to handle one case.
    match fs::rename(src, dst) {
        Ok(()) => Ok(()),
        // 18 = EXDEV: different filesystems; rename cannot do that, so
        // copy and then remove the original, as mv does.
        Err(e) if e.raw_os_error() == Some(18) => {
            copy_any(Path::new(src), Path::new(dst))?;
            let meta = fs::symlink_metadata(src)?;
            if meta.is_dir() { fs::remove_dir_all(src) } else { fs::remove_file(src) }
        }
        Err(e) => Err(e),
    }
}

/// Copy a file, symlink or whole directory tree.
fn copy_any(src: &Path, dst: &Path) -> std::io::Result<()> {
    let meta = fs::symlink_metadata(src)?;
    if meta.file_type().is_symlink() {
        std::os::unix::fs::symlink(fs::read_link(src)?, dst)
    } else if meta.is_dir() {
        fs::create_dir(dst)?;
        fs::set_permissions(dst, meta.permissions())?;
        for entry in fs::read_dir(src)? {
            let entry = entry?;
            copy_any(&entry.path(), &dst.join(entry.file_name()))?;
        }
        Ok(())
    } else {
        fs::copy(src, dst).map(|_| ())
    }
}

fn depth(path: &str) -> usize {
    path.matches('/').count()
}

/// Ask a yes/no question on the terminal (not stdin, which may be a pipe).
fn ask(question: &str) -> bool {
    let Ok(tty) = fs::OpenOptions::new().read(true).write(true).open("/dev/tty") else { return false };
    let mut writer = &tty;
    let _ = writer.write_all(question.as_bytes());
    let mut answer = String::new();
    let _ = std::io::BufReader::new(&tty).read_line(&mut answer);
    matches!(answer.trim(), "y" | "Y" | "yes")
}

/// Quote a path for display so it can be pasted back into a shell.
fn quote(s: &str) -> String {
    let safe = !s.is_empty()
        && s.chars().all(|c| c.is_ascii_alphanumeric() || "_./+-:=@%,".contains(c));
    if safe { s.to_string() } else { format!("'{}'", s.replace('\'', "'\\''")) }
}

#[cfg(test)]
mod tests {
    use super::*;

    fn rx(p: &str, w: bool) -> Regex {
        Regex::new(&format!("^{}$", glob_to_regex(p, w).unwrap().0)).unwrap()
    }

    #[test]
    fn groups_and_targets() {
        let re = rx("(*).txt", false);
        let caps = re.captures("notes.txt").unwrap();
        assert_eq!(expand_target("$1.md", &caps, "notes.txt", false).unwrap(), "notes.md");
        assert!(re.captures("dir/notes.txt").is_none()); // * does not cross /
    }

    #[test]
    fn recursive_and_alternation() {
        let re = rx("(**/)(*).(jpeg|JPG)", false);
        let caps = re.captures("a/b/x.JPG").unwrap();
        assert_eq!(expand_target("$1$2.jpg", &caps, "a/b/x.JPG", false).unwrap(), "a/b/x.jpg");
        assert!(re.captures("x.jpeg").is_some()); // **/ may match no directories
    }

    #[test]
    fn wildcard_mode() {
        let re = rx("*_[0-9]?.log", true);
        let caps = re.captures("app_12.log").unwrap();
        assert_eq!(expand_target("*-*?.txt", &caps, "app_12.log", true).unwrap(), "app-12.txt");
    }

    #[test]
    fn missing_group_is_an_error() {
        let re = rx("(*).txt", false);
        let caps = re.captures("a.txt").unwrap();
        assert!(expand_target("$2", &caps, "a.txt", false).is_err());
    }
}
