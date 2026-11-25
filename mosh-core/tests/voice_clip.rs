//! A voice recording paused and resumed is several clips on disk; the join
//! makes them the one clip a peer receives.

use std::fs::File;
use std::io::BufReader;
use std::path::{Path, PathBuf};

use mosh_core::voice_clip::join_segments;

fn fixture(name: &str) -> PathBuf {
    Path::new(env!("CARGO_MANIFEST_DIR"))
        .join("tests/fixtures")
        .join(name)
}

/// (samples, milliseconds) of the only audio track of the clip at `path`.
fn audio_track(path: &Path) -> (u32, u128) {
    let file = File::open(path).expect("clip opens");
    let size = file.metadata().expect("clip has a size").len();
    let reader = mp4::Mp4Reader::read_header(BufReader::new(file), size).expect("clip parses");
    let tracks: Vec<_> = reader.tracks().values().collect();
    assert_eq!(tracks.len(), 1, "one track");
    (tracks[0].sample_count(), tracks[0].duration().as_millis())
}

fn output(name: &str) -> PathBuf {
    let dir = std::env::temp_dir().join(format!("mosh-voice-clip-{}", std::process::id()));
    std::fs::create_dir_all(&dir).expect("temp dir");
    dir.join(name)
}

#[test]
fn joined_clip_plays_every_segment_in_order() {
    let (first, second) = (fixture("voice-first.m4a"), fixture("voice-second.m4a"));
    let joined = output("joined.m4a");

    join_segments(&[&first, &second], &joined).expect("segments join");

    let (first_samples, first_ms) = audio_track(&first);
    let (second_samples, second_ms) = audio_track(&second);
    let (samples, ms) = audio_track(&joined);
    assert_eq!(samples, first_samples + second_samples);
    assert!(ms.abs_diff(first_ms + second_ms) <= 1, "{ms} ms");
    std::fs::remove_file(joined).expect("joined clip is removed");
}

/// A second pause joins what the first join wrote with the next piece.
#[test]
fn a_joined_clip_joins_again_with_the_next_segment() {
    let (first, second) = (fixture("voice-first.m4a"), fixture("voice-second.m4a"));
    let (once, twice) = (output("once.m4a"), output("twice.m4a"));

    join_segments(&[&first, &second], &once).expect("segments join");
    join_segments(&[&once, &first], &twice).expect("a joined clip joins");

    let (first_samples, first_ms) = audio_track(&first);
    let (second_samples, second_ms) = audio_track(&second);
    let (samples, ms) = audio_track(&twice);
    assert_eq!(samples, 2 * first_samples + second_samples);
    assert!(ms.abs_diff(2 * first_ms + second_ms) <= 2, "{ms} ms");
    std::fs::remove_file(once).expect("first join is removed");
    std::fs::remove_file(twice).expect("second join is removed");
}

#[test]
fn segments_of_different_formats_are_refused_and_leave_no_clip() {
    let joined = output("mismatch.m4a");

    let refused = join_segments(
        &[fixture("voice-first.m4a"), fixture("voice-other-rate.m4a")],
        &joined,
    );

    assert!(refused.is_err());
    assert!(!joined.exists());
}

#[test]
fn a_missing_segment_is_an_error() {
    let joined = output("missing.m4a");

    let refused = join_segments(
        &[fixture("voice-first.m4a"), fixture("absent.m4a")],
        &joined,
    );

    assert!(refused.is_err());
    assert!(!joined.exists());
}
