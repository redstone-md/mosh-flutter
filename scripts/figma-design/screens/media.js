// A picture open in the viewer: "Conversation / Media viewer / Image" of the capture.
for (const Device of ['Desktop', 'Phone']) add(screen('Media viewer', Device), inst('Media viewer', { Kind: 'Image', Device }), { fillW: true, fillH: true });
