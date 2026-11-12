//! SolidCraft 98's single-threaded program, shared by terminal and board hosts.
#![no_std]
#![forbid(unsafe_code)]
extern crate alloc;

use alloc::{
    format,
    string::{String, ToString},
    vec,
    vec::Vec,
};
use sc98_core::{Feature, FeatureKind as K, Part};
pub use sc98_pixels::app::{Command, Layout};
use sc98_pixels::{
    app::{self, Action, Dialog, Event as UiEvent, Key as UiKey},
    draw::{Canvas, Rect},
    framebuffer::{Color, Framebuffer},
    model::{self, Part as PixelPart, Triangle, Vec3},
    view::Visibility,
    widgets::{self, ButtonState},
};
use sc98_term::{Button, Event, Frame, Key, Modifiers, MouseKind, Size, Wheel};

/// Storage names are supplied by the user; hosts decide how to resolve them.
pub trait Storage {
    type Error;
    fn load(&mut self, name: &str) -> Result<Vec<u8>, Self::Error>;
    fn save(&mut self, name: &str, bytes: &[u8]) -> Result<(), Self::Error>;
}

/// Small bounded file store for boards. Contents are lost on reset.
pub struct RamStorage {
    files: Vec<(String, Vec<u8>)>,
    limit: usize,
}
#[derive(Debug, PartialEq, Eq)]
pub enum RamError {
    NotFound,
    Full,
}
impl RamStorage {
    pub fn new(limit: usize) -> Self {
        Self {
            files: Vec::new(),
            limit,
        }
    }
    pub fn used(&self) -> usize {
        self.files.iter().map(|(_, b)| b.len()).sum()
    }
}
impl Storage for RamStorage {
    type Error = RamError;
    fn load(&mut self, name: &str) -> Result<Vec<u8>, RamError> {
        self.files
            .iter()
            .find(|(n, _)| n == name)
            .map(|(_, b)| b.clone())
            .ok_or(RamError::NotFound)
    }
    fn save(&mut self, name: &str, bytes: &[u8]) -> Result<(), RamError> {
        let old = self
            .files
            .iter()
            .find(|(n, _)| n == name)
            .map_or(0, |(_, b)| b.len());
        if self.used() - old + bytes.len() > self.limit
            || (old == 0 && !self.files.iter().any(|(n, _)| n == name) && self.files.len() >= 8)
            || name.len() > 240
        {
            return Err(RamError::Full);
        }
        if let Some((_, b)) = self.files.iter_mut().find(|(n, _)| n == name) {
            *b = bytes.to_vec();
        } else {
            self.files.push((name.to_string(), bytes.to_vec()));
        }
        Ok(())
    }
}

#[derive(Debug)]
pub enum Error<E> {
    Core(sc98_core::Error),
    Storage(E),
    Render(sc98_pixels::view::RenderError),
    Buffer,
    InvalidParameters,
    Expression(u8),
    NoSelection,
    NoSketch,
    NoSolid,
    Unsupported,
    MeshWarnings,
}
impl<E> From<sc98_core::Error> for Error<E> {
    fn from(e: sc98_core::Error) -> Self {
        Self::Core(e)
    }
}

