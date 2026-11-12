use sc98_app::{App, Layout, RamError, RamStorage, Storage};
use sc98_core::{Feature, FeatureKind as K, Part};
use sc98_term::{Cell, Config, Decoder, Encoder, Event, Key, KeyEvent, Modifiers, Size, Write};
fn key(k: Key) -> Event {
    Event::Key(KeyEvent {
        key: k,
        modifiers: Modifiers::default(),
    })
}
fn feed(app: &mut App<RamStorage>, bytes: &[u8]) {
    let mut decoder = Decoder::new();
    decoder.feed(bytes, |e| {
        app.tick(Some(e)).unwrap();
    });
}
fn fresh() -> App<RamStorage> {
    App::new(
        Layout::Compact,
        RamStorage::new(1_000_000),
        Part::new("Part1"),
    )
    .unwrap()
}
fn field(app: &mut App<RamStorage>, text: &str) {
    for _ in 0..24 {
        app.tick(Some(key(Key::Backspace))).unwrap();
    }
    feed(app, text.as_bytes());
}

#[test]
fn scripted_new_rectangle_extrude_export_matches_core() {
    let mut app: App<RamStorage> =
        App::sample(Layout::Compact, RamStorage::new(1_000_000)).unwrap();
    feed(&mut app, b"\x0er"); // Ctrl-N, rectangle
    field(&mut app, "80/2");
    feed(&mut app, b"\t");
    field(&mut app, "30");
    feed(&mut app, b"\r");
    feed(&mut app, b"e");
    field(&mut app, "12.3456789");
    feed(&mut app, b"\r");
    // File > Export, through the decoder and menu navigation.
    feed(&mut app, b"\x1bf");
    for _ in 0..6 {
        feed(&mut app, b"\x1b[B");
    }
    feed(&mut app, b"\r\r");
    let bytes = app.storage.load("Part1.stl").unwrap();
    let mut expected = Part::new("Part1");
    expected
        .add_feature(Feature {
            kind: K::Rectangle,
            p1: 40.,
            p2: 30.,
            ..Feature::default()
        })
        .unwrap();
    expected
        .add_feature(Feature {
            kind: K::Extrude,
            reference: 1,
            p1: 12.3456789,
            ..Feature::default()
        })
        .unwrap();
    assert_eq!(app.part(), &expected);
    assert_eq!(bytes, expected.mesh(64).unwrap().to_stl("Part1").unwrap());
    feed(&mut app, b"\x13\r");
    let saved = app.storage.load("Part1.sc98").unwrap();
    assert_eq!(saved, expected.to_sc98());
    feed(&mut app, b"\x0e\x0f\r");
    assert_eq!(app.part(), &expected);
}

#[test]
fn every_menu_item_dispatches_from_decoded_input() {
    for (menu, items) in sc98_pixels::app::MENUS.iter().enumerate() {
        for (index, item) in items.iter().enumerate() {
            let mut app: App<RamStorage> =
                App::sample(Layout::Compact, RamStorage::new(1_000_000)).unwrap();
            app.ui.selected = Some(0);
            let mnemonic = b"festvwh"[menu];
            feed(&mut app, &[27, mnemonic]);
            for _ in 0..index {
                feed(&mut app, b"\x1b[B");
            }
            feed(&mut app, b"\r");
            assert_eq!(app.last_command, Some(item.command), "{}", item.label);
        }
    }
}

#[test]
fn edit_delete_dependents_and_invalid_parameters() {
    let mut app = fresh();
    feed(&mut app, b"r\re\r");
    assert_eq!(app.part().features().len(), 2);
    feed(&mut app, b"\r");
    field(&mut app, "45");
    feed(&mut app, b"\r");
    assert_eq!(app.part().feature(2).unwrap().p1, 45.);
    app.ui.selected = Some(0);
    feed(&mut app, b"\x1b[3~");
    assert_eq!(app.part().features().len(), 2);
    feed(&mut app, b"\x1b");
    app.tick(Some(key(Key::Escape))).unwrap();
    assert_eq!(app.part().features().len(), 2);
    feed(&mut app, b"\x1b[3~\r");
    assert!(app.part().features().is_empty());
    feed(&mut app, b"r");
    field(&mut app, "-1");
    feed(&mut app, b"\r");
    assert!(app.part().features().is_empty());
}

