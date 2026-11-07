# Call engine bench

Runs any engine behind the `mosh_media_*` ABI as two processes joined by an
emulated link (delay, random loss, rate cap with a drop-tail queue) and drives
it the way mosh-core does. It reports setup time, mouth-to-ear delay, receive
loss and concealment, and CPU per peer.

Each peer gets its own PulseAudio server, so the engine's default devices are
that peer's `mic` and `spk` null sinks:

```sh
mkdir -p /tmp/mosh-pa
for side in a b; do
  cat > /tmp/mosh-pa/$side.pa <<PA
load-module module-native-protocol-unix socket=/tmp/mosh-pa/$side.sock auth-anonymous=1
load-module module-null-sink sink_name=mic rate=48000 channels=1
load-module module-null-sink sink_name=spk rate=48000 channels=1
set-default-sink spk
set-default-source mic.monitor
PA
  mkdir -p /tmp/mosh-pa/rt-$side
  XDG_RUNTIME_DIR=/tmp/mosh-pa/rt-$side HOME=/tmp/mosh-pa/rt-$side \
    DBUS_SESSION_BUS_ADDRESS=disabled: \
    pulseaudio -n -F /tmp/mosh-pa/$side.pa --daemonize=yes --exit-idle-time=-1
done
cargo run --release -- calibrate
cargo run --release -- run --engine <lib> --seconds 30 --delay-ms 30 --loss 0.05 \
  --rate-kbps 224 --budget-kbps 224
cargo run --release -- run --engine <lib> --seconds 20 --delay-ms 40 \
  --outage-at 10 --outage-ms 3000
node scripts/moss-prepare.mjs   # then, from the repository root:
mosh-probe/media-bench/target/release/mosh-media-bench run --moss --engine <lib>
```

`--moss` replaces the emulated link with two real Moss nodes on loopback; the
packets go through the media host's bounded carrier
(`src/transport.rs`). An outage drops every packet for
its length and plays a continuous tone instead of bursts. `recovery` reports
when the speaker is back at half its level from before the outage, and how
long it stayed under a tenth of it.

Mouth-to-ear: a 50 ms 1 kHz burst goes into the caller's `mic` every second.
Its onset in that sink's monitor is compared with its onset in the callee's
`spk` monitor, so playback buffering cancels out. `calibrate` records the same
monitor twice and should report about 0 ms.
