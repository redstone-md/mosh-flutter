//! Camera video as Mosh sends it: mosh-core's I420 camera frames enter
//! libwebrtc's encoder as they are, within the route's limits.
use std::time::Instant;

use anyhow::{Context, Result};
use libwebrtc::{
    MediaType,
    media_stream_track::MediaStreamTrack,
    peer_connection::PeerConnection,
    peer_connection_factory::{PeerConnectionFactory, native::PeerConnectionFactoryExt},
    rtp_sender::{RtpSender, VideoEncoderBackend},
    rtp_transceiver::RtpTransceiver,
    video_codec::VideoCodec,
    video_frame::{I420Buffer, VideoFrame, VideoRotation},
    video_source::{VideoResolution, native::NativeVideoSource},
    video_track::RtcVideoTrack,
};

use crate::{engine::transceiver, frames::i420_length};

/// The largest picture and frame rate a send budget carries. Under
/// 300 kbit/s a detailed 360p keyframe takes about a second to send, longer
/// than the renderer keeps a frame, so relayed calls send 270p15.
#[derive(Clone, Copy, Debug, PartialEq)]
struct Format {
    height: u32,
    fps: f64,
}

impl Format {
    fn for_budget(max_bps: u64) -> Self {
        match max_bps {
            ..300_000 => Self {
                height: 270,
                fps: 15.0,
            },
            300_000..600_000 => Self {
                height: 360,
                fps: 15.0,
            },
            _ => Self {
                height: 720,
                fps: 30.0,
            },
        }
    }

    /// How far the encoder scales a frame with this shorter side down to
    /// fit, in landscape and portrait alike.
    fn scale(&self, short_side: u32) -> f64 {
        (f64::from(short_side) / f64::from(self.height)).max(1.0)
    }
}

pub struct Camera {
    source: NativeVideoSource,
    track: RtcVideoTrack,
    sender: RtpSender,
    on: bool,
    format: Format,
    short_side: u32,
    epoch: Instant,
}

impl Camera {
    /// Adds the camera track, off, with Mosh's codec ranking. Call it
    /// inside a Tokio runtime: the source feeds black frames until the first
    /// camera frame, which the inactive sender discards.
    pub fn new(factory: &PeerConnectionFactory, pc: &PeerConnection) -> Result<Self> {
        let source = NativeVideoSource::new(VideoResolution::default(), false);
        let track = factory.create_video_track("camera", source.clone());
        track.set_enabled(false);
        let sender = pc
            .add_track(MediaStreamTrack::Video(track.clone()), &["mosh"])
            .map_err(|error| anyhow::anyhow!("video track: {error:?}"))?;
        prefer_codecs(factory, &transceiver(pc, &sender)?)?;
        let mut camera = Self {
            source,
            track,
            sender,
            on: false,
            format: Format::for_budget(0),
            short_side: 720,
            epoch: Instant::now(),
        };
        camera.apply(false, camera.format, camera.short_side)?;
        Ok(camera)
    }

    /// An off camera pauses the sender, so nothing is encoded or sent.
    pub fn set_enabled(&mut self, on: bool) -> Result<()> {
        if on == self.on {
            return Ok(());
        }
        self.apply(on, self.format, self.short_side)?;
        self.track.set_enabled(on);
        Ok(())
    }

    pub fn enabled(&self) -> bool {
        self.on
    }

    pub fn adapt(&mut self, max_bps: u64) -> Result<()> {
        self.apply(self.on, Format::for_budget(max_bps), self.short_side)
    }

    /// Sends one packed I420 camera frame while the camera is on.
    pub fn push(&mut self, width: u32, height: u32, planes: &[u8]) -> Result<()> {
        anyhow::ensure!(
            i420_length(width, height) == Some(planes.len()),
            "invalid camera frame"
        );
        if !self.on {
            return Ok(());
        }
        let short_side = width.min(height);
        if short_side != self.short_side {
            self.apply(self.on, self.format, short_side)?;
        }
        let frame = VideoFrame {
            rotation: VideoRotation::VideoRotation0,
            timestamp_us: self.epoch.elapsed().as_micros() as i64,
            frame_metadata: None,
            buffer: i420(width, height, planes).context("invalid camera frame")?,
        };
        self.source.capture_frame(&frame);
        Ok(())
    }

    /// Sets the sender to these limits and keeps them once libwebrtc accepts
    /// them; its own congestion control degrades further from there.
    fn apply(&mut self, on: bool, format: Format, short_side: u32) -> Result<()> {
        let mut parameters = self.sender.parameters();
        let encoding = parameters
            .encodings
            .first_mut()
            .context("video sender has no encoding")?;
        encoding.active = on;
        encoding.max_framerate = Some(format.fps);
        encoding.scale_resolution_down_by = Some(format.scale(short_side));
        self.sender
            .set_parameters(parameters)
            .map_err(|error| anyhow::anyhow!("video limits: {error:?}"))?;
        (self.on, self.format, self.short_side) = (on, format, short_side);
        Ok(())
    }
}

