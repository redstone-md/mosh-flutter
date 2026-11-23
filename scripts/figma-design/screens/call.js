// A call with video both ways, open to the whole window: "Calls / Active / Two-way video" of the capture.
// The window is not the shape the component was drawn at, so its stage is fitted again.
for (const Device of ['Desktop', 'Phone']) fitStage(add(screen('Video call', Device), inst('Call window', { State: 'Two-way video', Device }), { fillW: true, fillH: true }));
