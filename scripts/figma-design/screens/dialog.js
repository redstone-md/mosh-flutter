// A confirmation over the chat it is about: "Conversation / DM / Delete chat confirm" of the capture.
for (const Device of ['Desktop', 'Phone']) {
  const f = directChat('Delete chat', Device);
  dim(f);
  over(f, inst('Dialog', { Kind: 'Destructive', Device }));
}
