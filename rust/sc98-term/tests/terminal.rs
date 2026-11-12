use sc98_term::*;
use std::convert::Infallible;

#[derive(Default)]
struct Bytes(Vec<u8>);
impl Write for Bytes {
    type Error = Infallible;
    fn write_all(&mut self, bytes: &[u8]) -> Result<(), Self::Error> {
        self.0.extend_from_slice(bytes);
        Ok(())
    }
}

fn render<P: Pixel>(pixels: &[P], width: u16, height: u16, size: Size, config: Config) -> Vec<u8> {
    let mut cells = vec![Cell::EMPTY; usize::from(size.cols) * usize::from(size.rows)];
    let mut encoder = Encoder::new(&mut cells, size, config).unwrap();
    let mut out = Bytes::default();
    encoder
        .render(&Frame::new(pixels, width, height).unwrap(), &mut out)
        .unwrap();
    out.0
}

const ONE: Size = Size { cols: 1, rows: 1 };
const RED: Rgb = Rgb(255, 0, 0);
const BLUE: Rgb = Rgb(0, 0, 255);
const WHITE: Rgb = Rgb(255, 255, 255);

#[test]
fn shaded_golden_all_palettes_and_pixel_formats() {
    for (colours, expected) in [
        (
            ColourMode::TrueColour,
            "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m▀",
        ),
        (
            ColourMode::Ansi256,
            "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;5;9m\x1b[48;5;12m▀",
        ),
        (
            ColourMode::Ansi16,
            "\x1b[0m\x1b[2J\x1b[1;1H\x1b[91m\x1b[104m▀",
        ),
    ] {
        let config = Config {
            colours,
            ..Config::default()
        };
        assert_eq!(render(&[RED, BLUE], 1, 2, ONE, config), expected.as_bytes());
        assert_eq!(
            render(&[0xf800_u16, 0x001f], 1, 2, ONE, config),
            expected.as_bytes()
        );
        assert_eq!(
            render(&[Palette16(9), Palette16(12)], 1, 2, ONE, config),
            expected.as_bytes()
        );
    }
}

#[test]
fn braille_golden_all_palettes_and_each_dot() {
    for (colours, attrs) in [
        (
            ColourMode::TrueColour,
            "\x1b[38;2;255;255;255m\x1b[48;2;0;0;0m",
        ),
        (ColourMode::Ansi256, "\x1b[38;5;15m\x1b[48;5;0m"),
        (ColourMode::Ansi16, "\x1b[97m\x1b[40m"),
    ] {
        for (i, dot) in [0, 3, 1, 4, 2, 5, 6, 7].iter().enumerate() {
            let mut pixels = [Rgb::BLACK; 8];
            pixels[i] = WHITE;
            let glyph = char::from_u32(0x2800 | (1 << dot)).unwrap();
            let expected = format!("\x1b[0m\x1b[2J\x1b[1;1H{attrs}{glyph}");
            assert_eq!(
                render(
                    &pixels,
                    2,
                    4,
                    ONE,
                    Config {
                        mode: Mode::Wireframe,
                        colours,
                        ..Config::default()
                    }
                ),
                expected.as_bytes()
            );
        }
    }
}

#[test]
fn braille_averages_ink_and_supports_dark_lines() {
    let mut pixels = [WHITE; 8];
    pixels[0] = Rgb::BLACK;
    let config = Config {
        mode: Mode::Wireframe,
        wire_background: WHITE,
        ..Config::default()
    };
    assert_eq!(
        render(&pixels, 2, 4, ONE, config),
        "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;0;0;0m\x1b[48;2;255;255;255m⠁".as_bytes()
    );
    let mut pixels = [Rgb::BLACK; 8];
    pixels[0] = RED;
    pixels[1] = BLUE;
    let out = render(
        &pixels,
        2,
        4,
        ONE,
        Config {
            mode: Mode::Wireframe,
            ..Config::default()
        },
    );
    assert!(String::from_utf8(out)
        .unwrap()
        .contains("\x1b[38;2;127;0;127m"));
}

