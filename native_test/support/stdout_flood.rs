use std::io::{self, BufRead, Write};

// A pipe fixture for NativePeer's reply reader, independent of the Moss protocol.
fn main() {
    let marker = std::path::PathBuf::from(std::env::var("MOSH_LINK_TEST_DIR").unwrap())
        .join("stdout-drained");
    for command in io::stdin().lock().lines() {
        let command = command.unwrap();
        if command.contains("\"shutdown\"")
            || std::env::var("MOSH_LINK_TEST_API").as_deref() == Ok("1")
        {
            break;
        }
        if command.contains("\"prepare\"") {
            println!(
                "MOSH_TEST_JSON {{\"marker\":{:?}}}",
                marker.to_string_lossy()
            );
            io::stdout().flush().unwrap();
            io::stdout().write_all(&vec![b'x'; 1024 * 1024]).unwrap();
            io::stdout().write_all(b"\n").unwrap();
            io::stdout().flush().unwrap();
            std::fs::write(&marker, b"drained").unwrap();
        } else {
            println!("MOSH_TEST_JSON {{\"phase\":\"Idle\"}}");
            io::stdout().flush().unwrap();
        }
    }
}
