//! tui-capture — run a TUI in a pseudo-terminal of a fixed size, feed it keys on a schedule, and
//! save the screen at named moments as JSON, one cell = [char, fg, bg, bold, reverse].
//! Part of bash4humans (GPL-3.0-or-later): its tests run bash and zsh in it and compare the screens
//! cell by cell. Written as a Rust port of a Python script based on pyte, whose JSON format it keeps.
//!
//!   tui-capture SPEC.json OUTDIR
//!   SPEC: {"cmd": [...], "rows": 40, "cols": 133, "env": {...},
//!          "steps": [{"wait": 3}, {"keys": "c"}, {"sh": "command"}, {"snap": "name"}, ...]}
//!
//! Steps: "wait" reads the TUI's output for N seconds; "keys" types text or one of <up> <down> <left>
//! <right> <enter> <esc> <S-up> <S-down>, then reads for 0.4 s; "sh" starts a shell command in the
//! background; "snap" saves OUTDIR/<name>.json. At the end "q" is sent, and the TUI killed after 1 s.
//!
//! Colours are written as pyte wrote them: "default"; the 16 basic
//! colours by name ("red", "brown" for yellow, "brightblack" …); others as six hex digits.
//!
//! LEARNER NOTE — follows the earlier ports. New ideas here: a pseudo-terminal, channels between
//! threads (`mpsc`), `recv_timeout`, and a terminal emulator library.

use std::io::{Read, Write};
use std::num::NonZeroU16;
use std::sync::mpsc;
use std::thread;
use std::time::{Duration, Instant};

use portable_pty::{CommandBuilder, PtySize, native_pty_system};
use serde_json::{Value, json};

// ---------------------------------------------------------------------------
//  Colours, as pyte names them
// ---------------------------------------------------------------------------

/// pyte's names for the 16 basic colours, foreground and background alike. (pyte itself spells
/// background 105 "bfightmagenta", a typo; the correct name is used here.)
const NAMES: [&str; 16] = [
    "black", "red", "green", "brown", "blue", "magenta", "cyan", "white",
    "brightblack", "brightred", "brightgreen", "brightbrown", "brightblue", "brightmagenta", "brightcyan", "brightwhite",
];

/// Colour 16–255 of the xterm palette as six hex digits (as pyte's FG_BG_256 table).
fn xterm_hex(n: u8) -> String {
    let (r, g, b) = if n >= 232 {
        let v = 8 + 10 * (n - 232);
        (v, v, v) // the grey ramp
    } else {
        // the 6×6×6 colour cube
        let level = |x: u8| if x == 0 { 0 } else { 55 + 40 * x };
        let i = n - 16;
        (level(i / 36), level((i / 6) % 6), level(i % 6))
    };
    format!("{r:02x}{g:02x}{b:02x}")
}

fn colour_name(c: vt100::Color) -> String {
    match c {
        vt100::Color::Default => "default".into(),
        vt100::Color::Idx(n) if n < 16 => NAMES[n as usize].into(),
        vt100::Color::Idx(n) => xterm_hex(n),
        vt100::Color::Rgb(r, g, b) => format!("{r:02x}{g:02x}{b:02x}"),
    }
}

// ---------------------------------------------------------------------------
//  Snapshots
// ---------------------------------------------------------------------------

/// The whole screen as pyte's JSON: {"rows", "cols", "grid": [[[ch, fg, bg, bold, reverse], …], …]}.
fn snapshot(screen: &vt100::Screen, rows: u16, cols: u16) -> Value {
    let grid: Vec<Value> = (0..rows)
        .map(|y| {
            let line: Vec<Value> = (0..cols)
                .map(|x| match screen.cell(y, x) {
                    Some(c) => {
                        // pyte: an empty cell holds " ", the right half of a wide character "".
                        let ch = if c.is_wide_continuation() {
                            ""
                        } else if c.has_contents() {
                            c.contents()
                        } else {
                            " "
                        };
                        json!([ch, colour_name(c.fgcolor()), colour_name(c.bgcolor()), c.bold(), c.inverse()])
                    }
                    None => json!([" ", "default", "default", false, false]),
                })
                .collect();
            Value::Array(line)
        })
        .collect();
    json!({ "rows": rows, "cols": cols, "grid": grid })
}

/// Named keys -> the bytes a terminal sends for them; anything else is typed as it is.
fn key_bytes(k: &str) -> &str {
    match k {
        "<up>" => "\x1b[A",
        "<down>" => "\x1b[B",
        "<right>" => "\x1b[C",
        "<left>" => "\x1b[D",
        "<enter>" => "\r",
        "<esc>" => "\x1b",
        "<S-up>" => "\x1b[1;2A",
        "<S-down>" => "\x1b[1;2B",
        other => other,
    }
}

