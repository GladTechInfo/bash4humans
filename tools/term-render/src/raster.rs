//! Drawing a screen into pixels: the font, the cell grid, and the line-drawing characters that a
//! terminal draws itself rather than taking from the font.

use std::collections::BTreeSet;

use ab_glyph::{Font, FontVec, PxScale, ScaleFont, point};

use crate::screen::{Rgb, Screen};

// ---------------------------------------------------------------------------
//  Fonts
// ---------------------------------------------------------------------------

/// The four faces of the font, plus fonts to try for characters the main font lacks.
pub struct Fonts {
    /// regular, bold, italic, bold italic
    faces: [FontVec; 4],
    fallbacks: Vec<FontVec>,
    /// Font size in pixels (already multiplied by the scale).
    px: f32,
    pub cell_w: usize,
    pub cell_h: usize,
    /// Distance from the top of a cell down to the baseline, in pixels.
    baseline: f32,
    /// Characters no font had (reported at the end, so a wrong glyph is never silent).
    pub missing: BTreeSet<char>,
}

fn load(path: &std::path::Path) -> Result<FontVec, String> {
    let bytes = std::fs::read(path).map_err(|e| format!("{}: {e}", path.display()))?;
    FontVec::try_from_vec(bytes).map_err(|e| format!("{}: {e}", path.display()))
}

impl Fonts {
    /// Loads "MesloLGS NF Regular.ttf" and its bold/italic faces from `dir`.
    pub fn load(dir: &std::path::Path, fallbacks: &[String], px: f32) -> Result<Fonts, String> {
        let face = |name: &str| load(&dir.join(format!("MesloLGS NF {name}.ttf")));
        let faces = [face("Regular")?, face("Bold")?, face("Italic")?, face("Bold Italic")?];
        let fallbacks = fallbacks.iter().map(|f| load(std::path::Path::new(f))).collect::<Result<Vec<_>, _>>()?;

        // LEARNER NOTE — font metrics
        //   A font is designed in its own units; `as_scaled` converts them to pixels at a size.
        //   ascent = height above the baseline, descent = below it (negative), and the advance of
        //   a character = how far the pen moves after it. In a monospaced font every advance is
        //   the same, so the advance of "M" is the width of a terminal cell.
        let scaled = faces[0].as_scaled(PxScale::from(px));
        let cell_w = scaled.h_advance(faces[0].glyph_id('M')).round().max(1.0) as usize;
        let height = scaled.ascent() - scaled.descent() + scaled.line_gap();
        let cell_h = height.round().max(1.0) as usize;
        // Any spare pixels from rounding go half above, half below the text.
        let baseline = (scaled.ascent() + (cell_h as f32 - height) / 2.0).round();
        Ok(Fonts { faces, fallbacks, px, cell_w, cell_h, baseline, missing: BTreeSet::new() })
    }
}

// ---------------------------------------------------------------------------
//  The picture
// ---------------------------------------------------------------------------

/// An image as rows of RGB pixels.
pub struct Canvas {
    pub w: usize,
    pub h: usize,
    pub px: Vec<Rgb>,
}

/// Mixes colour `a` towards `b` by `t` (0 = a, 1 = b).
fn mix(a: Rgb, b: Rgb, t: f32) -> Rgb {
    let t = t.clamp(0.0, 1.0);
    let m = |x: u8, y: u8| (x as f32 + (y as f32 - x as f32) * t).round() as u8;
    [m(a[0], b[0]), m(a[1], b[1]), m(a[2], b[2])]
}

/// Coverage is rounded to eighths, so an image uses few distinct colours (a GIF may hold 256)
/// and the same character always comes out the same.
fn steps(c: f32) -> f32 {
    (c.clamp(0.0, 1.0) * 8.0).round() / 8.0
}

impl Canvas {
    pub fn new(w: usize, h: usize, bg: Rgb) -> Canvas {
        Canvas { w, h, px: vec![bg; w * h] }
    }

    fn fill(&mut self, x0: usize, y0: usize, w: usize, h: usize, c: Rgb) {
        for y in y0..(y0 + h).min(self.h) {
            for x in x0..(x0 + w).min(self.w) {
                self.px[y * self.w + x] = c;
            }
        }
    }

    /// Paints colour `c` over pixel (x, y) with coverage `cov` (0..1).
    fn blend(&mut self, x: i64, y: i64, c: Rgb, cov: f32) {
        if x < 0 || y < 0 || x as usize >= self.w || y as usize >= self.h || cov <= 0.0 {
            return;
        }
        let i = y as usize * self.w + x as usize;
        self.px[i] = mix(self.px[i], c, steps(cov));
    }

