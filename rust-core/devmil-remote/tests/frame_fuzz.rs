//! Seeded fuzzing of the frame reader and the server's envelope parsing: random, truncated,
//! oversized and invalid UTF-8 input must end in an error, never a panic or an allocation
//! beyond the frame limit.
use devmil_remote::frame::{self, FrameClock, FrameError};
use std::io::Cursor;

struct XorShift(u32);

impl XorShift {
    fn next(&mut self) -> u32 {
        self.0 ^= self.0 << 13;
        self.0 ^= self.0 >> 17;
        self.0 ^= self.0 << 5;
        self.0
    }

    fn below(&mut self, bound: u32) -> u32 {
        if bound == 0 { 0 } else { self.next() % bound }
    }
}

#[test]
fn random_streams_never_panic() {
    let mut random = XorShift(0x5eed_6175);
    let clock = FrameClock::new();
    for _ in 0..20_000 {
        let length = random.below(64) as usize;
        let mut bytes: Vec<u8> = (0..length).map(|_| random.below(256) as u8).collect();
        if random.below(3) == 0 && bytes.len() >= 4 {
            // A plausible small header so payload paths run too.
            bytes[0] = 0;
            bytes[1] = 0;
            bytes[2] = 0;
        }
        let mut input = Cursor::new(bytes);
        loop {
            match frame::read_frame(&mut input, 1024, &clock) {
                Ok(payload) => {
                    assert!(!payload.is_empty() && payload.len() <= 1024);
                    let _ = serde_json::from_slice::<serde_json::Value>(&payload);
                }
                Err(_) => break,
            }
        }
    }
}

#[test]
fn invalid_utf8_is_not_valid_json() {
    let mut bytes = Vec::new();
    frame::write_frame(&mut bytes, &[b'"', 0xc3, 0x28, b'"']).unwrap();
    let payload = frame::read_frame(&mut Cursor::new(bytes), 64, &FrameClock::new()).unwrap();
    assert!(serde_json::from_slice::<serde_json::Value>(&payload).is_err());
}

#[test]
fn oversize_and_truncated_frames_are_typed() {
    let clock = FrameClock::new();
    let oversize = 2_000_u32.to_be_bytes().to_vec();
    assert_eq!(
        frame::read_frame(&mut Cursor::new(oversize), 1024, &clock),
        Err(FrameError::Length)
    );
    let truncated = vec![0, 0, 0, 10, b'{'];
    assert_eq!(
        frame::read_frame(&mut Cursor::new(truncated), 1024, &clock),
        Err(FrameError::Truncated)
    );
}