// ---------------------------------------------------------------------------
//  Main program
// ---------------------------------------------------------------------------

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().collect();
    let [_, spec_path, outdir] = args.as_slice() else {
        return Err("usage: tui-capture SPEC.json OUTDIR".into());
    };
    let spec: Value = serde_json::from_str(&std::fs::read_to_string(spec_path).map_err(|e| format!("{spec_path}: {e}"))?)
        .map_err(|e| format!("{spec_path}: {e}"))?;
    std::fs::create_dir_all(outdir).map_err(|e| format!("{outdir}: {e}"))?;
    let rows = spec["rows"].as_u64().ok_or("spec: rows missing")? as u16;
    let cols = spec["cols"].as_u64().ok_or("spec: cols missing")? as u16;
    let cmd: Vec<&str> = spec["cmd"].as_array().ok_or("spec: cmd missing")?.iter().filter_map(Value::as_str).collect();
    if cmd.is_empty() {
        return Err("spec: cmd is empty".into());
    }

    // The pseudo-terminal, already at the right size, with the TUI started in it.
    let pty = native_pty_system()
        .openpty(PtySize { rows, cols, pixel_width: 0, pixel_height: 0 })
        .map_err(|e| format!("pty: {e}"))?;
    let mut command = CommandBuilder::new(cmd[0]);
    command.args(&cmd[1..]);
    command.cwd(std::env::current_dir().map_err(|e| e.to_string())?); // like Python: the current directory
    command.env("TERM", "xterm-256color");
    command.env("COLORTERM", "truecolor");
    if let Some(env) = spec["env"].as_object() {
        for (k, v) in env {
            command.env(k, v.as_str().unwrap_or(""));
        }
    }
    let mut child = pty.slave.spawn_command(command).map_err(|e| format!("starting {}: {e}", cmd[0]))?;
    drop(pty.slave); // only the TUI needs this end

    // LEARNER NOTE — a reading thread and a channel
    //   Reading from the terminal waits until the TUI prints something, so a separate thread does
    //   it and passes each chunk through a channel (`mpsc` = many senders, one receiver). The main
    //   thread can then wait for output *with a time limit* (`recv_timeout`), which a plain read
    //   cannot do.
    let mut reader = pty.master.try_clone_reader().map_err(|e| e.to_string())?;
    let mut writer = pty.master.take_writer().map_err(|e| e.to_string())?;
    let (tx, rx) = mpsc::channel::<Vec<u8>>();
    thread::spawn(move || {
        let mut buf = [0u8; 65536];
        while let Ok(n) = reader.read(&mut buf) {
            if n == 0 || tx.send(buf[..n].to_vec()).is_err() {
                break;
            }
        }
    });

    let size = |n: u16| NonZeroU16::new(n).ok_or("rows and cols must not be 0");
    let mut term = vt100::Parser::new(size(rows)?, size(cols)?, 0);
    // Feed the TUI's output to the emulator for `seconds`.
    let pump = |term: &mut vt100::Parser, seconds: f64| {
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        while let Some(left) = end.checked_duration_since(Instant::now()) {
            match rx.recv_timeout(left) {
                Ok(data) => term.process(&data),
                Err(mpsc::RecvTimeoutError::Timeout) => break,
                Err(mpsc::RecvTimeoutError::Disconnected) => break, // the TUI has exited
            }
        }
    };

    for step in spec["steps"].as_array().ok_or("spec: steps missing")? {
        if let Some(s) = step["wait"].as_f64() {
            pump(&mut term, s);
        } else if let Some(k) = step["keys"].as_str() {
            writer.write_all(key_bytes(k).as_bytes()).map_err(|e| e.to_string())?;
            writer.flush().map_err(|e| e.to_string())?;
            pump(&mut term, 0.4);
        } else if let Some(sh) = step["sh"].as_str() {
            std::process::Command::new("sh").arg("-c").arg(sh).spawn().map_err(|e| format!("sh: {e}"))?;
        } else if let Some(name) = step["snap"].as_str() {
            pump(&mut term, 0.05);
            let path = std::path::Path::new(outdir).join(format!("{name}.json"));
            std::fs::write(&path, snapshot(term.screen(), rows, cols).to_string())
                .map_err(|e| format!("{}: {e}", path.display()))?;
            eprintln!("snap {name}");
        }
    }

    // Ask the TUI to quit, give it a second, then make sure it is gone.
    let _ = writer.write_all(b"q");
    let _ = writer.flush();
    pump(&mut term, 1.0);
    let _ = child.kill();
    Ok(())
}

fn main() {
    if let Err(e) = run() {
        eprintln!("tui-capture: {e}");
        std::process::exit(1);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn palette_matches_pyte() {
        // Values from pyte.graphics.FG_BG_256.
        assert_eq!(xterm_hex(16), "000000");
        assert_eq!(xterm_hex(17), "00005f");
        assert_eq!(xterm_hex(196), "ff0000");
        assert_eq!(xterm_hex(208), "ff8700");
        assert_eq!(xterm_hex(232), "080808");
        assert_eq!(xterm_hex(255), "eeeeee");
        assert_eq!(colour_name(vt100::Color::Idx(3)), "brown");
        assert_eq!(colour_name(vt100::Color::Idx(13)), "brightmagenta");
        assert_eq!(colour_name(vt100::Color::Rgb(255, 135, 0)), "ff8700");
    }
}
