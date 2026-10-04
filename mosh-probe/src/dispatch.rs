use crate::*;

pub(super) fn run() {
    let cli = Cli::parse();
    if let Some(name) = cli.bind_interface.clone() {
        mosh_core::moss_ffi::set_bind_interface(Some(name));
    }

    let result = match cli.command {
        Command::Doctor {
            with_node,
            listen_port,
        } => doctor(cli.moss_lib, cli.bind_interface, with_node, listen_port),
        Command::Listen {
            display_name,
            listen_port,
            static_peer,
            timeout_secs,
        } => listen(
            cli.moss_lib,
            display_name,
            listen_port,
            static_peer,
            timeout_secs,
        ),
        Command::ListenMany {
            sessions,
            display_name,
            listen_port,
            timeout_secs,
        } => listen_many(
            cli.moss_lib,
            sessions,
            display_name,
            listen_port,
            timeout_secs,
        ),
        Command::DialMany {
            invites,
            display_name,
            listen_port,
            message,
            timeout_secs,
        } => dial_many(
            cli.moss_lib,
            invites,
            display_name,
            listen_port,
            message,
            timeout_secs,
        ),
        Command::Dial {
            invite,
            display_name,
            listen_port,
            static_peer,
            message,
            timeout_secs,
        } => dial(
            cli.moss_lib,
            invite,
            display_name,
            listen_port,
            static_peer,
            message,
            timeout_secs,
        ),
        Command::GroupListen {
            label,
            display_name,
            listen_port,
            timeout_secs,
            leave_after_heard,
            linger_secs,
        } => group_listen(
            cli.moss_lib,
            label,
            display_name,
            listen_port,
            timeout_secs,
            leave_after_heard,
            linger_secs,
        ),
        Command::GroupDial {
            invite,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
        } => group_dial(
            cli.moss_lib,
            invite,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
        ),
        Command::ChannelListen {
            channel,
            display_name,
            listen_port,
            timeout_secs,
        } => channel_listen(
            cli.moss_lib,
            channel,
            display_name,
            listen_port,
            timeout_secs,
        ),
        Command::ChannelDial {
            channel,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
            send_without_peers,
        } => channel_dial(
            cli.moss_lib,
            channel,
            display_name,
            listen_port,
            message,
            timeout_secs,
            linger_secs,
            send_without_peers,
        ),
    };

    if let Err(error) = result {
        emit("probe", "error", serde_json::json!(error.to_string()));
        std::process::exit(1);
    }
}
