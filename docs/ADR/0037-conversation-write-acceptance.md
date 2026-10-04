# ADR 0037: conversation write acceptance

Accepted 2026-10-03. The exported Rust contract changes were explicitly approved.

History previously discarded serialization and redb failures. Its accepted-row
count and ConversationRuntime's record finalization could advance without a
durable write. DM commands and ticks also had separate dequeue implementations.

History write methods, ConversationRuntime persistence methods and
ConversationSession.write_extra now return Result with PersistenceError.
ChannelRuntimeError and PrivateGroupError gain Persistence, mapped to the
existing ConversationBridgeErrorKind.Persistence. Generated bridge signatures,
DTOs, database tables and dependencies are unchanged. External Rust consumers
must handle Results and the additional native error variants.

ConversationRuntime owns pending writes in runtime_writes.rs. It retries
message/attempt writes atomically with the latest outcome, then saves extra
state and records. Accepted tail rows advance their count individually. Record
finalization happens only after required writes succeed. One conversation's
refusal does not prevent other conversations from saving. A refused atomic send
blocks message-only tail writes for that conversation. Memory-only runtimes
continue to treat persistence as successful.

Snapshot reads retry pending writes and return the current in-memory view even
when storage refuses. They log the refusal while retaining the write for retry,
so one failed save cannot hide conversations. Text sends still return
Persistence on refused admission before publishing. DM and group creation return
Persistence before exposing its new session.

DM and group MLS snapshots and their restoring records share one encrypted redb
transaction. DM read-receipt replay depends on both the consumed MLS ratchet and
the record's read_message_ids. Rejoining after a refused durable close can replace
the local signer, so writing its snapshot first would invalidate the retained
old record.
A refused pair write leaves the earlier pair recoverable and remains pending
for retry. Ordinary pre-Welcome DM snapshots retain their existing placeholder
policy. This reuses the atomic writer used by DM device transitions without
changing public contracts or database tables.

Creating a DM or group saves only its own atomic pair before inserting the session.
A refused save closes the provisional room and leaves no session or retry that
can silently create it later. Unrelated pending history cannot refuse creation.

DM send admission first persists the existing Pending state. If admission
refuses, the attempt becomes Failed and only its failed-status save is retried.
An uncertain Pending commit replays Failed through existing recovery, so a
command that returned Persistence cannot secretly publish after repair or
restart. Flutter keeps its failed draft and may issue a deliberate new command.

Accepted admission activates Queued. Subsequent refused writes retain the
accepted message and return Queued. Commands and ticks use one dequeue in
private_dm_runtime/outbox.rs, saving queued work before publishing. Settlement
saves both the delivery result and the advanced MLS snapshot, including queues
whose history tail was already saved. A post-publication save refusal stays
pending and reports the real transport result, including file/voice manifests.

Group/channel text pre-publication refusal settles Failed and returns Persistence
before reaching Moss. These short action mappings remain local because only
the kind owns its mutable Outbox. The shared writer owns persistence retries;
it does not add a generic callback or another ConversationSession method.

Tests use the encrypted redb store, MLS and real Moss. A test-only reversible
table-type fault exercises actual write refusal. Checks cover admission,
repair/reopen, deliberate retry, delivery and MLS settlement, record/tail
retries and isolation of atomic sends. A real Welcome after a refused close and
rejoin verifies recovery when either group record or snapshot storage refuses,
before retrying. Further cases cover refused creation, authenticated receipt
replay after restart, and attachment reads during refusal through repair and
rehydration. No production fault interface is added.

A filesystem I/O failure can poison redb and require reopening the database.
This decision does not add automatic database reopening. If the process exits
before a refused update succeeds, its earlier durable outcome remains. Tests
exercise redb validation refusal, not disk exhaustion or fsync uncertainty.

The new shared writer and DM outbox stay within source-size budgets. Existing
runtime/session exceptions from ADRs 0019 and 0026 remain; unrelated file splits
are outside this change. Test registration functions retain the existing
exception for independent cases.