#[test]
fn diff_only_changed_cells_and_attributes() {
    let mut cells = [Cell::EMPTY; 3];
    let mut encoder =
        Encoder::new(&mut cells, Size { cols: 3, rows: 1 }, Config::default()).unwrap();
    let mut out = Bytes::default();
    let mut pixels = [RED, RED, RED, BLUE, BLUE, BLUE];
    encoder
        .render(&Frame::new(&pixels, 3, 2).unwrap(), &mut out)
        .unwrap();
    assert_eq!(
        out.0,
        "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m▀▀▀".as_bytes()
    );
    out.0.clear();
    encoder
        .render(&Frame::new(&pixels, 3, 2).unwrap(), &mut out)
        .unwrap();
    assert!(out.0.is_empty());
    pixels[1] = Rgb(0, 255, 0);
    encoder
        .render(&Frame::new(&pixels, 3, 2).unwrap(), &mut out)
        .unwrap();
    assert_eq!(out.0, "\x1b[1;2H\x1b[38;2;0;255;0m▀".as_bytes());
    out.0.clear();
    pixels[1] = RED;
    pixels[4] = WHITE;
    encoder
        .render(&Frame::new(&pixels, 3, 2).unwrap(), &mut out)
        .unwrap();
    assert_eq!(
        out.0,
        "\x1b[1;2H\x1b[38;2;255;0;0m\x1b[48;2;255;255;255m▀".as_bytes()
    );
}

#[test]
fn diff_braille_erases_old_ink_and_skips_quantized_changes() {
    let mut cells = [Cell::EMPTY; 1];
    let mut encoder = Encoder::new(
        &mut cells,
        ONE,
        Config {
            mode: Mode::Wireframe,
            colours: ColourMode::Ansi16,
            ..Config::default()
        },
    )
    .unwrap();
    let mut out = Bytes::default();
    let mut pixels = [Rgb::BLACK; 8];
    pixels[0] = WHITE;
    encoder
        .render(&Frame::new(&pixels, 2, 4).unwrap(), &mut out)
        .unwrap();
    out.0.clear();
    pixels[0] = Rgb(254, 254, 254);
    encoder
        .render(&Frame::new(&pixels, 2, 4).unwrap(), &mut out)
        .unwrap();
    assert!(out.0.is_empty());
    pixels[0] = Rgb::BLACK;
    encoder
        .render(&Frame::new(&pixels, 2, 4).unwrap(), &mut out)
        .unwrap();
    assert_eq!(out.0, "\x1b[1;1H\x1b[30m⠀".as_bytes());
}

#[test]
fn scaling_nearest_box_and_letterbox_goldens() {
    let pixels = [
        RED,
        Rgb(0, 255, 0),
        RED,
        Rgb(0, 255, 0),
        BLUE,
        WHITE,
        BLUE,
        WHITE,
    ];
    assert_eq!(
        render(&pixels, 2, 4, ONE, Config::default()),
        "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m▀".as_bytes()
    );
    assert_eq!(
        render(
            &pixels,
            2,
            4,
            ONE,
            Config {
                filter: Filter::Box2x2,
                ..Config::default()
            }
        ),
        "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;127;127;0m\x1b[48;2;127;127;255m▀".as_bytes()
    );
    assert_eq!(render(&[RED, BLUE], 1, 2, Size { cols: 3, rows: 1 }, Config::default()), "\x1b[0m\x1b[2J\x1b[1;1H\x1b[38;2;0;0;0m\x1b[48;2;0;0;0m▀\x1b[38;2;255;0;0m\x1b[48;2;0;0;255m▀\x1b[38;2;0;0;0m\x1b[48;2;0;0;0m▀".as_bytes());
    // 1x1, odd and very wide inputs must fit without dividing by zero or indexing past an edge.
    for (w, h) in [(1, 1), (1, 9), (9, 1), (3, 5), (65535, 1)] {
        let pixels = vec![WHITE; usize::from(w) * usize::from(h)];
        assert!(!render(
            &pixels,
            w,
            h,
            Size { cols: 2, rows: 2 },
            Config {
                filter: Filter::Box2x2,
                ..Config::default()
            }
        )
        .is_empty());
    }
}