    /// The image as one flat RGB byte array (what the PNG and GIF encoders want).
    pub fn bytes(&self) -> Vec<u8> {
        self.px.iter().flatten().copied().collect()
    }
}

// ---------------------------------------------------------------------------
//  Characters drawn as shapes
// ---------------------------------------------------------------------------

/// A shape inside one cell: is the point (x, y), in pixels from the cell's top left, inside it?
/// `w`, `h` = the cell size, `t` = the thickness of a thin line.
fn shape_for(ch: char) -> Option<fn(f32, f32, f32, f32, f32) -> bool> {
    // LEARNER NOTE — functions as values
    //   `fn(f32, …) -> bool` is the type of a plain function. Each arm below hands back a small
    //   function (a closure that captures nothing becomes one), and the caller runs it for many
    //   points inside each pixel to work out how much of the pixel the shape covers.
    let s: fn(f32, f32, f32, f32, f32) -> bool = match ch {
        // Light box drawing: arms from the centre to the left/right/up/down edges.
        '─' => |x, y, w, h, t| arms(x, y, w, h, t, [true, true, false, false]),
        '│' => |x, y, w, h, t| arms(x, y, w, h, t, [false, false, true, true]),
        '┌' => |x, y, w, h, t| arms(x, y, w, h, t, [false, true, false, true]),
        '┐' => |x, y, w, h, t| arms(x, y, w, h, t, [true, false, false, true]),
        '└' => |x, y, w, h, t| arms(x, y, w, h, t, [false, true, true, false]),
        '┘' => |x, y, w, h, t| arms(x, y, w, h, t, [true, false, true, false]),
        '├' => |x, y, w, h, t| arms(x, y, w, h, t, [false, true, true, true]),
        '┤' => |x, y, w, h, t| arms(x, y, w, h, t, [true, false, true, true]),
        '┬' => |x, y, w, h, t| arms(x, y, w, h, t, [true, true, false, true]),
        '┴' => |x, y, w, h, t| arms(x, y, w, h, t, [true, true, true, false]),
        '┼' => |x, y, w, h, t| arms(x, y, w, h, t, [true, true, true, true]),
        // Rounded corners: a quarter circle joining two arms.
        '╭' => |x, y, w, h, t| corner(x, y, w, h, t, 1.0, 1.0),
        '╮' => |x, y, w, h, t| corner(x, y, w, h, t, -1.0, 1.0),
        '╯' => |x, y, w, h, t| corner(x, y, w, h, t, -1.0, -1.0),
        '╰' => |x, y, w, h, t| corner(x, y, w, h, t, 1.0, -1.0),
        // Block elements: parts of the cell filled.
        '█' => |_, _, _, _, _| true,
        '▀' => |_, y, _, h, _| y < h / 2.0,
        '▄' => |_, y, _, h, _| y >= h / 2.0,
        '▌' => |x, _, w, _, _| x < w / 2.0,
        '▐' => |x, _, w, _, _| x >= w / 2.0,
        // Powerline separators (Nerd Font private use area), drawn to the exact cell edges so
        // neighbouring segments meet without a seam.
        '\u{e0b0}' => |x, y, w, h, _| x / w <= 1.0 - (2.0 * y / h - 1.0).abs(), // solid ▶
        '\u{e0b2}' => |x, y, w, h, _| x / w >= (2.0 * y / h - 1.0).abs(),       // solid ◀
        '\u{e0b1}' => |x, y, w, h, t| near_chevron(w - x, y, w, h, t),         // thin >
        '\u{e0b3}' => |x, y, w, h, t| near_chevron(x, y, w, h, t),             // thin <
        '\u{e0b4}' => |x, y, w, h, _| ellipse(x, y - h / 2.0, w, h / 2.0) <= 1.0, // solid ◗
        '\u{e0b6}' => |x, y, w, h, _| ellipse(w - x, y - h / 2.0, w, h / 2.0) <= 1.0, // solid ◖
        '\u{e0b5}' => |x, y, w, h, t| ring(x, y - h / 2.0, w, h / 2.0, t),
        '\u{e0b7}' => |x, y, w, h, t| ring(w - x, y - h / 2.0, w, h / 2.0, t),
        '\u{e0b8}' => |x, y, w, h, _| y / h >= x / w,         // ◣
        '\u{e0ba}' => |x, y, w, h, _| y / h >= 1.0 - x / w,   // ◢
        '\u{e0bc}' => |x, y, w, h, _| x / w + y / h <= 1.0,   // ◤
        '\u{e0be}' => |x, y, w, h, _| y / h <= x / w,         // ◥
        '\u{e0b9}' | '\u{e0bf}' => |x, y, w, h, t| near_line(x, y, 0.0, 0.0, w, h, t), // \
        '\u{e0bb}' | '\u{e0bd}' => |x, y, w, h, t| near_line(x, y, 0.0, h, w, 0.0, t), // /
        _ => return None,
    };
    Some(s)
}

