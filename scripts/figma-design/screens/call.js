// A call with video both ways, open to the whole window: "Calls / Active / Two-way video" of the capture.
for (const Device of ['Desktop', 'Phone']) add(screen('Video call', Device), inst('Call window', { State: 'Two-way video', Device }), { fillW: true, fillH: true });
