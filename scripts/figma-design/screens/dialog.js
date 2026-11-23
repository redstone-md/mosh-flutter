// A confirmation over the chat it is about: "Conversation / DM / Delete chat confirm" of the capture.
for (const Device of ['Desktop', 'Phone']) {
  // The capture keeps the details panel docked on the desktop.
  const f = directChat('Delete chat', Device, Device === 'Desktop');
  dim(f);
  over(f, inst('Dialog', { Kind: 'Destructive', Device }));
}
