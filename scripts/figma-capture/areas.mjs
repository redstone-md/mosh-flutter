import path from 'node:path';
import { fileURLToPath } from 'node:url';

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

export const REPO = fileURLToPath(new URL('../../', import.meta.url));
export const OUT = path.join(REPO, 'build', 'figma-capture');
