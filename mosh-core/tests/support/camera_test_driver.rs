//! Driver fixture for process/packet tests. Never packaged or built by default.
use std::{
    io::{Read, Write},
    time::{Duration, SystemTime, UNIX_EPOCH},
};

fn main() {
    if std::env::args().nth(1).as_deref() == Some("--list") {
        println!(r#"[{{"id":"test-camera","name":"Test camera","stable":false}}]"#);
        return;
    }
    assert_eq!(std::env::args().nth(1).as_deref(), Some("--capture"));
    std::thread::spawn(|| {
        let mut byte = [0];
        while std::io::stdin().read(&mut byte).is_ok_and(|read| read > 0) {}
        std::process::exit(0);
    });
    let mut output = std::io::stdout().lock();
    writeln!(output, r#"{{"ready":true}}"#).unwrap();
    output.flush().unwrap();
    if std::env::args().nth(2).as_deref() == Some("test-camera-stall") {
        loop {
            std::thread::park();
        }
    }
    let mut tick = 0u8;
    loop {
        let color = [tick, 255 - tick, tick / 2, 255];
        let pixels: Vec<_> = (0..320 * 180).flat_map(|_| color).collect();
        output.write_all(b"MCP1").unwrap();
        for field in [320u32, 180, pixels.len() as u32] {
            output.write_all(&field.to_be_bytes()).unwrap();
        }
        let at = SystemTime::now()
            .duration_since(UNIX_EPOCH)
            .unwrap()
            .as_millis() as u64;
        output.write_all(&at.to_be_bytes()).unwrap();
        output.write_all(&pixels).unwrap();
        output.flush().unwrap();
        tick = tick.wrapping_add(7);
        std::thread::sleep(Duration::from_nanos(1_000_000_000 / 30));
    }
}
