//! Current-directory storage for SolidCraft 98.
#![forbid(unsafe_code)]
use sc98_app::Storage;
use std::{
    io,
    path::{Path, PathBuf},
};
pub struct Directory {
    root: PathBuf,
}
impl Directory {
    pub fn new(root: impl Into<PathBuf>) -> Self {
        Self { root: root.into() }
    }
    fn path(&self, name: &str) -> io::Result<PathBuf> {
        let path = Path::new(name);
        if path.is_absolute()
            || path
                .components()
                .any(|c| !matches!(c, std::path::Component::Normal(_)))
        {
            return Err(io::Error::new(
                io::ErrorKind::InvalidInput,
                "Use a name in the current directory",
            ));
        }
        Ok(self.root.join(path))
    }
}
impl Storage for Directory {
    type Error = io::Error;
    fn load(&mut self, name: &str) -> io::Result<Vec<u8>> {
        std::fs::read(self.path(name)?)
    }
    fn save(&mut self, name: &str, bytes: &[u8]) -> io::Result<()> {
        std::fs::write(self.path(name)?, bytes)
    }
}
pub fn new_part() -> sc98_core::Part {
    sc98_core::Part::new("Part1")
}

/// Native console events for platforms without Unix termios byte reads.
#[cfg(not(unix))]
pub fn native_event(timeout: std::time::Duration) -> io::Result<Option<sc98_term::Event>> {
    use crossterm::event::{
        self, Event, KeyCode, KeyEventKind, KeyModifiers, MouseButton, MouseEventKind,
    };
    use sc98_term::{self as term, Key};
    if !event::poll(timeout)? {
        return Ok(None);
    }
    let modifier = |m: KeyModifiers| {
        term::Modifiers(
            if m.contains(KeyModifiers::SHIFT) {
                1
            } else {
                0
            } | if m.contains(KeyModifiers::ALT) { 2 } else { 0 }
                | if m.contains(KeyModifiers::CONTROL) {
                    4
                } else {
                    0
                },
        )
    };
    let button = |b: MouseButton| match b {
        MouseButton::Left => term::Button::Left,
        MouseButton::Right => term::Button::Right,
        MouseButton::Middle => term::Button::Middle,
    };
    Ok(match event::read()? {
        Event::Key(k) if k.kind != KeyEventKind::Release => {
            let key = match k.code {
                KeyCode::Char(c) => Key::Char(c),
                KeyCode::Enter => Key::Enter,
                KeyCode::Esc => Key::Escape,
                KeyCode::Tab | KeyCode::BackTab => Key::Tab,
                KeyCode::Backspace => Key::Backspace,
                KeyCode::Delete => Key::Delete,
                KeyCode::Up => Key::Up,
                KeyCode::Down => Key::Down,
                KeyCode::Left => Key::Left,
                KeyCode::Right => Key::Right,
                KeyCode::Home => Key::Home,
                KeyCode::End => Key::End,
                KeyCode::PageUp => Key::PageUp,
                KeyCode::PageDown => Key::PageDown,
                KeyCode::Insert => Key::Insert,
                KeyCode::F(n) => Key::Function(n),
                _ => return Ok(None),
            };
            Some(term::Event::Key(term::KeyEvent {
                key,
                modifiers: modifier(k.modifiers),
            }))
        }
        Event::Mouse(m) => {
            let kind = match m.kind {
                MouseEventKind::Down(b) => term::MouseKind::Press(button(b)),
                MouseEventKind::Up(b) => term::MouseKind::Release(Some(button(b))),
                MouseEventKind::Drag(b) => term::MouseKind::Drag(Some(button(b))),
                MouseEventKind::ScrollUp => term::MouseKind::Wheel(term::Wheel::Up),
                MouseEventKind::ScrollDown => term::MouseKind::Wheel(term::Wheel::Down),
                _ => return Ok(None),
            };
            Some(term::Event::Mouse(term::Mouse {
                kind,
                col: m.column,
                row: m.row,
                modifiers: modifier(m.modifiers),
            }))
        }
        Event::Resize(cols, rows) => Some(term::Event::Size(term::Size { cols, rows })),
        _ => None,
    })
}
