# Invitations

Creating a personal-chat invitation saves it in the encrypted native store.
Generating, copying or replacing a link does not add a chat to the recent list.
Each new invitation is independent. Leaving the creation screen or restarting
the application keeps saved invitations usable and available on that screen.

The chat becomes visible after either Open chat or the first counterpart's
validated MLS admission. That decision persists. Going offline or restarting
does not hide the chat or make its invitation available again. Repeated Open
chat actions return the same conversation.

Saved unopened invitations have Copy, Replace link and Open chat actions. An
opened chat awaiting its counterpart also offers Copy and Replace in its header
menu. The native `invite_available` field controls these actions. Connection
status and display names cannot determine whether an invitation is consumed.

Replace link preserves the session, mesh, MLS keys and existing chat-list entry.
It saves a new signed admission token before returning the new URI. A refused
save preserves the earlier URI. Both raw and authenticated KeyPackages must
carry the current token; removing the token cannot bypass replacement. Admission
already received by the creator wins a replacement race. After admission,
replacement is refused and the admitted conversation continues.

Invitations have no application expiry. The first independent counterpart
consumes one permanently. The native store saves that fact, its MLS signer and
the corresponding Welcome together before publishing Welcome. Repeated packages
from the admitted signer receive the cached Welcome after restart. A different
signer cannot obtain it. Authorized linked-device admission keeps its existing
separate protocol.

## Link format

New signed personal-chat links use `mosh://invite/<base64url>` and contain all
verification data. No lookup server or extra network request is needed. A
normal signed link is 294 characters; saved invitations with a replacement
token are 305 characters. Targeting a particular installation adds 43 characters.
The target, route, token and full MLS signing key are covered by both the Moss
identity and MLS signatures.

Legacy query-string links and stored records remain readable. Legacy records
remain visible. Restoring their actual MLS membership prevents an already
admitted counterpart from being mistaken for an unused invitation when no
message history exists. Linked clients belonging to the local user do not count
as a counterpart.

Personal-chat and group invitation cards show at most two lines. Copy always
uses the complete URI. Group and device-link protocols retain their existing
formats; only the shared group-card presentation changes.

See [ADR 0042](../ADR/0042-durable-compact-dm-invitations.md) for wire and storage
details. Focused native tests cover hidden creation, durable opening, independent
invitations, replacement refusal, old/tokenless admission rejection, admission
races, Welcome retry and consumption after restart. Codec tests cover every
signed byte, malformed encodings and extended legacy transcripts. Flutter
parser tests cover routing extraction and malformed compact links; Rust owns
signature verification.
