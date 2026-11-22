//! term-render — turns tui-capture's screens (JSON) into images: a PNG from one screen, an
//! animated GIF from a directory of frames. Part of bash4humans (GPL-3.0-or-later); it makes the
//! README's pictures, so anyone can make them again from the repository (docs/demo/).
//!
//!   term-render png  SNAP.json OUT.png  [options]
//!   term-render gif  FRAMEDIR  OUT.gif  [options]     FRAMEDIR: tui-capture's "record" frames
//!   term-render text SNAP.json|FRAMEDIR               the text of every screen (to check it)
//!
//! Options:
//!   --fonts DIR        MesloLGS NF *.ttf (docs/demo/fonts.sh); default ~/.cache/bash4humans-demo/fonts
//!   --fallback FILE    another font for characters MesloLGS NF lacks (repeatable)
//!   --size PX          font size at scale 1 (14)          --scale N    multiply every size (1)
//!   --crop R0,C0,R1,C1 keep these rows and columns (inclusive, from 0)
//!   --cursor block|bar|none   (block)                     --pad PX     border at scale 1 (12)
//!   --hold S           how long the last GIF frame stays (3)
//!   --max-delay S      no GIF frame longer than this, except the last (2)
//!   --speed F          play the GIF F times faster (1)
//!
//! LEARNER NOTE — follows tui-capture. New ideas here: modules (`mod`), a font rasteriser
//! (ab_glyph), and writing PNG and GIF files.

mod raster;
mod screen;

use std::collections::HashMap;
use std::path::{Path, PathBuf};

use raster::{Canvas, CursorStyle, Fonts};
use screen::Screen;

/// The command-line options, with their defaults.
struct Opts {
    fonts: PathBuf,
    fallbacks: Vec<String>,
    size: f32,
    scale: f32,
    crop: Option<[usize; 4]>,
    cursor: CursorStyle,
    pad: f32,
    hold: f32,
    max_delay: f32,
    speed: f32,
}

fn parse_opts(args: &[String]) -> Result<Opts, String> {
    let home = std::env::var("HOME").unwrap_or_default();
    let mut o = Opts {
        fonts: PathBuf::from(format!("{home}/.cache/bash4humans-demo/fonts")),
        fallbacks: Vec::new(),
        size: 14.0,
        scale: 1.0,
        crop: None,
        cursor: CursorStyle::Block,
        pad: 12.0,
        hold: 3.0,
        max_delay: 2.0,
        speed: 1.0,
    };
    // LEARNER NOTE — walking through arguments
    //   An iterator hands out one argument at a time; `next()` inside the loop takes the value
    //   that follows an option, so "--size 16" is read as a pair.
    let mut it = args.iter();
    while let Some(a) = it.next() {
        let mut value = || it.next().ok_or(format!("{a} needs a value"));
        let num = |s: &String| s.parse::<f32>().map_err(|_| format!("{a}: not a number: {s}"));
        match a.as_str() {
            "--fonts" => o.fonts = PathBuf::from(value()?),
            "--fallback" => o.fallbacks.push(value()?.clone()),
            "--size" => o.size = num(value()?)?,
            "--scale" => o.scale = num(value()?)?,
            "--pad" => o.pad = num(value()?)?,
            "--hold" => o.hold = num(value()?)?,
            "--max-delay" => o.max_delay = num(value()?)?,
            "--speed" => o.speed = num(value()?)?,
            "--cursor" => {
                o.cursor = match value()?.as_str() {
                    "block" => CursorStyle::Block,
                    "bar" => CursorStyle::Bar,
                    "none" => CursorStyle::None,
                    other => return Err(format!("--cursor: block, bar or none, not {other}")),
                }
            }
            "--crop" => {
                let v: Vec<usize> = value()?.split(',').filter_map(|n| n.trim().parse().ok()).collect();
                let [r0, c0, r1, c1] = v[..] else { return Err("--crop R0,C0,R1,C1".into()) };
                o.crop = Some([r0, c0, r1, c1]);
            }
            other => return Err(format!("unknown option {other}")),
        }
    }
    Ok(o)
}

