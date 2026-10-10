# IVO-61: one desktop titlebar

## Approved scope

One application-level bar replaces the native caption and the route-local Mosh
header on Windows, macOS and Linux. It remains present in settings, setup,
loading/error screens and narrow windows. The separate call process keeps its
current native window.

The bar keeps the logo, MOSH, the chat-list toggle in chat routes and the selected
conversation's real status. Clicking status opens the existing diagnostics.
Setup, settings and an empty selection have no conversation status. Chat names
stay in their chat headers. Remove the technical product subtitle. Hide MOSH
before interactive controls at narrow widths. Use a 44 px minimum height that
grows with text, existing theme tokens, tooltips and keyboard focus.

Preserve native window actions, drag, resize, double-click and system menus.
Keep macOS traffic lights, Windows Snap Layouts and Linux caption placement from
GTK settings. Reuse window_manager and isolate native differences behind a
main-window controller. No Rust contracts, transport or dependencies change.

## Work and checks

1. Test the existing titlebar and real MoshApp seams, including narrow windows,
   route transitions, setup, status actions and window actions.
2. Move chrome above the router and reuse the conversation drawer. Add private
   native window hooks for caption geometry and desktop conventions.
3. Run focused Flutter checks, native builds/tests and the full Flutter suite.
   Review Standards and Spec against de5573ed, fix valid findings and commit.
4. Open a real PR, wait for CodeAnt and CI, fix valid review findings, merge the
   green reviewed head and publish the versioned release.

Risks: per-monitor DPI and hit testing on Windows; macOS native caption inset;
Linux decoration preferences and border resizing. Native hooks configure only
the main process. Desktop build CI checks platform compilation.
