//! Voice-clip facade: the join the composer asks for when a recording was
//! paused and resumed. Paths in, a `Result<_, String>` out, matching the
//! other media facades.

use std::path::Path;

use crate::voice_clip;

/// Joins the recorded `segments`, in order, into one clip at `output`.
/// Runs on the bridge's worker pool: a five-minute recording is a few
/// megabytes to copy.
pub fn join_voice_segments(segments: Vec<String>, output: String) -> Result<(), String> {
    voice_clip::join_segments(&segments, Path::new(&output))
}
