use sc98_pixels::{
    app::{Action, App, Command, Dialog, Event, Key, Layout, TOOLS},
    draw::{Bevel, Canvas, Rect, BLACK, FACE, WHITE},
    font,
    framebuffer::{BufferError, Color, Framebuffer, Indexed16, Rgb565, PALETTE},
    icons,
    model::{DemoPart, Feature, Part, Triangle, Vec3},
    view::{self, RenderError, Style, View, Visibility},
    widgets::{self, ButtonState, MessageKind},
};
use std::{fs, path::PathBuf};

fn golden(name: &str, pixels: &[u16]) {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("tests/golden")
        .join(format!("{name}.rgb565"));
    let bytes: Vec<u8> = pixels.iter().flat_map(|p| p.to_le_bytes()).collect();
    if std::env::var_os("UPDATE_GOLDENS").is_some() {
        fs::write(&path, &bytes).unwrap();
    }
    let reference = fs::read(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    assert_eq!(reference.len(), bytes.len(), "{name}: dimensions changed");
    if let Some(i) = reference.iter().zip(&bytes).position(|(a, b)| a != b) {
        panic!(
            "{name}: first changed pixel {}: reference {:04x}, actual {:04x}",
            i / 2,
            u16::from_le_bytes([reference[i / 2 * 2], reference[i / 2 * 2 + 1]]),
            pixels[i / 2]
        );
    }
}
fn image(w: usize, h: usize, draw: impl FnOnce(&mut Canvas<'_, Rgb565<'_>>)) -> Vec<u16> {
    let mut pixels = vec![0; w * h];
    let mut fb = Rgb565::new(&mut pixels, w, h).unwrap();
    draw(&mut Canvas::new(&mut fb));
    pixels
}
#[test]
fn framebuffer_bounds_blit_and_palette() {
    let mut pixels = [0x1234; 18];
    {
        let mut fb = Rgb565::new(&mut pixels[1..17], 4, 4).unwrap();
        fb.fill(-2, -2, 4, 4, WHITE);
        fb.set(-1, 0, BLACK);
        fb.set(4, 4, BLACK);
        fb.blit(3, 3, 2, 2, &[1, 2, 3, 4]).unwrap();
        assert_eq!(fb.blit(0, 0, 2, 2, &[0]), Err(BufferError::TooShort));
        assert_eq!(fb.pixels()[0], WHITE.0);
        assert_eq!(fb.pixels()[5], WHITE.0);
        assert_eq!(fb.pixels()[6], 0x1234);
        assert_eq!(fb.pixels()[15], 1);
    }
    assert_eq!(pixels[0], 0x1234);
    assert_eq!(pixels[17], 0x1234);
    assert!(matches!(
        Rgb565::new(&mut [], 0, 2),
        Err(BufferError::Dimensions)
    ));
    assert!(matches!(
        Rgb565::new(&mut [], 2, 2),
        Err(BufferError::TooShort)
    ));
    let mut indices = [0u8; 16];
    let mut fb = Indexed16::new(&mut indices, 16, 1).unwrap();
    for (i, c) in PALETTE.iter().enumerate() {
        fb.set(i as i32, 0, *c);
    }
    assert_eq!(fb.pixels(), &(0..16).collect::<Vec<_>>());
    fb.fill(-4, 0, 8, 1, PALETTE[12]);
    assert_eq!(&fb.pixels()[..4], &[12; 4]);
}
#[test]
fn const_art_matches_reference_and_golden() {
    let source = include_str!("../../../freebasic/src/font.bi");
    let widths = source
        .split("Dim Shared FontBits")
        .next()
        .unwrap()
        .split("= {")
        .nth(1)
        .unwrap();
    let numbers: Vec<u8> = widths
        .split(|c: char| !c.is_ascii_digit())
        .filter(|s| !s.is_empty())
        .map(|s| s.parse().unwrap())
        .collect();
    assert_eq!(numbers, font::WIDTHS);
    let bits = source.split("As UByte = {").nth(2).unwrap();
    let numbers: Vec<u8> = bits
        .split(|c: char| !c.is_ascii_digit())
        .filter(|s| !s.is_empty())
        .map(|s| s.parse().unwrap())
        .collect();
    assert_eq!(
        numbers,
        font::BITS.into_iter().flatten().collect::<Vec<_>>()
    );
    let source = include_str!("../../../freebasic/src/icons.bi");
    let art = source.split("Dim Shared IconArt").nth(1).unwrap();
    let rows: Vec<_> = art
        .split('"')
        .filter(|s| s.len() == 16 && s.bytes().all(|b| b == b'.' || b.is_ascii_hexdigit()))
        .collect();
    assert_eq!(rows.len(), 17 * 16);
    for (i, row) in rows.iter().enumerate() {
        for (j, b) in row.bytes().enumerate() {
            let expected = if b == b'.' {
                255
            } else {
                (b as char).to_digit(16).unwrap() as u8
            };
            assert_eq!(icons::ART[i / 16][i % 16 * 16 + j], expected);
        }
    }
    let names = source
        .split("Dim Shared IconName")
        .nth(1)
        .unwrap()
        .split("Dim Shared IconArt")
        .next()
        .unwrap();
    let names: Vec<_> = names
        .split('"')
        .enumerate()
        .filter_map(|(i, s)| if i % 2 == 1 { Some(s) } else { None })
        .collect();
    assert_eq!(names, icons::NAMES);
    assert_eq!(icons::NAMES.len(), 17);
    assert_eq!(font::HEIGHT, 11);
    golden(
        "art-256x160",
        &image(256, 160, |c| {
            c.fill(Rect::new(0, 0, 256, 160), FACE);
            for ch in 32u8..128 {
                let b = [ch];
                c.text(
                    4 + ((ch - 32) % 16) as i32 * 15,
                    4 + ((ch - 32) / 16) as i32 * 14,
                    std::str::from_utf8(&b).unwrap(),
                    BLACK,
                    false,
                );
            }
            for (i, name) in icons::NAMES.iter().enumerate() {
                c.icon(
                    4 + (i % 13) as i32 * 19,
                    94 + (i / 13) as i32 * 20,
                    name,
                    false,
                );
                c.icon(4 + (i % 13) as i32 * 19, 134, name, true);
            }
        }),
    );
}
#[test]
fn widgets_golden() {
    golden(
        "widgets-240x180",
        &image(240, 180, |c| {
            widgets::window(c, Rect::new(0, 0, 240, 180), "SolidCraft 98", true, true);
            for (i, kind) in [
                Bevel::Raised,
                Bevel::Button,
                Bevel::Pressed,
                Bevel::Sunken,
                Bevel::ThinUp,
                Bevel::ThinDown,
            ]
            .iter()
            .enumerate()
            {
                c.bevel(Rect::new(5 + i as i32 * 38, 26, 34, 19), *kind);
            }
            widgets::button(
                c,
                Rect::new(6, 50, 70, 23),
                "&OK",
                ButtonState {
                    default: true,
                    focused: true,
                    ..ButtonState::default()
                },
            );
            widgets::button(
                c,
                Rect::new(84, 50, 70, 23),
                "Cancel",
                ButtonState {
                    pressed: true,
                    ..ButtonState::default()
                },
            );
            widgets::button(
                c,
                Rect::new(162, 50, 70, 23),
                "Help",
                ButtonState {
                    disabled: true,
                    ..ButtonState::default()
                },
            );
            widgets::tree(c, Rect::new(6, 79, 144, 76), &DemoPart, Some(1), 0);
            widgets::edit(c, Rect::new(156, 80, 76, 21), "20.5", true);
            for (i, kind) in [
                MessageKind::Critical,
                MessageKind::Warning,
                MessageKind::Info,
                MessageKind::Question,
            ]
            .into_iter()
            .enumerate()
            {
                widgets::message_icon(
                    c,
                    158 + (i % 2) as i32 * 36,
                    105 + (i / 2) as i32 * 25,
                    kind,
                );
            }
            widgets::status_bar(c, Rect::new(0, 158, 240, 22), "Ready", false);
        }),
    );
    golden(
        "numbers-318x197",
        &image(318, 197, |c| {
            widgets::number_dialog(
                c,
                Rect::new(0, 0, 318, 197),
                "Sketch Rectangle",
                &[
                    ("Width (mm)", "80"),
                    ("Height (mm)", "50"),
                    ("Corner radius (mm)", "6"),
                ],
                1,
            )
        }),
    );
    golden(
        "message-240x142",
        &image(240, 142, |c| {
            widgets::message_box(
                c,
                Rect::new(0, 0, 240, 142),
                "SolidCraft 98",
                "Run-time error '13':\n\nType mismatch",
                MessageKind::Critical,
            )
        }),
    );
}
fn scene(style: Style, painter: bool) -> Vec<u16> {
    image(128, 96, |c| {
        let r = Rect::new(0, 0, 128, 96);
        let mut v = View::default();
        v.fit(r, &DemoPart);
        let mut z = vec![0.; 128 * 96];
        let mut faces = vec![0; 128 * 96];
        let mut order = [0; 24];
        let visibility = if painter {
            Visibility::Painter { order: &mut order }
        } else {
            Visibility::Depth {
                depth: &mut z,
                faces: &mut faces,
            }
        };
        view::render(c, r, &DemoPart, &v, style, visibility).unwrap();
    })
}
#[test]
fn view_goldens() {
    golden("depth-128x96", &scene(Style::Shaded, false));
    golden("painter-128x96", &scene(Style::Shaded, true));
    golden("wire-128x96", &scene(Style::Wireframe, true));
}
struct Mesh(Vec<Triangle>);
impl Part for Mesh {
    fn name(&self) -> &str {
        "Test"
    }
    fn features(&self) -> &[Feature<'_>] {
        &[]
    }
    fn triangles(&self) -> &[Triangle] {
        &self.0
    }
}
#[test]
fn depth_is_order_independent_and_interpolates_crossing_surfaces() {
    // Eye is +Y. Both triangles project onto exactly the same screen triangle;
    // their depth gradients cross through the middle.
    let tri = |ys: [f32; 3], color, face| Triangle {
        vertices: [
            Vec3::new(-10., ys[0], -10.),
            Vec3::new(10., ys[1], -10.),
            Vec3::new(0., ys[2], 10.),
        ],
        normal: Vec3::new(0., 1., 0.),
        color,
        face,
    };
    let a = tri([5., -5., 0.], Color::rgb(255, 0, 0), 1);
    let b = tri([-5., 5., 0.], Color::rgb(0, 0, 255), 2);
    let draw = |mesh: &Mesh| {
        image(64, 64, |c| {
            let mut z = [0.; 4096];
            let mut faces = [0; 4096];
            view::render(
                c,
                Rect::new(0, 0, 64, 64),
                mesh,
                &View {
                    yaw: 0.,
                    pitch: 0.,
                    zoom: 2.,
                    pan_x: 0.,
                    pan_y: 0.,
                },
                Style::Shaded,
                Visibility::Depth {
                    depth: &mut z,
                    faces: &mut faces,
                },
            )
            .unwrap();
        })
    };
    let first = draw(&Mesh(vec![a, b]));
    let second = draw(&Mesh(vec![b, a]));
    assert_eq!(first, second);
    let left = Color(first[38 * 64 + 24]).channels();
    let right = Color(first[38 * 64 + 40]).channels();
    assert!(left[2] > left[0], "left should be blue: {left:?}");
    assert!(right[0] > right[2], "right should be red: {right:?}");
}
#[test]
fn renderer_checks_scratch_and_skips_bad_geometry() {
    let mut rgb = [0; 64];
    let mut fb = Rgb565::new(&mut rgb, 8, 8).unwrap();
    let mut c = Canvas::new(&mut fb);
    let r = Rect::new(0, 0, 8, 8);
    assert_eq!(
        view::render(
            &mut c,
            r,
            &DemoPart,
            &View::default(),
            Style::Shaded,
            Visibility::Depth {
                depth: &mut [],
                faces: &mut []
            }
        ),
        Err(RenderError::DepthTooShort)
    );
    assert_eq!(
        view::render(
            &mut c,
            r,
            &DemoPart,
            &View::default(),
            Style::Shaded,
            Visibility::Painter { order: &mut [] }
        ),
        Err(RenderError::OrderTooShort)
    );
    let mut order = [0; 24];
    assert_eq!(
        view::render(
            &mut c,
            Rect::new(-1, 0, 8, 8),
            &DemoPart,
            &View::default(),
            Style::Wireframe,
            Visibility::Painter { order: &mut order }
        ),
        Err(RenderError::InvalidViewport)
    );
    let mut tri = DemoPart.triangles()[0];
    tri.vertices[0].x = f32::NAN;
    view::render(
        &mut c,
        r,
        &Mesh(vec![tri]),
        &View::default(),
        Style::Wireframe,
        Visibility::Painter { order: &mut [] },
    )
    .unwrap();
}
#[test]
fn both_layouts_menus_drawer_and_all_number_fields_work() {
    for layout in [Layout::Classic, Layout::Compact] {
        let mut app = App::new(layout, &DemoPart);
        let before = app.view.yaw;
        app.event(Event::Orbit { dx: 12., dy: 3. }, &DemoPart);
        assert_ne!(app.view.yaw, before);
        app.event(Event::Key(Key::Character('s')), &DemoPart);
        assert_eq!(app.style, Style::Wireframe);
        for m in 0..7 {
            app.menu = Some(m);
            app.hot_item = 0;
            let r = app.menu_rect(m);
            let result = app.event(
                Event::Click {
                    x: r.x + 25,
                    y: r.y + 8,
                },
                &DemoPart,
            );
            assert!(matches!(result, Action::Command(_)));
            app.dialog = Dialog::None;
        }
        app.command(Command::Rectangle, &DemoPart);
        for _ in 0..6 {
            app.event(Event::Key(Key::Tab), &DemoPart);
        }
        app.event(Event::Key(Key::Backspace), &DemoPart);
        app.event(Event::Text('7'), &DemoPart);
        assert!(
            matches!(app.event(Event::Key(Key::Enter),&DemoPart),Action::Parameters{count:7,values,..} if values[6]==7.)
        );
        app.dialog = Dialog::None;
        if layout == Layout::Compact {
            app.command(Command::Rectangle, &DemoPart);
            for _ in 0..2 {
                let r = app.dialog_rect();
                app.event(
                    Event::Click {
                        x: r.x + 20,
                        y: r.y + r.h - 52,
                    },
                    &DemoPart,
                );
            }
            app.event(Event::Key(Key::Backspace), &DemoPart);
            app.event(Event::Text('9'), &DemoPart);
            assert!(
                matches!(app.event(Event::Key(Key::Enter),&DemoPart),Action::Parameters{count:7,values,..} if values[6]==9.)
            );
        }
        if layout == Layout::Compact {
            app.event(Event::Key(Key::Tab), &DemoPart);
            assert!(app.drawer);
            let r = app.tool_rect(9);
            assert_eq!(TOOLS[9].1, Command::Shaded);
            assert_eq!(
                app.event(
                    Event::Click {
                        x: r.x + 4,
                        y: r.y + 4
                    },
                    &DemoPart
                ),
                Action::Command(Command::Shaded)
            );
            app.event(Event::Click { x: 230, y: 80 }, &DemoPart);
            assert!(!app.drawer);
        }
    }
}
#[test]
fn clipping_is_restored_and_lines_stay_inside_it() {
    let pixels = image(16, 16, |c| {
        let old = c.set_clip(Rect::new(4, 4, 8, 8));
        c.line(-10000, -10000, 10000, 10000, WHITE);
        c.fill(Rect::new(-99, 8, 1000, 1), WHITE);
        assert_eq!(c.set_clip(old), Rect::new(4, 4, 8, 8));
    });
    for y in 0..16 {
        for x in 0..16 {
            if !(4..12).contains(&x) || !(4..12).contains(&y) {
                assert_eq!(pixels[y * 16 + x], 0);
            }
        }
    }
}
