// Mosh+ in Settings, Profile: "Plus / Checkout / Payment details open", "Payment / Awaiting payment",
// "Recovery / Waiting for wallet" and "Membership / Active" of the capture. Per screen: its name and the kind of Mosh+ card it shows.
const PLUS = [['Mosh+, payment details', 'Details open'], ['Mosh+, awaiting payment', 'Awaiting payment'], ['Mosh+, recovery', 'Recovery'], ['Mosh+, active', 'Active']];
for (const [name, Kind] of PLUS) for (const Device of ['Desktop', 'Phone']) cardPage(name, Device, 1, 'Profile', inst('Mosh+ card', { Kind, Device }));
