# ADR 0042: durable compact DM invitations

Accepted 2026-10-08 for IVO-49 and IVO-52. The agreed invitation lifecycle
authorizes additive bridge commands, a snapshot flag and encrypted record
fields. No dependency or database table changes are needed.

## Durable lifecycle

The native DM owner retains invitations as sessions so their Moss subscription,
MLS private material and existing restoration stay together. Recent-chat
visibility is a separate durable decision. `create_pending_invite` saves a
hidden creator session; `open_session` saves visibility before returning it.
`list_pending_invites` lists only unexposed, unconsumed creator invitations.
Existing `create_invite` remains visible for group, channel and organization
offer callers. Existing join and linked-device entry points retain their list
behavior.

An optional encrypted `invitation` record stores opened and consumed decisions,
the admitted MLS signer, peer name and cached Welcome. Missing records use
legacy visibility. Restoration also checks actual MLS membership, including
local-user membership from signed device rosters, so missing inbound history
cannot enable a second independent counterpart.
Legacy records without an admitted-signer pin accept package retries only from
an actual counterpart MLS member. Neither these retries nor a replay carrying
changed cleartext metadata can overwrite the established contact name or Moss
route. Authenticated conversation frames retain their existing metadata updates.

The creator saves its first admission and advanced MLS snapshot in the existing
atomic DM transition before publishing Welcome. A refused save restores the
previous MLS state and leaves the invitation unconsumed. The admitted signer
alone can retry its cached Welcome, including after restart. The consumed fact
does not depend on transient connectivity. Linked-device admission does not
use the invitation capability and keeps its existing authorization and journal.

## Replacement

`replace_invite` drains already-received admission, refuses consumed sessions
and signs a fresh random admission token. It preserves the mesh/session IDs,
fingerprint and MLS keys. It returns only after the new invitation record and
MLS state commit; refusal restores the previous URI.

The `InvitationKeyPackage` control envelope contains the session ID, admission
token and encoded existing KeyPackage or authenticated KeyPackage envelope.
The owner compares its current durable invitation token before processing the
inner admission. Tokenless admission is accepted only for invitations that
never required one. This prevents old or stripped links from bypassing rotation
on the still-open conversation route. Targeted admission retains the dual proof
and the full recipient Moss/MLS identity checks from ADR 0038. Pending organization
recovery extracts the original package through the wrapper without changing its
private-material recovery contract.

## Compact proof

The path after `mosh://invite/` is unpadded canonical Base64URL. Its binary layout
is version byte `1`, flags byte, mesh token 8 bytes, session token 8 bytes,
Moss public key 32 bytes and MLS public key 32 bytes. Flag `2` adds an 8-byte
admission token; flag `1` adds the 32-byte intended Moss identity. Two 64-byte
Ed25519 signatures follow the payload, Moss first and MLS second. Unknown flags,
wrong lengths, noncanonical encoding and appended URL fields fail parsing.

Both signatures cover the complete binary payload using the existing
length-prefixed signing input, an empty organization, the reconstructed mesh
ID and `dm-invite-owner-v2`. The fingerprint is the first 16 bytes of the MLS
public key, as in existing DMs. The separate context prevents interpreting
compact proof bytes as an existing sender proof. The general `SenderProof`
representation stays unchanged.

Only canonical generated query URLs with fixed-size routing tokens are
compacted. Extended or reordered legacy query URLs retain their complete
canonical URL proof and parser. Existing links and encrypted records stay
readable; older application versions cannot read the new compact path.
Device linking and group invitations retain their existing formats.

Flutter extracts structural route/fingerprint data for invite detection and
navigation. The native parser verifies both signatures before admission.
`SessionSnapshot.invite_available` supplies invitation actions from real durable
state. Native and Flutter callers gain create-pending, list-pending, replace and
open bridge operations; root bridge code generation updates committed bindings.

New modules remain below 400 lines. Existing runtime/session type and constructor
exceptions from ADRs 0019, 0026 and 0038 remain. Scenario tests retain the existing
exception allowing a complete setup/attack/control case over 50 lines.
