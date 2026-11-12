//! Terminal host. All modelling and interaction live in sc98-app.
#![forbid(unsafe_code)]
use sc98_app::{App, Layout};
use sc98_term::{Cell, Config, Decoder, Encoder, Event, Size, Write, ENTER, EXIT, SIZE_PROBE};
use sc98_term_app::Directory;
#[cfg(unix)]
use std::io::Read;
use std::{
    io::{self, Write as IoWrite},
    time::{Duration, Instant},
};

type Result<T> = std::result::Result<T, Box<dyn std::error::Error>>;
fn screen_error(e: impl std::fmt::Debug) -> io::Error {
    io::Error::other(format!("{e:?}"))
}
struct Output<W>(W);
impl<W: IoWrite> Write for Output<W> {
    type Error = io::Error;
    fn write_all(&mut self, b: &[u8]) -> io::Result<()> {
        self.0.write_all(b)
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
fn bounded(size: Size) -> Size {
    Size {
        cols: size.cols.clamp(1, 320),
        rows: size.rows.clamp(1, 120),
    }
}
fn size() -> Size {
    bounded(
        crossterm::terminal::size()
            .map(|(cols, rows)| Size { cols, rows })
            .unwrap_or_default(),
    )
}
fn main() {
    if let Err(e) = run() {
        eprintln!("SolidCraft 98: {e}");
        std::process::exit(1);
    }
}
fn run() -> Result<()> {
    let mut layout = Layout::Compact;
    let mut capture = false;
    let mut new = false;
    let mut path = None;
    for arg in std::env::args().skip(1) {
        match arg.as_str() {
            "--classic" => layout = Layout::Classic,
            "--compact" => layout = Layout::Compact,
            "--capture" => capture = true,
            "--new" => new = true,
            "--help" | "-h" => {
                println!("SolidCraft 98\n\n--compact  --classic  --new  --capture  [part.sc98]\n\nCtrl-N/O/S: New/Open/Save; R/C: Rectangle/Circle; E/V/H: Extrude/Revolve/Hole.\nAlt-F/E/S/T/V/W/H: menus; Tab: tools; arrows: select/orbit; Enter: edit.\nS: shading; I: isometric; F: fit; Del: delete; Ctrl-Q: quit.\nNumber boxes: Backspace, Tab, Enter. File names: Backspace, Enter, Escape.");
                return Ok(());
            }
            _ if !arg.starts_with('-') => path = Some(arg),
            _ => return Err(format!("Unknown option: {arg}").into()),
        }
    }
    let storage = Directory::new(std::env::current_dir()?);
    let mut app: App<Directory> = if new {
        App::new(layout, storage, sc98_term_app::new_part()).map_err(screen_error)?
    } else {
        App::sample(layout, storage).map_err(screen_error)?
    };
    if let Some(path) = path {
        app.open_named(&path).map_err(screen_error)?;
    }
    let mut cells = vec![Cell::EMPTY; 320 * 120];
    let initial = if capture {
        Size {
            cols: 320,
            rows: 120,
        }
    } else {
        size()
    };
    let mut encoder = Encoder::new(&mut cells, initial, Config::default()).map_err(screen_error)?;
    app.tick(Some(Event::Size(initial))).map_err(screen_error)?;
    // Drop buffered output before restoring the terminal, including errors.
    let _terminal = if capture {
        None
    } else {
        Some(Terminal::enter()?)
    };
    let mut output = Output(io::BufWriter::new(io::stdout()));
    if capture {
        encoder.render(&app.tick(None).map_err(screen_error)?, &mut output)?;
        output.0.flush()?;
        return Ok(());
    }
    // VMIN=0 / VTIME=1 supplies bounded reads and a 100 ms escape timeout,
    // with no input thread and exact raw-mode restoration by crossterm.
    #[cfg(unix)]
    {
        let status = std::process::Command::new("stty")
            .args(["min", "0", "time", "1"])
            .status()?;
        if !status.success() {
            return Err("Could not configure terminal input".into());
        }
    }
    let mut decoder = Decoder::new();
    #[cfg(unix)]
    let mut bytes = [0; 256];
    #[cfg(unix)]
    let mut stdin = io::stdin();
    let mut poll = Instant::now();
    loop {
        encoder.render(&app.tick(None).map_err(screen_error)?, &mut output)?;
        output.0.flush()?;
        let mut events = Vec::new();
        #[cfg(unix)]
        {
            let n = stdin.read(&mut bytes)?;
            decoder.feed(&bytes[..n], |e| events.push(e));
            if n == 0 {
                if let Some(e) = decoder.escape_timeout() {
                    events.push(e);
                }
            }
        }
        #[cfg(not(unix))]
        {
            if let Some(event) = sc98_term_app::native_event(Duration::from_millis(100))? {
                events.push(event);
            }
            let _ = &mut decoder;
        }
        if poll.elapsed() >= Duration::from_millis(250) {
            events.push(Event::Size(size()));
            poll = Instant::now();
        }
        for event in events {
            let event = match event {
                Event::Size(s) => Event::Size(bounded(s)),
                e => e,
            };
            encoder.handle_event(event).map_err(screen_error)?;
            app.tick(Some(event)).map_err(screen_error)?;
        }
        if app.quit {
            return Ok(());
        }
    }
}
