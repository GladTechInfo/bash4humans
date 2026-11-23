//! tui-capture — run a TUI in a pseudo-terminal of a fixed size, feed it keys on a schedule, and
//! save the screen at named moments as JSON.
//! Part of bash4humans (GPL-3.0-or-later): its tests run bash and zsh in it and compare the screens
//! cell by cell. Written as a Rust port of a Python script based on pyte, whose JSON format it keeps.
//!
//!   tui-capture SPEC.json OUTDIR
//!   SPEC: {"cmd": [...], "rows": 40, "cols": 133, "env": {...},
//!          "steps": [{"wait": 3}, {"keys": "c"}, {"sh": "command"}, {"snap": "name"}, ...]}
//!
//! Steps: "wait" reads the TUI's output for N seconds; "keys" types text or a named key (<up>,
//! <enter>, <tab>, <A-left>, <C-r> …, see key_bytes), then reads for "after" seconds (0.4);
//! "type" types text one character every "delay" seconds (0.12); "sh" starts a shell command in
//! the background; "snap" saves OUTDIR/<name>.json; "record": "DIR" saves a frame every
//! "interval" seconds (0.1) as OUTDIR/DIR/00001.json … (with "t", seconds) until {"stop": true}.
//! At the end "q" is sent, and the TUI killed after 1 s.
//! A cell: [char, fg, bg, bold, reverse, italic, underline] (pyte's five fields, then two more).
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

/// The whole screen as pyte's JSON: {"rows", "cols", "grid": [[[ch, fg, bg, bold, reverse, italic,
/// underline], …], …], "cursor": [row, col], "cursor_visible"}.
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
                        // pyte's five fields first (the tests read those), then italic and underline.
                        json!([
                            ch,
                            colour_name(c.fgcolor()),
                            colour_name(c.bgcolor()),
                            c.bold(),
                            c.inverse(),
                            c.italic(),
                            c.underline()
                        ])
                    }
                    None => json!([" ", "default", "default", false, false, false, false]),
                })
                .collect();
            Value::Array(line)
        })
        .collect();
    // The cursor too (the tests ignore it; animations draw it).
    let (cy, cx) = screen.cursor_position();
    json!({ "rows": rows, "cols": cols, "grid": grid, "cursor": [cy, cx], "cursor_visible": !screen.hide_cursor() })
}

/// Named keys -> the bytes an xterm sends for them; anything else is typed as it is.
///   <up> <down> <right> <left> <home> <end> <enter> <tab> <bs> <esc> <del>,
///   with a modifier: <S-up>, <A-left>, <C-right>, <C-S-left> … (S = Shift, A = Alt, C = Ctrl),
///   <S-tab>, and a modifier with one character: <C-r> (Ctrl+R), <A-r> (Alt+R), <C-A-x>.
fn key_bytes(k: &str) -> String {
    // LEARNER NOTE — returning String instead of &str
    //   The old version handed back slices of string literals. Bytes built at run time (a Ctrl
    //   character worked out from a letter) need an owned String, so every arm makes one.
    let Some(inner) = k.strip_prefix('<').and_then(|s| s.strip_suffix('>')) else {
        return k.to_string();
    };
    match inner {
        "enter" => return "\r".into(),
        "tab" => return "\t".into(),
        "S-tab" => return "\x1b[Z".into(),
        "bs" => return "\x7f".into(),
        "esc" => return "\x1b".into(),
        "del" => return "\x1b[3~".into(),
        _ => {}
    }
    // Split "C-A-left" into the modifiers and the key name.
    let mut shift = false;
    let mut alt = false;
    let mut ctrl = false;
    let mut name = inner;
    while name.len() > 2 && name.as_bytes()[1] == b'-' {
        match &name[..1] {
            "S" => shift = true,
            "A" => alt = true,
            "C" => ctrl = true,
            _ => return k.to_string(), // not a key name: type it as text
        }
        name = &name[2..];
    }
    // xterm: CSI 1;<m><letter>, where m = 1 + Shift(1) + Alt(2) + Ctrl(4); without a modifier, CSI <letter>.
    let arrow = match name {
        "up" => Some('A'),
        "down" => Some('B'),
        "right" => Some('C'),
        "left" => Some('D'),
        "end" => Some('F'),
        "home" => Some('H'),
        _ => None,
    };
    if let Some(letter) = arrow {
        let m = 1 + shift as u8 + 2 * alt as u8 + 4 * ctrl as u8;
        return if m == 1 { format!("\x1b[{letter}") } else { format!("\x1b[1;{m}{letter}") };
    }
    // One character with Ctrl and/or Alt: Ctrl keeps the low five bits (r -> 0x12), Alt puts ESC first.
    let mut chars = name.chars();
    if let (Some(c), None, true) = (chars.next(), chars.next(), ctrl || alt) {
        let mut s = String::new();
        if alt {
            s.push('\x1b');
        }
        if ctrl && c.is_ascii() {
            s.push(((c.to_ascii_lowercase() as u8) & 0x1f) as char);
        } else {
            s.push(c);
        }
        return s;
    }
    k.to_string()
}

/// Saves a frame every `interval` seconds while the program's output is read, for animations:
/// OUTDIR/<dir>/00001.json …, each with "t", the seconds since recording began.
struct Recorder {
    dir: std::path::PathBuf,
    interval: f64,
    start: Instant,
    next: Instant,
    count: u32,
}

impl Recorder {
    /// How long until the next frame is due.
    fn until_due(&self) -> Duration {
        self.next.saturating_duration_since(Instant::now())
    }

