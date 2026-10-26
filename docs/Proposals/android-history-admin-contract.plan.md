# Withdrawn: administrator approval of group history

Status: withdrawn on 2026-10-26, before implementation. The user rejected manual
administrator approval as an unacceptable recovery workflow. The former full
proposal remains in Git history; it is not an active implementation contract.

Do not implement its approval queue, review UI, Confirm/Decline actions,
`list_group_history_reviews` or `resolve_group_history_review`. Replacing those
buttons with blind administrator signing is not the selected design either.

The accepted direction is automatic recovery from a **currently authorized
holder**, explicitly trusting its historical-context assertion while preserving
original authorship and independently checking current membership and recipient
access. A malicious holder can lie or collude with a departed author; this trust
is not independent cryptographic proof of pre-removal creation time.

The active exact proposals are the [shared history contract](android-history-contracts.plan.md)
and [automatic group contract](android-history-automatic-contract.plan.md).
The owner approved those concrete automatic contracts after clarification.
The rejected manual proposal confers no implementation authorization.
