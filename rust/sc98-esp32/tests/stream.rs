use sc98_esp32::{run, Stream};
use sc98_term::{Write, ENTER, EXIT};
struct Serial {
    input: std::collections::VecDeque<u8>,
    output: Vec<u8>,
}
impl Write for Serial {
    type Error = ();
    fn write_all(&mut self, b: &[u8]) -> Result<(), ()> {
        self.output.extend_from_slice(b);
        Ok(())
    }
}
impl Stream for Serial {
    fn read_byte(&mut self) -> Result<Option<u8>, ()> {
        Ok(self.input.pop_front())
    }
    fn idle(&mut self) {}
}
#[test]
fn serial_host_runs_the_program_and_restores_terminal() {
    let mut serial = Serial {
        input: b"\x0er\re\r\x13\r\x11".to_vec().into(),
        output: Vec::new(),
    };
    run(&mut serial).unwrap();
    assert!(serial.output.starts_with(ENTER));
    assert!(serial.output.ends_with(EXIT));
    assert!(serial.output.len() > ENTER.len() + EXIT.len());
}

#[test]
fn serial_error_still_restores_terminal() {
    struct Failed {
        output: Vec<u8>,
    }
    impl Write for Failed {
        type Error = ();
        fn write_all(&mut self, b: &[u8]) -> Result<(), ()> {
            self.output.extend_from_slice(b);
            Ok(())
        }
    }
    impl Stream for Failed {
        fn read_byte(&mut self) -> Result<Option<u8>, ()> {
            Err(())
        }
        fn idle(&mut self) {}
    }
    let mut serial = Failed { output: Vec::new() };
    assert!(run(&mut serial).is_err());
    assert!(serial.output.ends_with(EXIT));
}
