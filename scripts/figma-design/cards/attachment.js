// Attachments: the file card (attachment_card._FileCardShell, AttachmentThumb),
// the picture and video card, and the file row of the conversation details
// (ConversationSharedFile), which is the file card on a surface.
card('Attachment', 'A file shows its name, its size and the one thing that can be done with it now: download it, stop the transfer or try again. A picture and a video show their preview first. The cards have no plate of their own; they sit in a bubble, in either of its colours, or in the list of shared files. A long name is cut at the end.');
// A card is as wide as a bubble's text on the phone, so it never widens the bubble past the feed.
const WIDTH = { Desktop: 320, Phone: MEASURE.Phone };
// Per state: the line under the name and the action.
const FILE = { Ready: ['1.2 MB', null], 'To download': ['1.2 MB', 'download'], Transfer: ['58% of 1.2 MB', 'close'], Failed: ['Transfer failed', 'refresh'] };
function file({ State, Tone, Device }) {
  const c = TONES[Tone], [detail, act] = FILE[State], failed = State === 'Failed';
  const f = box('File card', { component: true, dir: 'H', gap: 3, w: WIDTH[Device], minHk: 12 });
  const thumb = add(f, box('thumb', { dir: 'H', wk: 10, hk: 10, r: 'medium', fill: failed ? c.failPlate : c.plate, justify: 'CENTER' }));
  add(thumb, icon(failed ? 'error' : 'file', failed && Tone === 'Surface' ? 'error' : c.glyph));
  const col = add(f, box('file', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
  add(col, text('coast-route.pdf', 'labelLarge', c.ink, { name: 'name', truncate: true }), { fillW: true });
  add(col, text(detail, 'labelMedium', failed ? c.error : c.quiet, { name: 'detail ' + State, truncate: true }), { fillW: true });
  if (State === 'Transfer') {
    const bar = add(col, inst('Linear progress', { Kind: 'Determinate' }), { fillW: true });
    // The bar's own amber would vanish on the outgoing bubble.
    if (Tone === 'Outgoing') { bar.fills = paint(c.rest); bar.children[0].fills = paint(c.accent); }
  }
  if (act) add(f, action(act, Device, { ink: Tone === 'Outgoing' ? c.ink : null }));
  return f;
}
const STATES = Object.keys(FILE);
const files = backdrop(await grid('File card', perDevice(toneRows(ONE)), axis('State', STATES), file));
prop(files, 'Name', 'TEXT', 'coast-route.pdf', 'name');
for (const s of STATES) prop(files, 'Detail, ' + s.toLowerCase(), 'TEXT', FILE[s][0], 'detail ' + s);

const PREVIEW = { Desktop: 200, Phone: 148 };
const MEDIA = { Ready: '2.7 MB', Loading: '58% of 2.7 MB', Failed: 'Could not load' };
function media({ Kind, State, Tone, Device }) {
  const c = TONES[Tone], w = WIDTH[Device], h = PREVIEW[Device], failed = State === 'Failed';
  const m = box('Media card', { component: true, dir: 'V', gap: 2, w, align: 'MIN' });
  // The preview stands for the picture itself, which a screen puts in its place.
  const view = add(m, box('preview', { dir: 'H', w, h, r: 'medium', fill: failed ? 'errorContainer' : 'tertiaryContainer', justify: 'CENTER', clip: true }), { fillW: true });
  if (failed) add(view, action('refresh', Device, { Kind: 'Tonal' }));
  else if (State === 'Loading') add(view, inst('Circular progress', { Size: 'Large' }));
  else if (Kind === 'Image') add(view, icon('image', 'onTertiaryContainer', 8));
  else add(add(view, box('play', { dir: 'H', wk: 12, hk: 12, r: 'full', fill: 'surface', justify: 'CENTER' })), icon('play', 'onSurface', 6));
  const line = add(m, box('caption', { dir: 'H', gap: 2, pad: [0, 1] }), { fillW: true });
  add(line, text(Kind === 'Image' ? 'harbour.jpg' : 'waves.mp4', 'labelLarge', c.ink, { name: 'name ' + Kind, truncate: true }), { fillW: true });
  add(line, text(MEDIA[State], 'labelMedium', failed ? c.error : c.quiet, { name: 'detail' }));
  return m;
}
const medias = backdrop(display(await grid('Media card', perDevice(toneRows(axis('Kind', ['Image', 'Video']))), axis('State', Object.keys(MEDIA)), media)));
prop(medias, 'Name, image', 'TEXT', 'harbour.jpg', 'name Image');
prop(medias, 'Name, video', 'TEXT', 'waves.mp4', 'name Video');

const shared = box('Shared files', { dir: 'V', gap: 1, w: 320 });
[['Ready', 'ridge-trail.jpg'], ['To download', 'waves.mp4'], ['Transfer', 'tide-tables.xlsx'], ['Failed', 'packing-list.docx']].forEach(([State, Name]) => add(shared, setProps(inst('File card', { State, Tone: 'Surface', Device: 'Desktop' }), { Name }), { fillW: true }));
await examples('Shared files in the conversation details', [shared]);
