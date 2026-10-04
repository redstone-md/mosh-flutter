use clap::{Parser, Subcommand};

#[derive(Parser)]
#[command(
    name = "mosh-probe",
    about = "Headless two-ended reachability probe for the Mosh DM stack"
)]
pub(crate) struct Cli {
    /// Explicit path to the moss shared library. Defaults to the same
    /// candidate search the desktop app uses.
    #[arg(long, global = true)]
    pub(crate) moss_lib: Option<std::path::PathBuf>,

    /// Bind moss to a specific network interface, mirroring the desktop app's
    /// VPN-bypass toggle. Pass the adapter name exactly as `doctor` prints it.
    #[arg(long, global = true)]
    pub(crate) bind_interface: Option<String>,

    #[command(subcommand)]
    pub(crate) command: Command,
}

#[derive(Subcommand)]
pub(crate) enum Command {
    /// Print local network, library and node facts, then exit.
    Doctor {
        /// Also start a throwaway node and report what it observes about
        /// itself. Costs a few seconds; skip it for a pure offline check.
        #[arg(long)]
        with_node: bool,
        /// Port for the throwaway node. 0 lets the OS choose.
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
    },
    /// Create an invite, print it, and wait for the peer to complete MLS.
    Listen {
        #[arg(long, default_value = "probe-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long)]
        static_peer: Option<String>,
        /// Give up after this many seconds.
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Create concurrent invites on one node.
    ListenMany {
        #[arg(long, default_value_t = 2)]
        sessions: usize,
        #[arg(long, default_value = "probe-listen-many")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Accept concurrent invites and require every message to be delivered.
    DialMany {
        /// Repeat once per invite.
        #[arg(long = "invite", required = true)]
        invites: Vec<String>,
        #[arg(long, default_value = "probe-dial-many")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Accept an invite, then send a message and wait for it to be delivered.
    Dial {
        #[arg(long)]
        invite: String,
        #[arg(long, default_value = "probe-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long)]
        static_peer: Option<String>,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Create a private group, print its invite, and wait to hear a message
    /// from whoever joins. This end owns the verdict: a group has no delivery
    /// receipt, so being received is the only proof the frame crossed.
    GroupListen {
        #[arg(long)]
        label: Option<String>,
        #[arg(long, default_value = "probe-group-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        /// Leave the group once the message is heard, so the far end can be
        /// watched taking over as admin (ADR 0023).
        #[arg(long, default_value_t = false)]
        leave_after_heard: bool,
        /// Stay on the mesh this long after leaving, so the departure frame
        /// goes out before the node does.
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
    },
    /// Join a private group from its invite, then send one message.
    GroupDial {
        #[arg(long)]
        invite: String,
        #[arg(long, default_value = "probe-group-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        /// Stay on the mesh this long after sending. Leaving immediately takes
        /// the node down while the frame is still in flight.
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
    },
    /// Join a public channel and wait to hear a message from anyone else.
    ChannelListen {
        #[arg(long)]
        channel: String,
        #[arg(long, default_value = "probe-channel-listen")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
    },
    /// Join a public channel and send one message into it.
    ChannelDial {
        #[arg(long)]
        channel: String,
        #[arg(long, default_value = "probe-channel-dial")]
        display_name: String,
        #[arg(long, default_value_t = 0)]
        listen_port: u16,
        #[arg(long, default_value = "probe ping")]
        message: String,
        #[arg(long, default_value_t = 180)]
        timeout_secs: u64,
        #[arg(long, default_value_t = 30)]
        linger_secs: u64,
        /// Send straight away and stop after one attempt, to watch what a
        /// publish with nobody to publish to reports. Expect a Failed send.
        /// The default is the opposite: the send retries on that refusal
        /// until the budget is spent.
        #[arg(long, default_value_t = false)]
        send_without_peers: bool,
    },
}
