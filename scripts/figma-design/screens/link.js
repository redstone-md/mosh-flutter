// Linking a device, in Settings, Devices: the trusted device ("Devices / Link / Showing QR" and
// "Enter confirmation code" of the capture) and the new one ("Devices / Join / Import QR or link",
// "Show confirmation code" and the phone's "Scanner / Camera open"). Per screen: its name and the kind of Link card it shows.
const LINKS = [['Link a device, show QR', 'Show QR'], ['Link a device, enter code', 'Enter code'], ['Connect this device, read QR', 'Read QR'], ['Connect this device, show code', 'Show code']];
for (const [name, Kind] of LINKS) for (const Device of ['Desktop', 'Phone']) cardPage(name, Device, 2, 'Devices', inst('Link card', { Kind, Device }));
add(screen('Scan the QR', 'Phone'), inst('Scanner', { State: 'Camera open' }), { fillW: true, fillH: true });
