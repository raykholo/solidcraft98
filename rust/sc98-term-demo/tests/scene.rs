use sc98_term::{Cell, Config, Encoder, Frame, Mode, Rgb, Size};
use sc98_term_demo::{Canvas, Counter};

#[test]
fn cube_rotates_in_both_modes_and_diffs_are_smaller_than_full_frames() {
    for mode in [Mode::Shaded, Mode::Wireframe] {
        let mut canvas = Canvas::new(mode);
        canvas.cube(0.4, mode, 1.0);
        assert!(canvas
            .pixels
            .iter()
            .any(|&p| p == Rgb(192, 220, 255) || p == Rgb(165, 178, 200)));
        let first = canvas.pixels.clone();
        let mut cells = vec![Cell::EMPTY; 160 * 60];
        let mut encoder = Encoder::new(
            &mut cells,
            Size::default(),
            Config {
                mode,
                ..Config::default()
            },
        )
        .unwrap();
        let mut out = Counter::default();
        encoder
            .render(
                &Frame::new(&canvas.pixels, canvas.width, canvas.height).unwrap(),
                &mut out,
            )
            .unwrap();
        let full = out.0;
        canvas.cube(0.43, mode, 1.0);
        assert_ne!(first, canvas.pixels);
        out.0 = 0;
        encoder
            .render(
                &Frame::new(&canvas.pixels, canvas.width, canvas.height).unwrap(),
                &mut out,
            )
            .unwrap();
        assert!(out.0 > 0 && out.0 < full, "{mode:?}: {} / {full}", out.0);
        out.0 = 0;
        encoder
            .render(
                &Frame::new(&canvas.pixels, canvas.width, canvas.height).unwrap(),
                &mut out,
            )
            .unwrap();
        assert_eq!(out.0, 0);
    }
}

#[test]
fn pattern_spans_colour_range_and_cube_is_repeatable() {
    let mut canvas = Canvas::new(Mode::Shaded);
    canvas.pattern();
    assert_eq!(canvas.pixels[0], Rgb(0, 0, 220));
    let last = canvas.pixels.last().unwrap();
    assert_eq!((last.0, last.1), (255, 255));
    canvas.cube(0.4, Mode::Shaded, 1.0);
    let first = canvas.pixels.clone();
    canvas.pattern();
    canvas.cube(0.4, Mode::Shaded, 1.0);
    assert_eq!(first, canvas.pixels);
}
