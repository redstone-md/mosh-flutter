// What a conversation shows when it has nothing to show
// (conversation_screen_body._ConversationEmpty and its load error), beside the
// notices of an empty chat list (RailNotice), which the Chat list card owns as List notice;
// what takes the whole screen when Mosh has nothing else to show yet (MoshLockScreen,
// FirstRunGate's read error); and where a dragged file lands (chat_drop_zone._DropOverlay).
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

// Per kind: mark, title, line, the action with its glyph, and a second, quiet action.
const NOTICES = {
  Locked: ['lock', 'Mosh is locked', 'Biometric authentication was canceled. Tap Retry to unlock your conversations.', ['Retry', 'refresh']],
  Unlocking: [null, 'Unlocking Mosh…'],
  'Not secured': ['shield_warning', 'Device not secured', 'Mosh requires a screen lock (PIN, pattern or biometric) to protect your conversations. Set one in the system settings, then reopen Mosh.'],
  'Setup not read': ['error', 'Could not read your setup', 'Your setup or existing conversations could not be read. Retry, and if the problem continues, restart Mosh.', ['Retry', 'refresh'], 'Share app log'],
};
display(await grid('Screen notice', axis('Kind', Object.keys(NOTICES)), DEVICES, ({ Kind, Device }) => {
  const [glyph, title, line, act, more] = NOTICES[Kind];
  const n = surface('Screen notice', 'background', { component: true, dir: 'V', gap: 4, pad: [12, 4], w: Device === 'Phone' ? PHONE_SCREEN : 480 });
  // While Mosh works there is nothing to read a mark for: the spinner stands in its place.
  add(n, glyph ? icon(glyph, more ? 'error' : 'onSurfaceVariant', 10) : inst('Circular progress', { Size: 'Large' }));
  const col = add(n, box('text', { dir: 'V', gap: 2 }), { fillW: true });
  para(col, title, 'headlineSmall', 'onSurface', 'title').textAlignHorizontal = 'CENTER';
  if (line) para(col, line, 'bodyMedium', 'onSurfaceVariant', 'line').textAlignHorizontal = 'CENTER';
  if (act) add(n, labelButton(Device, act[0], { glyph: act[1] }));
  if (more) add(n, labelButton(Device, more, { Kind: 'Text', glyph: 'share' }));
  return n;
}));
// Only the desktop has a pointer to drag a file with. The feed under the zone goes dark, and the dashed edge says where the file lands.
await grid('Drop zone', ONE, ONE, () => {
  const d = box('Drop zone', { component: true, dir: 'V', gap: 2, w: FEED.Desktop, h: 320, r: 'large', clip: true, stroke: 'primary', sw: 'thick', justify: 'CENTER' });
  d.dashPattern = [8, 8];
  add(d, icon('attach', 'primary', 8));
  add(d, text('Drop a file to share it', 'titleSmall', 'onSurface'));
  tint(d, BENEATH, 'scrim');
  return d;
});