/// Reads one screen from a JSON file, cropped as asked; also returns its "t" (recording time).
fn read_screen(path: &Path, o: &Opts) -> Result<(Screen, f32), String> {
    let text = std::fs::read_to_string(path).map_err(|e| format!("{}: {e}", path.display()))?;
    let v: serde_json::Value = serde_json::from_str(&text).map_err(|e| format!("{}: {e}", path.display()))?;
    let mut s = Screen::from_json(&v).map_err(|e| format!("{}: {e}", path.display()))?;
    if let Some([r0, c0, r1, c1]) = o.crop {
        s = s.crop(r0, c0, r1, c1);
    }
    Ok((s, v["t"].as_f64().unwrap_or(0.0) as f32))
}

/// The frames of a recording, in order (00001.json, 00002.json …).
fn frame_files(dir: &Path) -> Result<Vec<PathBuf>, String> {
    let mut files: Vec<PathBuf> = std::fs::read_dir(dir)
        .map_err(|e| format!("{}: {e}", dir.display()))?
        .filter_map(|e| e.ok().map(|e| e.path()))
        .filter(|p| p.extension().is_some_and(|x| x == "json"))
        .collect();
    files.sort();
    if files.is_empty() {
        return Err(format!("{}: no frames", dir.display()));
    }
    Ok(files)
}

fn load_fonts(o: &Opts) -> Result<Fonts, String> {
    Fonts::load(&o.fonts, &o.fallbacks, o.size * o.scale)
}

fn report_missing(fonts: &Fonts) {
    if !fonts.missing.is_empty() {
        let list: Vec<String> = fonts.missing.iter().map(|c| format!("U+{:04X} {c}", *c as u32)).collect();
        eprintln!("term-render: no font has: {}", list.join(", "));
    }
}

fn write_png(cv: &Canvas, out: &Path) -> Result<(), String> {
    let file = std::fs::File::create(out).map_err(|e| format!("{}: {e}", out.display()))?;
    let mut enc = png::Encoder::new(std::io::BufWriter::new(file), cv.w as u32, cv.h as u32);
    enc.set_color(png::ColorType::Rgb);
    enc.set_depth(png::BitDepth::Eight);
    let mut w = enc.write_header().map_err(|e| e.to_string())?;
    w.write_image_data(&cv.bytes()).map_err(|e| e.to_string())
}

fn cmd_png(snap: &Path, out: &Path, o: &Opts) -> Result<(), String> {
    let (s, _) = read_screen(snap, o)?;
    let mut fonts = load_fonts(o)?;
    let cv = raster::draw(&s, &mut fonts, (o.pad * o.scale).round() as usize, o.cursor);
    report_missing(&fonts);
    write_png(&cv, out)?;
    eprintln!("{}: {}x{}", out.display(), cv.w, cv.h);
    Ok(())
}

