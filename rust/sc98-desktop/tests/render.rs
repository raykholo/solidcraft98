use sc98_desktop::{screenshot, Screen};
use sc98_pixels::{
    app::{App, Command, Event, Key, Layout},
    model::{DemoPart, Part},
};
use std::{fs, path::PathBuf};

#[test]
fn screenshots_and_colour_modes() {
    let docs = PathBuf::from(env!("CARGO_MANIFEST_DIR")).join("../docs");
    for (layout, name) in [
        (Layout::Classic, "desktop-640x480.png"),
        (Layout::Compact, "desktop-320x240.png"),
    ] {
        let part = DemoPart;
        let mut app = App::new(layout, &part);
        let mut screen = Screen::new(layout, part.triangles().len(), false, false);
        screen.draw(&app, &part, false, false).unwrap();
        assert_eq!(screen.output.len(), screen.width * screen.height);
        assert!(screen.output.contains(&0xffffff));
        let path = docs.join(name);
        if std::env::var_os("UPDATE_SCREENSHOTS").is_some() {
            screenshot(layout, &path, false, false).unwrap();
        }
        let decoder = png::Decoder::new(fs::File::open(&path).unwrap());
        let mut reader = decoder.read_info().unwrap();
        let mut bytes = vec![0; reader.output_buffer_size()];
        let info = reader.next_frame(&mut bytes).unwrap();
        assert_eq!(
            (info.width as usize, info.height as usize),
            (screen.width, screen.height)
        );
        let actual: Vec<u8> = screen
            .rgb
            .iter()
            .flat_map(|&p| sc98_pixels::framebuffer::Color(p).channels())
            .collect();
        assert_eq!(&bytes[..info.buffer_size()], &actual);
        app.event(Event::Key(Key::Tab), &part);
        app.selected = Some(2);
        screen.draw(&app, &part, false, false).unwrap();
        app.command(Command::Rectangle, &part);
        for _ in 0..6 {
            app.event(Event::Key(Key::Tab), &part);
        }
        screen.draw(&app, &part, false, false).unwrap();
        let mut indexed = Screen::new(layout, part.triangles().len(), true, true);
        indexed
            .draw(&App::new(layout, &part), &part, true, true)
            .unwrap();
        assert!(indexed
            .output
            .iter()
            .all(|&p| sc98_pixels::framebuffer::PALETTE
                .iter()
                .any(|c| c.xrgb() == p)));
    }
}

#[test]
fn frame_time_300_triangles() {
    for t in sc98_desktop::benchmark(120).unwrap() {
        eprintln!(
            "300 triangles, 320x240, {:?}, {}: {:.3} ms/frame ({} frames, warm-up excluded)",
            t.style,
            if t.painter { "painter" } else { "depth" },
            t.per_frame.as_secs_f64() * 1000.,
            t.frames
        );
        assert!(t.per_frame > std::time::Duration::ZERO);
    }
}