/// Straight arms of a box-drawing character: [left, right, up, down].
fn arms(x: f32, y: f32, w: f32, h: f32, t: f32, a: [bool; 4]) -> bool {
    let (cx, cy) = ((w / 2.0).floor(), (h / 2.0).floor());
    let on_h = y >= cy - t / 2.0 && y < cy + t / 2.0;
    let on_v = x >= cx - t / 2.0 && x < cx + t / 2.0;
    (a[0] && on_h && x <= cx + t / 2.0)
        || (a[1] && on_h && x >= cx - t / 2.0)
        || (a[2] && on_v && y <= cy + t / 2.0)
        || (a[3] && on_v && y >= cy - t / 2.0)
}

/// A rounded corner. (dx, dy) point from the centre towards the two arms: ╭ = (1, 1) has its
/// arms to the right and downwards.
fn corner(x: f32, y: f32, w: f32, h: f32, t: f32, dx: f32, dy: f32) -> bool {
    let (cx, cy) = ((w / 2.0).floor(), (h / 2.0).floor());
    let r = (w / 2.0).min(h / 2.0);
    // The circle's centre sits r away from the cell centre, towards both arms.
    let (ox, oy) = (cx + dx * r, cy + dy * r);
    let (px, py) = ((x - ox) * dx, (y - oy) * dy); // flipped so the corner is always "╭"
    if px <= 0.0 && py <= 0.0 {
        let d = (px * px + py * py).sqrt();
        return (d - r).abs() < t / 2.0;
    }
    // Beyond the curve: straight on to the cell edges.
    (px > 0.0 && (y - cy).abs() < t / 2.0) || (py > 0.0 && (x - cx).abs() < t / 2.0)
}

/// Distance of (x, y) from the segment (x0, y0)-(x1, y1), compared with half the thickness.
fn near_line(x: f32, y: f32, x0: f32, y0: f32, x1: f32, y1: f32, t: f32) -> bool {
    let (dx, dy) = (x1 - x0, y1 - y0);
    let k = (((x - x0) * dx + (y - y0) * dy) / (dx * dx + dy * dy)).clamp(0.0, 1.0);
    let (qx, qy) = (x0 + k * dx - x, y0 + k * dy - y);
    (qx * qx + qy * qy).sqrt() < t / 2.0
}

/// The thin chevron "<": from the top right corner to the middle of the left edge and back.
fn near_chevron(x: f32, y: f32, w: f32, h: f32, t: f32) -> bool {
    near_line(x, y, w, 0.0, 0.0, h / 2.0, t) || near_line(x, y, 0.0, h / 2.0, w, h, t)
}

/// (x/a)² + (y/b)²: below 1 inside the ellipse with half-axes a and b.
fn ellipse(x: f32, y: f32, a: f32, b: f32) -> f32 {
    (x / a).powi(2) + (y / b).powi(2)
}

fn ring(x: f32, y: f32, a: f32, b: f32, t: f32) -> bool {
    ellipse(x, y, a, b) <= 1.0 && ellipse(x, y, a - t, b - t) > 1.0 && x >= 0.0
}

/// Shades ░ ▒ ▓: the foreground at a quarter, half, three quarters over the background.
fn shade(ch: char) -> Option<f32> {
    match ch {
        '░' => Some(0.25),
        '▒' => Some(0.5),
        '▓' => Some(0.75),
        _ => None,
    }
}

// ---------------------------------------------------------------------------
//  Drawing a screen
// ---------------------------------------------------------------------------

/// How the cursor is drawn.
#[derive(Clone, Copy, PartialEq)]
pub enum CursorStyle {
    Block,
    Bar,
    None,
}

