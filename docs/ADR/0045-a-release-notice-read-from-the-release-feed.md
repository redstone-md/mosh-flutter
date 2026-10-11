# ADR 0045: a release notice, read from the release feed

Date: 2026-10-11
Status: Accepted

For [IVO-63](https://linear.app/ivoxygen/issue/IVO-63/dobavit-avtoobnovlenie),
About says when a newer release exists and hands over its page. It reads the
newest published release, compares it with the installed version, and shows the
version with a button that opens the release page. Downloading, installing and
restarting stay with the platform and the person.

Mosh ships without a trusted signature ([CODE_SIGNING.md](../../CODE_SIGNING.md)),
and that is what rules out an in-app installer. Windows SmartScreen and the
macOS Gatekeeper flow repeat for every downloaded build, and writing an
unidentified bundle into `/Applications` is the operation Gatekeeper exists to
stop. Automating the download would trade a documented one-time warning for a
worse flow, so that work belongs with signing and notarization rather than here.

The check is the only request Mosh makes on its own account besides Moss, so it
is confined on purpose: it runs while the About card is mounted, never polls, is
not retried by its provider, and carries no identity — the feed is a public
repository, so no credential travels and the only fact shared is the version
being asked about. A peer-to-peer messenger that reported home in the background
would be a different product; opening About is the consent.

The feed is this repository's release API, which the release workflow already
fills with the installers and the checksums beside them. Adding a second
distribution channel would make those published checksums a claim about something
other than what people download. A feed that cannot answer — a missing tag, a
page that is not a URL, a body that is not an object — reads as "could not
check" with a retry, never as "you are up to date", and comparison ignores
pre-release and build suffixes and never proposes a downgrade.

The earlier settings redesign excluded an updater action from About. That
exclusion covered a settings surface with no data behind it; this notice is
narrower and replaces it, which is why About gains one line and no switch.
