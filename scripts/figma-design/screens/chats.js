// The chat list and an open direct chat: "Chats / List / Chats" and
// "Conversation / DM / Thread" of the capture, on the desktop with the details panel open.
directChat('Direct chat with details', 'Desktop', true);
chats(fill(screen('Chat list', 'Phone'), 'panels'), 'Phone').layoutSizingHorizontal = 'FILL';
directChat('Direct chat', 'Phone');
