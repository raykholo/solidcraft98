//! Shared layout, hit testing and input state. Core commands are returned as
//! actions so a board or desktop host can connect its own model adapter.
use crate::{
    draw::*,
    framebuffer::{Color, Framebuffer},
    model::Part,
    view::{self, RenderError, Style, View, Visibility},
    widgets::{self, ButtonState, MessageKind},
    Scalar,
};

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Layout {
    Classic,
    Compact,
}
impl Layout {
    pub const fn size(self) -> (usize, usize) {
        match self {
            Self::Classic => (640, 480),
            Self::Compact => (320, 240),
        }
    }
    pub fn viewport(self) -> Rect {
        match self {
            Self::Classic => Rect::new(174, 99, 452, 235),
            Self::Compact => Rect::new(6, 66, 308, 148),
        }
    }
    pub fn tree_rect(self) -> Rect {
        match self {
            Self::Classic => Rect::new(8, 97, 160, 239),
            Self::Compact => Rect::new(6, 108, 150, 74),
        }
    }
    pub fn timeline_rect(self) -> Rect {
        match self {
            Self::Classic => Rect::new(8, 340, 620, 110),
            Self::Compact => Rect::new(6, 184, 308, 32),
        }
    }
    fn tools(self) -> Rect {
        match self {
            Self::Classic => Rect::new(0, 41, 640, 29),
            Self::Compact => Rect::new(4, 44, 312, 61),
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Command {
    New,
    Open,
    Save,
    SaveAs,
    Floppy,
    Publish,
    Export,
    Close,
    Exit,
    Undo,
    Edit,
    Delete,
    Rectangle,
    Circle,
    Extrude,
    Revolve,
    Hole,
    Isometric,
    Fit,
    Regenerate,
    Shaded,
    Turbo,
    Cascade,
    TileH,
    TileV,
    Help,
    About,
}
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Action {
    None,
    Command(Command),
    Parameters {
        command: Command,
        values: [f64; 7],
        count: usize,
    },
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Escape,
    Enter,
    Tab,
    Backspace,
    Delete,
    Up,
    Down,
    Left,
    Right,
    Plus,
    Minus,
    Character(char),
    F1,
    F5,
}
#[derive(Clone, Copy, Debug)]
pub enum Event {
    Click { x: i32, y: i32 },
    Hover { x: i32, y: i32 },
    Orbit { dx: Scalar, dy: Scalar },
    Pan { dx: Scalar, dy: Scalar },
    Zoom(Scalar),
    Key(Key),
    Text(char),
}
#[derive(Clone, Copy, Debug)]
pub struct MenuItem {
    pub label: &'static str,
    pub shortcut: &'static str,
    pub command: Command,
}
macro_rules! item {
    ($label:literal,$shortcut:literal,$cmd:ident) => {
        MenuItem {
            label: $label,
            shortcut: $shortcut,
            command: Command::$cmd,
        }
    };
}
pub const MENU_TITLES: [&str; 7] = [
    "&File",
    "&Edit",
    "&Sketch",
    "F&eatures",
    "&View",
    "&Window",
    "&Help",
];
pub const MENUS: [&[MenuItem]; 7] = [
    &[
        item!("&New Part", "Ctrl+N", New),
        item!("&Open...", "Ctrl+O", Open),
        item!("&Save", "Ctrl+S", Save),
        item!("Save &As...", "", SaveAs),
        item!("Sen&d To 3 1/2 Floppy (A:)...", "", Floppy),
        item!("Publish to &Web...", "", Publish),
        item!("Export for &Rapid Prototyping (*.stl)...", "", Export),
        item!("&Close", "", Close),
        item!("E&xit", "", Exit),
    ],
    &[
        item!("&Undo Last Feature", "Ctrl+Z", Undo),
        item!("&Edit Feature...", "Enter", Edit),
        item!("&Delete Feature", "Del", Delete),
    ],
    &[
        item!("&Rectangle...", "R", Rectangle),
        item!("&Circle...", "C", Circle),
    ],
    &[
        item!("&Extrude...", "E", Extrude),
        item!("Re&volve...", "V", Revolve),
        item!("&Hole...", "H", Hole),
    ],
    &[
        item!("&Isometric", "I", Isometric),
        item!("Zoom to &Fit", "F", Fit),
        item!("&Regenerate", "F5", Regenerate),
        item!("&Shaded", "S", Shaded),
        item!("&Turbo", "", Turbo),
    ],
    &[
        item!("&Cascade", "", Cascade),
        item!("Tile &Horizontally", "", TileH),
        item!("Tile &Vertically", "", TileV),
    ],
    &[
        item!("&Contents", "F1", Help),
        item!("&About SolidCraft 98...", "", About),
    ],
];
pub const TOOLS: [(&str, Command); 13] = [
    ("New", Command::New),
    ("Open", Command::Open),
    ("Save", Command::Save),
    ("SketchRect", Command::Rectangle),
    ("SketchCircle", Command::Circle),
    ("Extrude", Command::Extrude),
    ("Revolve", Command::Revolve),
    ("Hole", Command::Hole),
    ("Orbit", Command::Isometric),
    ("Shaded", Command::Shaded),
    ("ZoomFit", Command::Fit),
    ("Regen", Command::Regenerate),
    ("Turbo", Command::Turbo),
];

#[derive(Clone, Copy, Debug)]
struct Number {
    bytes: [u8; 24],
    len: usize,
}
impl Number {
    const fn new() -> Self {
        Self {
            bytes: [0; 24],
            len: 0,
        }
    }
    fn set(&mut self, t: &str) {
        self.len = t.len().min(24);
        self.bytes[..self.len].copy_from_slice(&t.as_bytes()[..self.len]);
    }
    fn text(&self) -> &str {
        core::str::from_utf8(&self.bytes[..self.len]).unwrap_or("")
    }
    fn push(&mut self, ch: char) {
        if self.len < 24
            && (ch.is_ascii_digit()
                || matches!(
                    ch,
                    '.' | '-' | '+' | 'e' | 'E' | '*' | '/' | '(' | ')' | ' '
                ))
        {
            self.bytes[self.len] = ch as u8;
            self.len += 1;
        }
    }
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Dialog {
    None,
    Message,
    Numbers(Command),
}

pub struct App {
    pub layout: Layout,
    pub view: View,
    pub style: Style,
    pub drawer: bool,
    pub selected: Option<usize>,
    pub menu: Option<usize>,
    pub hot_item: usize,
    pub dialog: Dialog,
    pub turbo: bool,
    pub status: &'static str,
    pub message: &'static str,
    /// Number evaluator supplied by the program (for arithmetic expressions).
    pub evaluate: fn(&str) -> Result<f64, u8>,
    numbers: [Number; 7],
    field: usize,
    field_count: usize,
    top: usize,
}
impl App {
    pub fn new<P: Part + ?Sized>(layout: Layout, p: &P) -> Self {
        let mut view = View::default();
        view.fit(layout.viewport(), p);
        Self {
            layout,
            view,
            style: Style::Shaded,
            drawer: false,
            selected: None,
            menu: None,
            hot_item: 0,
            dialog: Dialog::None,
            turbo: false,
            status: "Ready",
            message: "",
            evaluate: |text| text.parse::<f64>().map_err(|_| 13),
            numbers: [Number::new(); 7],
            field: 0,
            field_count: 0,
            top: 0,
        }
    }
    pub fn menu_rect(&self, index: usize) -> Rect {
        let (w, _) = self.layout.size();
        let mut x = 2;
        for title in MENU_TITLES.iter().take(index) {
            x += caption_width(title) + 14;
        }
        let width = MENUS[index]
            .iter()
            .map(|i| caption_width(i.label) + text_width(i.shortcut, false) + 48)
            .max()
            .unwrap_or(120)
            .min(w as i32 - 4);
        Rect::new(
            x.min(w as i32 - width - 2),
            41,
            width,
            MENUS[index].len() as i32 * 17 + 6,
        )
    }
    pub fn tool_rect(&self, i: usize) -> Rect {
        let t = self.layout.tools();
        if self.layout == Layout::Compact {
            Rect::new(
                t.x + 6 + (i % 10) as i32 * 25,
                t.y + 3 + (i / 10) as i32 * 27,
                23,
                23,
            )
        } else {
            let separators = [3, 5, 8, 12].iter().filter(|&&at| at <= i).count();
            Rect::new(4 + i as i32 * 24 + separators as i32 * 8, t.y + 3, 24, 23)
        }
    }

    pub fn dialog_rect(&self) -> Rect {
        let (w, h) = self.layout.size();
        let dw = if matches!(self.dialog, Dialog::Numbers(_)) {
            318
        } else {
            300
        };
        let dh = if matches!(self.dialog, Dialog::Numbers(_)) {
            84 + self.visible_fields() as i32 * 32
                + if self.layout == Layout::Compact && self.field_count > 3 {
                    17
                } else {
                    0
                }
        } else {
            142
        };
        Rect::new((w as i32 - dw) / 2, (h as i32 - dh) / 2, dw, dh)
    }
    pub fn event<P: Part + ?Sized>(&mut self, e: Event, p: &P) -> Action {
        if self.dialog != Dialog::None {
            return self.dialog_event(e);
        }
        match e {
            Event::Orbit { dx, dy } => {
                self.view.orbit(dx, dy);
            }
            Event::Pan { dx, dy } => {
                self.view.pan_x += dx;
                self.view.pan_y += dy;
            }
            Event::Zoom(f) => self.view.zoom_by(f),
            Event::Hover { x, y } => {
                if let Some(m) = self.menu {
                    let r = self.menu_rect(m);
                    if r.contains(x, y) {
                        self.hot_item = ((y - r.y - 3).max(0) / 17) as usize;
                        self.hot_item = self.hot_item.min(MENUS[m].len() - 1);
                    }
                }
            }
            Event::Click { x, y } => {
                if (22..41).contains(&y) {
                    let mut xx = 2;
                    for (i, title) in MENU_TITLES.iter().enumerate() {
                        let w = caption_width(title) + 14;
                        if (xx..xx + w).contains(&x) {
                            self.menu = if self.menu == Some(i) { None } else { Some(i) };
                            self.hot_item = 0;
                            return Action::None;
                        }
                        xx += w;
                    }
                }
                if let Some(m) = self.menu {
                    let r = self.menu_rect(m);
                    self.menu = None;
                    if r.contains(x, y) {
                        let i = ((y - r.y - 3).max(0) / 17) as usize;
                        if let Some(item) = MENUS[m].get(i) {
                            return self.command(item.command, p);
                        }
                    }
                    return Action::None;
                }
                if self.layout == Layout::Compact
                    && ((!self.drawer && Rect::new(6, 43, 98, 20).contains(x, y))
                        || (self.drawer && Rect::new(220, 74, 88, 23).contains(x, y)))
                {
                    self.drawer = !self.drawer;
                    return Action::None;
                }
                if self.layout == Layout::Classic || self.drawer {
                    for (i, (_, cmd)) in TOOLS.iter().enumerate() {
                        if self.tool_rect(i).contains(x, y) {
                            return self.command(*cmd, p);
                        }
                    }
                }
                if self.layout == Layout::Classic || self.drawer {
                    let r = self.layout.tree_rect();
                    if r.contains(x, y) && y >= r.y + 20 {
                        let i = self.top + ((y - r.y - 20) / 16) as usize;
                        if i < p.features().len() {
                            self.selected = Some(i);
                        }
                    }
                }
                let r = self.layout.timeline_rect();
                if (self.layout == Layout::Classic || self.drawer)
                    && r.contains(x, y)
                    && y >= r.y + 20
                {
                    let i = self.top + ((y - r.y - 20) / 15) as usize;
                    if i < p.features().len() {
                        self.selected = Some(i);
                    }
                }
            }
            Event::Key(key) => {
                if let Some(m) = self.menu {
                    match key {
                        Key::Escape => self.menu = None,
                        Key::Down => self.hot_item = (self.hot_item + 1) % MENUS[m].len(),
                        Key::Up => {
                            self.hot_item = (self.hot_item + MENUS[m].len() - 1) % MENUS[m].len()
                        }
                        Key::Left => {
                            self.menu = Some((m + 6) % 7);
                            self.hot_item = 0;
                        }
                        Key::Right => {
                            self.menu = Some((m + 1) % 7);
                            self.hot_item = 0;
                        }
                        Key::Enter => {
                            self.menu = None;
                            return self.command(MENUS[m][self.hot_item].command, p);
                        }
                        Key::Character(ch) => {
                            if let Some(item) = MENUS[m]
                                .iter()
                                .find(|item| mnemonic(item.label) == Some(ch.to_ascii_lowercase()))
                            {
                                self.menu = None;
                                return self.command(item.command, p);
                            }
                        }
                        _ => {}
                    }
                    return Action::None;
                }
                match key {
                    Key::Escape => self.drawer = false,
                    Key::Tab => self.drawer = !self.drawer,
                    Key::Up | Key::Down => {
                        if !p.features().is_empty() {
                            let i = self.selected.unwrap_or(0);
                            let i = if key == Key::Down {
                                (i + 1).min(p.features().len() - 1)
                            } else {
                                i.saturating_sub(1)
                            };
                            self.selected = Some(i);
                            self.top = i.saturating_sub(if self.layout == Layout::Compact {
                                2
                            } else {
                                10
                            });
                        }
                    }
                    Key::Plus => self.view.zoom_by(1.1),
                    Key::Minus => self.view.zoom_by(1. / 1.1),
                    Key::Enter => return self.command(Command::Edit, p),
                    Key::Delete => return self.command(Command::Delete, p),
                    Key::F1 => return self.command(Command::Help, p),
                    Key::F5 => return self.command(Command::Regenerate, p),
                    Key::Character(ch) => {
                        let cmd = match ch.to_ascii_lowercase() {
                            's' => Some(Command::Shaded),
                            'i' => Some(Command::Isometric),
                            'f' => Some(Command::Fit),
                            'r' => Some(Command::Rectangle),
                            'c' => Some(Command::Circle),
                            'e' => Some(Command::Extrude),
                            'v' => Some(Command::Revolve),
                            'h' => Some(Command::Hole),
                            _ => None,
                        };
                        if let Some(cmd) = cmd {
                            return self.command(cmd, p);
                        }
                    }
                    _ => {}
                }
            }
            Event::Text(_) => {}
        }
        Action::None
    }
    pub fn command<P: Part + ?Sized>(&mut self, command: Command, p: &P) -> Action {
        match command {
            Command::Shaded => {
                self.style = if self.style == Style::Shaded {
                    Style::Wireframe
                } else {
                    Style::Shaded
                }
            }
            Command::Isometric => {
                self.view = View::default();
                self.view.fit(self.layout.viewport(), p);
            }
            Command::Fit => self.view.fit(self.layout.viewport(), p),
            Command::Turbo => {
                self.turbo = !self.turbo;
                self.status = if self.turbo {
                    "Turbo quality. Please wait."
                } else {
                    "Ready"
                };
            }
            Command::Help => {
                self.dialog = Dialog::Message;
                self.message =
                    "Cannot find SC98.HLP.\nHelp is not installed.\nYou are on your own.";
            }
            Command::About => {
                self.dialog = Dialog::Message;
                self.message = "SolidCraft 98\nProfessional Edition\nBuild 1998.1023";
            }
            Command::Rectangle
            | Command::Circle
            | Command::Extrude
            | Command::Revolve
            | Command::Hole
            | Command::Edit => {
                self.field_count = field_names(command).len();
                self.field = 0;
                self.dialog = Dialog::Numbers(command);
                for (i, n) in self.numbers.iter_mut().enumerate() {
                    n.set(if i == 0 { "20" } else { "0" });
                }
            }
            Command::Regenerate => self.status = "Regenerated. The solver used a Variant.",
            _ => {}
        }
        Action::Command(command)
    }
    /// Start a number dialog using the model's current values. Editing an
    /// existing feature uses its kind so all of its parameters remain visible.
    pub fn set_parameters(&mut self, command: Command, values: &[&str]) {
        self.field_count = field_names(command).len();
        self.field = 0;
        self.dialog = Dialog::Numbers(command);
        for (i, number) in self.numbers.iter_mut().enumerate() {
            number.set(values.get(i).copied().unwrap_or("0"));
        }
    }
    /// Hosts can evaluate arithmetic before accepting a number dialog.
    pub fn parameter_texts(&self) -> [&str; 7] {
        core::array::from_fn(|i| self.numbers[i].text())
    }
    pub fn parameter_count(&self) -> usize {
        self.field_count
    }
    fn visible_fields(&self) -> usize {
        if self.layout == Layout::Compact {
            self.field_count.min(3)
        } else {
            self.field_count
        }
    }
    fn field_start(&self) -> usize {
        if self.layout == Layout::Compact {
            (self.field / 3) * 3
        } else {
            0
        }
    }
    fn dialog_event(&mut self, e: Event) -> Action {
        let r = self.dialog_rect();
        match e {
            Event::Key(Key::Escape) => self.dialog = Dialog::None,
            Event::Key(Key::Enter) => return self.accept(),
            Event::Text(ch) => {
                if matches!(self.dialog, Dialog::Numbers(_)) {
                    self.numbers[self.field].push(ch);
                }
            }
            Event::Key(Key::Backspace) => {
                self.numbers[self.field].len = self.numbers[self.field].len.saturating_sub(1)
            }
            Event::Key(Key::Tab) => {
                if self.field_count > 0 {
                    self.field = (self.field + 1) % self.field_count;
                }
            }
            Event::Click { x, y } => {
                if Rect::new(r.x + r.w - 21, r.y + 5, 16, 14).contains(x, y) {
                    self.dialog = Dialog::None;
                } else if matches!(self.dialog, Dialog::Message) {
                    if Rect::new(r.x + (r.w - 75) / 2, r.y + r.h - 36, 75, 23).contains(x, y) {
                        return self.accept();
                    }
                } else if matches!(self.dialog, Dialog::Numbers(_)) {
                    if self.layout == Layout::Compact
                        && self.field_count > 3
                        && Rect::new(r.x + 16, r.y + r.h - 59, 110, 18).contains(x, y)
                    {
                        let next = self.field_start() + 3;
                        self.field = if next >= self.field_count { 0 } else { next };
                        return Action::None;
                    }
                    let start = self.field_start();
                    for i in 0..self.visible_fields().min(self.field_count - start) {
                        if Rect::new(r.x + r.w - 112, r.y + 39 + i as i32 * 32, 96, 21)
                            .contains(x, y)
                        {
                            self.field = start + i;
                        }
                    }
                    if (r.y + r.h - 39..r.y + r.h - 16).contains(&y) {
                        if (r.x + r.w - 253..r.x + r.w - 178).contains(&x) {
                            return self.accept();
                        }
                        if (r.x + r.w - 172..r.x + r.w - 97).contains(&x) {
                            self.dialog = Dialog::None;
                        }
                        if (r.x + r.w - 91..r.x + r.w - 16).contains(&x) {
                            self.status = "Help is not installed.";
                        }
                    }
                }
            }
            _ => {}
        }
        Action::None
    }
    fn accept(&mut self) -> Action {
        if let Dialog::Numbers(command) = self.dialog {
            let mut values = [0.; 7];
            for (i, n) in self.numbers.iter().take(self.field_count).enumerate() {
                match (self.evaluate)(n.text()) {
                    Ok(v) if v.is_finite() => values[i] = v,
                    Err(11) => {
                        self.status = "Run-time error '11': Division by zero";
                        self.field = i;
                        return Action::None;
                    }
                    _ => {
                        self.status = "Run-time error '13': Type mismatch";
                        self.field = i;
                        return Action::None;
                    }
                }
            }
            self.dialog = Dialog::None;
            return Action::Parameters {
                command,
                values,
                count: self.field_count,
            };
        }
        self.dialog = Dialog::None;
        Action::None
    }
    pub fn render<F: Framebuffer, P: Part + ?Sized>(
        &self,
        fb: &mut F,
        p: &P,
        visibility: Visibility<'_>,
    ) -> Result<(), RenderError> {
        let (w, h) = self.layout.size();
        let w = w as i32;
        let h = h as i32;
        let mut c = Canvas::new(fb);
        widgets::window(&mut c, Rect::new(0, 0, w, h), "SolidCraft 98", true, true);
        c.fill(Rect::new(0, 22, w, 19), FACE);
        let mut x = 2;
        for (i, title) in MENU_TITLES.iter().enumerate() {
            let tw = caption_width(title) + 14;
            if self.menu == Some(i) {
                c.bevel(Rect::new(x, 23, tw, 17), Bevel::ThinDown);
            }
            c.caption(x + 7, 26, title, BLACK, false);
            x += tw;
        }
        if self.layout == Layout::Classic {
            c.fill(self.layout.tools(), FACE);
            c.hline(0, 41, w, WHITE);
            c.hline(0, 69, w, SHADOW);
            self.draw_tools(&mut c);
            widgets::window(&mut c, Rect::new(4, 73, 632, 383), p.name(), true, true);
            widgets::tree(&mut c, self.layout.tree_rect(), p, self.selected, self.top);
            widgets::timeline(
                &mut c,
                self.layout.timeline_rect(),
                p,
                self.selected,
                self.top,
            );
        } else {
            widgets::button(
                &mut c,
                Rect::new(6, 43, 98, 20),
                if self.drawer {
                    "Close drawer"
                } else {
                    "Tools / Features"
                },
                ButtonState::default(),
            );
            c.text(115, 48, p.name(), BLACK, false);
        }
        let vr = self.layout.viewport();
        c.bevel(
            Rect::new(vr.x - 2, vr.y - 2, vr.w + 4, vr.h + 4),
            Bevel::Sunken,
        );
        view::render(&mut c, vr, p, &self.view, self.style, visibility)?;
        if self.layout == Layout::Compact && self.drawer {
            let r = Rect::new(4, 43, 312, 175);
            c.fill(r, FACE);
            c.bevel(r, Bevel::Raised);
            self.draw_tools(&mut c);
            widgets::button(
                &mut c,
                Rect::new(220, 74, 88, 23),
                "Close drawer",
                ButtonState::default(),
            );
            widgets::tree(&mut c, self.layout.tree_rect(), p, self.selected, self.top);
            c.text(165, 115, "Feature history", BLACK, true);
            c.text(165, 133, "Up / Down: select", BLACK, false);
            c.text(165, 149, "Enter: edit", BLACK, false);
            c.text(165, 165, "Tab: close drawer", BLACK, false);
            widgets::timeline(
                &mut c,
                self.layout.timeline_rect(),
                p,
                self.selected,
                self.top,
            );
        }
        widgets::status_bar(&mut c, Rect::new(0, h - 22, w, 22), self.status, self.turbo);
        if let Some(m) = self.menu {
            let r = self.menu_rect(m);
            c.fill(r, FACE);
            c.bevel(r, Bevel::Raised);
            let old = c.set_clip(r.inset(3));
            for (i, item) in MENUS[m].iter().enumerate() {
                let y = r.y + 3 + i as i32 * 17;
                let hot = i == self.hot_item;
                let color = if hot { WHITE } else { BLACK };
                if hot {
                    c.fill(Rect::new(r.x + 3, y, r.w - 6, 17), SELECT);
                }
                let checked = (item.command == Command::Shaded && self.style == Style::Shaded)
                    || (item.command == Command::Turbo && self.turbo);
                if checked {
                    c.text(r.x + 6, y + 3, "x", color, false);
                }
                c.caption(r.x + 20, y + 3, item.label, color, false);
                if r.w > 250 {
                    c.text(
                        r.x + r.w - 12 - text_width(item.shortcut, false),
                        y + 3,
                        item.shortcut,
                        color,
                        false,
                    );
                }
            }
            c.set_clip(old);
        }
        match self.dialog {
            Dialog::None => {}
            Dialog::Message => widgets::message_box(
                &mut c,
                self.dialog_rect(),
                "SolidCraft 98",
                self.message,
                MessageKind::Info,
            ),
            Dialog::Numbers(command) => {
                let names = field_names(command);
                let mut fields = [("", ""); 7];
                let start = self.field_start();
                let count = self.visible_fields().min(self.field_count - start);
                for i in 0..count {
                    fields[i] = (names[start + i], self.numbers[start + i].text());
                }
                widgets::number_dialog(
                    &mut c,
                    self.dialog_rect(),
                    command_title(command),
                    &fields[..count],
                    self.field - start,
                );
                if self.layout == Layout::Compact && self.field_count > 3 {
                    let r = self.dialog_rect();
                    widgets::button(
                        &mut c,
                        Rect::new(r.x + 16, r.y + r.h - 59, 110, 18),
                        "More fields >",
                        ButtonState::default(),
                    );
                }
            }
        }
        Ok(())
    }
    fn draw_tools<F: Framebuffer>(&self, c: &mut Canvas<'_, F>) {
        for (i, (icon, cmd)) in TOOLS.iter().enumerate() {
            let r = self.tool_rect(i);
            if (*cmd == Command::Shaded && self.style == Style::Shaded)
                || (*cmd == Command::Turbo && self.turbo)
            {
                c.bevel(r, Bevel::ThinDown);
            }
            c.icon(r.x + 3, r.y + 3, icon, false);
        }
        if self.layout == Layout::Classic {
            for i in [3, 5, 8, 12] {
                let x = self.tool_rect(i).x - 5;
                c.vline(x, 45, 22, SHADOW);
                c.vline(x + 1, 45, 22, WHITE);
            }
            let x = self.tool_rect(12).x + 30;
            c.bevel(Rect::new(x, 45, 32, 21), Bevel::ThinDown);
            c.fill(Rect::new(x + 1, 46, 30, 19), Color::rgb(24, 0, 0));
            widgets::seven_segment(c, x + 4, 48, if self.turbo { 3 } else { 6 });
            widgets::seven_segment(c, x + 17, 48, if self.turbo { 3 } else { 6 });
            c.text(x + 35, 50, "MHz", BLACK, false);
        }
    }
}
fn mnemonic(t: &str) -> Option<char> {
    let mut chars = t.chars();
    while let Some(c) = chars.next() {
        if c == '&' {
            return chars.next().map(|c| c.to_ascii_lowercase());
        }
    }
    None
}
fn field_names(c: Command) -> &'static [&'static str] {
    match c {
        Command::Rectangle => &[
            "Width (mm)",
            "Height (mm)",
            "Corner X (mm)",
            "Corner Y (mm)",
            "Corner radius (mm)",
            "On feature # (0 = ground)",
            "Height above (mm)",
        ],
        Command::Circle => &[
            "Radius (mm)",
            "Centre X (mm)",
            "Centre Y (mm)",
            "On feature # (0 = ground)",
            "Height above (mm)",
        ],
        Command::Revolve => &["Angle (degrees)"],
        Command::Hole => &[
            "Diameter (mm)",
            "Depth (0 = through all)",
            "Centre X",
            "Centre Y",
        ],
        _ => &["Depth (mm)"],
    }
}
fn command_title(c: Command) -> &'static str {
    match c {
        Command::Rectangle => "Sketch Rectangle",
        Command::Circle => "Sketch Circle",
        Command::Extrude => "Extrude",
        Command::Revolve => "Revolve",
        Command::Hole => "Hole",
        _ => "Edit Feature",
    }
}
