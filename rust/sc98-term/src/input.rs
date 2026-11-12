use crate::Size;

#[derive(Clone, Copy, Debug, Default, PartialEq, Eq)]
pub struct Modifiers(pub u8);

impl Modifiers {
    pub const SHIFT: Self = Self(1);
    pub const ALT: Self = Self(2);
    pub const CTRL: Self = Self(4);
    pub const fn contains(self, other: Self) -> bool {
        self.0 & other.0 == other.0
    }
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Key {
    Char(char),
    Escape,
    Enter,
    Tab,
    Backspace,
    Up,
    Down,
    Right,
    Left,
    Home,
    End,
    Insert,
    Delete,
    PageUp,
    PageDown,
    Function(u8),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct KeyEvent {
    pub key: Key,
    pub modifiers: Modifiers,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Button {
    Left,
    Middle,
    Right,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Wheel {
    Up,
    Down,
    Left,
    Right,
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MouseKind {
    Press(Button),
    Release(Option<Button>),
    Drag(Option<Button>),
    Wheel(Wheel),
}
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub struct Mouse {
    pub kind: MouseKind,
    /// Zero-based terminal cell coordinates (not framebuffer pixel coordinates).
    pub col: u16,
    pub row: u16,
    pub modifiers: Modifiers,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum Event {
    Key(KeyEvent),
    Mouse(Mouse),
    Size(Size),
}

#[derive(Clone, Copy, Debug, PartialEq, Eq)]
enum State {
    Ground,
    Escape,
    Csi,
    Ss3,
    Utf8,
    Discard,
}

/// Streaming decoder with a 64-byte sequence bound. No read boundaries are special.
/// Call `escape_timeout` after a short idle timeout to disambiguate a lone Escape.
/// Incomplete CSI/SS3/UTF-8 remains buffered until completed or explicitly reset.
pub struct Decoder {
    state: State,
    buffer: [u8; 64],
    len: usize,
    utf8_len: usize,
    alt: bool,
}

impl Default for Decoder {
    fn default() -> Self {
        Self::new()
    }
}

impl Decoder {
    pub const fn new() -> Self {
        Self {
            state: State::Ground,
            buffer: [0; 64],
            len: 0,
            utf8_len: 0,
            alt: false,
        }
    }

    pub fn reset(&mut self) {
        self.state = State::Ground;
        self.len = 0;
        self.alt = false;
    }

    pub fn feed(&mut self, bytes: &[u8], mut emit: impl FnMut(Event)) {
        for &byte in bytes {
            self.push(byte, &mut emit);
        }
    }

    pub fn escape_timeout(&mut self) -> Option<Event> {
        if self.state == State::Escape {
            self.reset();
            Some(key(Key::Escape, Modifiers::default()))
        } else {
            None
        }
    }

    fn push(&mut self, byte: u8, emit: &mut impl FnMut(Event)) {
        // An Escape inside any unfinished sequence begins a new sequence.
        if byte == 0x1b {
            if self.state == State::Escape {
                emit(key(Key::Escape, Modifiers::default()));
            }
            self.reset();
            self.state = State::Escape;
            return;
        }
        match self.state {
            State::Escape => {
                self.len = 0;
                match byte {
                    b'[' => self.state = State::Csi,
                    b'O' => self.state = State::Ss3,
                    _ => {
                        self.state = State::Ground;
                        self.alt = true;
                        self.printable(byte, emit);
                    }
                }
            }
            State::Csi | State::Ss3 => {
                if byte < 0x20 {
                    self.reset();
                    self.printable(byte, emit);
                    return;
                }
                if (0x40..=0x7e).contains(&byte) {
                    if let Some(event) =
                        sequence(&self.buffer[..self.len], byte, self.state == State::Ss3)
                    {
                        emit(event);
                    }
                    self.reset();
                } else if self.len < self.buffer.len() {
                    self.buffer[self.len] = byte;
                    self.len += 1;
                } else {
                    self.state = State::Discard;
                }
            }
            State::Discard => {
                if (0x40..=0x7e).contains(&byte) {
                    self.reset();
                }
            }
            State::Utf8 => {
                if byte & 0xc0 != 0x80 {
                    self.reset();
                    self.printable(byte, emit);
                    return;
                }
                self.buffer[self.len] = byte;
                self.len += 1;
                if self.len == self.utf8_len {
                    if let Ok(text) = core::str::from_utf8(&self.buffer[..self.len]) {
                        if let Some(ch) = text.chars().next() {
                            emit(key(Key::Char(ch), Modifiers(if self.alt { 2 } else { 0 })));
                        }
                    }
                    self.reset();
                }
            }
            State::Ground => self.printable(byte, emit),
        }
    }

    fn printable(&mut self, byte: u8, emit: &mut impl FnMut(Event)) {
        let mut mods = Modifiers(if self.alt { 2 } else { 0 });
        let code = match byte {
            b'\r' | b'\n' => Some(Key::Enter),
            b'\t' => Some(Key::Tab),
            8 | 127 => Some(Key::Backspace),
            1..=26 => {
                mods.0 |= Modifiers::CTRL.0;
                Some(Key::Char(char::from(b'a' + byte - 1)))
            }
            0 => {
                mods.0 |= Modifiers::CTRL.0;
                Some(Key::Char(' '))
            }
            28..=31 => {
                mods.0 |= Modifiers::CTRL.0;
                Some(Key::Char(char::from(byte + 64)))
            }
            32..=126 => Some(Key::Char(char::from(byte))),
            0xc2..=0xf4 => {
                self.utf8_len = if byte < 0xe0 {
                    2
                } else if byte < 0xf0 {
                    3
                } else {
                    4
                };
                self.len = 1;
                self.buffer[0] = byte;
                self.state = State::Utf8;
                return;
            }
            _ => None,
        };
        if let Some(code) = code {
            emit(key(code, mods));
        }
        self.alt = false;
    }
}

fn key(key: Key, modifiers: Modifiers) -> Event {
    Event::Key(KeyEvent { key, modifiers })
}

fn params(bytes: &[u8], values: &mut [u16]) -> Option<usize> {
    if bytes.is_empty() {
        return Some(0);
    }
    let mut count = 0;
    for part in bytes.split(|b| *b == b';') {
        if count == values.len() || part.is_empty() {
            return None;
        }
        let mut value = 0_u16;
        for &b in part {
            if !b.is_ascii_digit() {
                return None;
            }
            value = value.checked_mul(10)?.checked_add(u16::from(b - b'0'))?;
        }
        values[count] = value;
        count += 1;
    }
    Some(count)
}

fn sequence(bytes: &[u8], final_byte: u8, ss3: bool) -> Option<Event> {
    if !ss3 && bytes.first() == Some(&b'<') {
        return mouse(&bytes[1..], final_byte);
    }
    let mut p = [0; 3];
    let count = params(bytes, &mut p)?;
    if !ss3 && final_byte == b'R' && count == 2 {
        if p[0] == 0 || p[1] == 0 {
            return None;
        }
        return Some(Event::Size(Size {
            cols: p[1],
            rows: p[0],
        }));
    }
    let modifiers = if count == 2 && (1..=8).contains(&p[1]) {
        Modifiers((p[1] - 1) as u8)
    } else if count < 2 {
        Modifiers::default()
    } else {
        return None;
    };
    let code = match final_byte {
        b'A' => Key::Up,
        b'B' => Key::Down,
        b'C' => Key::Right,
        b'D' => Key::Left,
        b'H' => Key::Home,
        b'F' => Key::End,
        b'P' => Key::Function(1),
        b'Q' => Key::Function(2),
        b'R' => Key::Function(3),
        b'S' => Key::Function(4),
        b'Z' if !ss3 && count == 0 => return Some(key(Key::Tab, Modifiers::SHIFT)),
        b'~' if !ss3 && count >= 1 => match p[0] {
            1 | 7 => Key::Home,
            2 => Key::Insert,
            3 => Key::Delete,
            4 | 8 => Key::End,
            5 => Key::PageUp,
            6 => Key::PageDown,
            11..=15 => Key::Function((p[0] - 10) as u8),
            17..=21 => Key::Function((p[0] - 11) as u8),
            23..=24 => Key::Function((p[0] - 12) as u8),
            _ => return None,
        },
        _ => return None,
    };
    Some(key(code, modifiers))
}

fn mouse(bytes: &[u8], final_byte: u8) -> Option<Event> {
    if final_byte != b'M' && final_byte != b'm' {
        return None;
    }
    let mut p = [0; 3];
    if params(bytes, &mut p)? != 3 || p[1] == 0 || p[2] == 0 || p[0] > 127 {
        return None;
    }
    let button = match p[0] & 3 {
        0 => Some(Button::Left),
        1 => Some(Button::Middle),
        2 => Some(Button::Right),
        _ => None,
    };
    let kind = if p[0] & 64 != 0 {
        MouseKind::Wheel(match p[0] & 3 {
            0 => Wheel::Up,
            1 => Wheel::Down,
            2 => Wheel::Left,
            _ => Wheel::Right,
        })
    } else if final_byte == b'm' || p[0] & 3 == 3 && p[0] & 32 == 0 {
        MouseKind::Release(button)
    } else if p[0] & 32 != 0 {
        MouseKind::Drag(button)
    } else {
        MouseKind::Press(button?)
    };
    let mut mods = 0;
    if p[0] & 4 != 0 {
        mods |= Modifiers::SHIFT.0;
    }
    if p[0] & 8 != 0 {
        mods |= Modifiers::ALT.0;
    }
    if p[0] & 16 != 0 {
        mods |= Modifiers::CTRL.0;
    }
    Some(Event::Mouse(Mouse {
        kind,
        col: p[1] - 1,
        row: p[2] - 1,
        modifiers: Modifiers(mods),
    }))
}
