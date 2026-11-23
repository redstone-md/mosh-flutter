// A picture open in the viewer: "Conversation / Media viewer / Image" of the capture.
// The viewer keeps a layer for the picture; the capture's own picture goes into it, whole.
const shot = figma.root.children.find((p) => p.name === 'Desktop · current').findOne((n) => n.name === 'Conversation / Media viewer / Image') ?? fail('the capture of the media viewer');
const image = (n) => Array.isArray(n.fills) && n.fills.find((f) => f.type === 'IMAGE');
const [largest] = shot.findAll(image).sort((a, b) => b.width - a.width);
for (const Device of ['Desktop', 'Phone']) {
  const picture = add(screen('Media viewer', Device), inst('Media viewer', { Kind: 'Image', Device }), { fillW: true, fillH: true }).findOne((n) => n.name === 'picture');
  picture.fills = [{ type: 'IMAGE', imageHash: image(largest).imageHash, scaleMode: 'FIT' }];
  picture.findOne((n) => n.name === 'icon').visible = false;
}
