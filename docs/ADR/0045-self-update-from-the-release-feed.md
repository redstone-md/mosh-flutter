# ADR 0045: Mosh updates itself from the release feed

Date: 2026-10-11
Status: Accepted

For [IVO-63](https://linear.app/ivoxygen/issue/IVO-63/dobavit-avtoobnovlenie),
About says when a newer release exists, and its button installs it: Mosh
downloads the artifact the release publishes, checks it against the checksum
published beside it, hands it to the platform's own installer, and comes back on
the new build. Nobody is sent to a download page to do by hand what the app can
do itself.

An earlier version of this decision stopped at naming the version and opening the
release page, on the argument that unsigned artifacts make an in-app update
impossible. That argument was wrong in an important way: the protections that
made it look impossible apply to files a *browser* downloads — a mark of the web
on Windows, a quarantine attribute on macOS — and Mosh's own HTTP client sets
neither. What stays true is that the artifacts carry no trusted signature
([CODE_SIGNING.md](../../CODE_SIGNING.md)), so a person who downloads an
installer by hand still meets SmartScreen or Gatekeeper. The updater takes the
path that avoids that, rather than one that defeats it.

Applying an update is per platform, because the platforms publish different
things:

- Windows ships `mosh-<version>-setup.exe`, an Inno Setup installer with
  `PrivilegesRequired=lowest`, so it installs per user without elevation. The
  updater starts it with `/SILENT /SUPPRESSMSGBOXES /NORESTART /RELAUNCH=1` and
  exits; Setup replaces the bundle and, because of `/RELAUNCH=1`, starts the new
  build itself. A scripted or deployed silent install stays quiet: the relaunch
  is gated in the installer script on that one flag.
- macOS ships a disk image holding the app, and About does **not** install it.
  The shipped app is sandboxed — `com.apple.security.app-sandbox` in
  `macos/Runner/Release.entitlements`, with user-selected file access and
  nothing more — and a sandboxed process can neither replace the bundle in
  `/Applications` nor mount the image. A child process inherits the sandbox, so
  a script started by the app cannot do it either. About offers the release page
  there instead of a button that cannot finish. Updating without that click
  needs something running outside the sandbox, the way Sparkle's Autoupdate
  does; that is its own piece of work and needs a Mac to verify.

The check stays as confined as before: it runs while the About card is mounted,
never polls, is not retried on its own, and reads a public repository with no
credential — the request is a plain GET of a fixed URL that says nothing about
the installation. It now also downloads, which is the one request that carries a
body — the artifact, whose published digest is verified before anything is
installed. Nothing is installed from a release that publishes no checksum, a
digest that does not match, or a download that did not finish: a failed update
leaves the installed build untouched and offers a retry.

What that digest does not do is decide who published the release: it is fetched
from the same release it describes, so it catches a download that was truncated,
corrupted or altered in transit, not one replaced on the publisher's side. Anyone
who could rewrite both the artifact and its sidecar would pass this check, and
installing their code is exactly the risk of shipping without a trusted publisher
signature — [CODE_SIGNING.md](../../CODE_SIGNING.md) records that the checksums
are the integrity statement and that signing is what would make the release
itself verifiable. Everything here narrows the window: nothing installs
unverified, nothing installs unasked, and nothing installs in the background.
None of it replaces a signature.

The feed is the release list rather than GitHub's "latest release" shorthand,
because that shorthand means "the most recent non-prerelease" and the release
workflow publishes `-rc` tags as pre-releases: About would stay silent about one
until the stable build arrived. Rows are compared by version rather than by the
date they were published, and the comparison ignores pre-release and build
suffixes, so the highest published version wins and an installed build is never
told it is older than it is.

A background updater that installs when it decides to was rejected for the same
reason the check is manual: a peer-to-peer messenger reports home as little as it
can, and an update stays something a person asks for.