#[test]
fn redraw_resize_config_and_ctrl_l() {
    let mut cells = [Cell::EMPTY; 4];
    let mut encoder = Encoder::new(&mut cells, ONE, Config::default()).unwrap();
    let frame = Frame::new(&[RED, BLUE], 1, 2).unwrap();
    let mut out = Bytes::default();
    encoder.render(&frame, &mut out).unwrap();
    let initial = out.0.clone();
    out.0.clear();
    encoder
        .handle_event(Event::Key(KeyEvent {
            key: Key::Char('l'),
            modifiers: Modifiers::CTRL,
        }))
        .unwrap();
    encoder.render(&frame, &mut out).unwrap();
    assert_eq!(out.0, initial);
    assert_eq!(
        encoder.resize(Size { cols: 9, rows: 9 }),
        Err(Error::Capacity)
    );
    assert_eq!(encoder.size(), ONE);
    encoder
        .handle_event(Event::Size(Size { cols: 2, rows: 2 }))
        .unwrap();
    out.0.clear();
    encoder.render(&frame, &mut out).unwrap();
    assert!(out.0.starts_with(b"\x1b[0m\x1b[2J"));
    encoder.configure(Config {
        mode: Mode::Wireframe,
        ..Config::default()
    });
    out.0.clear();
    encoder.render(&frame, &mut out).unwrap();
    assert!(out.0.starts_with(b"\x1b[0m\x1b[2J"));
}

#[test]
fn io_failure_retries_full_frame() {
    struct Fails;
    impl Write for Fails {
        type Error = ();
        fn write_all(&mut self, _: &[u8]) -> Result<(), ()> {
            Err(())
        }
    }
    let mut cells = [Cell::EMPTY; 1];
    let mut encoder = Encoder::new(&mut cells, ONE, Config::default()).unwrap();
    let frame = Frame::new(&[RED, BLUE], 1, 2).unwrap();
    assert_eq!(encoder.render(&frame, &mut Fails), Err(()));
    let mut out = Bytes::default();
    encoder.render(&frame, &mut out).unwrap();
    assert_eq!(out.0, render(&[RED, BLUE], 1, 2, ONE, Config::default()));
    encoder.redraw();
    // Fail after some complete cells/attributes have already been sent.
    struct Partial(usize);
    impl Write for Partial {
        type Error = ();
        fn write_all(&mut self, _: &[u8]) -> Result<(), ()> {
            self.0 += 1;
            if self.0 == 9 {
                Err(())
            } else {
                Ok(())
            }
        }
    }
    assert_eq!(encoder.render(&frame, &mut Partial(0)), Err(()));
    out.0.clear();
    encoder.render(&frame, &mut out).unwrap();
    assert_eq!(out.0, render(&[RED, BLUE], 1, 2, ONE, Config::default()));
}

#[test]
fn validates_storage_and_frame_dimensions() {
    assert!(matches!(Frame::new(&[RED], 0, 1), Err(FrameError::Empty)));
    assert!(matches!(Frame::new(&[RED], 1, 2), Err(FrameError::Length)));
    assert!(matches!(
        Encoder::new(&mut [], ONE, Config::default()),
        Err(Error::Capacity)
    ));
    assert!(matches!(
        Encoder::new(&mut [], Size { cols: 0, rows: 1 }, Config::default()),
        Err(Error::EmptySize)
    ));
    assert_eq!(std::mem::size_of::<Cell>(), 12);
}