fn cmd_gif(dir: &Path, out: &Path, o: &Opts) -> Result<(), String> {
    // 1. The screens, with each one's start time; a screen equal to the one before only
    //    lengthens that one.
    let mut shots: Vec<(Screen, f32)> = Vec::new();
    for f in frame_files(dir)? {
        let (s, t) = read_screen(&f, o)?;
        if shots.last().map(|(prev, _)| prev) != Some(&s) {
            shots.push((s, t));
        }
    }
    // 2. How long each stays, in hundredths of a second (the GIF unit).
    let mut delays = Vec::new();
    for i in 0..shots.len() {
        let secs = match shots.get(i + 1) {
            Some((_, next)) => ((next - shots[i].1) / o.speed).min(o.max_delay),
            None => o.hold,
        };
        delays.push((secs * 100.0).round().max(2.0) as u16);
    }
    // 3. Draw them all.
    let mut fonts = load_fonts(o)?;
    let pad = (o.pad * o.scale).round() as usize;
    let canvases: Vec<Canvas> = shots.iter().map(|(s, _)| raster::draw(s, &mut fonts, pad, o.cursor)).collect();
    report_missing(&fonts);
    let (w, h) = (canvases[0].w, canvases[0].h);

    // 4. One palette for the whole GIF when the frames use 256 colours or fewer (they usually
    //    do: coverage is rounded to eighths); otherwise each frame gets its own, reduced one.
    let mut index: HashMap<[u8; 3], u8> = HashMap::new();
    let mut palette: Vec<u8> = Vec::new();
    let mut exact = true;
    'outer: for cv in &canvases {
        for p in &cv.px {
            if !index.contains_key(p) {
                if index.len() == 256 {
                    exact = false;
                    break 'outer;
                }
                index.insert(*p, index.len() as u8);
                palette.extend_from_slice(p);
            }
        }
    }

    let file = std::fs::File::create(out).map_err(|e| format!("{}: {e}", out.display()))?;
    let global: &[u8] = if exact { &palette } else { &[] };
    let mut enc = gif::Encoder::new(std::io::BufWriter::new(file), w as u16, h as u16, global).map_err(|e| e.to_string())?;
    enc.set_repeat(gif::Repeat::Infinite).map_err(|e| e.to_string())?;

    // 5. Each frame stores only the rectangle that changed since the frame before.
    let mut prev: Option<&Canvas> = None;
    for (cv, delay) in canvases.iter().zip(&delays) {
        let (x0, y0, x1, y1) = match prev {
            None => (0, 0, w - 1, h - 1),
            Some(p) => changed_box(p, cv).unwrap_or((0, 0, 0, 0)),
        };
        let (bw, bh) = (x1 - x0 + 1, y1 - y0 + 1);
        let mut frame = if exact {
            let mut buf = Vec::with_capacity(bw * bh);
            for y in y0..=y1 {
                for x in x0..=x1 {
                    buf.push(index[&cv.px[y * w + x]]);
                }
            }
            gif::Frame { width: bw as u16, height: bh as u16, buffer: buf.into(), ..Default::default() }
        } else {
            let mut rgb = Vec::with_capacity(bw * bh * 3);
            for y in y0..=y1 {
                for x in x0..=x1 {
                    rgb.extend_from_slice(&cv.px[y * w + x]);
                }
            }
            gif::Frame::from_rgb_speed(bw as u16, bh as u16, &rgb, 10)
        };
        frame.left = x0 as u16;
        frame.top = y0 as u16;
        frame.delay = *delay;
        frame.dispose = gif::DisposalMethod::Keep;
        enc.write_frame(&frame).map_err(|e| e.to_string())?;
        prev = Some(cv);
    }
    drop(enc); // writes the GIF's trailer
    let size = std::fs::metadata(out).map(|m| m.len()).unwrap_or(0);
    let total: u32 = delays.iter().map(|&d| d as u32).sum();
    eprintln!(
        "{}: {}x{}, {} frames, {:.1} s, {} KiB{}",
        out.display(),
        w,
        h,
        canvases.len(),
        total as f32 / 100.0,
        size / 1024,
        if exact { "" } else { " (reduced palette)" }
    );
    Ok(())
}

/// The smallest rectangle (x0, y0, x1, y1) holding every pixel that differs; None if none does.
fn changed_box(a: &Canvas, b: &Canvas) -> Option<(usize, usize, usize, usize)> {
    let mut bx: Option<(usize, usize, usize, usize)> = None;
    for y in 0..a.h {
        for x in 0..a.w {
            if a.px[y * a.w + x] != b.px[y * a.w + x] {
                bx = Some(match bx {
                    None => (x, y, x, y),
                    Some((x0, y0, x1, y1)) => (x0.min(x), y0.min(y), x1.max(x), y1.max(y)),
                });
            }
        }
    }
    bx
}

fn cmd_text(path: &Path, o: &Opts) -> Result<(), String> {
    let files = if path.is_dir() { frame_files(path)? } else { vec![path.to_path_buf()] };
    for f in files {
        let (s, _) = read_screen(&f, o)?;
        println!("== {}", f.display());
        print!("{}", s.text());
    }
    Ok(())
}

fn run() -> Result<(), String> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let usage = "usage: term-render png SNAP.json OUT.png | gif FRAMEDIR OUT.gif | text SNAP|FRAMEDIR  [options]";
    match args.first().map(String::as_str) {
        Some("png") if args.len() >= 3 => cmd_png(Path::new(&args[1]), Path::new(&args[2]), &parse_opts(&args[3..])?),
        Some("gif") if args.len() >= 3 => cmd_gif(Path::new(&args[1]), Path::new(&args[2]), &parse_opts(&args[3..])?),
        Some("text") if args.len() >= 2 => cmd_text(Path::new(&args[1]), &parse_opts(&args[2..])?),
        _ => Err(usage.into()),
    }
}

fn main() {
    if let Err(e) = run() {
        eprintln!("term-render: {e}");
        std::process::exit(1);
    }
}