#[test]
fn circle_revolve_and_hole_change_real_model() {
    let mut app = fresh();
    feed(&mut app, b"c");
    field(&mut app, "5");
    feed(&mut app, b"\t");
    field(&mut app, "15");
    feed(&mut app, b"\rv\r");
    assert_eq!(app.part().feature(2).unwrap().kind, K::Revolve);
    assert!(!app.export_stl().unwrap().is_empty());
    feed(&mut app, b"\x0er\re\rh\r");
    assert_eq!(app.part().feature(3).unwrap().kind, K::Hole);
    let stl = app.export_stl().unwrap();
    assert_eq!(stl, app.part().mesh(64).unwrap().to_stl("Part1").unwrap());
}

#[test]
fn classic_and_compact_first_frame_chrome_matches_pixel_goldens() {
    for (layout, name) in [
        (Layout::Classic, "desktop-640x480.png"),
        (Layout::Compact, "desktop-320x240.png"),
    ] {
        let mut app: App<RamStorage> = App::sample(layout, RamStorage::new(1_000_000)).unwrap();
        app.tick(None).unwrap();
        let path = std::path::Path::new(env!("CARGO_MANIFEST_DIR"))
            .join("../docs")
            .join(name);
        let mut reader = png::Decoder::new(std::fs::File::open(path).unwrap())
            .read_info()
            .unwrap();
        let mut data = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut data).unwrap();
        let (w, h) = layout.size();
        assert_eq!((info.width as usize, info.height as usize), (w, h));
        // The real nine-feature sample replaces the bring-up golden's two boxes.
        // Compare the complete menu/title/toolbar and status chrome where shared.
        for y in (0..if layout == Layout::Classic { 72 } else { 43 }).chain(h - 22..h) {
            for x in 0..w {
                let i = y * w + x;
                let rgb = &data[i * 3..i * 3 + 3];
                let expected = sc98_pixels::framebuffer::Color::rgb(rgb[0], rgb[1], rgb[2]);
                assert_eq!(app.pixels()[i], expected.0, "{layout:?} at {x},{y}");
            }
        }
    }
}
struct Bytes(Vec<u8>);
impl Write for Bytes {
    type Error = core::convert::Infallible;
    fn write_all(&mut self, b: &[u8]) -> Result<(), Self::Error> {
        self.0.extend_from_slice(b);
        Ok(())
    }
}
#[test]
fn unchanged_frame_sends_no_bytes_and_view_input_changes_frame() {
    let mut app: App<RamStorage> =
        App::sample(Layout::Compact, RamStorage::new(1_000_000)).unwrap();
    let mut cells = vec![Cell::EMPTY; 160 * 60];
    let mut encoder = Encoder::new(&mut cells, Size::default(), Config::default()).unwrap();
    let mut bytes = Bytes(Vec::new());
    encoder
        .render(&app.tick(None).unwrap(), &mut bytes)
        .unwrap();
    assert!(!bytes.0.is_empty());
    bytes.0.clear();
    encoder
        .render(&app.tick(None).unwrap(), &mut bytes)
        .unwrap();
    assert!(bytes.0.is_empty());
    encoder
        .render(&app.tick(Some(key(Key::Right))).unwrap(), &mut bytes)
        .unwrap();
    assert!(!bytes.0.is_empty());
    let style = app.ui.style;
    feed(&mut app, b"s");
    assert_ne!(style, app.ui.style);
}
#[test]
fn ram_store_replaces_files_within_budget() {
    let mut s = RamStorage::new(4);
    s.save("a", &[1, 2, 3]).unwrap();
    assert_eq!(s.save("b", &[4, 5]), Err(RamError::Full));
    s.save("a", &[4]).unwrap();
    s.save("b", &[2, 3, 4]).unwrap();
    assert_eq!(s.used(), 4);
    assert_eq!(s.load("missing"), Err(RamError::NotFound));
}

