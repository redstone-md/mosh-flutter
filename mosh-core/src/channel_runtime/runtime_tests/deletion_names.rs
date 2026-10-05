use super::*;

#[test]
fn shared_deletion_accepts_existing_display_names_outside_its_wire_limit() {
    let _guard = MOSS_TEST_LOCK.lock().unwrap_or_else(|p| p.into_inner());
    let mut fixture = Fixture::new();
    for name in ["Alice\nAdmin".into(), "😀".repeat(65)] {
        fixture.runtime.channels.get_mut(ROOM).unwrap().display_name = name;
        let sent = fixture.runtime.send(ROOM, "erase me".into()).unwrap();
        let result = fixture
            .runtime
            .delete_messages(ROOM, &[sent.message_id], DeleteScope::ForEveryone)
            .unwrap();
        assert_eq!(result.deleted_count, 1);
        assert!(fixture
            .runtime
            .poll(ROOM)
            .unwrap()
            .messages
            .iter()
            .all(|message| message.body.is_empty()));
    }
}
