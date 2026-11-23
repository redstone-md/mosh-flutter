// A group with its feed: "Conversation / Group / Thread" of the capture. Without the details panel the feed has the width a window usually gives it.
const row = stretch(screen('Group', 'Desktop'), 'panels');
chats(row, 'Desktop', { open: 'Weekend plans' });
conversation(row, 'Desktop', 'Group', GROUP, 'Encrypted group');
