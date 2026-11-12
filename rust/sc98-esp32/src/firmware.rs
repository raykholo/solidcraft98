use embedded_io::Write as IoWrite;
use sc98_esp32::Stream;
use sc98_term::Write;

#[cfg(any(
    all(
        feature = "esp32c3",
        any(feature = "esp32c6", feature = "esp32s3", feature = "esp32")
    ),
    all(feature = "esp32c6", any(feature = "esp32s3", feature = "esp32")),
    all(feature = "esp32s3", feature = "esp32")
))]
compile_error!("Select exactly one chip feature; disable default features for other chips.");

#[cfg(not(feature = "esp32"))]
struct Serial(esp_hal::usb_serial_jtag::UsbSerialJtag<'static, esp_hal::Blocking>);
#[cfg(feature = "esp32")]
struct Serial(esp_hal::uart::Uart<'static, esp_hal::Blocking>);
impl Write for Serial {
    type Error = ();
    fn write_all(&mut self, bytes: &[u8]) -> Result<(), ()> {
        IoWrite::write_all(&mut self.0, bytes).map_err(|_| ())?;
        IoWrite::flush(&mut self.0).map_err(|_| ())
    }
}
impl Stream for Serial {
    fn read_byte(&mut self) -> Result<Option<u8>, ()> {
        #[cfg(feature = "esp32")]
        {
            let mut byte = [0; 1];
            let count = self.0.read_buffered_bytes(&mut byte).map_err(|_| ())?;
            Ok((count > 0).then_some(byte[0]))
        }
        #[cfg(not(feature = "esp32"))]
        match self.0.read_byte() {
            Ok(b) => Ok(Some(b)),
            Err(nb::Error::WouldBlock) => Ok(None),
            Err(nb::Error::Other(_)) => Err(()),
        }
    }
    fn idle(&mut self) {
        esp_hal::delay::Delay::new().delay_millis(10);
    }
}
#[esp_hal::main]
fn main() -> ! {
    // The compact framebuffer and terminal history live on the heap, not stack.
    esp_alloc::heap_allocator!(300 * 1024);
    let peripherals = esp_hal::init(esp_hal::Config::default());
    #[cfg(not(feature = "esp32"))]
    let mut serial = Serial(esp_hal::usb_serial_jtag::UsbSerialJtag::new(
        peripherals.USB_DEVICE,
    ));
    #[cfg(feature = "esp32")]
    let mut serial =
        match esp_hal::uart::Uart::new(peripherals.UART0, esp_hal::uart::Config::default()) {
            Ok(uart) => Serial(uart.with_tx(peripherals.GPIO1).with_rx(peripherals.GPIO3)),
            Err(_) => loop {
                core::hint::spin_loop();
            },
        };
    let _ = sc98_esp32::run(&mut serial);
    loop {
        core::hint::spin_loop();
    }
}
#[panic_handler]
fn panic(_info: &core::panic::PanicInfo<'_>) -> ! {
    loop {
        core::hint::spin_loop();
    }
}
