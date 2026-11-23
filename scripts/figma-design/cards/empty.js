// What a conversation shows when it has nothing to show
// (conversation_screen_body._ConversationEmpty and its load error), beside the
// notices of an empty chat list (sessions_rail_list._EmptyState,
// sessions_screen._ErrorState), which the Chat list card owns as List notice.
card('Empty and error state', 'An empty place says what will appear in it and what to do next, in the same voice as the rest of the app and without a drawing to fill the room. When loading failed it says what is safe, and offers to try again. The chat list’s own notices are the List notice of the Chat list card; here they stand beside the conversation’s so the two read as one family.');
// Per kind: title, line, and the action when there is one.
const EMPTY = {
  'New chat': ['No messages yet', 'Messages you send here are end-to-end encrypted'],
  'Waiting for contact': ['Waiting for Maya', 'The invite has not been opened yet. You can write now, and your messages are delivered once it is.'],
  Channel: ['Nothing in #photography yet', 'Anyone who joins can read what is posted here'],
  'Could not load': ['This conversation could not be loaded', 'Its messages are safe on this device', 'Try again'],
};
display(await grid('Conversation empty', axis('Kind', Object.keys(EMPTY)), DEVICES, ({ Kind, Device }) => {
  const [title, line, act] = EMPTY[Kind];
  const e = surface('Conversation empty', 'background', { component: true, dir: 'V', gap: 2, pad: [12, feedPad(Device)], w: FEED[Device] });
  const col = add(e, box('text', { dir: 'V', gap: 1, w: Math.min(360, FEED[Device] - 64) }));
  titled(col, [title, 'titleMedium', act ? 'error' : 'onSurface'], [line, 'bodyMedium', 'onSurfaceVariant'], true);
  if (act) add(e, labelButton(Device, act, { Kind: 'Outlined' }));
  return e;
}));
await examples('The chat list: no chats, nothing found, could not load', ['No chats', 'No results', 'Could not load'].map((Kind) => inst('List notice', { Kind, Device: 'Desktop' })), 'MIN');
