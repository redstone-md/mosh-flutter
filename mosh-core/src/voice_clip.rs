//! The clip a voice message is sent as.
//!
//! A recording that was paused and resumed is several finished MP4 clips
//! on disk: the recorder closes its file at every pause so the pause can be
//! listened to. [`join_segments`] copies their AAC frames, untouched and in
//! order, into the one clip a peer receives.

use std::fs::File;
use std::io::{BufReader, BufWriter};
use std::path::Path;

use mp4::{
    AacConfig, MediaConfig, Mp4Config, Mp4Reader, Mp4Sample, Mp4Track, Mp4Writer, TrackConfig,
    TrackType,
};

type Reader = Mp4Reader<BufReader<File>>;

/// Writes the audio of `segments`, in order, to a new clip at `output`.
///
/// Every segment must be AAC at the sample rate and channel layout of the
/// first: one recorder made them all, so anything else is a bug upstream.
/// A failed join leaves no file at `output`.
pub fn join_segments(segments: &[impl AsRef<Path>], output: &Path) -> Result<(), String> {
    let joined = write_joined(segments, output);
    if joined.is_err() {
        // Best effort: the caller is told about the join, not the cleanup.
        let _ = std::fs::remove_file(output);
    }
    joined
}

fn write_joined(segments: &[impl AsRef<Path>], output: &Path) -> Result<(), String> {
    let mut opened = Vec::with_capacity(segments.len());
    for path in segments {
        opened.push(Segment::open(path.as_ref())?);
    }
    let format = opened
        .first()
        .ok_or("no voice segments to join")?
        .format
        .clone();
    if opened.iter().any(|segment| segment.format != format) {
        return Err("voice segments differ in audio format".into());
    }
    let file = File::create(output).map_err(|error| format!("create voice clip: {error}"))?;
    let mut writer = Mp4Writer::write_start(BufWriter::new(file), &container(format.timescale))
        .map_err(describe)?;
    writer.add_track(&format).map_err(describe)?;
    let mut start_time = 0;
    for Segment {
        reader, track_id, ..
    } in &mut opened
    {
        for sample_id in 1..=reader.sample_count(*track_id).map_err(describe)? {
            let Some(sample) = reader.read_sample(*track_id, sample_id).map_err(describe)? else {
                continue;
            };
            let duration = u64::from(sample.duration);
            let sample = Mp4Sample {
                start_time,
                ..sample
            };
            writer.write_sample(1, &sample).map_err(describe)?;
            start_time += duration;
        }
    }
    writer.write_end().map_err(describe)
}

/// One finished piece of a recording: its audio track and how it is encoded.
struct Segment {
    reader: Reader,
    track_id: u32,
    format: TrackConfig,
}

impl Segment {
    fn open(path: &Path) -> Result<Self, String> {
        let file = File::open(path).map_err(|error| format!("open voice segment: {error}"))?;
        let size = file
            .metadata()
            .map_err(|error| format!("read voice segment: {error}"))?
            .len();
        let reader = Mp4Reader::read_header(BufReader::new(file), size).map_err(describe)?;
        let track = reader
            .tracks()
            .values()
            .find(|track| matches!(track.track_type(), Ok(TrackType::Audio)))
            .ok_or("voice segment has no audio track")?;
        let (track_id, format) = (track.track_id(), audio_format(track)?);
        Ok(Self {
            reader,
            track_id,
            format,
        })
    }
}

/// How an audio track is encoded, as the writer takes it. The bitrate is
/// left out: it is a statistic of one segment, not part of the format.
fn audio_format(track: &Mp4Track) -> Result<TrackConfig, String> {
    Ok(TrackConfig {
        track_type: TrackType::Audio,
        timescale: track.timescale(),
        language: "und".into(),
        media_conf: MediaConfig::AacConfig(AacConfig {
            bitrate: 0,
            profile: track.audio_profile().map_err(describe)?,
            freq_index: track.sample_freq_index().map_err(describe)?,
            chan_conf: track.channel_config().map_err(describe)?,
        }),
    })
}

fn container(timescale: u32) -> Mp4Config {
    let brand = |name: &str| name.parse().expect("a four-character brand");
    Mp4Config {
        major_brand: brand("M4A "),
        minor_version: 0,
        compatible_brands: vec![brand("M4A "), brand("isom"), brand("mp42")],
        timescale,
    }
}

fn describe(error: mp4::Error) -> String {
    format!("voice clip: {error}")
}