/// Ranks the codecs only this device's hardware encodes first, then VP9: on
/// the relay regression it keeps 480x270 where VP8 drops to 360x198. Codecs
/// only one side has fall out in negotiation.
fn prefer_codecs(factory: &PeerConnectionFactory, transceiver: &RtpTransceiver) -> Result<()> {
    let hardware = hardware_only_mime_types(
        &factory.video_encoder_codecs(VideoEncoderBackend::Hardware),
        &factory.video_encoder_codecs(VideoEncoderBackend::Software),
    );
    let mut codecs = factory
        .get_rtp_receiver_capabilities(MediaType::Video)
        .codecs;
    codecs.sort_by_key(|codec| rank(&codec.mime_type, &hardware));
    transceiver
        .set_codec_preferences(codecs)
        .map_err(|error| anyhow::anyhow!("video codec preferences: {error:?}"))
}

/// MIME types of the hardware codecs no software encoder here also
/// provides. The Android and Apple hardware factories list libvpx's VP8 and
/// VP9 and libaom's AV1 as fallbacks beside MediaCodec or VideoToolbox, so a
/// listed codec there may be software; our libwebrtc has no software H.264
/// or H.265, so those are the hardware's. On Linux NVENC's AV1 drops to the
/// rest, though a negotiated AV1 still encodes on NVENC.
fn hardware_only_mime_types(hardware: &[VideoCodec], software: &[VideoCodec]) -> Vec<String> {
    hardware
        .iter()
        .filter(|codec| !software.contains(codec))
        .map(|codec| format!("video/{}", codec.as_str()))
        .collect()
}

fn rank(mime_type: &str, hardware: &[String]) -> u8 {
    if hardware
        .iter()
        .any(|name| mime_type.eq_ignore_ascii_case(name))
    {
        0
    } else if mime_type.eq_ignore_ascii_case("video/VP9") {
        1
    } else {
        2
    }
}

/// A packed I420 frame (the Y plane, then U, then V, rows unpadded) within
/// the ABI's bounds as libwebrtc's buffer; none for any other length.
pub(crate) fn i420(width: u32, height: u32, planes: &[u8]) -> Option<I420Buffer> {
    if i420_length(width, height) != Some(planes.len()) {
        return None;
    }
    let mut buffer = I420Buffer::new(width, height);
    let (stride_y, stride_u, stride_v) = buffer.strides();
    let (y, u, v) = buffer.data_mut();
    let luma = width as usize * height as usize;
    let (source_y, chroma) = planes.split_at(luma);
    let (source_u, source_v) = chroma.split_at(luma / 4);
    copy_plane(source_y, width, y, stride_y);
    copy_plane(source_u, width / 2, u, stride_u);
    copy_plane(source_v, width / 2, v, stride_v);
    Some(buffer)
}

/// Copies unpadded rows into a plane whose rows are `stride` bytes apart.
fn copy_plane(source: &[u8], width: u32, target: &mut [u8], stride: u32) {
    let width = width as usize;
    for (from, to) in source
        .chunks_exact(width)
        .zip(target.chunks_mut(stride as usize))
    {
        to[..width].copy_from_slice(from);
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn budgets_map_to_the_route_formats_and_never_upscale() {
        assert_eq!(
            Format::for_budget(224_000),
            Format {
                height: 270,
                fps: 15.0
            }
        );
        assert_eq!(
            Format::for_budget(450_000),
            Format {
                height: 360,
                fps: 15.0
            }
        );
        assert_eq!(
            Format::for_budget(3_000_000),
            Format {
                height: 720,
                fps: 30.0
            }
        );
        assert_eq!(Format::for_budget(224_000).scale(1080), 4.0);
        assert_eq!(Format::for_budget(3_000_000).scale(180), 1.0);
    }

    #[test]
    fn hardware_codecs_rank_first_then_vp9() {
        let hardware = ["video/h264".to_string()];
        let mut codecs = [
            "video/VP8",
            "video/rtx",
            "video/VP9",
            "video/H264",
            "video/AV1",
        ];
        codecs.sort_by_key(|codec| rank(codec, &hardware));
        assert_eq!(
            codecs,
            [
                "video/H264",
                "video/VP9",
                "video/VP8",
                "video/rtx",
                "video/AV1"
            ]
        );
    }

    #[test]
    fn software_codecs_listed_under_android_hardware_do_not_outrank_vp9() {
        let hardware = hardware_only_mime_types(
            &[
                VideoCodec::VP8,
                VideoCodec::AV1,
                VideoCodec::VP9,
                VideoCodec::H264,
            ],
            &[VideoCodec::VP8, VideoCodec::VP9, VideoCodec::AV1],
        );
        let mut codecs = ["video/VP8", "video/AV1", "video/VP9", "video/H264"];
        codecs.sort_by_key(|codec| rank(codec, &hardware));
        assert_eq!(
            codecs,
            ["video/H264", "video/VP9", "video/VP8", "video/AV1"]
        );
    }
}
