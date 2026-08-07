# ADR-005: Packaged Plan Catalog and Enterprise Access

- Status: Accepted
- Date: 2026-08-01
- Applies To: Phase 17 production accounts and entitlements

## Decision

PFSS uses packaged combined-user limits. An Owner and an employee each consume
one user allocation; role does not affect billing. The Owner's optional
operational employee profile does not consume another user because it remains
linked to the same membership.

Public paid plans use Apple auto-renewable subscriptions. PFSS does not sell
recurring employee add-ons or seat packs. When a company reaches its user or
record limit, PFSS recommends the next published tier.

| Plan | Billing | Duration | Users | Devices | Leads | Customers | Jobs |
| --- | --- | ---: | ---: | ---: | ---: | ---: | ---: |
| Beta Test | Complimentary grant | 90 days | 5 | 10 | 1,000 | 1,000 | 3,000 |
| Trial | Apple introductory trial | 14 days | 2 | 4 | 5 | 5 | 10 |
| Base | Apple, $7.99 monthly | Monthly | 3 | 6 | 1,000 | 1,000 | 3,000 |
| Pro | Apple, $14.99 monthly | Monthly | 5 | 10 | 3,000 | 3,000 | 9,000 |
| Expert | Apple, $29.99 monthly | Monthly | 10 | 20 | 10,000 | 10,000 | 50,000 |
| Enterprise / Custom | Direct organization contract | Custom | Custom | Custom | Unlimited or custom | Unlimited or custom | Unlimited or custom |

Device limits equal twice the packaged user limit. Enterprise limits are
server-authored through a future PFSS developer management application and are
never controlled by the customer-facing app.

## Enforcement Rules

- The server counts invited, active, and suspended memberships as users.
- Reaching a limit prevents creation but never deletes company data.
- Existing records remain readable and editable after a downgrade.
- Archived records count until a supported permanent-deletion workflow removes
  them from the authoritative server record set.
- Unlimited is represented as no limit, not a large sentinel value.
- Expired, revoked, missing, or malformed allocations grant no new authority.
- Past-due and cancelled paid accounts retain safe read-only access while
  pending and suspended accounts are blocked.
- Enterprise authorization requires a privileged, audited server action with a
  contract reference, effective date, and optional expiration date.

## Consequences

This avoids App Store seat-quantity complexity, makes upgrades understandable,
and keeps billing roles independent of operational roles. Enterprise access
requires a separate administrator interface and an explicit server allocation
source before it can be issued.
