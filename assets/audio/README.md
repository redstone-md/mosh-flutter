# Call ringtones

`ringtone_incoming.wav` (incoming calls and the Settings sound test) and
`ringtone_outgoing.wav` (outgoing calls) are user-supplied recordings, converted
from the supplied MP3 files without resampling.

| File | Source MP3 SHA-256 | Length |
|---|---|---|
| `ringtone_incoming.wav` | `6b1be0d0ef146643a0136e5646297bb62cae91080221acc22f6c176d7097a672` | 15.1 s |
| `ringtone_outgoing.wav` | `1b0b4083a654d36ddb2471362670969a5243f9aae20a4696dea19cf90367dd95` | 12.8 s |

Conversion: decode with ffmpeg, apply a 10 ms linear fade at both ends so the
loop boundary is silent, write a canonical 44-byte WAV header. The payload is
stereo little-endian signed PCM16 at 48,000 Hz.

Rust embeds both fixed recordings. The ringtone callback reads the PCM payload
and interpolates at the output device's sample rate, preserving stereo or
averaging for mono. Extra output channels stay silent. Per-recording gain keeps
their loudness at the previous ringtone's level. There is no runtime asset
lookup or general-purpose audio decoder. Replacements must retain the documented
PCM format and pass the recording metadata tests.

Android packages the same recordings as uncompressed Flutter assets and plays
them with `MediaPlayer`: incoming uses `USAGE_NOTIFICATION_RINGTONE` (including
silent/vibrate mode), outgoing uses `USAGE_VOICE_COMMUNICATION_SIGNALLING`.
Playback requests transient audio focus, expires after 30 seconds, and is stopped
on answer/end through the existing `RingtonePlayer` owner. A stale stop or delayed
preparation callback cannot affect a newer ringtone. Desktop playback stays on CPAL.
