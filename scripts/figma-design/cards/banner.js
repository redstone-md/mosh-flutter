// Banners of a conversation and of the start screen (CryptoNoticeBanner,
// ChatErrorBanner, OrgAddMissingBanner, GroupRejoinNeededError,
// PersistenceWarningBanner), the update notice of About (AboutUpdateNotice)
// and the notes set inside a form (SetupPrivacyNote, the open-channel warning,
// the note of a ready invite).
card('Banner', 'A banner says something about the whole conversation or the whole app and stays until it stops being true or is closed. Its tone is how much it asks of the reader: a fact about the chat is quiet and carries only a coloured mark, a warning and an error take the whole plate. A banner with something to do offers one action. An inline note is the same message inside a form, beside the field it is about.');
// A tone is the fill, the edge, the ink of the mark, of the title and of the detail, then the fill and the ink of the mark's plate.
// A quiet tone lies on the panel level and differs only in the colour of its mark.
// On a warning and an error the plate is the background's tone, so the mark is the one bright thing on them.
const quiet = (mark) => [LEVEL.panel.fill, 'outlineVariant', mark, 'onSurface', 'onSurfaceVariant', 'surfaceContainerHighest', mark];
const NOTICE_TONES = {
  Secure: quiet('primary'), Open: quiet('tertiary'), Neutral: quiet('onSurfaceVariant'), Success: quiet('success'),
  Warning: ['warningContainer', null, 'onWarningContainer', 'onWarningContainer', 'onWarningContainer', LEVEL.background.fill, 'warning'],
  Error: ['errorContainer', null, 'onErrorContainer', 'onErrorContainer', 'onErrorContainer', LEVEL.background.fill, 'error'],
};
/**
 * A message on a toned surface: mark, title, detail; the caller adds what it ends with (an action, a close button).
 * Everything is centred on the middle of the message. A title with a detail under it is tall enough for the mark
 * to stand on a plate; beside one line the mark is the bare icon. o: w, r.
 */
function notice(name, Tone, glyph, title, detail, o = {}) {
  const [fill, edge, mark, ink, soft, plateFill, plateInk] = NOTICE_TONES[Tone], plated = title && detail;
  const n = box(name, { component: true, dir: 'H', gap: 3, pad: [3, 3, 3, plated ? 3 : 4], w: o.w, r: o.r ?? 'large', fill, stroke: edge });
  add(n, plated ? plate(glyph, plateFill, plateInk) : icon(glyph, mark)).name = 'mark';
  const col = add(n, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  if (title) para(col, title, 'titleSmall', ink, 'title');
  if (detail) para(col, detail, 'bodySmall', title ? soft : ink, 'detail');
  return n;
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
  // On a toned plate the close button takes the plate's ink.
  if (tail === 'close') add(b, action('close', Device, { ink: NOTICE_TONES[Tone][1] ? null : NOTICE_TONES[Tone][2] })).name = 'close';
  else if (tail) add(b, labelButton(Device, tail, { Kind: 'Outlined' }));
  // A control at the end brings its own room around its glyph or label.
  if (tail) space(b, 'paddingRight', 2);
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
  if (act) add(row, textButton(Device, act));
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