    /// Saves a frame if one is due.
    fn tick(&mut self, screen: &vt100::Screen, rows: u16, cols: u16) -> Result<(), String> {
        let now = Instant::now();
        if now < self.next {
            return Ok(());
        }
        self.count += 1;
        let mut frame = snapshot(screen, rows, cols);
        frame["t"] = json!((now - self.start).as_secs_f64());
        let path = self.dir.join(format!("{:05}.json", self.count));
        std::fs::write(&path, frame.to_string()).map_err(|e| format!("{}: {e}", path.display()))?;
        // The next frame is due one interval later; after a long stall, start again from now.
        self.next += Duration::from_secs_f64(self.interval);
        if self.next < now {
            self.next = now + Duration::from_secs_f64(self.interval);
        }
        Ok(())
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
    // Feed the TUI's output to the emulator for `seconds`, saving frames when recording.
    // LEARNER NOTE — a closure that borrows
    //   `pump` reads `rx` from its surroundings (a closure "captures" it); the terminal and the
    //   recorder are passed in, because the loop below also uses them between calls.
    // "answer_cpr": true - answer the cursor-position query ESC[6n with ESC[ROW;COLR, as a
    // terminal does (off by default: the parity tests run without it).
    let answer_cpr = spec["answer_cpr"].as_bool().unwrap_or(false);
    let pump = |term: &mut vt100::Parser,
                rec: &mut Option<Recorder>,
                writer: &mut Box<dyn Write + Send>,
                seconds: f64|
     -> Result<(), String> {
        let end = Instant::now() + Duration::from_secs_f64(seconds);
        while let Some(left) = end.checked_duration_since(Instant::now()) {
            let wait = match rec {
                Some(r) => left.min(r.until_due()),
                None => left,
            };
            match rx.recv_timeout(wait) {
                Ok(data) => {
                    term.process(&data);
                    // LEARNER NOTE — `windows(n)`: every run of n neighbouring bytes, to find a
                    //   byte sequence inside a slice.
                    if answer_cpr && data.windows(4).any(|w| w == b"\x1b[6n") {
                        let (y, x) = term.screen().cursor_position();
                        let _ = write!(writer, "\x1b[{};{}R", y + 1, x + 1);
                        let _ = writer.flush();
                    }
                }
                Err(mpsc::RecvTimeoutError::Timeout) => {
                    if rec.is_none() {
                        break; // nothing more within `left`
                    }
                }
                Err(mpsc::RecvTimeoutError::Disconnected) => break, // the TUI has exited
            }
            if let Some(r) = rec {
                r.tick(term.screen(), rows, cols)?;
            }
        }
        Ok(())
    };
    let mut rec: Option<Recorder> = None;

    for step in spec["steps"].as_array().ok_or("spec: steps missing")? {
        if let Some(s) = step["wait"].as_f64() {
            pump(&mut term, &mut rec, &mut writer, s)?;
        } else if let Some(k) = step["keys"].as_str() {
            writer.write_all(key_bytes(k).as_bytes()).map_err(|e| e.to_string())?;
            writer.flush().map_err(|e| e.to_string())?;
            pump(&mut term, &mut rec, &mut writer, step["after"].as_f64().unwrap_or(0.4))?;
        } else if let Some(text) = step["type"].as_str() {
            // Typed one character at a time, as a person would ("delay" seconds apart).
            let delay = step["delay"].as_f64().unwrap_or(0.12);
            for c in text.chars() {
                writer.write_all(c.to_string().as_bytes()).map_err(|e| e.to_string())?;
                writer.flush().map_err(|e| e.to_string())?;
                pump(&mut term, &mut rec, &mut writer, delay)?;
            }
        } else if let Some(dir) = step["record"].as_str() {
            let dir = std::path::Path::new(outdir).join(dir);
            std::fs::create_dir_all(&dir).map_err(|e| format!("{}: {e}", dir.display()))?;
            let now = Instant::now();
            let interval = step["interval"].as_f64().unwrap_or(0.1);
            rec = Some(Recorder { dir, interval, start: now, next: now, count: 0 });
        } else if step["stop"].as_bool() == Some(true) {
            rec = None;
        } else if let Some(sh) = step["sh"].as_str() {
            std::process::Command::new("sh").arg("-c").arg(sh).spawn().map_err(|e| format!("sh: {e}"))?;
        } else if let Some(name) = step["snap"].as_str() {
            pump(&mut term, &mut rec, &mut writer, 0.05)?;
            let path = std::path::Path::new(outdir).join(format!("{name}.json"));
            std::fs::write(&path, snapshot(term.screen(), rows, cols).to_string())
                .map_err(|e| format!("{}: {e}", path.display()))?;
            eprintln!("snap {name}");
        } else {
            return Err(format!("spec: unknown step {step}"));
        }
    }

    // Ask the TUI to quit, give it a second, then make sure it is gone.
    let _ = writer.write_all(b"q");
    let _ = writer.flush();
    rec = None;
    let _ = pump(&mut term, &mut rec, &mut writer, 1.0);
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

    #[test]
    fn key_names() {
        assert_eq!(key_bytes("<up>"), "\x1b[A");
        assert_eq!(key_bytes("<S-up>"), "\x1b[1;2A");
        assert_eq!(key_bytes("<S-down>"), "\x1b[1;2B");
        assert_eq!(key_bytes("<A-left>"), "\x1b[1;3D");
        assert_eq!(key_bytes("<C-right>"), "\x1b[1;5C");
        assert_eq!(key_bytes("<C-r>"), "\x12");
        assert_eq!(key_bytes("<A-r>"), "\x1br");
        assert_eq!(key_bytes("<tab>"), "\t");
        assert_eq!(key_bytes("<S-tab>"), "\x1b[Z");
        assert_eq!(key_bytes("ls -l"), "ls -l");
        assert_eq!(key_bytes("<b>"), "<b>");
    }
}
