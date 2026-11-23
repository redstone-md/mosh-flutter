// A group with its feed and its details: "Conversation / Group / Thread" of the capture.
const row = stretch(screen('Group', 'Desktop'), 'panels');
chats(row, 'Desktop', { open: 'Weekend plans' });
conversation(row, 'Desktop', 'Group', GROUP, 'Encrypted group');
add(row, inst('Details panel', { Kind: 'Group', Device: 'Desktop' }), { fillH: true });
