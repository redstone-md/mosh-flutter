// Dialogs: MoshDialog (confirmations, the rename form, notices), the call's
// device dialog and VpnConsentModal, with the scrim every modal surface lies on.
card('Dialog', 'A dialog stops the screen for one decision. It names the decision in its title, says what follows in a sentence or two, and ends with the answers, the one that goes on at the right. A destructive answer is the only red on it. Cancel, Escape and a press on the scrim all leave without a change, so only a dialog without answers of its own has a close button. On the phone long answers stack, the main one on top.');

await grid('Scrim', ONE, ONE, () => {
  const s = box('Scrim', { component: true, w: 240, h: 96, fill: 'surfaceContainerLowest' });
  bind(s, 'opacity', 'state/scrim');
  return s;
});

const VPN_TITLE = 'A VPN is carrying Mosh’s traffic';
const VPN_BODY = ['Everything Mosh sends goes through your VPN, which stops other people from finding you. Mosh can use wlan0 instead.', 'Peers will see your real network address rather than the VPN’s. Mosh restarts to apply this, and you can change it later in Settings.'];
// Per kind: the title, the body, the answer that leaves and the answer that goes on.
const KINDS = {
  Confirm: ['Leave #photography?', ['You can join this channel again by its name.'], 'Cancel', 'Leave channel'],
  Destructive: ['Delete chat with Maya Chen?', ['Saved history for this private chat will be removed from this device. You cannot undo this.'], 'Cancel', 'Delete chat'],
  Input: ['Rename chat', [], 'Cancel', 'Save'],
  Notice: ['Restart Mosh to apply the connection', ['Setup is saved. Close Mosh completely and open it again to apply the network interface. The running connection has not changed.'], null, 'Understood'],
  Devices: ['Call devices', [], null, null],
  'VPN consent': [VPN_TITLE, VPN_BODY, 'Keep using the VPN', 'Route around the VPN'],
  'VPN restarting': [VPN_TITLE, VPN_BODY, 'Keep using the VPN', 'Restarting…'],
  'VPN not saved': [VPN_TITLE, VPN_BODY, 'Keep using the VPN', 'Route around the VPN'],
};
function dialog({ Kind, Device }) {
  const [title, body, leave, go] = KINDS[Kind], vpn = Kind.startsWith('VPN'), busy = Kind === 'VPN restarting';
  const d = surface('Dialog', 'modal', { component: true, dir: 'V', gap: 4, pad: 6, w: DIALOG[Device], r: 'extraLarge', align: 'MIN' });
  const head = add(d, box('head', { dir: 'H', gap: 2, align: 'MIN' }), { fillW: true });
  para(head, title, 'titleLarge', 'onSurface', 'title');
  if (Kind === 'Devices') add(head, action('close', Device)).name = 'close';
  body.forEach((p, i) => para(d, p, 'bodyMedium', 'onSurfaceVariant', i ? 'body, more' : 'body'));
  if (Kind === 'Input') add(d, setProps(inst('Text field', { State: 'Filled', Device }), { Label: 'Chat name', Value: 'Weekend plans' }), { fillW: true });
  if (Kind === 'Devices') {
    for (const [Label, Value] of [['Microphone', 'USB Microphone'], ['Speaker', 'Studio Headphones'], ['Camera', 'System default']]) add(d, setProps(inst('Select', { State: 'Closed', Device }), { Label, Value }), { fillW: true });
    para(d, 'Video is sent as VP8 at 1280×720, 30 frames a second', 'bodySmall', 'onSurfaceMuted', 'video format');
  }
  if (Kind === 'VPN not saved') add(d, setProps(inst('Inline error'), { Message: 'Your answer could not be saved. Try again.' }), { fillW: true });
  if (!go) return d;
  // The phone has no room for two long answers side by side.
  const stacked = vpn && Device === 'Phone';
  const answers = add(d, box('answers', { dir: stacked ? 'V' : 'H', gap: 2, pad: [2, 0, 0, 0], justify: stacked ? 'MIN' : 'MAX' }), { fillW: true });
  const main = Kind === 'Destructive' ? danger(Device, go) : button(Device, go, { Kind: leave ? 'Primary' : 'Text', State: busy ? 'Loading' : 'Default' });
  const other = leave && button(Device, leave, { Kind: 'Text', State: busy ? 'Disabled' : 'Default' });
  for (const b of stacked ? [main, other] : [other, main]) if (b) add(answers, b, { fillW: stacked });
  return d;
}
display(await grid('Dialog', axis('Kind', Object.keys(KINDS)), DEVICES, dialog));
