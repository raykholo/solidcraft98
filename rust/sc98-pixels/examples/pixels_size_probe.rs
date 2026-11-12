//! A linked bare-metal size probe, not a board support package. It exercises
//! both layouts and render styles using RGB565 and indexed framebuffers.
#![cfg_attr(target_os = "none", no_std)]
#![cfg_attr(target_os = "none", no_main)]

#[cfg(target_os = "none")]
#[panic_handler]
fn panic(_: &core::panic::PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}

#[cfg(target_os = "none")]
#[no_mangle]
pub extern "C" fn _start() -> ! {
    exercise();
    loop {
        core::hint::spin_loop();
    }
}

#[cfg(not(target_os = "none"))]
fn main() {
    exercise();
}

fn exercise() {
    use sc98_pixels::{
        app::{App, Event, Key, Layout},
        framebuffer::{Indexed16, Rgb565},
        model::{DemoPart, Part},
        view::Visibility,
    };
    let mut pixels = [0u16; 640 * 480];
    let mut indices = [0u8; 320 * 240];
    let mut order = [0usize; 24];
    let part = DemoPart;
    for layout in [Layout::Compact, Layout::Classic] {
        let (w, h) = layout.size();
        let mut app = App::new(layout, &part);
        let _ = app.event(
            core::hint::black_box(Event::Key(Key::Character('s'))),
            &part,
        );
        if let Ok(mut fb) = Rgb565::new(&mut pixels, w, h) {
            let result = app.render(&mut fb, &part, Visibility::Painter { order: &mut order });
            let _ = core::hint::black_box(result);
            core::hint::black_box(fb.pixels());
        }
    }
    let app = App::new(Layout::Compact, &part);
    if let Ok(mut fb) = Indexed16::new(&mut indices, 320, 240) {
        let result = app.render(
            &mut fb,
            &part,
            Visibility::Painter {
                order: &mut order[..part.triangles().len()],
            },
        );
        let _ = core::hint::black_box(result);
        core::hint::black_box(fb.pixels());
    }
}
