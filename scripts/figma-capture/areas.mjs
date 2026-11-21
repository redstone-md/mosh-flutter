// Capture areas in canvas order. Each owns one Figma section per page and
// one scenario test under scenarios/.
export const AREAS = [
  { area: 'onboarding', section: 'Onboarding' },
  { area: 'chats', section: 'Chats' },
  { area: 'conversation', section: 'Conversation' },
  { area: 'calls', section: 'Calls' },
  { area: 'settings', section: 'Settings' },
  { area: 'account', section: 'Devices · Plus · VPN' },
];

// Form factor → Figma page and frames per row.
export const PAGES = {
  desktop: { page: 'Desktop · current', cols: 4 },
  mobile: { page: 'Mobile · current', cols: 8 },
};

export const REPO = new URL('../../', import.meta.url).pathname;
export const OUT = `${REPO}build/figma-capture`;