/// Borrowed adapter for the real core types; no self-referential feature names.
pub struct PartAdapter<'a> {
    pub part: &'a Part,
    features: Vec<model::Feature<'a>>,
    triangles: &'a [Triangle],
    edges: &'a [model::Edge],
}
impl<'a> PartAdapter<'a> {
    pub fn new(part: &'a Part, triangles: &'a [Triangle], edges: &'a [model::Edge]) -> Self {
        let features = part
            .features()
            .iter()
            .map(|f| model::Feature {
                name: &f.name,
                kind: match f.kind {
                    K::Rectangle => model::FeatureKind::Rectangle,
                    K::Circle => model::FeatureKind::Circle,
                    K::Extrude => model::FeatureKind::Extrude,
                    K::Revolve => model::FeatureKind::Revolve,
                    K::Hole => model::FeatureKind::Hole,
                    _ => model::FeatureKind::Unsupported,
                },
            })
            .collect();
        Self {
            part,
            features,
            triangles,
            edges,
        }
    }
}
impl PixelPart for PartAdapter<'_> {
    fn name(&self) -> &str {
        &self.part.title
    }
    fn features(&self) -> &[model::Feature<'_>] {
        &self.features
    }
    fn triangles(&self) -> &[Triangle] {
        self.triangles
    }
    fn edges(&self) -> &[model::Edge] {
        self.edges
    }
}
fn point(p: [f32; 3]) -> Vec3 {
    Vec3::new(p[0], p[1], p[2])
}
fn colour(c: u32) -> Color {
    Color::rgb((c >> 16) as u8, (c >> 8) as u8, c as u8)
}
fn kind_command(k: K) -> Option<Command> {
    Some(match k {
        K::Rectangle => Command::Rectangle,
        K::Circle => Command::Circle,
        K::Extrude => Command::Extrude,
        K::Revolve => Command::Revolve,
        K::Hole => Command::Hole,
        _ => return None,
    })
}
fn values(f: &Feature) -> Vec<f64> {
    match f.kind {
        K::Rectangle => vec![f.p1, f.p2, f.x, f.y, f.p3, f.reference as f64, f.z],
        K::Circle => vec![f.p1, f.x, f.y, f.reference as f64, f.z],
        K::Hole => vec![f.p1, f.p2, f.x, f.y],
        _ => vec![f.p1],
    }
}

