// Banners of a conversation and of the start screen (CryptoNoticeBanner,
// ChatErrorBanner, OrgAddMissingBanner, GroupRejoinNeededError,
// PersistenceWarningBanner), the update notice of About (AboutUpdateNotice)
// and the notes set inside a form (SetupPrivacyNote, the open-channel warning,
// the note of a ready invite).
card('Banner', 'A banner says something about the whole conversation or the whole app and stays until it stops being true or is closed. Its tone is how much it asks of the reader: a fact about the chat is quiet and carries only a coloured mark, a warning and an error take the whole plate. A banner with something to do offers one action. An inline note is the same message inside a form, beside the field it is about.');
// A tone is the fill, the edge, the ink of the mark, of the title and of the detail.
// A quiet tone lies on the panel level and differs only in the colour of its mark.
const quiet = (mark) => [LEVEL.panel.fill, 'outlineVariant', mark, 'onSurface', 'onSurfaceVariant'];
const NOTICE_TONES = {
  Secure: quiet('primary'), Open: quiet('tertiary'), Neutral: quiet('onSurfaceVariant'), Success: quiet('success'),
  Warning: ['warningContainer', null, 'onWarningContainer', 'onWarningContainer', 'onWarningContainer'],
  Error: ['errorContainer', null, 'onErrorContainer', 'onErrorContainer', 'onErrorContainer'],
};
/**
 * A message on a toned surface: mark, title, detail. The mark is as tall as the first line and stands beside it,
 * as far from the left edge as from the top one; one line of text leaves it as far from the bottom too.
 * A longer message runs on under the first line. The caller adds what the message ends with through ending(). o: w, r.
 */
function notice(name, Tone, glyph, title, detail, o = {}) {
  const [fill, edge, mark, ink, soft] = NOTICE_TONES[Tone];
  const n = box(name, { component: true, dir: 'H', gap: 3, pad: 4, w: o.w, r: o.r ?? 'large', fill, stroke: edge, align: 'MIN' });
  add(n, icon(glyph, mark)).name = 'mark';
  const col = add(n, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  if (title) para(col, title, 'titleSmall', ink, 'title');
  // Alone, the detail is the message: it takes the line height of the mark beside it.
  if (detail) para(col, detail, title ? 'bodySmall' : 'bodyMedium', title ? soft : ink, 'detail');
  return n;
}
/** Ends [banner] with a control on its first line: the control is taller than the line and keeps its own room around it. edge: the space key left to the banner's edge. */
function ending(banner, control, edge) {
  add(add(banner, box('ending', { dir: 'H', hk: 5 })), control);
  space(banner, 'paddingRight', edge);
}
// Per banner: tone, mark, title, detail, and what it ends with.
const BANNERS = {
  'Encrypted group': ['Secure', 'lock', 'End-to-end encrypted group', 'Messages are protected by end-to-end encryption. New members cannot see earlier messages.', 'close'],
  'Public channel': ['Open', 'tag', 'Public channel', 'Anyone who joins this channel can read it. Messages here are not end-to-end encrypted.', 'close'],
  'History waiting': ['Open', 'history', 'Waiting for message history', 'Earlier messages are restored when a participant comes online'],
  'Device removal': ['Open', 'link_off', 'Removing device', 'Removal finishes when the other participants come online and receive the update'],
  'Add members': ['Neutral', 'group', '2 members from the list are not in this group', null, 'Add to group'],
  Storage: ['Warning', 'warning', 'History is not being saved', 'You can keep messaging, but messages may be lost after restarting the app. Reason: the system keychain is locked.'],
  'Chat error': ['Error', 'error', 'Maya Chen is already in another call', null, 'close'],
  'Rejoin group': ['Error', 'error', 'Group out of sync', 'Ask an administrator to invite you again'],
};
display(await grid('Banner', axis('Kind', Object.keys(BANNERS)), DEVICES, ({ Kind, Device }) => {
  const [Tone, glyph, title, detail, tail] = BANNERS[Kind];
  const b = notice('Banner', Tone, glyph, title, detail, { w: FEED[Device] - px('space/' + feedPad(Device)) * 2 });
  // On a toned surface the close button takes the surface's ink. Its glyph ends as far from the edge as the mark starts.
  if (tail === 'close') ending(b, action('close', Device, { ink: NOTICE_TONES[Tone][1] ? null : NOTICE_TONES[Tone][2] }), Device === 'Phone' ? 1 : 2);
  else if (tail) ending(b, labelButton(Device, tail, { Kind: 'Outlined' }), 3);
  return b;
}));

// The update notice is a line in the About card: what Mosh knows about its own version, and the one thing to do about it.
const UPDATES = {
  'Up to date': ['success', 'primary', 'This is the newest release'],
  Checking: ['refresh', 'onSurfaceMuted', 'Checking for updates…'],
  Available: ['update', 'primary', 'Version 0.22.0 is available', 'Update'],
  'Release page only': ['update', 'primary', 'Version 0.22.0 is available', 'Open release page'],
  Downloading: ['download', 'primary', 'Downloading the update… 60%'],
  Installing: ['update', 'primary', 'Installing and restarting…'],
  'Check failed': ['error', 'warning', 'Could not check for updates', 'Try again'],
  'Update failed': ['error', 'error', 'Could not update', 'Try again'],
};
display(await grid('Update notice', axis('State', Object.keys(UPDATES)), DEVICES, ({ State, Device }) => {
  const [glyph, ink, line, act] = UPDATES[State];
  const n = box('Update notice', { component: true, dir: 'V', gap: 2, w: Device === 'Desktop' ? 480 : DIALOG.Phone, minHk: controlHeight(Device), justify: 'CENTER', align: 'MIN' });
  const row = add(n, box('line', { dir: 'H', gap: 3 }), { fillW: true });
  add(row, icon(glyph, ink));
  para(row, line, 'bodyMedium', 'onSurfaceVariant', 'status');
  if (act) {
    // A text button's label, not its invisible edge, ends on the line the values above it end on:
    // the button hangs over the right edge by its own side padding.
    const b = labelButton(Device, act, { Kind: 'Text' });
    add(add(row, box('action', { dir: 'H', w: b.width - px('space/4'), h: b.height })), b);
  }
  if (State === 'Downloading') add(n, inst('Linear progress', { Kind: 'Determinate' }), { fillW: true });
  return n;
}));

const NOTES = {
  Privacy: ['Secure', 'lock', null, 'Your name is stored on this device and shown only to the people you talk to'],
  'Open channel': ['Warning', 'warning', null, 'End-to-end encryption is off in public channels. Anyone who joins this channel can read its messages.'],
  'Invite ready': ['Success', 'success', 'Invite ready', 'Share the link with one person'],
};
display(await grid('Inline note', axis('Kind', Object.keys(NOTES)), DEVICES, ({ Kind, Device }) => {
  const [Tone, glyph, title, detail] = NOTES[Kind];
  // A note sits inside a card, so its corners are a step tighter than a banner's.
  return notice('Inline note', Tone, glyph, title, detail, { w: DIALOG[Device], r: 'medium' });
}));
