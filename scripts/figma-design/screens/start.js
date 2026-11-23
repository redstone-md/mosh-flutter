// The start menu: "Onboarding / Start menu / Default" of the capture, where no chat exists yet.
const MIDDLE = { dir: 'V', justify: 'CENTER', align: 'CENTER' };
const row = stretch(screen('Start menu', 'Desktop'), 'panels');
chats(row, 'Desktop', { none: true });
add(stretch(row, 'place', MIDDLE), inst('Start menu', { Device: 'Desktop' }));
add(screen('Start menu', 'Phone'), inst('Start menu', { Device: 'Phone' }), { fillW: true });
