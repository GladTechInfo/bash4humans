// suggest.rs - "did you mean": find command names close to a mistyped one.
//
// Candidates are every executable in $PATH plus any names the shell sends on
// stdin (aliases, functions, builtins - only bash knows those). Closeness is
// the "optimal string alignment" distance: the number of single-character
// insertions, deletions, substitutions or swaps of neighbours needed to turn
// one word into the other ("gti" -> "git" is 1).

use std::collections::BTreeSet;
use std::io::{BufRead, IsTerminal};
use std::os::unix::fs::PermissionsExt;
use std::process::ExitCode;

pub fn run(args: &[String]) -> ExitCode {
    // Learner note: `let [word] = args else { ... }` is a "let-else": it
    // succeeds only if args has exactly one element, binding it to `word`;
    // otherwise the else block runs, and it must leave the function.
    let [word] = args else {
        eprintln!("usage: b4h-tool suggest WORD");
        return ExitCode::from(2);
    };

    // Learner note: a BTreeSet keeps its items sorted and drops duplicates,
    // so the same command found in two PATH directories is counted once.
    let mut names: BTreeSet<String> = BTreeSet::new();
    collect_path_commands(&mut names);

    // Read extra names from stdin only when something is piped in;
    // reading from a terminal would wait for the user to type.
    let stdin = std::io::stdin();
    if !stdin.is_terminal() {
        // Learner note: `.lines()` yields Result<String> per line;
        // `.map_while(Result::ok)` stops at the first read error.
        for line in stdin.lock().lines().map_while(Result::ok) {
            let line = line.trim();
            if !line.is_empty() {
                names.insert(line.to_string());
            }
        }
    }

    // Allow more typos in longer words.
    let len = word.chars().count();
    let limit = if len <= 4 { 1 } else if len <= 8 { 2 } else { 3 };

    // Learner note: a Vec of tuples; each entry is (distance, not an
    // anagram?, different first letter?, name). Sorting tuples compares the
    // first field, then the next. false sorts before true, so anagrams
    // ("sl" for "ls" - letters swapped) and same-first-letter names come first.
    let first = word.chars().next();
    let sorted_word = sorted_chars(word);
    let mut hits: Vec<(usize, bool, bool, &String)> = Vec::new();
    for name in &names {
        if name == word {
            continue;
        }
        let d = distance(word, name);
        if d <= limit {
            let not_anagram = sorted_chars(name) != sorted_word;
            hits.push((d, not_anagram, name.chars().next() != first, name));
        }
    }
    hits.sort();

    for (_, _, _, name) in hits.iter().take(3) {
        println!("{name}");
    }
    if hits.is_empty() { ExitCode::from(1) } else { ExitCode::SUCCESS }
}

/// The characters of `s` in sorted order: equal for two anagrams.
fn sorted_chars(s: &str) -> Vec<char> {
    let mut v: Vec<char> = s.chars().collect();
    // Learner note: sort_unstable is a little faster than sort and fine
    // when equal items need not keep their original order.
    v.sort_unstable();
    v
}

/// Add every executable file found in the directories of $PATH.
fn collect_path_commands(names: &mut BTreeSet<String>) {
    // Learner note: `if let Some(x) = ...` runs the block only when the
    // Option holds a value. `var_os` returns None when PATH is unset.
    let Some(path) = std::env::var_os("PATH") else { return };
    for dir in std::env::split_paths(&path) {
        // Unreadable or missing directories are skipped silently.
        let Ok(entries) = std::fs::read_dir(&dir) else { continue };
        for entry in entries.flatten() {
            // `metadata()` follows symlinks, so a link to a program counts.
            let Ok(meta) = entry.path().metadata() else { continue };
            let executable = meta.permissions().mode() & 0o111 != 0;
            if meta.is_file() && executable {
                if let Some(name) = entry.file_name().to_str() {
                    names.insert(name.to_string());
                }
            }
        }
    }
}

/// Optimal string alignment distance between `a` and `b`.
fn distance(a: &str, b: &str) -> usize {
    // Work on characters, not bytes, so non-ASCII names count correctly.
    let a: Vec<char> = a.chars().collect();
    let b: Vec<char> = b.chars().collect();
    let (n, m) = (a.len(), b.len());

    // d[i][j] = distance between the first i chars of a and first j of b.
    // Learner note: `vec![vec![0; m + 1]; n + 1]` builds an (n+1) x (m+1)
    // table of zeros.
    let mut d = vec![vec![0usize; m + 1]; n + 1];
    for i in 0..=n {
        d[i][0] = i;
    }
    for j in 0..=m {
        d[0][j] = j;
    }
    for i in 1..=n {
        for j in 1..=m {
            let cost = if a[i - 1] == b[j - 1] { 0 } else { 1 };
            d[i][j] = (d[i - 1][j] + 1) // delete
                .min(d[i][j - 1] + 1) // insert
                .min(d[i - 1][j - 1] + cost); // substitute
            // swap of two neighbouring characters
            if i > 1 && j > 1 && a[i - 1] == b[j - 2] && a[i - 2] == b[j - 1] {
                d[i][j] = d[i][j].min(d[i - 2][j - 2] + 1);
            }
        }
    }
    d[n][m]
}

// Learner note: `#[cfg(test)]` compiles this module only for `cargo test`.
#[cfg(test)]
mod tests {
    use super::distance;

    #[test]
    fn distances() {
        assert_eq!(distance("gti", "git"), 1); // swap
        assert_eq!(distance("sl", "ls"), 1);
        assert_eq!(distance("pyhton", "python"), 1);
        assert_eq!(distance("grpe", "grep"), 1);
        assert_eq!(distance("abc", "abc"), 0);
        assert_eq!(distance("kitten", "sitting"), 3);
    }
}