fn key_event(key: Key) -> Event {
    Event::Key(KeyEvent {
        key,
        modifiers: Modifiers::default(),
    })
}
fn decode_split(sequence: &[u8], expected: Event) {
    // Every possible single read split, plus one byte at a time.
    for split in 0..=sequence.len() {
        let mut decoder = Decoder::new();
        let mut events = Vec::new();
        decoder.feed(&sequence[..split], |e| events.push(e));
        decoder.feed(&sequence[split..], |e| events.push(e));
        assert_eq!(events, [expected], "sequence {sequence:?}, split {split}");
    }
    let mut decoder = Decoder::new();
    let mut events = Vec::new();
    for byte in sequence {
        decoder.feed(&[*byte], |e| events.push(e));
    }
    assert_eq!(events, [expected]);
}

#[test]
fn keys_csi_ss3_and_tilde_every_split() {
    for (suffix, key) in [
        (b'A', Key::Up),
        (b'B', Key::Down),
        (b'C', Key::Right),
        (b'D', Key::Left),
        (b'H', Key::Home),
        (b'F', Key::End),
        (b'P', Key::Function(1)),
        (b'Q', Key::Function(2)),
        (b'R', Key::Function(3)),
        (b'S', Key::Function(4)),
    ] {
        for prefix in *b"[O" {
            decode_split(&[27, prefix, suffix], key_event(key));
        }
    }
    for (number, code) in [
        (1, Key::Home),
        (2, Key::Insert),
        (3, Key::Delete),
        (4, Key::End),
        (5, Key::PageUp),
        (6, Key::PageDown),
        (7, Key::Home),
        (8, Key::End),
        (11, Key::Function(1)),
        (12, Key::Function(2)),
        (13, Key::Function(3)),
        (14, Key::Function(4)),
        (15, Key::Function(5)),
        (17, Key::Function(6)),
        (18, Key::Function(7)),
        (19, Key::Function(8)),
        (20, Key::Function(9)),
        (21, Key::Function(10)),
        (23, Key::Function(11)),
        (24, Key::Function(12)),
    ] {
        decode_split(format!("\x1b[{number}~").as_bytes(), key_event(code));
    }
    for modifiers in 1..=8 {
        let expected = Event::Key(KeyEvent {
            key: Key::Up,
            modifiers: Modifiers(modifiers - 1),
        });
        decode_split(format!("\x1b[1;{modifiers}A").as_bytes(), expected);
        decode_split(format!("\x1bO1;{modifiers}A").as_bytes(), expected);
    }
    decode_split(
        b"\x1b[15;5~",
        Event::Key(KeyEvent {
            key: Key::Function(5),
            modifiers: Modifiers::CTRL,
        }),
    );
    decode_split(
        b"\x1b[Z",
        Event::Key(KeyEvent {
            key: Key::Tab,
            modifiers: Modifiers::SHIFT,
        }),
    );
}

#[test]
fn printable_unicode_controls_alt_and_escape() {
    for ch in ['a', ' ', '~', 'é', '界', '🦀'] {
        decode_split(ch.to_string().as_bytes(), key_event(Key::Char(ch)));
    }
    for (byte, code) in [
        (b'\r', Key::Enter),
        (b'\n', Key::Enter),
        (b'\t', Key::Tab),
        (127, Key::Backspace),
        (8, Key::Backspace),
    ] {
        decode_split(&[byte], key_event(code));
    }
    for (byte, ch) in [(1, 'a'), (12, 'l'), (17, 'q'), (26, 'z')] {
        decode_split(
            &[byte],
            Event::Key(KeyEvent {
                key: Key::Char(ch),
                modifiers: Modifiers::CTRL,
            }),
        );
    }
    decode_split(
        b"\x1bx",
        Event::Key(KeyEvent {
            key: Key::Char('x'),
            modifiers: Modifiers::ALT,
        }),
    );
    decode_split(
        "\x1bé".as_bytes(),
        Event::Key(KeyEvent {
            key: Key::Char('é'),
            modifiers: Modifiers::ALT,
        }),
    );
    let mut decoder = Decoder::new();
    decoder.feed(b"\x1b", |_| panic!("early escape"));
    assert_eq!(decoder.escape_timeout(), Some(key_event(Key::Escape)));
    assert_eq!(decoder.escape_timeout(), None);
    decoder.feed(b"\x1b[1;", |_| panic!("partial CSI"));
    assert_eq!(decoder.escape_timeout(), None);
    let mut events = Vec::new();
    decoder.feed(b"5A", |e| events.push(e));
    assert_eq!(
        events,
        [Event::Key(KeyEvent {
            key: Key::Up,
            modifiers: Modifiers::CTRL
        })]
    );
}

