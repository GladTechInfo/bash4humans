// b4h-tool - the compiled helper behind two bash4humans features:
//
//   b4h-tool mv [options] SOURCE-PATTERN DESTINATION   bulk rename, like zsh's zmv
//   b4h-tool suggest WORD                              "did you mean" for unknown commands
//
// The shell functions `zmv` and `command_not_found_handle` (lib/*.bash) call it.

// Learner note: `mod name;` tells Rust that the code in src/name.rs is part of
// this program. Each file is a "module" with its own namespace.
mod mv;
mod p10k;
mod suggest;

// Learner note: `use` brings a name into scope so it can be written short.
// `std::process::ExitCode` is the value `main` returns to set the exit status.
use std::process::ExitCode;

const USAGE: &str = "\
usage: b4h-tool mv [-n] [-f] [-i] [-v] [-p] [-C] [-W] [--dotglob] SOURCE-PATTERN DESTINATION
       b4h-tool suggest WORD        (extra candidate names may be given on stdin)
       b4h-tool p10k-config IN.zsh OUT.bash   convert a Powerlevel10k config to bash
       b4h-tool --version";

// Learner note: `fn main() -> ExitCode` means main returns an exit code
// instead of nothing. Returning ExitCode::from(2) makes the process exit 2.
fn main() -> ExitCode {
    // Learner note: `std::env::args()` yields the command-line words as
    // Strings. `.skip(1)` drops the program name; `.collect()` gathers the
    // rest into a Vec<String> (a growable list).
    let args: Vec<String> = std::env::args().skip(1).collect();

    // Learner note: `match` compares a value against patterns, top to bottom.
    // `args.first()` is an Option: Some(&first_word) or None if empty.
    // `.map(|s| s.as_str())` turns Option<&String> into Option<&str> so it
    // can be compared with string literals.
    match args.first().map(|s| s.as_str()) {
        Some("mv") => mv::run(&args[1..]),
        Some("suggest") => suggest::run(&args[1..]),
        Some("p10k-config") => p10k::run(&args[1..]),
        Some("--version") => {
            // env!("CARGO_PKG_VERSION") is filled in at compile time from Cargo.toml.
            println!("b4h-tool {}", env!("CARGO_PKG_VERSION"));
            ExitCode::SUCCESS
        }
        _ => {
            eprintln!("{USAGE}");
            ExitCode::from(2)
        }
    }
}
