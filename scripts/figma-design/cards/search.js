// Search inside a conversation (ConversationSearchBox, ConversationFilterToggle,
// MobileConversationSearch, MobileConversationFilterNotice,
// ConversationSearchEmpty) and message selection (MessageSelectionBar,
// MessageSelectionActions, Checkbox; "Selection actions" is MessageSelectionComposer, the phone's bottom bar).
card('Search and selection', 'Search opens under the header of a conversation and narrows the feed as you type; the switch beside it leaves only messages with files. On the phone the files filter is a line that says what is shown and how to go back. Selecting messages replaces the header with a count and the actions, and on the phone the actions move to the bottom, within reach of the thumb.');
display(await grid('Conversation search', axis('State', ['Search', 'Files']), DEVICES, ({ State, Device }) => {
  const phone = Device === 'Phone', files = State === 'Files';
  const b = box('Conversation search', { component: true, dir: 'H', gap: 2, pad: [2, feedPad(Device)], w: FEED[Device] });
  if (phone && files) {
    add(b, icon('attach', 'primary'));
    add(b, text('Files', 'labelLarge', 'onSurface'), { fillW: true });
    add(b, setProps(inst('Button', { Kind: 'Text', Device, State: 'Default' }), { Label: 'All messages' }));
    return b;
  }
  // On the phone the X beside the field closes the search, so the field keeps no clear button of its own.
  const field = files ? setProps(inst('Search field', { State: 'Empty', Device }), { Placeholder: 'Search files', Shortcut: false }) : setProps(inst('Search field', { State: 'Query', Device }), { Clear: !phone });
  add(b, field, { fillW: true });
  add(b, phone ? action('close', Device) : segmented(Device, files));
  return b;
}));
const empty = await grid('Search empty', ONE, ONE, () => {
  const e = box('Search empty', { component: true, dir: 'V', gap: 1, pad: [8, 4], w: 390 });
  const title = add(e, text('No messages match “lighthouse keeper”', 'titleSmall', 'onSurface', { name: 'title', w: 320 }), { fillW: true });
  const detail = add(e, text('Search looks through the messages on this device.', 'bodySmall', 'onSurfaceVariant', { w: 320 }), { fillW: true });
  title.textAlignHorizontal = detail.textAlignHorizontal = 'CENTER';
  return e;
});
prop(empty, 'Title', 'TEXT', 'No messages match “lighthouse keeper”', 'title');

await grid('Checkbox', axis('Value', ['Unchecked', 'Checked']), DEVICES, ({ Value, Device }) => {
  const on = Value === 'Checked';
  const mark = box('mark', { dir: 'H', wk: 6, hk: 6, r: 'full', justify: 'CENTER', fill: on ? 'primary' : null, stroke: on ? null : 'outline', sw: 'thick' });
  if (on) add(mark, icon('check', 'onPrimary', 4));
  return shell('Checkbox', mark, Device);
}, 64);
/** A Button turned destructive: the error colour takes the place of the primary one. */
function danger(Device, Label, glyph) {
  const b = setProps(inst('Button', { Kind: 'Primary', Device, State: 'Default' }), { Label, Icon: true, 'Icon glyph': ICONS[glyph] });
  b.fills = paint('error');
  b.findOne((n) => n.type === 'TEXT').fills = paint('onError');
  b.findOne((n) => n.name === 'glyph').fills = paint('onError');
  return b;
}
const textButton = (Device, Label, glyph) => setProps(inst('Button', { Kind: 'Text', Device, State: 'Default' }), glyph ? { Label, Icon: true, 'Icon glyph': ICONS[glyph] } : { Label });
const bars = display(await grid('Selection bar', ONE, DEVICES, ({ Device }) => {
  const phone = Device === 'Phone';
  const b = box('Selection bar', { component: true, dir: 'H', gap: 2, pad: [2, feedPad(Device)], w: FEED[Device], fill: 'surface' });
  add(b, text('3 selected', 'titleMedium', 'onSurface', { name: 'count', truncate: true }), { fillW: true });
  if (!phone) { add(b, textButton(Device, 'Copy', 'copy')); add(b, danger(Device, 'Delete', 'delete')); }
  add(b, textButton(Device, 'Cancel'));
  return b;
}));
prop(bars, 'Count', 'TEXT', '3 selected', 'count');
display(await grid('Selection actions', ONE, axis('Device', ['Phone']), ({ Device }) => {
  const b = box('Selection actions', { component: true, dir: 'H', gap: 2, pad: [2, 3], w: FEED[Device], fill: 'surface', justify: 'CENTER' });
  add(b, textButton(Device, 'Copy', 'copy'));
  add(b, danger(Device, 'Delete', 'delete'));
  return b;
}));

const PICKED = [
  ['Incoming', 'Leo can drive. He has room for three and the gear.', false], ['Incoming', 'I booked the cabin near the lighthouse for two nights.', true],
  ['Outgoing', 'Perfect. I will bring the camera and the thermos.', false], ['Outgoing', 'Should we leave at 6 to beat the traffic?', true], ['Outgoing', 'Sending the packing list in a minute.', true],
];
/** A feed in selection mode: every message gets a checkbox, and a chosen one a band across the feed. */
function selecting(Device) {
  const t = box('Selecting · ' + Device, { dir: 'V', w: FEED[Device], fill: 'surface', align: 'MIN' });
  add(t, inst('Selection bar', { Device }), { fillW: true });
  for (const [side, Text, on] of PICKED) {
    const row = add(t, box('row', { dir: 'H', gap: 2, pad: [1, feedPad(Device)], fill: on ? 'secondaryContainer' : null }), { fillW: true });
    add(row, inst('Checkbox', { Value: on ? 'Checked' : 'Unchecked', Device }));
    const place = add(row, box('place', { dir: 'H', justify: side === 'Outgoing' ? 'MAX' : 'MIN' }), { fillW: true });
    add(place, setProps(inst(side + ' message', { Position: 'Single', Device, State: 'Default' }), { Text }));
  }
  if (Device === 'Phone') add(t, inst('Selection actions', { Device }), { fillW: true });
  return t;
}
await examples('Selecting messages', [selecting('Desktop'), selecting('Phone')], 'MIN');
