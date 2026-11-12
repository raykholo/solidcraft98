#![forbid(unsafe_code)]
use minifb::{Key as HostKey, KeyRepeat, MouseButton, MouseMode, Scale, Window, WindowOptions};
use sc98_desktop::{benchmark, screenshot, DesktopResult, Screen};
use sc98_pixels::{
    app::{Action, App, Command, Event, Key, Layout},
    model::{DemoPart, Part},
};
use std::{env, io, path::PathBuf};

#[derive(Debug)]
struct Options {
    layout: Layout,
    painter: bool,
    indexed: bool,
    screenshot: Option<PathBuf>,
    benchmark: bool,
    frames: Option<usize>,
}
fn options() -> DesktopResult<Option<Options>> {
    let mut o = Options {
        layout: Layout::Classic,
        painter: false,
        indexed: false,
        screenshot: None,
        benchmark: false,
        frames: None,
    };
    let mut args = env::args().skip(1);
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--compact" | "--320x240" => o.layout = Layout::Compact,
            "--640x480" => o.layout = Layout::Classic,
            "--painter" => o.painter = true,
            "--indexed" => o.indexed = true,
            "--benchmark" => o.benchmark = true,
            "--screenshot" => {
                o.screenshot =
                    Some(PathBuf::from(args.next().ok_or_else(|| {
                        io::Error::other("--screenshot needs a PNG path")
                    })?))
            }
            "--frames" => {
                o.frames = Some(
                    args.next()
                        .ok_or_else(|| io::Error::other("--frames needs a count"))?
                        .parse()?,
                )
            }
            "--help" | "-h" => {
                println!("SolidCraft 98 Professional Edition\n\n--compact       320 x 240 screen\n--640x480       640 x 480 screen (default)\n--painter       shade without a depth buffer\n--indexed       16-colour display\n--screenshot P  save a PNG and exit\n--benchmark     time a 300-triangle part\n--frames N      close the window after N frames\n\nDrag: orbit; right drag: pan; wheel or +/-: zoom\nS: shaded; I: isometric; F: fit; Tab: drawer\nMenus: click, then arrows and Enter; Esc: close");
                return Ok(None);
            }
            _ => return Err(io::Error::other(format!("Unknown option: {arg}")).into()),
        }
    }
    Ok(Some(o))
}
fn main() -> DesktopResult<()> {
    let Some(o) = options()? else {
        return Ok(());
    };
    if o.benchmark {
        for t in benchmark(120)? {
            println!(
                "300 triangles, 320x240, {:?}, {}: {:.3} ms/frame ({} frames, warm-up excluded)",
                t.style,
                if t.painter { "painter" } else { "depth" },
                t.per_frame.as_secs_f64() * 1000.,
                t.frames
            );
        }
        return Ok(());
    }
    if let Some(path) = o.screenshot {
        return screenshot(o.layout, &path, o.painter, o.indexed);
    }
    let part = DemoPart;
    let mut app = App::new(o.layout, &part);
    let mut screen = Screen::new(o.layout, part.triangles().len(), o.painter, o.indexed);
    let mut window = Window::new(
        "SolidCraft 98 - Professional Edition",
        screen.width,
        screen.height,
        WindowOptions {
            scale: Scale::X1,
            ..WindowOptions::default()
        },
    )?;
    window.set_target_fps(60);
    let mut previous = None;
    let mut left_was_down = false;
    let mut frames = 0;
    while window.is_open() && o.frames.is_none_or(|limit| frames < limit) {
        let left = window.get_mouse_down(MouseButton::Left);
        let right = window.get_mouse_down(MouseButton::Right);
        if let Some((x, y)) = window.get_mouse_pos(MouseMode::Discard) {
            app.event(
                Event::Hover {
                    x: x as i32,
                    y: y as i32,
                },
                &part,
            );
            if left && !left_was_down {
                let a = app.event(
                    Event::Click {
                        x: x as i32,
                        y: y as i32,
                    },
                    &part,
                );
                if handle(a, &mut app) {
                    break;
                }
            }
            if let Some((px, py)) = previous {
                if app.menu.is_none()
                    && app.dialog == sc98_pixels::app::Dialog::None
                    && app.layout.viewport().contains(x as i32, y as i32)
                    && !app.drawer
                {
                    if left && left_was_down {
                        app.event(
                            Event::Orbit {
                                dx: x - px,
                                dy: y - py,
                            },
                            &part,
                        );
                    }
                    if right {
                        app.event(
                            Event::Pan {
                                dx: x - px,
                                dy: y - py,
                            },
                            &part,
                        );
                    }
                }
            }
            previous = Some((x, y));
        } else {
            previous = None;
        }
        left_was_down = left;
        if let Some((_, dy)) = window.get_scroll_wheel() {
            app.event(Event::Zoom(libm::powf(1.1, dy)), &part);
        }
        let ctrl = window.is_key_down(HostKey::LeftCtrl) || window.is_key_down(HostKey::RightCtrl);
        let alt = window.is_key_down(HostKey::LeftAlt) || window.is_key_down(HostKey::RightAlt);
        for key in window.get_keys_pressed(KeyRepeat::Yes) {
            if ctrl {
                let cmd = match key {
                    HostKey::N => Some(Command::New),
                    HostKey::O => Some(Command::Open),
                    HostKey::S => Some(Command::Save),
                    HostKey::Z => Some(Command::Undo),
                    _ => None,
                };
                if let Some(cmd) = cmd {
                    let a = app.command(cmd, &part);
                    if handle(a, &mut app) {
                        return Ok(());
                    }
                }
                continue;
            }
            if alt {
                if let Some(i) = match key {
                    HostKey::F => Some(0),
                    HostKey::E => Some(1),
                    HostKey::S => Some(2),
                    HostKey::T => Some(3),
                    HostKey::V => Some(4),
                    HostKey::W => Some(5),
                    HostKey::H => Some(6),
                    _ => None,
                } {
                    app.menu = Some(i);
                    app.hot_item = 0;
                }
                continue;
            }
            let numbers = matches!(app.dialog, sc98_pixels::app::Dialog::Numbers(_));
            let event = if numbers {
                text_key(key)
                    .map(Event::Text)
                    .or_else(|| ui_key(key).map(Event::Key))
            } else {
                ui_key(key).map(Event::Key)
            };
            if let Some(event) = event {
                let a = app.event(event, &part);
                if handle(a, &mut app) {
                    return Ok(());
                }
            }
        }
        screen.draw(&app, &part, o.painter, o.indexed)?;
        window.update_with_buffer(&screen.output, screen.width, screen.height)?;
        frames += 1;
    }
    Ok(())
}
// Commands that need the core are surfaced honestly by the demo host. The
// reusable App returns each action so the real host can implement it later.
fn handle(a: Action, app: &mut App) -> bool {
    match a {
        Action::Command(Command::Exit) => return true,
        Action::Parameters { .. } => app.status = "Dimensions accepted.",
        Action::Command(
            Command::Open
            | Command::Save
            | Command::SaveAs
            | Command::Floppy
            | Command::Publish
            | Command::Export
            | Command::New
            | Command::Close
            | Command::Undo
            | Command::Delete,
        ) => {
            app.dialog = sc98_pixels::app::Dialog::Message;
            app.message = "No disk in drive A:.\nPlease insert a disk.";
        }
        _ => {}
    }
    false
}
fn ui_key(k: HostKey) -> Option<Key> {
    Some(match k {
        HostKey::Escape => Key::Escape,
        HostKey::Enter => Key::Enter,
        HostKey::Tab => Key::Tab,
        HostKey::Backspace => Key::Backspace,
        HostKey::Delete => Key::Delete,
        HostKey::Up => Key::Up,
        HostKey::Down => Key::Down,
        HostKey::Left => Key::Left,
        HostKey::Right => Key::Right,
        HostKey::Equal | HostKey::NumPadPlus => Key::Plus,
        HostKey::Minus | HostKey::NumPadMinus => Key::Minus,
        HostKey::F1 => Key::F1,
        HostKey::F5 => Key::F5,
        HostKey::A => Key::Character('a'),
        HostKey::B => Key::Character('b'),
        HostKey::C => Key::Character('c'),
        HostKey::D => Key::Character('d'),
        HostKey::E => Key::Character('e'),
        HostKey::F => Key::Character('f'),
        HostKey::G => Key::Character('g'),
        HostKey::H => Key::Character('h'),
        HostKey::I => Key::Character('i'),
        HostKey::J => Key::Character('j'),
        HostKey::K => Key::Character('k'),
        HostKey::L => Key::Character('l'),
        HostKey::M => Key::Character('m'),
        HostKey::N => Key::Character('n'),
        HostKey::O => Key::Character('o'),
        HostKey::P => Key::Character('p'),
        HostKey::Q => Key::Character('q'),
        HostKey::R => Key::Character('r'),
        HostKey::S => Key::Character('s'),
        HostKey::T => Key::Character('t'),
        HostKey::U => Key::Character('u'),
        HostKey::V => Key::Character('v'),
        HostKey::W => Key::Character('w'),
        HostKey::X => Key::Character('x'),
        HostKey::Y => Key::Character('y'),
        HostKey::Z => Key::Character('z'),
        _ => return None,
    })
}
fn text_key(k: HostKey) -> Option<char> {
    Some(match k {
        HostKey::Key0 | HostKey::NumPad0 => '0',
        HostKey::Key1 | HostKey::NumPad1 => '1',
        HostKey::Key2 | HostKey::NumPad2 => '2',
        HostKey::Key3 | HostKey::NumPad3 => '3',
        HostKey::Key4 | HostKey::NumPad4 => '4',
        HostKey::Key5 | HostKey::NumPad5 => '5',
        HostKey::Key6 | HostKey::NumPad6 => '6',
        HostKey::Key7 | HostKey::NumPad7 => '7',
        HostKey::Key8 | HostKey::NumPad8 => '8',
        HostKey::Key9 | HostKey::NumPad9 => '9',
        HostKey::Period | HostKey::NumPadDot => '.',
        HostKey::Minus | HostKey::NumPadMinus => '-',
        HostKey::Equal | HostKey::NumPadPlus => '+',
        HostKey::E => 'e',
        _ => return None,
    })
}