/// Draws `screen` with `pad` pixels of background around it.
pub fn draw(screen: &Screen, fonts: &mut Fonts, pad: usize, cursor: CursorStyle) -> Canvas {
    let (cw, ch) = (fonts.cell_w, fonts.cell_h);
    let mut cv = Canvas::new(screen.cols * cw + 2 * pad, screen.rows * ch + 2 * pad, crate::screen::DEFAULT_BG);
    let thin = (fonts.px / 12.0).round().max(1.0); // line thickness, as terminals scale it
    let mut cells = screen.cells.clone();

    // A block cursor is the cell in reverse video; a bar is a thin line at its left edge.
    if let (Some((r, c)), CursorStyle::Block) = (screen.cursor, cursor) {
        if let Some(cell) = cells.get_mut(r).and_then(|row| row.get_mut(c)) {
            std::mem::swap(&mut cell.fg, &mut cell.bg);
        }
    }

    // Backgrounds first: a glyph wider than its cell (many icons) may then reach into the next.
    for (r, row) in cells.iter().enumerate() {
        for (c, cell) in row.iter().enumerate() {
            cv.fill(pad + c * cw, pad + r * ch, cw, ch, cell.bg);
        }
    }

    for (r, row) in cells.iter().enumerate() {
        for (c, cell) in row.iter().enumerate() {
            let (x0, y0) = (pad + c * cw, pad + r * ch);
            let Some(chr) = cell.ch.chars().next() else { continue }; // right half of a wide char
            if chr == ' ' {
            } else if let Some(f) = shape_for(chr) {
                // 4×4 sample points per pixel: the share inside the shape = the pixel's coverage.
                for y in 0..ch {
                    for x in 0..cw {
                        let mut n = 0;
                        for sy in 0..4 {
                            for sx in 0..4 {
                                let (fx, fy) = (x as f32 + (sx as f32 + 0.5) / 4.0, y as f32 + (sy as f32 + 0.5) / 4.0);
                                n += f(fx, fy, cw as f32, ch as f32, thin) as u32;
                            }
                        }
                        cv.blend((x0 + x) as i64, (y0 + y) as i64, cell.fg, n as f32 / 16.0);
                    }
                }
            } else if let Some(a) = shade(chr) {
                let c = mix(cell.bg, cell.fg, a);
                cv.fill(x0, y0, cw, ch, c);
            } else {
                glyph(&mut cv, fonts, chr, cell.bold, cell.italic, x0, y0, cell.fg);
            }
            if cell.underline {
                let uy = y0 as f32 + fonts.baseline + (fonts.px / 10.0).round();
                for x in 0..cw {
                    for t in 0..thin as usize {
                        cv.blend((x0 + x) as i64, uy as i64 + t as i64, cell.fg, 1.0);
                    }
                }
            }
        }
    }

    if let (Some((r, c)), CursorStyle::Bar) = (screen.cursor, cursor) {
        let fg = cells.get(r).and_then(|row| row.get(c)).map_or(crate::screen::DEFAULT_FG, |cell| cell.fg);
        cv.fill(pad + c * cw, pad + r * ch, (thin as usize) * 2, ch, fg);
    }
    cv
}

/// Draws one character from the font (or a fallback font) with its baseline in the cell.
fn glyph(cv: &mut Canvas, fonts: &mut Fonts, chr: char, bold: bool, italic: bool, x0: usize, y0: usize, fg: Rgb) {
    let face = &fonts.faces[bold as usize + 2 * italic as usize];
    // GlyphId 0 is the font's "missing character" box: try the regular face, then the fallbacks.
    let font = [face]
        .into_iter()
        .chain(std::iter::once(&fonts.faces[0]))
        .chain(fonts.fallbacks.iter())
        .find(|f| f.glyph_id(chr).0 != 0);
    let Some(font) = font else {
        fonts.missing.insert(chr);
        return;
    };
    let g = font.glyph_id(chr).with_scale_and_position(PxScale::from(fonts.px), point(x0 as f32, y0 as f32 + fonts.baseline));
    if let Some(outline) = font.outline_glyph(g) {
        let b = outline.px_bounds();
        // LEARNER NOTE — rasterising
        //   `draw` calls the closure once per pixel the outline touches, with how much of that
        //   pixel it covers (0..1); the pixel is then mixed towards the text colour by that much.
        outline.draw(|x, y, cov| cv.blend(b.min.x as i64 + x as i64, b.min.y as i64 + y as i64, fg, cov));
    }
}
