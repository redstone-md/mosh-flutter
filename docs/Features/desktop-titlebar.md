# Desktop titlebar

The main window has one integrated top bar on Windows, macOS and Linux. It is
present in conversations, settings, first-run setup and loading/error screens.
The separate call window keeps its native caption and independent lifecycle.

The bar has Mosh branding and the chat-list toggle in chat routes. When a
conversation is selected, its current state opens the existing connection
details. A channel says Broadcast without claiming a verified connection.
Settings, setup and empty selection have no conversation indicator. The chat
name remains in the chat header.

At narrow widths the product wordmark and status text yield before controls.
The logo and buttons remain on one row. The bar has a 44 logical-pixel minimum
height and grows with text scaling. Caption and diagnostic controls have
localized tooltips, accessible names and keyboard actions.

## Native behavior

- Windows keeps its resize frame and Alt+Space menu. Right-clicking blank
  titlebar space opens the system menu. The rendered maximize rectangle returns
  HTMAXBUTTON on the top-level HWND for Windows 11 Snap Layouts. Flutter's child
  view passes these hits through on the same UI thread. Region changes follow
  window layout and DPI; blank space drags and double-clicks maximize/restore.
- macOS keeps AppKit traffic lights and fullscreen actions. Branding reserves
  their actual horizontal space. Double-click honors the system's titlebar
  minimize/zoom/none preference.
- Linux follows GTK's `gtk-decoration-layout`, including runtime changes and
  left-hand controls. Blank space drags, double-clicks maximize/restore and
  right-click opens the window menu. The existing resize-area widget provides
  borders when the desktop removes server decorations.

No Rust API, storage format, transport or package dependency changes.

## Checks

Widget tests exercise the real app across routes and setup, caption commands,
keyboard access, focus/fullscreen events, DPI changes and Linux preferences.
The Windows build runs native hit-test regressions, including unconfigured
call-window behavior, resize routing and replacing caption geometry. Linux
debug builds and a real first-run render check the GTK runner integration.

The OS owns the Windows 11 Snap flyout and macOS traffic-light animation.
Their visual appearance still depends on the installed desktop version.
