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
