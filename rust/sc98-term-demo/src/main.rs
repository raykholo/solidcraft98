#![forbid(unsafe_code)]

use sc98_term::{
    Cell, ColourMode, Config, Decoder, Encoder, Event, Filter, Frame, Key, Mode, Modifiers,
    MouseKind, Size, Wheel, Write, ENTER, EXIT, SIZE_PROBE,
};
use sc98_term_demo::{Canvas, Counter, Scalar};
use std::io::{self, Read, Write as IoWrite};
use std::sync::mpsc::{self, Receiver};
use std::time::{Duration, Instant};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;

struct Output<W>(W);
impl<W: IoWrite> Write for Output<W> {
    type Error = io::Error;
    fn write_all(&mut self, bytes: &[u8]) -> io::Result<()> {
        self.0.write_all(bytes)
    }
}

struct Terminal;
impl Terminal {
    fn enter() -> io::Result<Self> {
        crossterm::terminal::enable_raw_mode()?;
        let guard = Self;
        io::stdout().write_all(ENTER)?;
        io::stdout().write_all(SIZE_PROBE)?;
        io::stdout().flush()?;
        Ok(guard)
    }
}
impl Drop for Terminal {
    fn drop(&mut self) {
        let _ = io::stdout().write_all(EXIT);
        let _ = io::stdout().flush();
        let _ = crossterm::terminal::disable_raw_mode();
    }
}

fn main() {
    if let Err(error) = run() {
        eprintln!("SolidCraft 98: {error}");
        std::process::exit(1);
    }
}

fn run() -> Result<()> {
    let mut config = Config::default();
    let mut measure = false;
    let mut pattern = false;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--measure" => measure = true,
            "--wireframe" => config.mode = Mode::Wireframe,
            "--pattern" => pattern = true,
            "--256" => config.colours = ColourMode::Ansi256,
            "--16" => config.colours = ColourMode::Ansi16,
            "--box" => config.filter = Filter::Box2x2,
            "--help" | "-h" => {
                println!("SolidCraft 98 — now with fewer cables.\n\n--wireframe  --pattern  --256  --16  --box  --measure\n\nCtrl-Q quits; S shades; P shows the test card; B smooths; Space pauses.\nLeft/Right or mouse drag turns the part; the wheel zooms; Ctrl-L redraws.");
                return Ok(());
            }
            _ => return Err(format!("Unknown option: {arg}. Try --help.").into()),
        }
    }
    if measure {
        return measurements();
    }
    let _terminal = Terminal::enter()?;
    let input = input_thread();
    let mut decoder = Decoder::new();
    let mut cells = vec![Cell::EMPTY; 320 * 120];
    let mut encoder =
        Encoder::new(&mut cells, host_size(), config).map_err(|e| format!("Screen: {e:?}"))?;
    let mut canvas = Canvas::new(config.mode);
    let mut output = Output(io::BufWriter::new(io::stdout()));
    let mut angle: Scalar = 0.4;
    let mut zoom: Scalar = 1.0;
    let mut paused = false;
    let mut last_input = Instant::now();
    let mut last_size = Instant::now();
    loop {
        let tick = Instant::now();
        let mut events = Vec::new();
        loop {
            match input.try_recv() {
                Ok(Ok(bytes)) => {
                    decoder.feed(&bytes, |e| events.push(e));
                    last_input = Instant::now();
                }
                Ok(Err(error)) => return Err(error.into()),
                Err(mpsc::TryRecvError::Disconnected) => return Ok(()),
                Err(mpsc::TryRecvError::Empty) => break,
            }
        }
        if last_input.elapsed() >= Duration::from_millis(60) {
            if let Some(event) = decoder.escape_timeout() {
                events.push(event);
            }
        }
        for event in events {
            let event = match event {
                Event::Size(size) => Event::Size(bounded(size)),
                other => other,
            };
            encoder
                .handle_event(event)
                .map_err(|e| format!("Screen: {e:?}"))?;
            match event {
                Event::Key(key) => match key.key {
                    Key::Char('q') if key.modifiers.contains(Modifiers::CTRL) => {
                        output.0.flush()?;
                        return Ok(());
                    }
                    Key::Char('s' | 'S') => {
                        config.mode = if config.mode == Mode::Shaded {
                            Mode::Wireframe
                        } else {
                            Mode::Shaded
                        };
                        canvas = Canvas::new(config.mode);
                        encoder.configure(config);
                    }
                    Key::Char('p' | 'P') => pattern = !pattern,
                    Key::Char('b' | 'B') => {
                        config.filter = if config.filter == Filter::Nearest {
                            Filter::Box2x2
                        } else {
                            Filter::Nearest
                        };
                        encoder.configure(config);
                    }
                    Key::Char(' ') => paused = !paused,
                    Key::Left => angle -= 0.1,
                    Key::Right => angle += 0.1,
                    _ => {}
                },
                Event::Mouse(mouse) => match mouse.kind {
                    MouseKind::Drag(_) => angle = Scalar::from(mouse.col) * 0.03,
                    MouseKind::Wheel(Wheel::Up) => zoom = (zoom * 1.1).min(2.0),
                    MouseKind::Wheel(Wheel::Down) => zoom = (zoom / 1.1).max(0.2),
                    _ => {}
                },
                _ => {}
            }
        }
        if last_size.elapsed() >= Duration::from_millis(250) {
            encoder
                .resize(host_size())
                .map_err(|e| format!("Screen: {e:?}"))?;
            last_size = Instant::now();
        }
        if pattern {
            canvas.pattern();
        } else {
            canvas.cube(angle, config.mode, zoom);
        }
        let frame = Frame::new(&canvas.pixels, canvas.width, canvas.height)
            .map_err(|e| format!("Picture: {e:?}"))?;
        encoder.render(&frame, &mut output)?;
        output.0.flush()?;
        if !paused {
            angle += 0.03;
        }
        std::thread::sleep(Duration::from_millis(50).saturating_sub(tick.elapsed()));
    }
}

