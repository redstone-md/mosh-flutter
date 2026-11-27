// Mosh+ in the profile settings: buying it (PlusCurrencyCheckout, PlusPaymentTerms),
// a payment that is awaited (PlusPendingPayment), getting a purchase back on
// another device (PlusRecoveryPanel) and the membership itself (PlusMembershipStatus).
card('Mosh+', 'Mosh+ is one card that changes with how far the purchase has got. It names the price and what it buys before anything else, and keeps the mint, the recipient and the terms folded under a line, since they are checked once and not read each time. A payment is made on another device, so the card then shows a QR to scan and says that Mosh can be closed meanwhile. While a payment is awaited the card offers no second purchase. A paid membership says until when it runs and holds the one setting it has.');
const OFFER = '5 USDC for 30 days';
const TERMS = 'Payment details and terms';
/** The [buttons] of the card in a row. */
function buttonRow(c, buttons) {
  const r = wrapRow(c, 'actions', 2);
  buttons.forEach((b) => add(r, b));
}
/** What is bought and for how much, with the choice of currency beside it (under it on the phone, where the price needs the line), and the way to [buy] or to get a purchase back. */
function offer(c, Device, buy = 'Buy Mosh+') {
  const r = add(c, box('offer', Device === 'Phone' ? { dir: 'V', gap: 3, align: 'MIN' } : { dir: 'H', gap: 3 }), { fillW: true });
  const col = add(r, box('text', { dir: 'V', align: 'MIN' }), { fillW: true });
  para(col, OFFER, 'titleLarge', 'onSurface', 'price');
  para(col, 'One payment, no automatic charges', 'bodySmall', 'onSurfaceVariant', 'terms');
  add(r, segmentChoice(Device, ['USDC', 'CLXAI']));
  buttonRow(c, [labelButton(Device, buy), labelButton(Device, 'Recover purchase', { Kind: 'Text' })]);
}
/** A QR to scan with another device, and under it the line that says with what. */
function scan(c, line) {
  const q = add(c, box('scan', { dir: 'V', gap: 3 }), { fillW: true });
  add(q, inst('QR code'));
  para(q, line, 'bodySmall', 'onSurfaceVariant', 'how').textAlignHorizontal = 'CENTER';
}
// Per kind: what the card holds under its header.
const KINDS = {
  Buy: (c, Device) => { offer(c, Device); fold(c, Device, 'Closed', TERMS); },
  'Details open': (c, Device) => {
    offer(c, Device);
    fold(c, Device, 'Open', TERMS);
    const d = add(c, box('details', { dir: 'V', gap: 2, pad: [0, 3], align: 'MIN' }), { fillW: true });
    add(d, setProps(inst('Value row', { Device }), { Label: 'Network', Value: 'Solana Mainnet' }), { fillW: true });
    // An address is checked character by character, so it is shown whole, on lines of its own.
    for (const [label, address] of [['Token mint', 'EPjFWdd5AufqSSqeM2qN1xzybapC8G4wEGGkZwyTDt1v'], ['Recipient', '11111111111111111111111111111111']]) {
      const fact = add(d, box(label, { dir: 'V', align: 'MIN' }), { fillW: true });
      para(fact, label, 'bodyMedium', 'onSurfaceVariant', 'label');
      para(fact, address, 'bodyMedium', 'onSurface', 'address');
    }
    para(d, 'Renewal adds 30 days after the paid term. A first purchase starts once the payment is verified and rounds up to a UTC day. Underpayments do not activate Mosh+, and overpayments add no extra time. Network fees are extra and require SOL in the paying wallet.', 'bodySmall', 'onSurfaceVariant', 'renewal');
    para(d, 'Billing does not receive your Mosh account. It can link purchases in the same renewal series and see wallet payments. Small groups of buyers can still be correlated. The badge and its visibility sync with your linked devices.', 'bodySmall', 'onSurfaceVariant', 'privacy');
    buttonRow(d, ['Purchase terms', 'Payment support'].map((l) => labelButton(Device, l, { Kind: 'Text' })));
  },
  'Awaiting payment': (c, Device) => {
    const col = add(c, box('text', { dir: 'V', gap: 1, align: 'MIN' }), { fillW: true });
    para(col, OFFER, 'titleLarge', 'onSurface', 'price');
    para(col, 'Waiting for a finalized payment. You can close Mosh and return later.', 'bodyMedium', 'onSurfaceVariant', 'status');
    scan(c, 'Scan with your phone’s Camera app and pay from your wallet');
    buttonRow(c, [labelButton(Device, 'Copy payment link', { Kind: 'Outlined', glyph: 'copy' }), labelButton(Device, 'Check payment', { Kind: 'Text', glyph: 'refresh' })]);
    fold(c, Device, 'Closed', TERMS);
  },
  Recovery: (c, Device) => {
    para(c, 'Only the wallet that paid can recover its remaining periods. This restores Mosh+ to this account, without chats or account keys. Each purchase permits one additional certificate; old certificates keep their original expiry.', 'bodyMedium', 'onSurfaceVariant', 'about');
    add(c, setProps(inst('Code plate'), { Label: 'Device code', Code: 'R4KD-92QX' }), { fillW: true });
    scan(c, 'Scan with your phone’s Camera app, open the page in your wallet browser and compare the device code before confirming');
    buttonRow(c, [labelButton(Device, 'Copy recovery link', { Kind: 'Outlined', glyph: 'copy' }), labelButton(Device, 'Open recovery page', { Kind: 'Outlined', glyph: 'open_external' }), labelButton(Device, 'Refresh status', { Kind: 'Text', glyph: 'refresh' })]);
  },
  Active: (c, Device) => {
    const s = add(c, box('status', { dir: 'H', gap: 2 }), { fillW: true });
    add(s, icon('success', 'success'));
    para(s, 'Mosh+ valid until 2026-12-18 23:55 UTC', 'titleSmall', 'onSurface', 'until');
    add(c, setProps(inst('Switch row', { Value: 'On', State: 'Default', Device }), { Title: 'Show my Mosh+ badge', Subtitle: 'One setting for all conversations. Previously shared proof may remain with other people.' }), { fillW: true });
    add(c, inst('Divider', { Orientation: 'Horizontal' }), { fillW: true });
    offer(c, Device, 'Add 30 days');
    fold(c, Device, 'Closed', TERMS);
  },
};
display(await grid('Mosh+ card', axis('Kind', Object.keys(KINDS)), DEVICES, ({ Kind, Device }) => {
  const c = cardSurface('Mosh+ card', { component: true, dir: 'V', gap: 4, pad: cardPad(Device), w: CARD_W[Device], align: 'MIN' });
  header(c, 'plus_badge', 'Mosh+', 'Support Mosh development');
  KINDS[Kind](c, Device);
  return c;
}));
