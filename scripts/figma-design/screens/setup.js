// The first step of setup, the name: "Onboarding / Name / Empty" of the capture.
add(fill(screen('Setup, your name', 'Desktop', 'Onboarding'), 'place', { dir: 'V', justify: 'CENTER', align: 'CENTER' }), inst('Wizard step', { Kind: 'Setup name', Device: 'Desktop' }));
add(screen('Setup, your name', 'Phone'), inst('Wizard step', { Kind: 'Setup name', Device: 'Phone' }), { fillW: true });
