# README visuals

## Desktop screenshot

`chat-desktop.png` renders the real `MoshApp` at 1440 × 900 logical pixels,
captured at 1.5× resolution. The bundled Inter weights and Material icons are
loaded through the existing preview helper.

The names, messages, attachments, delivery indicators and connection states
are fictional. `ScriptableGateway`, `ScriptableBridge` and the existing shell
harness supply the data. No Rust runtime, live network or personal data is used.

Regenerate from the repository root:

```sh
flutter test scripts/capture_readme.dart --dart-define=SETUP_PREVIEW=true
```

Inspect the PNG before committing it. The capture script is outside `test/`
so normal test runs do not rewrite documentation images.

## Mesh illustration

`mesh-conversations.png` was generated with the built-in `imagegen` tool on
2026-10-03. It is decorative artwork, not a diagram of runtime topology or
evidence of a security property. Its generated pixels are preserved.

Prompt:

```text
Use case: stylized-concept. Asset type: a wide editorial banner illustration for the GitHub README of Mosh, a desktop-first peer-to-peer messenger. Generate a polished restrained 3D illustration at approximately 1792 by 640 pixels, very wide composition. Scene: matte charcoal background #0B0C0D. Subject: two beautifully crafted smoked-glass conversation bubbles, connected across a sparse peer-to-peer mesh of four small luminous nodes and fine curved paths. One bubble is dark translucent graphite, one has a softly lit lime edge. The arrangement conveys conversations traveling between devices. Fine silver edges, subtle glass refraction, carefully controlled lime green #B7D84A illumination, a few softly glowing packet dots traveling along the paths. Composition: centered horizontal composition, subject contained in the middle two thirds, generous clean dark margins, low camera angle with gentle depth, calm studio lighting, sharp elegant materials, understated and legible at small sizes. Match the existing Mosh charcoal and lime UI palette. No text, letters, logos, watermark, interface screenshot, computer screen, generic shield, padlock, cyberpunk decoration, purple, blue neon, busy particles, or exaggerated bloom. This is supporting artwork; the real product screenshot is separate.
```

## Linked-device illustration

`linked-devices.png` was generated with the built-in `imagegen` tool on
2026-10-03. `mesh-conversations.png` was the material, lighting and palette
reference. The laptop and phone are conceptual artwork; their screens do not
represent app UI. Its generated pixels are preserved.

Prompt:

```text
Use case: stylized-concept. Asset type: a matching wide illustration for a GitHub README feature panel. Input image 1 is a MATERIAL, LIGHTING AND COLOR reference only; create a new scene, not an edit of those chat bubbles. Match its polished smoked glass, matte near-black #0B0C0D background, fine silver edges and restrained lime #B7D84A illumination. Primary request: show a desktop laptop and a smartphone connected as one user's linked messaging devices. Both devices are carefully made translucent graphite glass with blank dark screens containing only a small simple lime outlined conversation bubble, no text and no interface. A delicate short curved lime filament joins them, with a single small luminous packet between the devices. The laptop is on the left, the phone is on the right, both fully visible, gently angled toward each other, clean three-quarter product view. Wide horizontal composition approximately 1792 by 640 pixels, generous dark margins, subject in the central two thirds, calm studio reflections, same ground plane and subtle depth as the reference, beautifully controlled highlights. Make a visually coherent companion to the reference, elegant and quiet. No QR codes, padlocks, shields, decorative satellites, busy mesh, text, letters, logos, watermark, purple, blue neon, or exaggerated bloom. Supporting conceptual artwork, not a screenshot and not a network/security diagram.
```