/// Storage format for the app's framebuffer. The PC uses RGB565; small boards
/// can use RGB332 without a second framebuffer or a conversion allocation.
pub trait ScreenPixel: sc98_term::Pixel + Copy + Default {
    fn from_color(color: Color) -> Self;
    const BYTES: usize = core::mem::size_of::<Self>();
}
impl ScreenPixel for u16 {
    fn from_color(color: Color) -> Self {
        color.0
    }
}
#[derive(Clone, Copy, Default)]
pub struct Rgb332(pub u8);
impl ScreenPixel for Rgb332 {
    fn from_color(color: Color) -> Self {
        let [r, g, b] = color.channels();
        Self((r & 224) | ((g >> 3) & 28) | (b >> 6))
    }
}
impl sc98_term::Pixel for Rgb332 {
    fn rgb(self) -> sc98_term::Rgb {
        let r = self.0 >> 5;
        let g = (self.0 >> 2) & 7;
        let b = self.0 & 3;
        sc98_term::Rgb(
            (r << 5) | (r << 2) | (r >> 1),
            (g << 5) | (g << 2) | (g >> 1),
            b * 85,
        )
    }
}
struct Screen<'a, P> {
    pixels: &'a mut [P],
    width: usize,
    height: usize,
}
impl<P: ScreenPixel> Framebuffer for Screen<'_, P> {
    fn width(&self) -> usize {
        self.width
    }
    fn height(&self) -> usize {
        self.height
    }
    fn set(&mut self, x: i32, y: i32, color: Color) {
        if x >= 0 && y >= 0 && (x as usize) < self.width && (y as usize) < self.height {
            self.pixels[y as usize * self.width + x as usize] = P::from_color(color);
        }
    }
}
pub struct App<S: Storage, P: ScreenPixel = u16> {
    part: Part,
    pub ui: app::App,
    pub storage: S,
    pub quit: bool,
    pub last_command: Option<Command>,
    pixels: Vec<P>,
    triangles: Vec<Triangle>,
    edges: Vec<model::Edge>,
    order: Vec<usize>,
    dirty: bool,
    size: Size,
    drag: Option<(i32, i32, Button)>,
    pending: Option<(Feature, Option<usize>)>,
    file: Option<Command>,
    filename: String,
    path: Option<String>,
    delete: Option<usize>,
}
impl<S: Storage, P: ScreenPixel> App<S, P> {
    pub fn new(layout: Layout, storage: S, part: Part) -> Result<Self, Error<S::Error>> {
        let mut ui = app::App::new(layout, &PartAdapter::new(&part, &[], &[]));
        ui.evaluate = |text| sc98_core::expr::evaluate(text).map_err(|e| e.code());
        let (w, h) = layout.size();
        let mut app = Self {
            part,
            ui,
            storage,
            quit: false,
            last_command: None,
            pixels: vec![P::default(); w * h],
            triangles: Vec::new(),
            edges: Vec::new(),
            order: Vec::new(),
            dirty: true,
            size: Size::default(),
            drag: None,
            pending: None,
            file: None,
            filename: String::new(),
            path: None,
            delete: None,
        };
        app.rebuild(true)?;
        Ok(app)
    }
    pub fn sample(layout: Layout, storage: S) -> Result<Self, Error<S::Error>> {
        Self::new(
            layout,
            storage,
            Part::from_sc98(include_bytes!("../../../samples/Mounting Plate.sc98"))?.part,
        )
    }
    pub fn part(&self) -> &Part {
        &self.part
    }
    pub fn pixels(&self) -> &[P] {
        &self.pixels
    }
    pub fn memory(&self) -> (usize, usize, usize) {
        (
            self.pixels.len() * P::BYTES,
            self.triangles.len() * core::mem::size_of::<Triangle>()
                + self.edges.len() * core::mem::size_of::<model::Edge>()
                + self.order.len() * core::mem::size_of::<usize>(),
            self.part.features().len(),
        )
    }
    fn rebuild(&mut self, fit: bool) -> Result<(), Error<S::Error>> {
        self.dirty = true;
        // Drop the display cache before building/exporting a double-precision mesh.
        self.triangles = Vec::new();
        self.order = Vec::new();
        self.edges = Vec::new();
        let rebuilt = self.part.rebuild(16)?;
        self.triangles = rebuilt
            .mesh
            .triangles()
            .iter()
            .map(|t| Triangle {
                vertices: t.vertices.map(point),
                normal: point(t.normal),
                color: colour(t.colour),
                face: t.feature as u16,
            })
            .collect();
        self.edges = rebuilt
            .edges
            .iter()
            .map(|e| model::Edge {
                vertices: e.vertices.map(point),
                color: colour(e.colour),
            })
            .collect();
        self.order.resize(self.triangles.len(), 0);
        if !rebuilt.invalid_features.is_empty() {
            self.ui.status = "Some features no longer fit. Edit their numbers.";
        }
        if fit {
            self.ui.view.fit(
                self.ui.layout.viewport(),
                &PartAdapter::new(&self.part, &self.triangles, &self.edges),
            );
        }
        Ok(())
    }
    fn ui_event(&mut self, event: UiEvent) -> Action {
        if let (Some(id), UiEvent::Click { x, y }) = (self.delete, event) {
            let r = self.ui.dialog_rect();
            if Rect::new(r.x + (r.w - 75) / 2, r.y + r.h - 36, 75, 23).contains(x, y) {
                self.delete = None;
                self.ui.dialog = Dialog::None;
                if self.remove(id).is_err() {
                    self.message("Could not delete that feature.");
                }
                return Action::None;
            }
        }
        let result = self.ui.event(
            event,
            &PartAdapter::new(&self.part, &self.triangles, &self.edges),
        );
        if result == Action::None && self.ui.dialog == Dialog::None {
            self.pending = None;
            self.delete = None;
        }
        result
    }
    fn selected_solid(&self) -> Option<usize> {
        let id = self.ui.selected? + 1;
        let f = self.part.feature(id)?;
        if f.kind == K::Extrude {
            Some(id)
        } else if f.kind == K::Hole {
            f.parent()
        } else {
            None
        }
    }
    /// All entry points (menus, toolbar, keyboard) use this command dispatcher.
    pub fn command(&mut self, command: Command) -> Result<(), Error<S::Error>> {
        self.dirty = true;
        self.last_command = Some(command);
        match command {
            Command::New | Command::Close => {
                self.part = Part::new("Part1");
                self.path = None;
                self.pending = None;
                self.delete = None;
                self.ui.selected = None;
                self.ui.dialog = Dialog::None;
                self.ui.status = "New part created.";
                self.rebuild(true)?;
            }
            Command::Open | Command::SaveAs | Command::Export => self.start_file(command),
            Command::Save => {
                if let Some(path) = self.path.clone() {
                    self.save_named(&path)?;
                } else {
                    self.start_file(Command::SaveAs);
                }
            }
            Command::Exit => self.quit = true,
            Command::Rectangle
            | Command::Circle
            | Command::Extrude
            | Command::Revolve
            | Command::Hole
            | Command::Edit => {
                let mut edit = None;
                let f = match command {
                    Command::Edit => {
                        let id = self.ui.selected.ok_or(Error::NoSelection)? + 1;
                        edit = Some(id);
                        self.part.feature(id).ok_or(Error::NoSelection)?.clone()
                    }
                    Command::Rectangle => Feature {
                        kind: K::Rectangle,
                        p1: 40.,
                        p2: 30.,
                        reference: self.selected_solid().unwrap_or(0) as i16,
                        ..Feature::default()
                    },
                    Command::Circle => Feature {
                        kind: K::Circle,
                        p1: 15.,
                        reference: self.selected_solid().unwrap_or(0) as i16,
                        ..Feature::default()
                    },
                    Command::Extrude | Command::Revolve => Feature {
                        kind: if command == Command::Extrude {
                            K::Extrude
                        } else {
                            K::Revolve
                        },
                        p1: if command == Command::Extrude {
                            20.
                        } else {
                            360.
                        },
                        reference: self.part.last_free_sketch().ok_or(Error::NoSketch)? as i16,
                        ..Feature::default()
                    },
                    _ => {
                        let id = self
                            .selected_solid()
                            .or_else(|| self.part.last_solid())
                            .ok_or(Error::NoSolid)?;
                        let sketch = self
                            .part
                            .feature(id)
                            .and_then(|f| f.parent())
                            .and_then(|id| self.part.feature(id))
                            .ok_or(Error::NoSketch)?;
                        Feature {
                            kind: K::Hole,
                            p1: 8.,
                            reference: id as i16,
                            x: sketch.x
                                + if sketch.kind == K::Rectangle {
                                    sketch.p1 / 2.
                                } else {
                                    0.
                                },
                            y: sketch.y
                                + if sketch.kind == K::Rectangle {
                                    sketch.p2 / 2.
                                } else {
                                    0.
                                },
                            ..Feature::default()
                        }
                    }
                };
                let kind = kind_command(f.kind).ok_or(Error::Unsupported)?;
                let strings: Vec<String> = values(&f).iter().map(ToString::to_string).collect();
                let fields: Vec<&str> = strings.iter().map(String::as_str).collect();
                self.ui.set_parameters(kind, &fields);
                self.pending = Some((f, edit));
            }
            Command::Delete => {
                let id = self.ui.selected.ok_or(Error::NoSelection)? + 1;
                let dependents = self.part.dependents(id)?;
                if dependents.len() > 1 {
                    self.delete = Some(id);
                    self.message(
                        "Delete this feature and everything\nbuilt on it? Enter: Yes  Esc: Cancel",
                    );
                } else {
                    self.remove(id)?;
                }
            }
            Command::Undo => {
                let n = self.part.features().len();
                if n > 0 {
                    self.remove(n)?;
                }
            }
            Command::Regenerate => self.rebuild(false)?,
            Command::Floppy => self.message("There is no drive A:.\nUse File, Save As."),
            Command::Publish => self.message("The Internet is under construction."),
            Command::Cascade | Command::TileH | Command::TileV => {
                self.ui.status = "One part open. It already fits."
            }
            other => {
                self.ui.command(
                    other,
                    &PartAdapter::new(&self.part, &self.triangles, &self.edges),
                );
            }
        }
        Ok(())
    }
    fn message(&mut self, text: &'static str) {
        self.ui.dialog = Dialog::Message;
        self.ui.message = text;
    }
    fn remove(&mut self, id: usize) -> Result<(), Error<S::Error>> {
        self.part.delete_with_dependents(id)?;
        self.ui.selected = None;
        self.rebuild(false)
    }
    fn start_file(&mut self, command: Command) {
        self.file = Some(command);
        self.filename = self
            .path
            .clone()
            .unwrap_or_else(|| format!("{}.sc98", self.part.title));
        if command == Command::Export {
            self.filename = format!("{}.stl", self.part.title);
        }
    }
    pub fn open_named(&mut self, name: &str) -> Result<(), Error<S::Error>> {
        let bytes = self.storage.load(name).map_err(Error::Storage)?;
        let loaded = Part::from_sc98(&bytes)?;
        self.part = loaded.part;
        self.path = Some(name.to_string());
        self.ui.selected = None;
        self.ui.status = "Part opened.";
        self.rebuild(true)
    }
    pub fn save_named(&mut self, name: &str) -> Result<(), Error<S::Error>> {
        self.dirty = true;
        self.storage
            .save(name, &self.part.to_sc98())
            .map_err(Error::Storage)?;
        self.path = Some(name.to_string());
        self.ui.status = "Part saved.";
        Ok(())
    }
    pub fn export_stl(&mut self) -> Result<Vec<u8>, Error<S::Error>> {
        self.triangles = Vec::new();
        self.order = Vec::new();
        self.edges = Vec::new();
        let result = (|| {
            let mesh = self.part.mesh(64)?;
            if !mesh.warnings.is_empty() {
                return Err(Error::MeshWarnings);
            }
            Ok(mesh.to_stl(&self.part.title)?)
        })();
        self.rebuild(false)?;
        result
    }
    fn accept_parameters(&mut self, v: &[f64]) -> Result<(), Error<S::Error>> {
        let (mut f, edit) = self.pending.clone().ok_or(Error::InvalidParameters)?;
        let at = |i: usize| v.get(i).copied().unwrap_or(0.);
        f.p1 = at(0);
        match f.kind {
            K::Rectangle => {
                f.p2 = at(1);
                f.x = at(2);
                f.y = at(3);
                f.p3 = at(4);
                f.reference = at(5) as i16;
                f.z = at(6);
                if at(5) != f64::from(f.reference) {
                    return Err(Error::InvalidParameters);
                }
            }
            K::Circle => {
                f.x = at(1);
                f.y = at(2);
                f.reference = at(3) as i16;
                f.z = at(4);
                if at(3) != f64::from(f.reference) {
                    return Err(Error::InvalidParameters);
                }
            }
            K::Hole => {
                f.p2 = at(1);
                f.x = at(2);
                f.y = at(3);
            }
            _ => {}
        }
        if !v.iter().all(|n| n.is_finite())
            || (f.kind != K::Revolve && f.p1 <= 0.)
            || (f.kind == K::Rectangle && (f.p2 <= 0. || f.p3 < 0. || f.p3 * 2. > f.p1.min(f.p2)))
            || (f.kind == K::Hole && f.p2 < 0.)
            || (f.kind == K::Revolve && (f.p1 == 0. || f.p1.abs() > 360.))
        {
            return Err(Error::InvalidParameters);
        }
        if f.kind == K::Revolve {
            let sketch = f
                .parent()
                .and_then(|id| self.part.feature(id))
                .ok_or(Error::NoSketch)?;
            let (lo, hi) = if sketch.kind == K::Circle {
                (sketch.x - sketch.p1, sketch.x + sketch.p1)
            } else {
                (sketch.x, sketch.x + sketch.p1)
            };
            if lo < 0. && hi > 0. {
                return Err(Error::InvalidParameters);
            }
        }
        if f.kind == K::Hole
            && f.parent()
                .and_then(|id| self.part.feature(id))
                .is_some_and(|b| f.p2 > b.p1 + 0.000001)
        {
            return Err(Error::InvalidParameters);
        }
        // Check references and containment with exactly the core's rules before committing.
        let mut candidate = self.part.clone();
        let id = if let Some(id) = edit {
            candidate.edit_feature(id, f)?;
            id
        } else {
            candidate.add_feature(f)?
        };
        if !candidate.ref_ok(id) {
            return Err(Error::InvalidParameters);
        }
        if let Some(f) = candidate.feature(id).filter(|f| f.kind == K::Hole) {
            let overlaps = candidate.features().iter().enumerate().any(|(i, h)| {
                i + 1 != id
                    && h.kind == K::Hole
                    && h.reference == f.reference
                    && (h.x - f.x) * (h.x - f.x) + (h.y - f.y) * (h.y - f.y)
                        < ((h.p1 + f.p1) / 2. + 0.01) * ((h.p1 + f.p1) / 2. + 0.01)
            });
            if overlaps {
                return Err(Error::InvalidParameters);
            }
        }
        self.part = candidate;
        self.pending = None;
        self.ui.dialog = Dialog::None;
        self.ui.selected = Some(id - 1);
        self.ui.status = if edit.is_some() {
            "Feature changed."
        } else {
            "Feature created."
        };
        self.rebuild(edit.is_none())
    }
    fn action(&mut self, action: Action) -> Result<(), Error<S::Error>> {
        match action {
            Action::Command(c) => {
                // The pixel layer already applied view commands; only dispatch model commands again.
                self.last_command = Some(c);
                if !matches!(
                    c,
                    Command::Shaded
                        | Command::Isometric
                        | Command::Fit
                        | Command::Turbo
                        | Command::Help
                        | Command::About
                ) {
                    self.command(c)?;
                }
            }
            Action::Parameters { values, count, .. } => self.accept_parameters(&values[..count])?,
            Action::None => {}
        }
        Ok(())
    }
    fn input(&mut self, event: Event) -> Result<(), Error<S::Error>> {
        if self.file.is_some() && !matches!(event, Event::Key(_) | Event::Size(_)) {
            return Ok(());
        }
        if let Event::Size(size) = event {
            if size.cols > 0 && size.rows > 0 {
                self.size = size;
            }
            return Ok(());
        }
        if let Event::Key(key) = event {
            if key.modifiers.contains(Modifiers::CTRL) && key.key == Key::Char('q') {
                self.quit = true;
                return Ok(());
            }
            if self.file.is_some() {
                match key.key {
                    Key::Escape => self.file = None,
                    Key::Backspace => {
                        self.filename.pop();
                    }
                    Key::Char(c) if !c.is_control() && self.filename.len() < 240 => {
                        self.filename.push(c)
                    }
                    Key::Enter => {
                        let name = self.filename.clone();
                        let command = self.file.take();
                        match command {
                            Some(Command::Open) => self.open_named(&name)?,
                            Some(Command::Export) => {
                                let bytes = self.export_stl()?;
                                self.storage.save(&name, &bytes).map_err(Error::Storage)?;
                                self.ui.status = "STL exported.";
                            }
                            _ => self.save_named(&name)?,
                        }
                    }
                    _ => {}
                }
                return Ok(());
            }
            if let Some(id) = self.delete {
                if key.key == Key::Enter {
                    self.delete = None;
                    self.ui.dialog = Dialog::None;
                    return self.remove(id);
                }
                if key.key == Key::Escape {
                    self.delete = None;
                }
            }
            if key.key == Key::Escape && matches!(self.ui.dialog, Dialog::Numbers(_)) {
                self.pending = None;
            }
            if self.ui.dialog == Dialog::None {
                if key.modifiers.contains(Modifiers::CTRL) {
                    if let Key::Char(c) = key.key {
                        let command = match c {
                            'n' => Some(Command::New),
                            'o' => Some(Command::Open),
                            's' => Some(Command::Save),
                            'z' => Some(Command::Undo),
                            _ => None,
                        };
                        if let Some(c) = command {
                            return self.command(c);
                        }
                    }
                }
                if key.modifiers.contains(Modifiers::ALT) {
                    if let Key::Char(c) = key.key {
                        if let Some(i) = "festvwh".chars().position(|m| m == c.to_ascii_lowercase())
                        {
                            self.ui.menu = Some(i);
                            self.ui.hot_item = 0;
                            return Ok(());
                        }
                    }
                }
            }
            if matches!(self.ui.dialog, Dialog::Numbers(_)) && key.key == Key::Enter {
                let mut v = Vec::new();
                for text in self
                    .ui
                    .parameter_texts()
                    .iter()
                    .take(self.ui.parameter_count())
                {
                    v.push(
                        sc98_core::expr::evaluate(text).map_err(|e| Error::Expression(e.code()))?,
                    );
                }
                return self.accept_parameters(&v);
            }
            let numeric = matches!(self.ui.dialog, Dialog::Numbers(_));
            let ui = match key.key {
                Key::Char(c) if numeric => UiEvent::Text(c),
                Key::Char('+') => UiEvent::Key(UiKey::Plus),
                Key::Char('-') => UiEvent::Key(UiKey::Minus),
                Key::Char(c) => UiEvent::Key(UiKey::Character(c)),
                Key::Escape => UiEvent::Key(UiKey::Escape),
                Key::Enter => UiEvent::Key(UiKey::Enter),
                Key::Tab => UiEvent::Key(UiKey::Tab),
                Key::Backspace => UiEvent::Key(UiKey::Backspace),
                Key::Delete => UiEvent::Key(UiKey::Delete),
                Key::Up => UiEvent::Key(UiKey::Up),
                Key::Down => UiEvent::Key(UiKey::Down),
                Key::Left if self.ui.dialog == Dialog::None && self.ui.menu.is_none() => {
                    UiEvent::Orbit { dx: -10., dy: 0. }
                }
                Key::Left => UiEvent::Key(UiKey::Left),
                Key::Right if self.ui.dialog == Dialog::None && self.ui.menu.is_none() => {
                    UiEvent::Orbit { dx: 10., dy: 0. }
                }
                Key::Right => UiEvent::Key(UiKey::Right),
                Key::Function(1) => UiEvent::Key(UiKey::F1),
                Key::Function(5) => UiEvent::Key(UiKey::F5),
                _ => return Ok(()),
            };
            let action = self.ui_event(ui);
            self.action(action)?;
        }
        if let Event::Mouse(mouse) = event {
            if matches!(mouse.kind, MouseKind::Release(_)) {
                self.drag = None;
                return Ok(());
            }
            // Match the encoder's integer aspect fit, including letterbox margins.
            let (w, h) = self.ui.layout.size();
            let w = w as u32;
            let h = h as u32;
            let cols = u32::from(self.size.cols);
            let rows = u32::from(self.size.rows) * 2;
            let (fw, fh) = if cols * h <= rows * w {
                (cols, (h * cols / w).max(1))
            } else {
                ((w * rows / h).max(1), rows)
            };
            let left = (cols - fw) / 2;
            let top = (rows - fh) / 2;
            let mx = u32::from(mouse.col);
            let my = u32::from(mouse.row) * 2 + 1;
            if mx < left || my < top || mx >= left + fw || my >= top + fh {
                return Ok(());
            }
            let x = ((mx - left) * w / fw) as i32;
            let y = ((my - top) * h / fh) as i32;
            let ui = match mouse.kind {
                MouseKind::Press(b) => {
                    if self.ui.layout.viewport().contains(x, y) {
                        self.drag = Some((x, y, b));
                    }
                    UiEvent::Click { x, y }
                }
                MouseKind::Release(_) => {
                    self.drag = None;
                    return Ok(());
                }
                MouseKind::Drag(_) => {
                    if let Some((px, py, b)) = self.drag {
                        self.drag = Some((x, y, b));
                        if b == Button::Right {
                            UiEvent::Pan {
                                dx: (x - px) as f32,
                                dy: (y - py) as f32,
                            }
                        } else {
                            UiEvent::Orbit {
                                dx: (x - px) as f32,
                                dy: (y - py) as f32,
                            }
                        }
                    } else {
                        UiEvent::Hover { x, y }
                    }
                }
                MouseKind::Wheel(Wheel::Up) => UiEvent::Zoom(1.1),
                MouseKind::Wheel(Wheel::Down) => UiEvent::Zoom(1. / 1.1),
                _ => return Ok(()),
            };
            let action = self.ui_event(ui);
            self.action(action)?;
        }
        Ok(())
    }
    /// Apply one decoded input (or an idle tick) and draw the current framebuffer.
    /// User errors are displayed in the app; transport/storage remain host-owned.
    pub fn tick(&mut self, input: Option<Event>) -> Result<Frame<'_, P>, Error<S::Error>> {
        if let Some(event) = input {
            self.dirty = true;
            if let Err(error) = self.input(event) {
                let text = match error {
                    Error::NoSketch => "Sketch a rectangle or circle first.",
                    Error::NoSolid => "A hole needs an extrude's top face.",
                    Error::NoSelection => "Select a feature to edit or delete.",
                    Error::Expression(11) => "Run-time error '11': Division by zero",
                    Error::Expression(_) => "Run-time error '13': Type mismatch",
                    Error::InvalidParameters => "Check the dimensions and feature reference.",
                    Error::Storage(_) => "Could not open or save that file.",
                    Error::Unsupported => "Requires SolidCraft 2000.",
                    Error::MeshWarnings => "Cannot export: some bodies could not be meshed.",
                    _ => "Could not complete command.",
                };
                self.ui.status = text;
                if let Some((f, _)) = &self.pending {
                    if let Some(kind) = kind_command(f.kind) {
                        self.ui.dialog = Dialog::Numbers(kind);
                    }
                } else {
                    self.message(text);
                }
            }
        }
        let (width, height) = self.ui.layout.size();
        if !self.dirty {
            return Frame::new(&self.pixels, width as u16, height as u16)
                .map_err(|_| Error::Buffer);
        }
        let (w, h) = self.ui.layout.size();
        let mut fb = Screen {
            pixels: &mut self.pixels,
            width: w,
            height: h,
        };
        let adapter = PartAdapter::new(&self.part, &self.triangles, &self.edges);
        self.ui
            .render(
                &mut fb,
                &adapter,
                Visibility::Painter {
                    order: &mut self.order,
                },
            )
            .map_err(Error::Render)?;
        if let Some(command) = self.file {
            let mut c = Canvas::new(&mut fb);
            let r = Rect::new((w as i32 - 300) / 2, (h as i32 - 142) / 2, 300, 142);
            widgets::window(
                &mut c,
                r,
                if command == Command::Open {
                    "Open Part"
                } else if command == Command::Export {
                    "Export for Rapid Prototyping"
                } else {
                    "Save Part"
                },
                true,
                true,
            );
            c.text(r.x + 12, r.y + 38, "File name:", Color::rgb(0, 0, 0), false);
            c.text(
                r.x + 12,
                r.y + 58,
                &self.filename,
                Color::rgb(0, 0, 0),
                false,
            );
            widgets::button(
                &mut c,
                Rect::new(r.x + 12, r.y + 104, 276, 23),
                "Enter: OK   Esc: Cancel",
                ButtonState::default(),
            );
        }
        self.dirty = false;
        Frame::new(&self.pixels, w as u16, h as u16).map_err(|_| Error::Buffer)
    }
}
