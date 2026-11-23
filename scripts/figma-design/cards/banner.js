// Banners of a conversation and of the start screen (CryptoNoticeBanner,
// ChatErrorBanner, OrgAddMissingBanner, GroupRejoinNeededError,
// PersistenceWarningBanner), the update notice of About (AboutUpdateNotice)
// and the notes set inside a form (SetupPrivacyNote, the open-channel warning,
// the note of a ready invite).
card('Banner', 'A banner says something about the whole conversation or the whole app and stays until it stops being true or is closed. Its tone is how much it asks of the reader: a fact about the chat is quiet and carries only a coloured mark, a warning and an error take the whole plate. A banner with something to do offers one action. An inline note is the same message inside a form, beside the field it is about.');
// A tone is the plate, the edge, the ink of the mark, of the title and of the detail.
const TONES_OF = {
  Secure: ['surfaceContainerLow', 'outlineVariant', 'primary', 'onSurface', 'onSurfaceVariant'],
  Open: ['surfaceContainerLow', 'outlineVariant', 'tertiary', 'onSurface', 'onSurfaceVariant'],
  Neutral: ['surfaceContainerLow', 'outlineVariant', 'onSurfaceVariant', 'onSurface', 'onSurfaceVariant'],
  Success: ['surfaceContainerLow', 'outlineVariant', 'success', 'onSurface', 'onSurfaceVariant'],
  Warning: ['warningContainer', null, 'onWarningContainer', 'onWarningContainer', 'onWarningContainer'],
  Error: ['errorContainer', null, 'onErrorContainer', 'onErrorContainer', 'onErrorContainer'],
};
/** A message on a toned plate: mark, title, detail, then what [tail] adds (an action, a close button). */
function notice(name, Tone, glyph, title, detail, o = {}) {
  const [plate, edge, mark, ink, quiet] = TONES_OF[Tone];
  const n = box(name, { component: true, dir: 'H', gap: 3, pad: [3, 3, 3, 4], w: o.w, r: 'large', fill: plate, stroke: edge, align: 'MIN' });
  add(add(n, box('mark', { dir: 'H', hk: 5 })), icon(glyph, mark));
  const col = add(n, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  if (title) para(col, title, 'titleSmall', ink, 'title');
  if (detail) para(col, detail, 'bodySmall', title ? quiet : ink, 'detail');
  return n;
}
// Per banner: tone, mark, title, detail, and what it ends with.
const BANNERS = {
  'Encrypted group': ['Secure', 'lock', 'End-to-end encrypted group', 'Messages are protected by end-to-end encryption. New members cannot see earlier messages.', 'close'],
  'Public channel': ['Open', 'tag', 'Public channel', 'Anyone who joins this channel can read it. Messages here are not end-to-end encrypted.', 'close'],
  'History waiting': ['Open', 'history', 'Waiting for message history', 'Earlier messages are restored when a participant comes online.'],
  'Device removal': ['Open', 'link_off', 'Removing device', 'Removal finishes when the other participants come online and receive the update.'],
  'Add members': ['Neutral', 'group', '2 members from the list are not in this group', null, 'Add to group'],
  Storage: ['Warning', 'warning', 'History is not being saved', 'You can keep messaging, but messages may be lost after restarting the app. Reason: the system keychain is locked.'],
  'Chat error': ['Error', 'error', 'Maya Chen is already in another call', null, 'close'],
  'Rejoin group': ['Error', 'error', 'Group out of sync', 'Ask an administrator to invite you again.'],
};
display(await grid('Banner', axis('Kind', Object.keys(BANNERS)), DEVICES, ({ Kind, Device }) => {
  const [Tone, glyph, title, detail, tail] = BANNERS[Kind];
  const b = notice('Banner', Tone, glyph, title, detail, { w: FEED[Device] - px('space/' + feedPad(Device)) * 2 });
  if (tail === 'close') add(b, action('close', Device, { ink: TONES_OF[Tone][2] === 'primary' || TONES_OF[Tone][2] === 'tertiary' ? null : TONES_OF[Tone][2] })).name = 'close';
  else if (tail) add(b, button(Device, tail, { Kind: 'Outlined' }));
  // The close button and the action are taller than a line of text: the plate keeps its padding around the text.
  if (tail) { b.paddingTop = b.paddingBottom = 0; space(b, 'paddingTop', 2); space(b, 'paddingBottom', 2); space(b, 'paddingRight', 2); b.counterAxisAlignItems = detail ? 'MIN' : 'CENTER'; }
  return b;
}));

// The update notice is a line in the About card: what Mosh knows about its own version, and the one thing to do about it.
const UPDATES = {
  'Up to date': ['success', 'primary', 'This is the newest release.'],
  Checking: ['refresh', 'onSurfaceMuted', 'Checking for updates…'],
  Available: ['update', 'primary', 'Version 0.22.0 is available.', 'Update'],
  'Release page only': ['update', 'primary', 'Version 0.22.0 is available.', 'Open release page'],
  Downloading: ['download', 'primary', 'Downloading the update… 60%'],
  Installing: ['update', 'primary', 'Installing and restarting…'],
  'Check failed': ['error', 'warning', 'Could not check for updates.', 'Try again'],
  'Update failed': ['error', 'error', 'Could not update.', 'Try again'],
};
display(await grid('Update notice', axis('State', Object.keys(UPDATES)), DEVICES, ({ State, Device }) => {
  const [glyph, ink, line, act] = UPDATES[State];
  const n = box('Update notice', { component: true, dir: 'V', gap: 2, w: Device === 'Desktop' ? 480 : 326, minHk: controlHeight(Device), justify: 'CENTER', align: 'MIN' });
  const row = add(n, box('line', { dir: 'H', gap: 3 }), { fillW: true });
  add(row, icon(glyph, ink));
  para(row, line, 'bodyMedium', 'onSurfaceVariant', 'status');
  if (act) add(row, textButton(Device, act));
  if (State === 'Downloading') add(n, inst('Linear progress', { Kind: 'Determinate' }), { fillW: true });
  return n;
}));

const NOTES = {
  Privacy: ['Secure', 'lock', null, 'Your name is stored on this device and shown only to the people you talk to.'],
  'Open channel': ['Warning', 'warning', null, 'End-to-end encryption is off in public channels. Anyone who joins this channel can read its messages.'],
  'Invite ready': ['Success', 'success', 'Invite ready', 'Share the link with one person.'],
};
display(await grid('Inline note', axis('Kind', Object.keys(NOTES)), DEVICES, ({ Kind, Device }) => {
  const [Tone, glyph, title, detail] = NOTES[Kind];
  return notice('Inline note', Tone, glyph, title, detail, { w: Device === 'Desktop' ? 400 : 326 });
}));