#[test]
fn report_memory_for_sample() {
    let app: App<RamStorage> = App::sample(Layout::Compact, RamStorage::new(32768)).unwrap();
    let (frame, cache, features) = app.memory();
    eprintln!("Mounting Plate: {features} features; framebuffer={frame}, display cache={cache} bytes on {}-bit host",usize::BITS);
    eprintln!(
        "core Feature={}, Triangle={}, pixel Triangle={}, Edge={}, terminal Cell={}",
        std::mem::size_of::<Feature>(),
        std::mem::size_of::<sc98_core::Triangle>(),
        std::mem::size_of::<sc98_pixels::model::Triangle>(),
        std::mem::size_of::<sc98_pixels::model::Edge>(),
        std::mem::size_of::<Cell>()
    );
    for segments in [16, 32, 64] {
        let mesh = app.part().mesh(segments).unwrap();
        eprintln!(
            "sample mesh {segments} segments: {} triangles, {} bytes of triangle records",
            mesh.triangles().len(),
            std::mem::size_of_val(mesh.triangles())
        );
    }
    let rebuilt = app.part().rebuild(16).unwrap();
    eprintln!(
        "display: {} triangles, {} edges",
        rebuilt.mesh.triangles().len(),
        rebuilt.edges.len()
    );
}

#[test]
fn rgb332_reduces_framebuffer_without_changing_part_or_stl() {
    let mut app = sc98_app::App::<_, sc98_app::Rgb332>::new(
        Layout::Compact,
        RamStorage::new(32768),
        Part::new("Part1"),
    )
    .unwrap();
    let mut decoder = Decoder::new();
    decoder.feed(b"r\re\r", |e| {
        app.tick(Some(e)).unwrap();
    });
    assert_eq!(app.memory().0, 76800);
    assert_eq!(
        app.export_stl().unwrap(),
        app.part().mesh(64).unwrap().to_stl("Part1").unwrap()
    );
}

#[test]
fn mouse_toolbar_and_orbit_work_with_letterboxing() {
    use sc98_term::{Button, Mouse, MouseKind};
    let mut app: App<RamStorage> =
        App::new(Layout::Classic, RamStorage::new(32768), Part::new("Part1")).unwrap();
    app.tick(Some(Event::Size(Size {
        cols: 320,
        rows: 100,
    })))
    .unwrap();
    // 320x200 raster fits the classic image to 266x200, with 27-pixel side margins.
    let tool = app.ui.tool_rect(3);
    let x = tool.x + tool.w / 2;
    let y = tool.y + tool.h / 2;
    let mouse = |kind, x: i32, y: i32| {
        Event::Mouse(Mouse {
            kind,
            col: (27 + x * 266 / 640) as u16,
            row: (y * 200 / 480 / 2) as u16,
            modifiers: Modifiers::default(),
        })
    };
    app.tick(Some(mouse(MouseKind::Press(Button::Left), x, y)))
        .unwrap();
    assert_eq!(app.last_command, Some(sc98_app::Command::Rectangle));
    app.tick(Some(key(Key::Escape))).unwrap();
    let yaw = app.ui.view.yaw;
    app.tick(Some(mouse(MouseKind::Press(Button::Left), 300, 200)))
        .unwrap();
    app.tick(Some(mouse(MouseKind::Drag(Some(Button::Left)), 340, 220)))
        .unwrap();
    assert_ne!(app.ui.view.yaw, yaw);
}

#[test]
fn file_dialog_does_not_click_through_to_toolbar() {
    let mut app = fresh();
    feed(&mut app, b"\x13");
    app.tick(Some(sc98_term::Event::Mouse(sc98_term::Mouse {
        kind: sc98_term::MouseKind::Press(sc98_term::Button::Left),
        col: 10,
        row: 15,
        modifiers: Modifiers::default(),
    })))
    .unwrap();
    assert!(app.part().features().is_empty());
    feed(&mut app, b"\r");
    assert!(app.storage.load("Part1.sc98").is_ok());
}

#[test]
fn sample_export_preserves_core_stl_bytes() {
    let mut app: App<RamStorage> = App::sample(Layout::Compact, RamStorage::new(32768)).unwrap();
    let expected = app
        .part()
        .mesh(64)
        .unwrap()
        .to_stl(&app.part().title)
        .unwrap();
    assert_eq!(app.export_stl().unwrap(), expected);
}
