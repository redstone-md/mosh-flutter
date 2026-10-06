# Clipboard attachments

Ctrl+V on Windows/Linux, Cmd+V on macOS and the composer's context-menu Paste
share one path (`clipboard_paste_handler.dart`):

1. A file copied in a file manager attaches first. `super_clipboard` reads it
   as `Formats.fileUri`: `CF_HDROP` on Windows, `public.file-url` on macOS and
   `text/uri-list` on Linux. It wins over images because Finder also puts the
   file's icon on the clipboard as TIFF. Non-`file:` URIs are ignored.
2. Otherwise a copied image (PNG, JPEG, GIF, WebP, TIFF) attaches as
   `clipboard-<ms>.<ext>`.
3. Otherwise the platform's text paste runs unchanged.

Files and images go through the shared ingest with the picker's and drop
zone's 50 MB ceiling, original name, MIME by extension, miniature and clear
preview. A copied file is streamed with a running size limit, so one that grows
while being read is refused without loading it whole, and nothing is
attached from a partial read. A folder reports `attachmentNotAFile`; a missing
or unreadable file reports `attachmentUnreadable`.

Attaching is gated off while a send is in flight or the composer is disabled;
then Paste inserts text into the draft as before. A paste started while
another is still reading the clipboard is swallowed, so a held or repeated
shortcut does not attach the same file twice. A clipboard the platform refuses
to open is reported and falls back to text paste.

Only the first of several copied files attaches, as with a multi-file drop.
The context-menu Paste appears only when the platform reports text on the
clipboard; Windows Explorer copies only `CF_HDROP`, so there the shortcut is
the way to paste a file. Real file-manager copies are a manual check per
desktop platform; widget tests use a fake clipboard reader with real files.
