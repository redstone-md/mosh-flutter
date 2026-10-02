# ADR 0036: first-run gate and local display name

Accepted 2026-10-02.

First-run setup gates mounting the existing router instead of redirecting its
routes. This retains a conversation invitation received during setup in the
router's memory and keeps the conversation launcher separate from initial
setup. Conversation polling starts after the gate; device linking retains its
own protocol service and polling.

The non-secret name, progress and completion flag use a feature-local, versioned
Dart preference file with serialized atomic replacement, reusing the existing
application support directory. Moving these UI preferences into the encrypted
Rust conversation records would couple first-run navigation to message storage
and require a new bridge contract. Invitation and QR secrets never enter this
file. Name edits change the default for new conversations, preserving existing
conversation names and identities.
