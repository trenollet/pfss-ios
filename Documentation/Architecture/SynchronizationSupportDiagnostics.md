# Synchronization Support Diagnostics

- Status: Implemented in Phase 20 Step 7
- Client builds: 20.7.2 Owner acceptance; 20.7.3 employee visibility correction
- Retention: 30 days
- Maximum package size: 256 KB

## Purpose

PFSS can create a support case from an enrolled device without exporting the
local database or requiring a direct device connection. The user must review
the disclosure and explicitly consent before every submission. PFSS never
uploads diagnostics silently.

## Device Collection Boundary

The client includes only synchronization control information:

- app version and build;
- device model and operating-system version;
- local synchronization cursor, connectivity, cloud-access state, and latest
  recovery summary;
- operation, record, quarantine, conflict, and idempotency identifiers;
- entity type, action, status, timestamps, failure category/code, retry result,
  and a fixed allowlist of synchronization metadata.

The collector never encodes operation payload bytes, record/base record data,
conflict versions, customer details, job notes, invoices, photos, attachments,
credentials, device tokens, or encryption keys. The server reconstructs the
stored package from its own strict allowlist instead of trusting arbitrary
client JSON.

## Trusted Case Header

`POST /v1/support/sync-diagnostics` authenticates the enrolled device and adds
the tenant, member, role, and device identifiers from server-side identity.
Client-supplied identity is not accepted. A successful submission returns a
human-readable `PFSS-XXXX-XXXX` case number.

The D1 `synchronization_diagnostics` table stores the tenant-scoped index,
trusted source identity, build information, object key, size, submission time,
and expiration time. The redacted JSON package is stored in the existing
private R2 archive bucket under
`support-diagnostics/<tenant-id>/<diagnostic-id>.json`.

## Authorization and Audit

- Any active enrolled member can submit diagnostics from their own device.
- Members can retrieve only cases they submitted.
- Managers and Owners can list and retrieve cases within their tenant.
- Only Managers and Owners can delete a case before automatic expiration.
- Submission, authenticated retrieval, and deletion write tenant audit events.
- Cross-tenant lookup returns no diagnostic.
- A device can submit no more than five packages per hour.

Endpoints:

- `POST /v1/support/sync-diagnostics`
- `GET /v1/support/sync-diagnostics`
- `GET /v1/support/sync-diagnostics/:caseCode`
- `DELETE /v1/support/sync-diagnostics/:caseCode`

## Retention and Failure Behavior

The daily Worker schedule removes expired R2 objects and their D1 index rows.
If D1 indexing fails after an R2 upload, the Worker deletes the orphaned object
before returning failure. User deletion removes the R2 object first and then
marks the indexed case deleted with an audit event.

## Verification

- Worker regression: 73 tests passed.
- TypeScript validation passed.
- The signed app and iOS test targets compiled successfully on a physical-device
  destination. Simulator execution is not claimed because local simulator
  runtimes remain unavailable.
- Migration `0027_phase20_sync_diagnostics.sql` applied after D1 recovery
  bookmark
  `00000257-00000000-000050cf-24349ab9b06c950cdbdee3024efcb266`.
- Staging Worker version
  `50e359a9-0fc4-43cc-906e-865c0119d152` deployed.
- Live case `PFSS-C6XB-PN2D` was submitted from Tim-iPhone17pro using build
  20.7.2. Its trusted header, 30-day expiration, synchronization summary, and
  redaction boundary were verified. The package contained no payload, body,
  record data, base record data, or conflict-version fields. The temporary
  support download was deleted after inspection.
- Build 20.7.3 moved **Send Sync Diagnostics** from the Owner-only Account
  Security section to App Information beneath Sync Status for every enrolled
  role. Live employee case `PFSS-AMW2-BPA5` was submitted from the iPad Pro
  mini. The server header identified role `member`, the exact enrolled device,
  iPadOS 26.5, and build 20.7.3. The package contained 33 synchronized
  operation summaries and no forbidden payload or record-data fields. The
  temporary support download was deleted after inspection.