#[test]
fn mouse_all_buttons_actions_modifiers_and_splits() {
    for (n, button) in [(0, Button::Left), (1, Button::Middle), (2, Button::Right)] {
        for (bits, final_byte, kind) in [
            (n, 'M', MouseKind::Press(button)),
            (n, 'm', MouseKind::Release(Some(button))),
            (n + 32, 'M', MouseKind::Drag(Some(button))),
        ] {
            for flags in 0..8 {
                let raw_mods = ((flags & 1) * 4) | ((flags & 2) * 4) | ((flags & 4) * 4);
                decode_split(
                    format!("\x1b[<{};160;60{final_byte}", bits + raw_mods).as_bytes(),
                    Event::Mouse(Mouse {
                        kind,
                        col: 159,
                        row: 59,
                        modifiers: Modifiers(flags as u8),
                    }),
                );
            }
        }
    }
    for (raw, kind) in [
        (3, MouseKind::Release(None)),
        (35, MouseKind::Drag(None)),
        (64, MouseKind::Wheel(Wheel::Up)),
        (65, MouseKind::Wheel(Wheel::Down)),
        (66, MouseKind::Wheel(Wheel::Left)),
        (67, MouseKind::Wheel(Wheel::Right)),
    ] {
        decode_split(
            format!("\x1b[<{raw};1;1M").as_bytes(),
            Event::Mouse(Mouse {
                kind,
                col: 0,
                row: 0,
                modifiers: Modifiers::default(),
            }),
        );
    }
}

#[test]
fn probe_and_session_controls() {
    decode_split(b"\x1b[60;160R", Event::Size(Size::default()));
    for mode in [1000, 1002, 1006] {
        assert!(ENTER
            .windows(format!("\x1b[?{mode}h").len())
            .any(|w| w == format!("\x1b[?{mode}h").as_bytes()));
        assert!(EXIT
            .windows(format!("\x1b[?{mode}l").len())
            .any(|w| w == format!("\x1b[?{mode}l").as_bytes()));
    }
    assert!(SIZE_PROBE.windows(4).any(|w| w == b"\x1b[6n"));
}

#[test]
fn malformed_and_oversized_sequences_recover() {
    for sequence in [
        b"\x1b[99999999999A".as_slice(),
        b"\x1b[<0;0;1M",
        b"\x1b[<128;1;1M",
        b"\x1b[<0;1M",
        b"\x1b[0;2R",
        b"\x1b[1;;2A",
        b"\x1b[1;9A",
        b"\x1b[?25h",
        b"\xff",
        b"\xc0\xaf",
        b"\xed\xa0\x80",
        b"\xf4\x90\x80\x80",
    ] {
        let mut decoder = Decoder::new();
        let mut events = Vec::new();
        decoder.feed(sequence, |e| events.push(e));
        decoder.feed(b"x", |e| events.push(e));
        assert_eq!(events, [key_event(Key::Char('x'))], "{sequence:?}");
    }
    let mut decoder = Decoder::new();
    let mut events = Vec::new();
    decoder.feed(b"\x1b[", |e| events.push(e));
    decoder.feed(&[b'1'; 100], |e| events.push(e));
    decoder.feed(b"Ax\x1b[12\x1bOB", |e| events.push(e));
    assert_eq!(events, [key_event(Key::Char('x')), key_event(Key::Down)]);
}