fn input_thread() -> Receiver<io::Result<Vec<u8>>> {
    let (send, recv) = mpsc::sync_channel(16);
    std::thread::spawn(move || {
        let mut stdin = io::stdin().lock();
        let mut bytes = [0; 256];
        loop {
            match stdin.read(&mut bytes) {
                Ok(0) => break,
                Ok(n) => {
                    if send.send(Ok(bytes[..n].to_vec())).is_err() {
                        break;
                    }
                }
                Err(error) if error.kind() == io::ErrorKind::Interrupted => continue,
                Err(error) => {
                    let _ = send.send(Err(error));
                    break;
                }
            }
        }
    });
    recv
}

fn bounded(size: Size) -> Size {
    Size {
        cols: size.cols.clamp(1, 320),
        rows: size.rows.clamp(1, 120),
    }
}
fn host_size() -> Size {
    bounded(
        crossterm::terminal::size()
            .map(|(cols, rows)| Size { cols, rows })
            .unwrap_or_default(),
    )
}

fn measurements() -> Result<()> {
    println!("160x60 cells, 0.03 rad/step, mean of 60 diffed rotation steps; nearest filter");
    println!("mode,colours,pattern_full,cube_full,rotation_mean,USB_full_ms,USB_step_ms,serial_full_ms,serial_step_ms");
    for mode in [Mode::Shaded, Mode::Wireframe] {
        for colours in [
            ColourMode::TrueColour,
            ColourMode::Ansi256,
            ColourMode::Ansi16,
        ] {
            let mut cells = vec![Cell::EMPTY; 160 * 60];
            let mut encoder = Encoder::new(
                &mut cells,
                Size::default(),
                Config {
                    mode,
                    colours,
                    ..Config::default()
                },
            )
            .map_err(|e| format!("{e:?}"))?;
            let mut canvas = Canvas::new(mode);
            let mut count = Counter::default();
            canvas.pattern();
            encoder.render(
                &Frame::new(&canvas.pixels, canvas.width, canvas.height)
                    .map_err(|e| format!("{e:?}"))?,
                &mut count,
            )?;
            let pattern_full = count.0;
            canvas.cube(0.4, mode, 1.0);
            encoder.redraw();
            count.0 = 0;
            encoder.render(
                &Frame::new(&canvas.pixels, canvas.width, canvas.height)
                    .map_err(|e| format!("{e:?}"))?,
                &mut count,
            )?;
            let full = count.0;
            count.0 = 0;
            for step in 1..=60 {
                canvas.cube(0.4 + step as Scalar * 0.03, mode, 1.0);
                encoder.render(
                    &Frame::new(&canvas.pixels, canvas.width, canvas.height)
                        .map_err(|e| format!("{e:?}"))?,
                    &mut count,
                )?;
            }
            let mean = count.0 as f64 / 60.0;
            println!(
                "{mode:?},{colours:?},{pattern_full},{full},{mean:.1},{:.3},{:.3},{:.3},{:.3}",
                full as f64 / 1000.0,
                mean / 1000.0,
                full as f64 / 11.52,
                mean / 11.52
            );
        }
    }
    Ok(())
}
