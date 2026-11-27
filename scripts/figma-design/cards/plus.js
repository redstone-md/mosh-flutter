// Mosh+ in the profile settings: buying it (PlusCurrencyCheckout, PlusPaymentTerms),
// a payment that is awaited (PlusPendingPayment), getting a purchase back on
// another device (PlusRecoveryPanel) and the membership itself (PlusMembershipStatus).
card('Mosh+', 'Mosh+ is one card that changes with how far the purchase has got. It names the price and what it buys before anything else, and keeps the mint, the recipient and the terms folded under a line, since they are checked once and not read each time. A payment is made on another device, so the card then shows a QR to scan and says that Mosh can be closed meanwhile. While a payment is awaited the card offers no second purchase. A paid membership says until when it runs and holds the one setting it has.');
const PLUS_W = { Desktop: 560, Phone: ROW.Phone };
const OFFER = '5 USDC for 30 days';
/** The currencies to pay in, the first one chosen. */
function currencies(Device) {
  const c = box('currency', { dir: 'H', pad: 1, gap: 1, r: 'full', fill: 'surfaceContainerLowest' });
  ['USDC', 'CLXAI'].forEach((Label, i) => add(c, setProps(inst('Segment', { Selected: i ? 'No' : 'Yes', State: 'Default', Device }), { Label })));
  return c;
}
/** A row of the card's actions, which runs on to a second line where the card is narrow. */
function actions(c, buttons) {
  const r = add(c, box('actions', { dir: 'H', gap: 2 }), { fillW: true });
  r.layoutWrap = 'WRAP'; space(r, 'counterAxisSpacing', 2);
  buttons.forEach((b) => add(r, b));
}
/** What is bought and for how much, with the choice of currency beside it (under it on the phone, where the price needs the line), and the way to buy or to get a purchase back. */
function offer(c, Device) {
  const r = add(c, box('offer', Device === 'Phone' ? { dir: 'V', gap: 3, align: 'MIN' } : { dir: 'H', gap: 3 }), { fillW: true });
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  para(col, OFFER, 'titleLarge', 'onSurface', 'price');
  para(col, 'One payment, no automatic charges', 'bodySmall', 'onSurfaceVariant', 'terms');
  add(r, currencies(Device));
  actions(c, [labelButton(Device, 'Buy Mosh+'), labelButton(Device, 'Recover purchase', { Kind: 'Text' })]);
}
/** The line the payment details fold under. */
function fold(c, Device, State = 'Closed') {
  add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
  add(c, setProps(inst('Disclosure', { State, Device }), { Label: 'Payment details and terms' }), { fillW: true });
}
/** A QR to scan with another device, and under it the line that says with what. */
function scan(c, line) {
  const q = add(c, box('scan', { dir: 'V', gap: 3 }), { fillW: true });
  add(q, inst('QR code'));
  para(q, line, 'bodySmall', 'onSurfaceVariant', 'how').textAlignHorizontal = 'CENTER';
}
// Per kind: what the card holds under its header.
const KINDS = {
  Buy: (c, Device) => { offer(c, Device); fold(c, Device); },
  'Details open': (c, Device) => {
    offer(c, Device);
    fold(c, Device, 'Open');
    const d = add(c, box('details', { dir: 'V', gap: 2, pad: [0, 3], align: 'MIN' }), { fillW: true });
    for (const [Label, Value] of [['Network', 'Solana Mainnet'], ['Token mint', 'EPjFWdd5…wyTDt1v'], ['Recipient', '11111111…11111111']]) add(d, setProps(inst('Value row', { Device }), { Label, Value }), { fillW: true });
    para(d, 'Renewal adds 30 days after the paid term. A first purchase starts once the payment is verified and rounds up to a UTC day. Underpayments do not activate Mosh+, and overpayments add no extra time. Network fees are extra and require SOL in the paying wallet.', 'bodySmall', 'onSurfaceVariant', 'terms');
    para(d, 'Billing does not receive your Mosh account. It can link purchases in the same renewal series and see wallet payments. The badge and its visibility sync with your linked devices.', 'bodySmall', 'onSurfaceVariant', 'privacy');
    actions(d, ['Purchase terms', 'Payment support'].map((l) => labelButton(Device, l, { Kind: 'Text' })));
  },
  'Awaiting payment': (c, Device) => {
    const col = add(c, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
    para(col, OFFER, 'titleLarge', 'onSurface', 'price');
    para(col, 'Waiting for a finalized payment. You can close Mosh and return later.', 'bodyMedium', 'onSurfaceVariant', 'status');
    scan(c, 'Scan with your phone’s Camera app and pay from your wallet');
    actions(c, [labelButton(Device, 'Copy payment link', { Kind: 'Outlined', glyph: 'copy' }), labelButton(Device, 'Check payment', { Kind: 'Text', glyph: 'refresh' })]);
    fold(c, Device);
  },
  Recovery: (c, Device) => {
    para(c, 'Only the wallet that paid can recover its remaining periods. This restores Mosh+ to this account, without chats or account keys.', 'bodyMedium', 'onSurfaceVariant', 'about');
    add(c, setProps(inst('Code plate'), { Label: 'Device code', Code: 'R4KD-92QX' }), { fillW: true });
    scan(c, 'Scan with your phone’s Camera app, open the page in your wallet browser and compare the device code before confirming');
    actions(c, [labelButton(Device, 'Copy recovery link', { Kind: 'Outlined', glyph: 'copy' }), labelButton(Device, 'Open recovery page', { Kind: 'Outlined', glyph: 'open_external' }), labelButton(Device, 'Refresh status', { Kind: 'Text', glyph: 'refresh' })]);
  },
  Active: (c, Device) => {
    const s = add(c, box('status', { dir: 'H', gap: 2 }), { fillW: true });
    add(s, icon('success', 'success'));
    para(s, 'Mosh+ valid until 2026-12-18 23:55 UTC', 'titleSmall', 'onSurface', 'until');
    add(c, setProps(inst('Switch row', { Value: 'On', State: 'Default', Device }), { Title: 'Show my Mosh+ badge', Subtitle: 'One setting for all conversations. Previously shared proof may remain with other people.' }), { fillW: true });
    actions(c, [labelButton(Device, 'Add 30 days', { Kind: 'Outlined' })]);
    fold(c, Device);
  },
};
display(await grid('Mosh+ card', axis('Kind', Object.keys(KINDS)), DEVICES, ({ Kind, Device }) => {
  const c = cardSurface('Mosh+ card', { component: true, dir: 'V', gap: 4, pad: cardPad(Device), w: PLUS_W[Device], align: 'MIN' });
  header(c, 'plus_badge', 'Mosh+', 'Support Mosh development');
  KINDS[Kind](c, Device);
  return c;
}));
