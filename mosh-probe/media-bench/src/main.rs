//! media-bench run --engine <lib> [--seconds 30] [--delay-ms 0] [--loss 0]
//!                 [--rate-kbps N] [--budget-kbps N]
//! media-bench calibrate
mod audio;
mod bench;
mod engine;
mod frame;
mod link;
mod worker;

use anyhow::{Context, Result};
use std::time::Duration;

fn main() -> Result<()> {
    let args: Vec<String> = std::env::args().skip(1).collect();
    let flag = |name: &str| {
        args.iter()
            .position(|a| a == name)
            .and_then(|i| args.get(i + 1))
            .cloned()
    };
    match args.first().map(String::as_str) {
        Some("worker") => worker::run(&args[1], args[2] == "caller"),
        Some("calibrate") => {
            println!("{}", bench::calibrate(10)?);
            Ok(())
        }
        Some("run") => {
            let number = |name: &str, default: f64| -> Result<f64> {
                flag(name).map_or(Ok(default), |v| v.parse().context(name.to_string()))
            };
            let rate = number("--rate-kbps", 0.0)?;
            let budget = number("--budget-kbps", 0.0)?;
            let options = bench::Options {
                engine: flag("--engine").context("--engine")?,
                seconds: number("--seconds", 30.0)? as u64,
                shape: link::Shape {
                    delay: Duration::from_millis(number("--delay-ms", 0.0)? as u64),
                    loss: number("--loss", 0.0)?,
                    rate_bps: (rate > 0.0).then_some((rate * 1000.0) as u64),
                    queue_bytes: 32 * 1024,
                },
                budget_bps: (budget > 0.0).then_some((budget * 1000.0) as u64),
            };
            println!("{}", bench::run(options)?);
            Ok(())
        }
        _ => anyhow::bail!("usage: media-bench run --engine <lib> | calibrate"),
    }
}
