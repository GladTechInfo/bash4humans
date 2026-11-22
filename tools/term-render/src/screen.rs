//! A captured screen: tui-capture's JSON read into plain Rust values, and the colour palette.

use serde_json::Value;

/// One colour as red, green, blue.
pub type Rgb = [u8; 3];

/// The terminal's own foreground and background ("default" in the capture).
pub const DEFAULT_FG: Rgb = [0xd4, 0xd7, 0xdd];
pub const DEFAULT_BG: Rgb = [0x16, 0x18, 0x1d];

/// The 16 basic colours, under the names tui-capture (like pyte) gives them. The same palette
/// as the igtop/istop images, so all the project images look alike.
fn named(name: &str) -> Option<Rgb> {
    // LEARNER NOTE — `match` on strings
    //   A `match` compares the string with each literal in turn; `_` catches the rest. Returning
    //   `Option` lets the caller decide what an unknown name means.
    Some(match name {
        "black" => [0x16, 0x18, 0x1d],
        "red" => [0xe0, 0x6c, 0x75],
        "green" => [0x98, 0xc3, 0x79],
        "brown" => [0xe5, 0xc0, 0x7b], // yellow
        "blue" => [0x61, 0xaf, 0xef],
        "magenta" => [0xc6, 0x78, 0xdd],
        "cyan" => [0x56, 0xb6, 0xc2],
        "white" => [0xd4, 0xd7, 0xdd],
        "brightblack" => [0x5c, 0x63, 0x70],
        "brightred" => [0xff, 0x7b, 0x86],
        "brightgreen" => [0xb5, 0xe8, 0x90],
        "brightbrown" => [0xff, 0xd5, 0x8a], // bright yellow
        "brightblue" => [0x82, 0xc4, 0xff],
        "brightmagenta" => [0xde, 0x9c, 0xf0],
        "brightcyan" => [0x7f, 0xd4, 0xde],
        "brightwhite" => [0xff, 0xff, 0xff],
        _ => return None,
    })
}

/// "default", a name, or six hex digits -> a colour.
fn parse_colour(s: &str, default: Rgb) -> Rgb {
    if s == "default" {
        return default;
    }
    if let Some(c) = named(s) {
        return c;
    }
    if s.len() == 6 {
        if let Ok(v) = u32::from_str_radix(s, 16) {
            return [(v >> 16) as u8, (v >> 8) as u8, v as u8];
        }
    }
    default
}

/// One cell of the screen, its colours already worked out (reverse video applied).
#[derive(Clone, PartialEq)]
pub struct Cell {
    /// The character; empty for the right half of a wide character.
    pub ch: String,
    pub fg: Rgb,
    pub bg: Rgb,
    pub bold: bool,
    pub italic: bool,
    pub underline: bool,
}

/// A whole screen (or the part of it that was cropped).
#[derive(Clone, PartialEq)]
pub struct Screen {
    pub rows: usize,
    pub cols: usize,
    pub cells: Vec<Vec<Cell>>,
    /// Where the cursor is (row, column), when it is shown.
    pub cursor: Option<(usize, usize)>,
}

impl Screen {
    /// Reads tui-capture's JSON: {"grid": [[[ch, fg, bg, bold, reverse, italic?, underline?], …], …],
    /// "cursor"?: [row, col], "cursor_visible"?: bool}.
    pub fn from_json(v: &Value) -> Result<Screen, String> {
        let grid = v["grid"].as_array().ok_or("no \"grid\" in the snapshot")?;
        let mut cells = Vec::new();
        for row in grid {
            let row = row.as_array().ok_or("a grid row is not an array")?;
            let mut line = Vec::new();
            for c in row {
                let c = c.as_array().ok_or("a cell is not an array")?;
                // `get(i)` gives None past the end, so older five-field captures still work.
                let text = |i: usize| c.get(i).and_then(Value::as_str).unwrap_or("default");
                let flag = |i: usize| c.get(i).and_then(Value::as_bool).unwrap_or(false);
                let mut fg = parse_colour(text(1), DEFAULT_FG);
                let mut bg = parse_colour(text(2), DEFAULT_BG);
                if flag(4) {
                    std::mem::swap(&mut fg, &mut bg); // reverse video
                }
                line.push(Cell {
                    ch: c.first().and_then(Value::as_str).unwrap_or(" ").to_string(),
                    fg,
                    bg,
                    bold: flag(3),
                    italic: flag(5),
                    underline: flag(6),
                });
            }
            cells.push(line);
        }
        let rows = cells.len();
        let cols = cells.first().map_or(0, Vec::len);
        let visible = v["cursor_visible"].as_bool().unwrap_or(false);
        let cursor = match v["cursor"].as_array() {
            Some(rc) if visible && rc.len() == 2 => {
                Some((rc[0].as_u64().unwrap_or(0) as usize, rc[1].as_u64().unwrap_or(0) as usize))
            }
            _ => None,
        };
        Ok(Screen { rows, cols, cells, cursor })
    }

    /// Keeps rows r0..=r1 and columns c0..=c1 (clamped to the screen).
    pub fn crop(&self, r0: usize, c0: usize, r1: usize, c1: usize) -> Screen {
        let r1 = r1.min(self.rows.saturating_sub(1));
        let c1 = c1.min(self.cols.saturating_sub(1));
        let cells: Vec<Vec<Cell>> = self.cells[r0..=r1].iter().map(|row| row[c0..=c1].to_vec()).collect();
        let cursor = self
            .cursor
            .filter(|&(r, c)| r >= r0 && r <= r1 && c >= c0 && c <= c1)
            .map(|(r, c)| (r - r0, c - c0));
        Screen { rows: r1 - r0 + 1, cols: c1 - c0 + 1, cells, cursor }
    }

    /// The screen as plain text, one line per row (for checking what an image shows).
    pub fn text(&self) -> String {
        let mut out = String::new();
        for row in &self.cells {
            let line: String = row.iter().map(|c| c.ch.as_str()).collect();
            out.push_str(line.trim_end());
            out.push('\n');
        }
        out
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn colours() {
        assert_eq!(parse_colour("default", DEFAULT_FG), DEFAULT_FG);
        assert_eq!(parse_colour("ff8700", DEFAULT_FG), [0xff, 0x87, 0x00]);
        assert_eq!(parse_colour("brightbrown", DEFAULT_FG), [0xff, 0xd5, 0x8a]);
    }

    #[test]
    fn reverse_and_old_cells() {
        let v: Value = serde_json::from_str(r#"{"grid": [[["a", "red", "default", false, true]]]}"#).unwrap();
        let s = Screen::from_json(&v).unwrap();
        assert_eq!(s.cells[0][0].fg, DEFAULT_BG);
        assert_eq!(s.cells[0][0].bg, named("red").unwrap());
        assert!(!s.cells[0][0].underline);
    }
}
