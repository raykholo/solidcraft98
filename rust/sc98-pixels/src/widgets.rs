//! Windows Standard controls, following gfx.bas, gui.bas and part.bas.
use crate::{
    draw::*,
    framebuffer::{Color, Framebuffer},
    model::Part,
    Scalar,
};

#[derive(Clone, Copy, Debug, Default)]
pub struct ButtonState {
    pub pressed: bool,
    pub focused: bool,
    pub default: bool,
    pub disabled: bool,
}
pub fn button<F: Framebuffer>(c: &mut Canvas<'_, F>, mut r: Rect, label: &str, s: ButtonState) {
    c.fill(r, FACE);
    if s.default {
        c.frame(r, BLACK);
        r = r.inset(1);
    }
    c.bevel(
        r,
        if s.pressed {
            Bevel::Pressed
        } else {
            Bevel::Button
        },
    );
    let off = i32::from(s.pressed);
    c.caption(
        r.x + (r.w - caption_width(label)) / 2 + off,
        r.y + (r.h - 11) / 2 + off,
        label,
        BLACK,
        s.disabled,
    );
    if s.focused {
        c.focus(r.inset(3));
    }
}
pub fn caption_button<F: Framebuffer>(c: &mut Canvas<'_, F>, x: i32, y: i32, kind: u8) {
    let r = Rect::new(x, y, 16, 14);
    c.fill(r, FACE);
    c.bevel(r, Bevel::Button);
    match kind {
        0 => c.fill(Rect::new(x + 4, y + 9, 6, 2), BLACK),
        1 => {
            c.frame(Rect::new(x + 4, y + 3, 8, 7), BLACK);
            c.hline(x + 4, y + 4, 8, BLACK);
        }
        _ => {
            for i in 0..6 {
                c.hline(x + 4 + i, y + 3 + i, 2, BLACK);
                c.hline(x + 9 - i, y + 3 + i, 2, BLACK);
            }
        }
    }
}
pub fn window<F: Framebuffer>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    title: &str,
    active: bool,
    app_icon: bool,
) {
    c.fill(r, FACE);
    c.bevel(r, Bevel::Raised);
    c.gradient(
        Rect::new(r.x + 3, r.y + 3, r.w - 6, 18),
        if active { SELECT } else { SHADOW },
        if active {
            Color::rgb(16, 132, 208)
        } else {
            Color::rgb(181, 181, 181)
        },
    );
    let old = c.set_clip(
        c.clip()
            .intersect(Rect::new(r.x + 4, r.y + 3, r.w - 63, 18)),
    );
    if app_icon {
        c.icon(r.x + 5, r.y + 4, "App", false);
    }
    c.text(
        r.x + if app_icon { 24 } else { 7 },
        r.y + 6,
        title,
        WHITE,
        true,
    );
    c.set_clip(old);
    caption_button(c, r.x + r.w - 21, r.y + 5, 2);
    if app_icon {
        caption_button(c, r.x + r.w - 39, r.y + 5, 1);
        caption_button(c, r.x + r.w - 55, r.y + 5, 0);
    }
}
pub fn edit<F: Framebuffer>(c: &mut Canvas<'_, F>, r: Rect, value: &str, focused: bool) {
    c.bevel(r, Bevel::Sunken);
    c.fill(r.inset(2), WHITE);
    let old = c.set_clip(c.clip().intersect(r.inset(3)));
    let x = c.text(r.x + 4, r.y + (r.h - 11) / 2, value, BLACK, false);
    if focused {
        c.vline(x, r.y + 4, r.h - 8, BLACK);
    }
    c.set_clip(old);
}
pub fn tree<F: Framebuffer, P: Part + ?Sized>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    p: &P,
    selected: Option<usize>,
    top: usize,
) {
    c.bevel(r, Bevel::Sunken);
    c.fill(r.inset(2), WHITE);
    let old = c.set_clip(c.clip().intersect(r.inset(2)));
    c.text(r.x + 23, r.y + 7, p.name(), BLACK, false);
    c.frame(Rect::new(r.x + 8, r.y + 7, 9, 9), SHADOW);
    c.hline(r.x + 10, r.y + 11, 5, BLACK);
    for (i, f) in p.features().iter().enumerate().skip(top) {
        let y = r.y + 20 + ((i - top) as i32) * 16;
        if y >= r.y + r.h {
            break;
        }
        for yy in (r.y + 15..y + 8).step_by(2) {
            c.pixel(r.x + 31, yy, SHADOW);
        }
        for xx in (r.x + 31..r.x + 40).step_by(2) {
            c.pixel(xx, y + 7, SHADOW);
        }
        c.icon(r.x + 41, y, f.kind.icon(), false);
        let sel = selected == Some(i);
        if sel {
            c.fill(
                Rect::new(r.x + 59, y + 1, text_width(f.name, false) + 4, 14),
                SELECT,
            );
        }
        c.text(
            r.x + 61,
            y + 3,
            f.name,
            if sel { WHITE } else { BLACK },
            false,
        );
    }
    c.set_clip(old);
}
pub fn timeline<F: Framebuffer, P: Part + ?Sized>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    p: &P,
    selected: Option<usize>,
    top: usize,
) {
    c.bevel(r, Bevel::Sunken);
    c.fill(r.inset(2), WHITE);
    let old = c.set_clip(c.clip().intersect(r.inset(2)));
    let widths = if r.w < 400 {
        [25, 90, 85, 100, 100]
    } else {
        [33, 107, 120, 180, 140]
    };
    let titles = ["#", "Feature", "Type", "Parameters", "Status"];
    let mut x = r.x + 2;
    for (w, t) in widths.iter().zip(titles) {
        c.fill(Rect::new(x, r.y + 2, *w, 18), FACE);
        c.bevel(Rect::new(x, r.y + 2, *w, 18), Bevel::Button);
        c.text(x + 6, r.y + 6, t, BLACK, false);
        x += w;
    }
    for (i, f) in p.features().iter().enumerate().skip(top) {
        let y = r.y + 20 + (i - top) as i32 * 15;
        if y >= r.y + r.h - 2 {
            break;
        }
        let sel = selected == Some(i);
        if sel {
            c.fill(Rect::new(r.x + 2, y, r.w - 4, 15), SELECT);
        }
        let tc = if sel { WHITE } else { BLACK };
        let mut num = [0u8; 20];
        let n = decimal(i + 1, &mut num);
        c.text(r.x + 8, y + 2, n, tc, false);
        c.text(r.x + widths[0] + 8, y + 2, f.name, tc, false);
        c.text(
            r.x + widths[0] + widths[1] + 8,
            y + 2,
            f.kind.name(),
            tc,
            false,
        );
        c.text(
            r.x + widths[0] + widths[1] + widths[2] + widths[3] + 8,
            y + 2,
            "OK",
            tc,
            false,
        );
        c.hline(r.x + 2, y + 14, r.w - 4, LIGHT);
    }
    c.set_clip(old);
}
pub fn status_bar<F: Framebuffer>(c: &mut Canvas<'_, F>, r: Rect, message: &str, turbo: bool) {
    c.fill(r, FACE);
    let msg = Rect::new(r.x + 2, r.y + 2, r.w - 91, r.h - 3);
    c.bevel(msg, Bevel::ThinDown);
    let old = c.set_clip(c.clip().intersect(msg.inset(1)));
    c.text(msg.x + 3, msg.y + 4, message, BLACK, false);
    c.set_clip(old);
    c.bevel(
        Rect::new(r.x + r.w - 87, r.y + 2, 30, r.h - 3),
        Bevel::ThinDown,
    );
    c.text(r.x + r.w - 83, r.y + 6, "mm", BLACK, false);
    c.bevel(
        Rect::new(r.x + r.w - 55, r.y + 2, 51, r.h - 3),
        Bevel::ThinDown,
    );
    c.text(
        r.x + r.w - 51,
        r.y + 6,
        if turbo { "33 MHz" } else { "66 MHz" },
        BLACK,
        false,
    );
}
#[derive(Clone, Copy, Debug)]
pub enum MessageKind {
    Critical,
    Warning,
    Question,
    Info,
}
pub fn message_icon<F: Framebuffer>(c: &mut Canvas<'_, F>, x: i32, y: i32, kind: MessageKind) {
    match kind {
        MessageKind::Critical => {
            for j in 0..32 {
                for i in 0..32 {
                    let dx = 2 * i - 31;
                    let dy = 2 * j - 31;
                    let r = dx * dx + dy * dy;
                    if r <= 841 {
                        c.pixel(
                            x + i,
                            y + j,
                            if r > 729 {
                                Color::rgb(128, 0, 0)
                            } else {
                                Color::rgb(255, 0, 0)
                            },
                        );
                    }
                }
            }
            for i in -6..=6 {
                c.fill(Rect::new(x + 15 + i, y + 15 + i, 3, 2), WHITE);
                c.fill(Rect::new(x + 15 + i, y + 15 - i, 3, 2), WHITE);
            }
        }
        MessageKind::Warning => {
            for j in 2..30 {
                let half = (j - 2) * 15 / 27;
                c.hline(
                    x + 15 - half,
                    y + j,
                    half * 2 + 2,
                    if j == 29 {
                        BLACK
                    } else {
                        Color::rgb(255, 255, 0)
                    },
                );
                c.pixel(x + 15 - half, y + j, BLACK);
                c.pixel(x + 16 + half, y + j, BLACK);
            }
            c.fill(Rect::new(x + 14, y + 10, 4, 11), BLACK);
            c.fill(Rect::new(x + 14, y + 23, 4, 3), BLACK);
        }
        _ => {
            for j in 0..26 {
                for i in 0..32 {
                    let dx = (i as Scalar - 15.5) / 15.5;
                    let dy = (j as Scalar - 12.5) / 12.5;
                    let r = dx * dx + dy * dy;
                    if r <= 1. {
                        c.pixel(x + i, y + j, if r > 0.86 { BLACK } else { WHITE });
                    }
                }
            }
            for j in 22..31 {
                c.hline(x + 6, y + j, if j < 26 { 28 - j } else { 2 }, WHITE);
                c.pixel(x + 5, y + j, BLACK);
            }
            c.text(
                x + 13,
                y + 7,
                if matches!(kind, MessageKind::Question) {
                    "?"
                } else {
                    "i"
                },
                Color::rgb(0, 0, 255),
                true,
            );
        }
    }
}
pub fn message_box<F: Framebuffer>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    title: &str,
    message: &str,
    kind: MessageKind,
) {
    window(c, r, title, true, false);
    message_icon(c, r.x + 16, r.y + 40, kind);
    let old = c.set_clip(
        c.clip()
            .intersect(Rect::new(r.x + 56, r.y + 28, r.w - 64, r.h - 65)),
    );
    for (i, line) in message.split('\n').enumerate() {
        c.text(r.x + 58, r.y + 38 + i as i32 * 13, line, BLACK, false);
    }
    c.set_clip(old);
    button(
        c,
        Rect::new(r.x + (r.w - 75) / 2, r.y + r.h - 36, 75, 23),
        "OK",
        ButtonState {
            default: true,
            focused: true,
            ..ButtonState::default()
        },
    );
}
pub fn number_dialog<F: Framebuffer>(
    c: &mut Canvas<'_, F>,
    r: Rect,
    title: &str,
    fields: &[(&str, &str)],
    focused: usize,
) {
    window(c, r, title, true, false);
    let old = c.set_clip(c.clip().intersect(r.inset(3)));
    let edit_x = r.x + r.w - 112;
    for (i, (name, value)) in fields.iter().enumerate() {
        let y = r.y + 39 + i as i32 * 32;
        let saved = c.set_clip(
            c.clip()
                .intersect(Rect::new(r.x + 16, y, edit_x - r.x - 22, 23)),
        );
        c.text(r.x + 16, y + 4, name, BLACK, false);
        c.set_clip(saved);
        edit(c, Rect::new(edit_x, y, 96, 21), value, i == focused);
    }
    for (i, t) in ["OK", "Cancel", "&Help"].iter().enumerate() {
        button(
            c,
            Rect::new(r.x + r.w - 253 + i as i32 * 81, r.y + r.h - 39, 75, 23),
            t,
            ButtonState {
                default: i == 0,
                ..ButtonState::default()
            },
        );
    }
    c.set_clip(old);
}
pub(crate) fn decimal(mut n: usize, buf: &mut [u8; 20]) -> &str {
    let mut at = 20;
    loop {
        at -= 1;
        buf[at] = b'0' + (n % 10) as u8;
        n /= 10;
        if n == 0 {
            break;
        }
    }
    core::str::from_utf8(&buf[at..]).unwrap_or("")
}

/// The toolbar's two-digit MHz display from app.bas.
pub fn seven_segment<F: Framebuffer>(c: &mut Canvas<'_, F>, x: i32, y: i32, digit: u8) {
    const MASKS: [u8; 10] = [63, 6, 91, 79, 102, 109, 125, 7, 127, 111];
    let mask = MASKS.get(digit as usize).copied().unwrap_or(0);
    for (i, r) in [
        Rect::new(x + 2, y, 7, 3),
        Rect::new(x + 8, y + 1, 3, 7),
        Rect::new(x + 8, y + 8, 3, 7),
        Rect::new(x + 2, y + 13, 7, 3),
        Rect::new(x, y + 8, 3, 7),
        Rect::new(x, y + 1, 3, 7),
        Rect::new(x + 2, y + 7, 7, 2),
    ]
    .iter()
    .enumerate()
    {
        c.fill(
            *r,
            if mask & (1 << i) != 0 {
                Color::rgb(255, 32, 32)
            } else {
                Color::rgb(64, 8, 8)
            },
        );
    }
}
