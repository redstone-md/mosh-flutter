// Attachments: the file card (FileCard),
// the picture and video card, and the file row of the conversation details
// (ConversationSharedFile), which is the file card on a surface.
card('Attachment', 'A file shows its name, its size and, on its plate, the one thing that can be done with it now: download it, stop the transfer, pick it up again or try again; the whole card is the target. A picture and a video show their preview first. The cards have no background of their own; they sit in a bubble, in either of its colours, or in the list of shared files. A long name is cut in the middle, so its start and its extension both show.');
// Per state: the line under the name and what the plate shows. The plate is the action and the whole card its target,
// which leaves the far corner free for the time of a message that is a file alone.
const FILE = { Ready: ['1.2 MB', 'file'], 'To download': ['1.2 MB', 'download'], Transfer: ['58% of 1.2 MB', 'close'], Paused: ['Paused', 'download'], Cancelled: ['Transfer cancelled', 'refresh'], Failed: ['Transfer failed', 'refresh'] };
/** The name of a file in [parent], at most [max] px wide. A long name is cut in the middle: its end is a text of its own, empty for a name that fits, and nameFile() shortens the start until both fit. */
function fileName(parent, chars, ink, layer, max) {
  const title = add(parent, box('title', { dir: 'H' }));
  add(title, text(chars, 'labelLarge', ink, { name: layer, cut: true }), { max });
  add(title, text('', 'labelLarge', ink, { name: 'name end' }));
  return title;
}
function file({ State, Tone, Device }) {
  const c = TONES[Tone], [detail, glyph] = FILE[State], failed = State === 'Failed';
  // The card is as tall as its plate, so in a bubble the plate keeps the bubble's 8 px on three sides and its 12 px corners stay concentric with the bubble's 20 px ones.
  const f = box('File card', { component: true, dir: 'H', gap: 3, w: attachmentWidth(Device) });
  const thumb = add(f, box('thumb', { dir: 'H', wk: 10, hk: 10, r: 'medium', fill: failed ? c.failPlate : c.plate, justify: 'CENTER' }));
  add(thumb, icon(glyph, failed && Tone === 'Surface' ? 'error' : c.glyph));
  // With the bar between them the two lines sit close, to stay within the plate's height.
  const col = add(f, box('file', { dir: 'V', gap: State === 'Transfer' ? undefined : 1, align: 'MIN' }), { fillW: true });
  fileName(col, 'coast-route.pdf', c.ink, 'name', attachmentWidth(Device) - px('space/10') - px('space/3'));
  // The bar runs above the detail, so the detail stays the last line, level with the time.
  if (State === 'Transfer') {
    const bar = add(col, inst('Linear progress', { Kind: 'Determinate' }), { fillW: true });
    // The bar's own amber would vanish on the outgoing bubble.
    if (Tone === 'Outgoing') { bar.fills = paint(c.rest); bar.children[0].fills = paint(c.accent); }
  }
  add(col, text(detail, 'labelMedium', failed ? c.error : c.quiet, { name: 'detail ' + State, truncate: true }), { fillW: true });
  return f;
}
const STATES = Object.keys(FILE);
// The card is pressed together with the 8 px the bubble or the list row keeps around it, 56 px in all, so no target is asked of the card alone.
const files = backdrop(display(await grid('File card', perDevice(toneRows(ONE)), axis('State', STATES), file)));
prop(files, 'Name', 'TEXT', 'coast-route.pdf', 'name');
prop(files, 'Name end', 'TEXT', '', 'name end');
for (const s of STATES) prop(files, 'Detail, ' + s.toLowerCase(), 'TEXT', FILE[s][0], 'detail ' + s);

const PREVIEW = { Desktop: 200, Phone: 148 };
// Per state: the line beside the name and the px held back for it, so the name knows where to be cut.
const MEDIA = { Ready: ['2.7 MB', 48], Loading: ['58% of 2.7 MB', 88], Failed: ['Could not load', 88] };
function media({ Kind, State, Tone, Device }) {
  const c = TONES[Tone], w = attachmentWidth(Device), h = PREVIEW[Device], failed = State === 'Failed';
  const m = box('Media card', { component: true, dir: 'V', gap: 2, w, align: 'MIN' });
  // The preview stands for the picture itself, which a screen puts in its place.
  const view = add(m, box('preview', { dir: 'H', w, h, r: 'medium', fill: failed ? 'errorContainer' : 'tertiaryContainer', justify: 'CENTER', clip: true }), { fillW: true });
  if (failed) add(view, action('refresh', Device, { Kind: 'Tonal' }));
  else if (State === 'Loading') add(view, inst('Circular progress', { Size: 'Large' }));
  else if (Kind === 'Image') add(view, icon('image', 'onTertiaryContainer', 8));
  else add(add(view, box('play', { dir: 'H', wk: 12, hk: 12, r: 'full', fill: 'surface', justify: 'CENTER' })), icon('play', 'onSurface', 6));
  // Set in as far as a message's text, so the file name and the text under it start on one line.
  const line = add(m, box('caption', { dir: 'H', gap: 2, pad: INSET }), { fillW: true });
  const [detail, room] = MEDIA[State];
  fileName(line, Kind === 'Image' ? 'harbour.jpg' : 'waves.mp4', c.ink, 'name ' + Kind, w - lineWidth(Device) + MEASURE[Device] - px('space/2') - room).layoutSizingHorizontal = 'FILL';
  add(line, text(detail, 'labelMedium', failed ? c.error : c.quiet, { name: 'detail' }));
  return m;
}
const medias = backdrop(display(await grid('Media card', perDevice(toneRows(axis('Kind', ['Image', 'Video']))), axis('State', Object.keys(MEDIA)), media)));
prop(medias, 'Name, image', 'TEXT', 'harbour.jpg', 'name Image');
prop(medias, 'Name, video', 'TEXT', 'waves.mp4', 'name Video');
prop(medias, 'Name end', 'TEXT', '', 'name end');

// A row keeps 8 px around its card, as a bubble does, so the row is the 56 px target.
const shared = box('Shared files', { dir: 'V', w: 320 + 2 * px('space/2') });
[['Ready', 'ridge-trail.jpg'], ['To download', 'waves.mp4'], ['Transfer', 'tide-tables.xlsx'], ['Failed', 'packing-list.docx']].forEach(([State, Name]) => add(add(shared, box('row', { dir: 'H', pad: 2 })), nameFile(inst('File card', { State, Tone: 'Surface', Device: 'Desktop' }), Name)));
await examples('Shared files in the conversation details', [shared]);
