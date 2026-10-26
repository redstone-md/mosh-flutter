//! Copied source UI metadata is not native notification/ownership authority.
use super::*;

pub(super) fn ownership_is_recomputed_from_verified_original_signers(f: &mut Fixture) {
    let mut own = record("own-background", "own text");
    let mut incoming = record("incoming-background", "incoming text");
    let mut unsigned = record("unsigned-background", "unsigned text");
    for (row, device, copied) in [
        (&mut own, f.source.device(), false),
        (&mut incoming, f.contact.device(), true),
    ] {
        let crypto = &f.peers[&device.device_id];
        let origin = crate::message_deletion::MessageOrigin::sign_mls(
            &format!("dm:{}", f.session),
            &row.message_id,
            row.body.as_bytes(),
            crypto,
            None,
            None,
        )
        .unwrap();
        row.metadata = Some(crate::message_deletion::MessageMetadata {
            origin: Some(origin),
            is_own: Some(copied),
            ..Default::default()
        });
    }
    unsigned.metadata = Some(crate::message_deletion::MessageMetadata {
        is_own: Some(false),
        ..Default::default()
    });
    let mut batch = f.batch(0, vec![own, incoming, unsigned]);
    batch.total = 3;
    let packet = f.packet(&f.source, DeviceMessage::HistoryBatch(batch));
    f.receive(&packet).unwrap();
    let snapshot = f.snapshot();
    for (id, expected) in [
        ("own-background", Some(true)),
        ("incoming-background", Some(false)),
        ("unsigned-background", None),
    ] {
        let message = snapshot
            .messages
            .iter()
            .find(|row| row.message_id.as_deref() == Some(id))
            .unwrap();
        assert_eq!(
            message.metadata.as_ref().and_then(|m| m.is_own),
            expected,
            "{id}"
        );
    }
}
