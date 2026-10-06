# Call ringtone

`cipher_stream.wav` is the original user-supplied `29_cipher_stream` composition.
It was synthesized locally without sampled audio and supplied for redistribution
with Mosh under this repository's GPL-3.0-or-later license.

The recording is a 2.8-second seamless loop with a silent tail. Its canonical
WAV header is 44 bytes; the payload is stereo little-endian signed PCM16 at
44,100 Hz. SHA-256 of the supplied file:
`a3da671ae7a73fef0e25308dc6c47b460d0fac1dce032c51eccd24bf28e5cbd4`.

Rust embeds this single fixed recording. The ringtone callback reads its PCM
payload and interpolates at the output device's sample rate, preserving stereo
or averaging for mono. Extra output channels stay silent. There is no runtime
asset lookup or general-purpose audio decoder. Replacements must retain the
documented PCM format and pass the recording metadata tests.
