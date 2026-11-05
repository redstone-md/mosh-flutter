//! Length-prefixed frames on the worker's stdin/stdout.
use std::io::{Read, Write};

pub const COMMAND: u8 = b'C';
pub const REPLY: u8 = b'R';
pub const PACKET: u8 = b'P';

pub fn write(out: &mut impl Write, kind: u8, payload: &[u8]) -> std::io::Result<()> {
    let mut header = [kind, 0, 0, 0, 0];
    header[1..].copy_from_slice(&(payload.len() as u32).to_be_bytes());
    out.write_all(&header)?;
    out.write_all(payload)?;
    out.flush()
}

pub fn read(input: &mut impl Read) -> std::io::Result<(u8, Vec<u8>)> {
    let mut header = [0; 5];
    input.read_exact(&mut header)?;
    let length = u32::from_be_bytes(header[1..].try_into().unwrap()) as usize;
    let mut payload = vec![0; length];
    input.read_exact(&mut payload)?;
    Ok((header[0], payload))
}
