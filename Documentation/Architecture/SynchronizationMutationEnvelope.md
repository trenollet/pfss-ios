# PFSS Synchronization Mutation Envelope

## Purpose

Phase 20 introduces a schema-versioned mutation envelope without invalidating
whole-record operations already stored on devices or accepted by the beta
Worker. Version 2 is a transport transition: it records durable mutation
identity and context now, while later steps replace whole-record bodies with
field patches and domain commands entity by entity.

## Version 2 fields

- `schemaVersion`: currently `2`.
- `operationID`: stable UUID matching the outer queued operation.
- `tenantID` and `deviceID`: optional informational context. Authentication is
  always authoritative; supplied values must match the authenticated session.
- `entityType` and `recordID`: stable record identity matching the outer
  operation.
- `baseRevision`: server revision observed when the mutation was created.
- `mutationKind`: `wholeRecord`, `fieldPatch`, or `domainCommand`.
- `changedFields`: explicit paths for future patch mutations.
- `commandName`: future domain-command identity.
- `recordData`: current whole-record bytes during migration.
- `clientCreatedAt` and `deviceModifiedAt`: audit evidence, not server ordering
  authority.
- `actorEmployeeID`: optional business actor evidence.
- Unknown top-level fields are retained during decode and re-encode.

## Compatibility

- New record mutations are written as version 2 envelopes.
- The client compatibility codec first recognizes a supported version 2
  envelope, then falls back to the Phase 15–19 legacy whole-record payload.
- Remote application, conflict comparison, and automatic catalog rebasing use
  the compatibility codec, so mixed old/new devices remain readable.
- The Worker continues reading `recordData` from both formats.

## Authority boundary

The Worker validates that version 2 envelope operation, entity, record, and
base-revision values match the outer authenticated operation. When tenant or
device context is supplied, it must match the authenticated identity. Client
timestamps, tenant values, device values, or future fields cannot assign
authority, revisions, or server acceptance order.

## Next migration step

Phase 20 Step 3 will use the stable operation and record identity from this
envelope to process independent dependency groups without global queue
blocking. Field patches and domain commands remain disabled until their entity
policies are implemented in Step 5.
