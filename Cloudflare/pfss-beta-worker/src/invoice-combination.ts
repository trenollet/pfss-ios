type ObjectValue = Record<string, any>;
type Identity = { tenantID: string; memberID: string; deviceID: string };
type CombinationEnv = { DB: D1Database };
const uuidPattern = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i;
const normalizedID = (value: unknown): string => {
  if (typeof value !== "string" || !uuidPattern.test(value)) throw new Error("invalid_invoice_combination");
  return value.toLowerCase();
};
const canonical = (value: any): string => JSON.stringify(value, (_key, item) =>
  item && typeof item === "object" && !Array.isArray(item)
    ? Object.fromEntries(Object.keys(item).sort().map(key => [key, item[key]])) : item);
function encode(value: unknown): string {
  return btoa(Array.from(new TextEncoder().encode(JSON.stringify(value)), b => String.fromCharCode(b)).join(""));
}
function decode(value: string): ObjectValue {
  return JSON.parse(new TextDecoder().decode(Uint8Array.from(atob(value), c => c.charCodeAt(0))));
}
function invoiceFromOperation(operationJSON: string): ObjectValue {
  return decode(decode(JSON.parse(operationJSON).payload.body).recordData);
}
function cents(value: unknown): number {
  if (typeof value !== "number" || !Number.isFinite(value) || value < 0 || value > 9e12 ||
      Math.abs(value * 100 - Math.round(value * 100)) > 0.0001) throw new Error("invalid_invoice_amount");
  return Math.round(value * 100);
}
function validDate(value: unknown): boolean {
  return typeof value === "string" && Number.isFinite(Date.parse(value));
}
// Mirror only ServiceLineItem's documented decodeIfPresent defaults. Older
// synchronized items omit these fields; opening them in Swift materializes
// the defaults without changing the invoice or its immutable payment proof.
// Keep request hashing byte-semantic and every revision/CAS guard unchanged.
function comparisonValue(value: any): any {
  if (Array.isArray(value)) return value.map(comparisonValue);
  if (!value || typeof value !== "object") return value;
  const result = Object.fromEntries(Object.entries(value).map(([key, item]) => [key, comparisonValue(item)]));
  if (typeof result.serviceType === "string" && typeof result.quantity === "number" &&
      typeof result.unitPrice === "number" && typeof result.lineTotal === "number") {
    result.discountMethod ??= "Dollar Amount";
    result.discountInputValue ??= 0;
    result.estimatedMinutesPerUnit ??= 0;
  }
  return result;
}
const equal = (a: unknown, b: unknown): boolean => canonical(comparisonValue(a)) === canonical(comparisonValue(b));
function sameIDs(a: unknown, b: string[]): boolean {
  if (!Array.isArray(a)) return false;
  const ids = a.map(normalizedID);
  return new Set(ids).size === ids.length && equal(ids.sort(), b.map(normalizedID).sort());
}
function response(value: unknown, status = 200): Response {
  return Response.json(value, { status });
}

/// Protect provenance from legacy whole-record writes and direct forged bills.
export function invoiceCombinationMutationError(current: ObjectValue | null, next: ObjectValue | null): string | null {
  if (!next) return current?.combination || current?.combinedIntoInvoiceID || current?.paymentCorrection
    ? "combined_invoice_requires_manual_correction" : null;
  if (!current && (next.combination || next.combinedIntoInvoiceID || next.paymentCorrection || String(next.invoiceNumber ?? "").endsWith("-C"))) {
    return "invoice_combination_requires_atomic_save";
  }
  if (current?.combinedIntoInvoiceID && !equal(current, next)) return "combined_source_is_read_only";
  if (current?.combination || current?.paymentCorrection) {
    const immutable = ["id", "invoiceNumber", "customerNumber", "siteID", "jobNumber", "associatedJobNumbers",
      "lineItems", "subtotal", "discount", "total", "taxSnapshot", "combination", "combinedIntoInvoiceID", "paymentCorrection"];
    if (immutable.some(key => !equal(current[key], next[key]))) return "combined_invoice_requires_manual_correction";
    if ((next.status === "Void" && current.status !== "Void") || next.amountPaid < current.amountPaid ||
        (current.status === "Void" && !equal(current, next))) return "combined_invoice_requires_manual_correction";
    const previousReceipts = current.receipts ?? [], nextReceipts = next.receipts ?? [];
    if (!Array.isArray(nextReceipts) || nextReceipts.length < previousReceipts.length ||
        !equal(nextReceipts.slice(0, previousReceipts.length), previousReceipts)) return "combined_payment_evidence_is_read_only";
    const activeRedistribution = current.paymentCorrection?.history?.at(-1) ?? current.combination?.paymentRedistribution;
    const carriedEvents = new Set((activeRedistribution?.pool.verifications ?? [])
      .flatMap((check: ObjectValue) => (check.paymentEventIDs ?? []).map((id: string) => id.toLowerCase())));
    const seenEvents = new Set<string>(), seenReceipts = new Set<string>();
    for (const receipt of nextReceipts) {
      const event = String(receipt.paymentEventID).toLowerCase(), id = String(receipt.id).toLowerCase();
      if ((carriedEvents.has(event) && !previousReceipts.some((r: ObjectValue) => String(r.paymentEventID).toLowerCase() === event)) ||
          seenEvents.has(event) || seenReceipts.has(id)) return "duplicate_combined_payment_event";
      seenEvents.add(event); seenReceipts.add(id);
    }
  } else if (next.combination || next.combinedIntoInvoiceID || next.paymentCorrection) return "invoice_combination_requires_atomic_save";
  return null;
}

export async function saveInvoiceCombination(request: Request, env: CombinationEnv, identity: Identity,
  enforceLimit?: () => Promise<Response | null>): Promise<Response> {
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > 2_000_000) return response({ error: "invoice_combination_too_large" }, 413);
  let body: ObjectValue;
  try { body = JSON.parse(raw); } catch { return response({ error: "invalid_invoice_combination" }, 400); }
  let requestID: string, invoiceID: string;
  try { requestID = normalizedID(body.requestID); invoiceID = normalizedID(body.invoice?.id); }
  catch { return response({ error: "invalid_invoice_combination" }, 400); }
  if (requestID !== invoiceID) return response({ error: "invalid_invoice_combination" }, 400);
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical(body)))),
    b => b.toString(16).padStart(2, "0")).join("");
  const existing = await env.DB.prepare(
    "SELECT request_hash AS hash, result_json AS result FROM invoice_combination_commits WHERE tenant_id = ?1 AND request_id = ?2",
  ).bind(identity.tenantID, requestID).first<{ hash: string; result: string }>();
  if (existing) return existing.hash === hash ? response(JSON.parse(existing.result))
    : response({ error: "invoice_combination_retry_changed" }, 409);

  try {
    const bill = body.invoice as ObjectValue;
    const priorInvoices = await env.DB.prepare(
      "SELECT entity_id AS id, operation_json AS operationJSON FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'invoice'",
    ).bind(identity.tenantID).all<{ id: string; operationJSON: string }>();
    if (priorInvoices.results.some(row => row.id === invoiceID || invoiceFromOperation(row.operationJSON).invoiceNumber === bill.invoiceNumber)) {
      return response({ error: "combined_invoice_number_or_identity_exists" }, 409);
    }
    const proposal = bill.combination as ObjectValue;
    if (!proposal || normalizedID(proposal.id) !== invoiceID || proposal.invoiceNumber !== bill.invoiceNumber ||
        typeof bill.invoiceNumber !== "string" || !bill.invoiceNumber.endsWith("-C") || bill.invoiceNumber.length > 80 ||
        proposal.billingCustomerNumber !== bill.customerNumber || bill.combinedIntoInvoiceID || bill.siteID ||
        bill.taxSnapshot || (bill.receipts?.length ?? 0) !== 0 || bill.lifecycleStatus !== "Active" && bill.lifecycleStatus !== "active" ||
        typeof bill.notes !== "string" || !validDate(bill.issueDate) || !validDate(bill.dueDate) || !validDate(proposal.createdAt)) {
      throw new Error("invalid_invoice_combination");
    }
    if (!Array.isArray(body.sources) || body.sources.length < 2 || body.sources.length > 50 ||
        !Array.isArray(proposal.sourceInvoices) || proposal.sourceInvoices.length !== body.sources.length) {
      throw new Error("invalid_invoice_combination");
    }
    const sourceIDs = body.sources.map((s: ObjectValue) => normalizedID(s.id));
    if (new Set(sourceIDs).size !== sourceIDs.length || sourceIDs.includes(invoiceID)) throw new Error("duplicate_invoice_selection");
    const customerID = normalizedID(body.billingCustomerID);
    const customerRow = await env.DB.prepare(
      "SELECT revision, operation_json AS operationJSON FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2",
    ).bind(identity.tenantID, customerID).first<{ revision: string; operationJSON: string }>();
    if (!customerRow) return response({ error: "billing_customer_not_synchronized" }, 409);
    const customer = invoiceFromOperation(customerRow.operationJSON);
    if (customer.customerNumber !== bill.customerNumber || customer.lifecycleStatus === "Archived" || customer.lifecycleStatus === "archived") {
      throw new Error("invalid_billing_customer");
    }
    const sources: { id: string; revision: string; invoice: ObjectValue }[] = [];
    for (let index = 0; index < body.sources.length; index++) {
      const reference = body.sources[index];
      const row = await env.DB.prepare(
        "SELECT revision, operation_json AS operationJSON FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'invoice' AND entity_id = ?2",
      ).bind(identity.tenantID, sourceIDs[index]).first<{ revision: string; operationJSON: string }>();
      if (!row || row.revision !== reference.revision) return response({ error: "invoice_combination_sources_changed" }, 409);
      const invoice = invoiceFromOperation(row.operationJSON);
      if (!equal(invoice, decode(reference.snapshotData)) || !equal(invoice, proposal.sourceInvoices[index])) {
        return response({ error: "invoice_combination_snapshot_mismatch" }, 409);
      }
      if (normalizedID(invoice.id) !== sourceIDs[index] ||
          invoice.status === "Void" || invoice.combinedIntoInvoiceID || invoice.combination || invoice.paymentCorrection ||
          invoice.lifecycleStatus === "Archived" || invoice.lifecycleStatus === "archived") {
        return response({ error: "invoice_combination_sources_changed" }, 409);
      }
      sources.push({ id: sourceIDs[index], revision: row.revision, invoice });
    }
    const subtotal = sources.reduce((sum, s) => sum + cents(s.invoice.subtotal), 0);
    const discount = sources.reduce((sum, s) => sum + cents(s.invoice.discount), 0);
    const total = sources.reduce((sum, s) => sum + cents(s.invoice.total), 0);
    if (![subtotal, discount, total].every(Number.isSafeInteger) || cents(bill.subtotal) !== subtotal ||
        cents(bill.discount) !== discount || cents(bill.total) !== total) throw new Error("invalid_invoice_amount");
    const jobs = [...new Set(sources.map(s => String(s.invoice.jobNumber ?? "")).filter(Boolean))];
    if (!equal(jobs, bill.associatedJobNumbers) || bill.jobNumber !== (jobs[0] ?? "")) throw new Error("invalid_combined_job_references");
    const expectedLines = sources.flatMap(source => (source.invoice.lineItems ?? []).map((line: ObjectValue) => ({ source, line })));
    if (!Array.isArray(proposal.lines) || proposal.lines.length !== expectedLines.length || expectedLines.length > 500) throw new Error("invalid_combined_line_items");
    const lineIDs = new Set<string>();
    proposal.lines.forEach((entry: ObjectValue, index: number) => {
      const { source, line } = expectedLines[index];
      const copy = { ...entry.item, id: line.id };
      const lineID = normalizedID(entry.item.id);
      if (lineIDs.has(lineID) || normalizedID(entry.sourceInvoiceID) !== source.id ||
          normalizedID(entry.sourceLineItemID) !== normalizedID(line.id) || !equal(copy, line)) throw new Error("invalid_combined_line_items");
      lineIDs.add(lineID);
    });
    if (!equal(bill.lineItems, proposal.lines.map((entry: ObjectValue) => entry.item))) throw new Error("invalid_combined_line_items");
    const redistribution = proposal.paymentRedistribution;
    const pool = redistribution?.pool;
    if (!pool || !Array.isArray(pool.verifications) || !Array.isArray(pool.adjustments) || pool.adjustments.length !== 0 ||
        redistribution.replacesRedistributionID || typeof redistribution.reason !== "string" || !redistribution.reason.trim()) throw new Error("invalid_payment_pool");
    normalizedID(pool.id); normalizedID(redistribution.id);
    const checks = new Map<string, ObjectValue>();
    const checkIDs = new Set<string>(), receiptIDs = new Set<string>(), eventIDs = new Set<string>();
    let collected = 0;
    for (const check of pool.verifications) {
      const sourceID = normalizedID(check.sourceInvoiceID), checkID = normalizedID(check.id);
      const source = sources.find(s => s.id === sourceID);
      if (!source || checks.has(sourceID) || checkIDs.has(checkID)) throw new Error("duplicate_payment_verification");
      const receipts = source.invoice.receipts ?? [];
      const basis = receipts.length ? receipts.reduce((sum: number, r: ObjectValue) => sum + cents(r.paymentAmount), 0) : cents(source.invoice.amountPaid);
      const paid = cents(check.collectedAmount);
      if (typeof check.note !== "string" || cents(check.recordedAmount) !== basis || paid > basis ||
          (paid !== basis && (typeof check.note !== "string" || !check.note.trim())) ||
          !sameIDs(check.receiptIDs, receipts.map((r: ObjectValue) => r.id)) ||
          !sameIDs(check.paymentEventIDs, receipts.map((r: ObjectValue) => r.paymentEventID))) throw new Error("invalid_payment_verification");
      for (const receipt of receipts) {
        const receiptID = normalizedID(receipt.id), eventID = normalizedID(receipt.paymentEventID);
        if (receiptIDs.has(receiptID) || eventIDs.has(eventID)) throw new Error("duplicate_payment_event");
        receiptIDs.add(receiptID); eventIDs.add(eventID);
      }
      checks.set(sourceID, check); checkIDs.add(checkID); collected += paid;
    }
    for (const source of sources) {
      if ((cents(source.invoice.amountPaid) > 0 || source.invoice.status === "Paid" || (source.invoice.receipts?.length ?? 0) > 0) && !checks.has(source.id)) {
        throw new Error("missing_collection_verification");
      }
    }
    const applied = Math.min(collected, total), balance = total - applied;
    if (!Number.isSafeInteger(collected) || cents(bill.amountPaid) !== applied || cents(bill.balanceDue) !== balance ||
        !Array.isArray(redistribution.allocations) || redistribution.allocations.length !== 1 ||
        normalizedID(redistribution.allocations[0].invoiceID) !== invoiceID ||
        cents(redistribution.allocations[0].invoiceTotal) !== total || cents(redistribution.allocations[0].appliedAmount) !== applied) throw new Error("invalid_payment_allocation");
    const requiredStatus = applied > 0 ? (applied >= total ? "Paid" : "Partially Paid") : "Draft";
    if (bill.status !== requiredStatus || (requiredStatus === "Paid" ? !validDate(bill.paidDate) : !!bill.paidDate)) throw new Error("invalid_combined_invoice_status");
    // Match the phone's canonical ISO8601 encoder (whole seconds). Financial
    // evidence must re-encode identically for subsequent revision checks.
    const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    for (const check of pool.verifications) { check.verifiedBy = identity.memberID; check.verifiedAt = now; }
    redistribution.preparedBy = identity.memberID; redistribution.preparedAt = now;
    const records: { invoice: ObjectValue; revision: string }[] = [...sources.map(source => ({
      invoice: { ...source.invoice, status: "Void", balanceDue: 0, combinedIntoInvoiceID: bill.id }, revision: crypto.randomUUID(),
    })), { invoice: bill, revision: crypto.randomUUID() }];
    const result = { invoiceID: bill.id, records };
    const statements: D1PreparedStatement[] = [env.DB.prepare(
      "INSERT INTO invoice_combination_commits (tenant_id, request_id, invoice_id, invoice_number, request_hash, result_json, created_at) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)",
    ).bind(identity.tenantID, requestID, invoiceID, bill.invoiceNumber, hash, JSON.stringify(result), now)];
    // The customer guard uses the same CHECK constraint as source guards.
    // Use a distinct customer-prefixed key, which cannot collide with invoice IDs.
    statements.push(env.DB.prepare(
      `INSERT INTO invoice_combination_sources (tenant_id, source_invoice_id, request_id, revision_guard)
       VALUES (?1, ?2, ?3, CASE WHEN EXISTS (SELECT 1 FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?4 AND revision = ?5) THEN 1 ELSE 0 END)`,
    ).bind(identity.tenantID, `customer:${customerID}:${requestID}`, requestID, customerID, customerRow.revision));
    for (const source of sources) statements.push(env.DB.prepare(
      `INSERT INTO invoice_combination_sources (tenant_id, source_invoice_id, request_id, revision_guard)
       VALUES (?1, ?2, ?3, CASE WHEN EXISTS (SELECT 1 FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'invoice' AND entity_id = ?2 AND revision = ?4) THEN 1 ELSE 0 END)`,
    ).bind(identity.tenantID, source.id, requestID, source.revision));
    for (const eventID of eventIDs) statements.push(env.DB.prepare(
      "INSERT INTO invoice_combination_payment_events (tenant_id, payment_event_id, request_id) VALUES (?1, ?2, ?3)",
    ).bind(identity.tenantID, eventID, requestID));
    for (const record of records) {
      const id = normalizedID(record.invoice.id), operationID = crypto.randomUUID();
      const operation = { id: operationID, idempotencyKey: `combine:${requestID}:${id}`, sequenceNumber: 0,
        type: "recordMutation", entityType: "invoice", entityID: id, actionName: "upsertRecord", createdAt: now,
        payload: { schemaVersion: 1, contentType: "application/json", body: encode({ schemaVersion: 2,
          operationID, entityType: "invoice", recordID: id, mutationKind: "wholeRecord", changedFields: [],
          recordData: encode(record.invoice), clientCreatedAt: now, deviceModifiedAt: now }) },
        metadata: { invoiceCombinationID: requestID } };
      const operationJSON = JSON.stringify(operation);
      const write = id === invoiceID
        ? `INSERT INTO synchronized_records (tenant_id, entity_type, entity_id, revision, operation_json, updated_by_member_id, updated_by_device_id, updated_at)
           VALUES (?1, 'invoice', ?2, ?3, ?4, ?5, ?6, ?7)`
        : `UPDATE synchronized_records SET revision = ?3, operation_json = ?4, updated_by_member_id = ?5,
           updated_by_device_id = ?6, updated_at = ?7 WHERE tenant_id = ?1 AND entity_type = 'invoice' AND entity_id = ?2`;
      statements.push(env.DB.prepare(write).bind(identity.tenantID, id, record.revision, operationJSON, identity.memberID, identity.deviceID, now));
      statements.push(env.DB.prepare(
        `INSERT INTO synchronized_operations (id, tenant_id, device_id, idempotency_key, operation_type, entity_type, entity_id, action_name, payload_json, created_at, accepted_at, revision)
         VALUES (?1, ?2, ?3, ?4, 'recordMutation', 'invoice', ?5, 'upsertRecord', ?6, ?7, ?7, ?8)`,
      ).bind(operationID, identity.tenantID, identity.deviceID, operation.idempotencyKey, id, operationJSON, now, record.revision));
      statements.push(env.DB.prepare(
        `INSERT INTO synchronization_change_log (tenant_id, tenant_sequence, operation_id, device_id, revision, payload_json, accepted_at)
         SELECT ?1, COALESCE(MAX(tenant_sequence), 0) + 1, ?2, ?3, ?4, ?5, ?6 FROM synchronization_change_log WHERE tenant_id = ?1`,
      ).bind(identity.tenantID, operationID, identity.deviceID, record.revision, operationJSON, now));
    }
    const limited = await enforceLimit?.();
    if (limited) return limited;
    await env.DB.batch(statements);
    return response(result, 201);
  } catch (error) {
    // A simultaneous identical retry may have won the transaction.
    const winner = await env.DB.prepare(
      "SELECT request_hash AS hash, result_json AS result FROM invoice_combination_commits WHERE tenant_id = ?1 AND request_id = ?2",
    ).bind(identity.tenantID, requestID).first<{ hash: string; result: string }>();
    if (winner?.hash === hash) return response(JSON.parse(winner.result));
    const message = error instanceof Error ? error.message : "invalid_invoice_combination";
    const validation = /^[a-z_]+$/.test(message);
    return response({ error: validation ? message : "invoice_combination_sources_changed" }, validation ? 400 : 409);
  }
}

/** Split/rebuild and redistribute one existing pool in a single transaction.
 * Sources stay owned by the group even when independent again: future changes
 * use this command, not a second combination that would count transfers twice.
 */
export async function correctInvoicePayments(request: Request, env: CombinationEnv, identity: Identity): Promise<Response> {
  const raw = await request.text();
  if (new TextEncoder().encode(raw).length > 2_000_000) return response({ error: "invoice_correction_too_large" }, 413);
  let body: ObjectValue, requestID: string, rootID: string;
  try { body = JSON.parse(raw); requestID = normalizedID(body.requestID); rootID = normalizedID(body.rootInvoiceID); }
  catch { return response({ error: "invalid_invoice_correction" }, 400); }
  const hash = Array.from(new Uint8Array(await crypto.subtle.digest("SHA-256", new TextEncoder().encode(canonical(body)))),
    b => b.toString(16).padStart(2, "0")).join("");
  const committed = async () => env.DB.prepare(
    "SELECT request_hash AS hash, result_json AS result FROM invoice_payment_corrections WHERE tenant_id = ?1 AND request_id = ?2",
  ).bind(identity.tenantID, requestID).first<{ hash: string; result: string }>();
  const existing = await committed();
  if (existing) return existing.hash === hash ? response(JSON.parse(existing.result)) : response({ error: "invoice_correction_retry_changed" }, 409);
  try {
    if (!Array.isArray(body.sources) || body.sources.length < 3 || body.sources.length > 51 ||
        !Array.isArray(body.originalInvoices) || body.originalInvoices.length < 2 || body.originalInvoices.length > 50 ||
        !Array.isArray(body.retainedInvoiceIDs) || body.retainedInvoiceIDs.length === 1) throw new Error("invalid_correction_selection");
    const ids = body.sources.map((s: ObjectValue) => normalizedID(s.id));
    const originalIDs = body.originalInvoices.map((s: ObjectValue) => normalizedID(s.id));
    const retainedIDs = body.retainedInvoiceIDs.map(normalizedID);
    if (new Set(ids).size !== ids.length || new Set(originalIDs).size !== originalIDs.length || originalIDs.includes(rootID) ||
        !sameIDs(ids, [...originalIDs, rootID]) || new Set(retainedIDs).size !== retainedIDs.length ||
        retainedIDs.some((id: string) => !originalIDs.includes(id))) throw new Error("invalid_correction_selection");
    const members = new Map<string, { invoice: ObjectValue; revision: string }>();
    for (const reference of body.sources) {
      const id = normalizedID(reference.id);
      const row = await env.DB.prepare("SELECT revision, operation_json AS operationJSON FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'invoice' AND entity_id = ?2")
        .bind(identity.tenantID, id).first<{ revision: string; operationJSON: string }>();
      if (!row || row.revision !== reference.revision) return response({ error: "invoice_correction_sources_changed" }, 409);
      const invoice = invoiceFromOperation(row.operationJSON);
      if (normalizedID(invoice.id) !== id) return response({ error: "invoice_correction_sources_changed" }, 409);
      if (!equal(invoice, decode(reference.snapshotData))) return response({ error: "invoice_correction_snapshot_mismatch" }, 409);
      members.set(id, { invoice, revision: row.revision });
    }
    const root = members.get(rootID)!.invoice;
    const initialCommit = await env.DB.prepare("SELECT request_id AS id FROM invoice_combination_commits WHERE tenant_id = ?1 AND invoice_id = ?2")
      .bind(identity.tenantID, rootID).first<{ id: string }>();
    if (!initialCommit || !root.combination) throw new Error("unavailable_payment_group");
    const oldCorrection = root.paymentCorrection;
    if (oldCorrection && (!Array.isArray(oldCorrection.history) || !oldCorrection.history.length || normalizedID(oldCorrection.rootInvoiceID) !== rootID)) throw new Error("invalid_payment_history");
    const history = oldCorrection?.history ?? [root.combination.paymentRedistribution];
    const prior = history[history.length - 1];
    const oldOriginals = oldCorrection?.originalInvoices ?? root.combination.sourceInvoices;
    if (!equal(body.originalInvoices.slice(0, oldOriginals.length), oldOriginals)) throw new Error("changed_original_evidence");
    const oldIDs = new Set(oldOriginals.map((s: ObjectValue) => normalizedID(s.id)));
    for (const original of body.originalInvoices) {
      const id = normalizedID(original.id), current = members.get(id)!.invoice;
      if (oldIDs.has(id)) {
        const owner = await env.DB.prepare("SELECT request_id AS id FROM invoice_combination_sources WHERE tenant_id = ?1 AND source_invoice_id = ?2")
          .bind(identity.tenantID, id).first<{ id: string }>();
        if (owner?.id !== initialCommit.id || (oldCorrection && current.paymentCorrection?.id !== oldCorrection.id) ||
            (!oldCorrection && normalizedID(current.combinedIntoInvoiceID) !== rootID)) throw new Error("unavailable_payment_group");
      } else if (!equal(original, current) || current.combination || current.combinedIntoInvoiceID || current.paymentCorrection ||
                 current.status === "Void" || current.lifecycleStatus === "Archived" || current.lifecycleStatus === "archived") {
        throw new Error("unavailable_added_invoice");
      }
    }
    const customerID = normalizedID(body.billingCustomerID);
    const customerRow = await env.DB.prepare("SELECT revision, operation_json AS operationJSON FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = 'customer' AND entity_id = ?2")
      .bind(identity.tenantID, customerID).first<{ revision: string; operationJSON: string }>();
    if (!customerRow) return response({ error: "billing_customer_not_synchronized" }, 409);
    const customer = invoiceFromOperation(customerRow.operationJSON);
    if (customer.lifecycleStatus === "Archived" || customer.lifecycleStatus === "archived") throw new Error("unavailable_billing_customer");
    const redistribution = body.redistribution, pool = redistribution?.pool;
    if (!pool || normalizedID(pool.id) !== normalizedID(prior.pool.id) ||
        normalizedID(redistribution.replacesRedistributionID) !== normalizedID(prior.id) ||
        !Array.isArray(pool.verifications) || !Array.isArray(pool.adjustments) ||
        !equal(pool.verifications.slice(0, prior.pool.verifications.length), prior.pool.verifications) ||
        !equal(pool.adjustments.slice(0, prior.pool.adjustments.length), prior.pool.adjustments) ||
        typeof redistribution.reason !== "string" || !redistribution.reason.trim()) throw new Error("changed_payment_history");
    const redistributionID = normalizedID(redistribution.id);
    if (history.some((entry: ObjectValue) => normalizedID(entry.id) === redistributionID)) throw new Error("reused_redistribution_identity");
    const now = new Date().toISOString().replace(/\.\d{3}Z$/, "Z");
    const verificationIDs = new Set<string>(), receiptIDs = new Set<string>(), events = new Set<string>();
    const verified = new Map<string, number>(), recorded = new Map<string, number>();
    const addedEvents: string[] = [];
    const legacyIDs = new Set<string>();
    let collected = 0;
    const checks = pool.verifications as ObjectValue[];
    for (let index = 0; index < checks.length; index++) {
      const check = checks[index], id = normalizedID(check.id), invoiceID = normalizedID(check.sourceInvoiceID);
      if (verificationIDs.has(id) || !members.has(invoiceID) || !sameIDs(check.receiptIDs, check.receiptIDs ?? []) ||
          !sameIDs(check.paymentEventIDs, check.paymentEventIDs ?? []) || check.receiptIDs.length !== check.paymentEventIDs.length) throw new Error("duplicate_payment_evidence");
      verificationIDs.add(id);
      const basis = cents(check.recordedAmount), amount = cents(check.collectedAmount);
      if (amount > basis || typeof check.note !== "string" || (amount !== basis && !check.note.trim())) throw new Error("invalid_payment_verification");
      if (!check.receiptIDs.length) {
        if (legacyIDs.has(invoiceID) || checks.slice(0, index).some(c => normalizedID(c.sourceInvoiceID) === invoiceID)) throw new Error("duplicate_payment_evidence");
        legacyIDs.add(invoiceID);
      } else if (legacyIDs.has(invoiceID) && check.isAdditionalReceiptCollection !== true) throw new Error("duplicate_payment_evidence");
      if (index >= prior.pool.verifications.length) {
        const current = members.get(invoiceID)!.invoice;
        const available = (current.receipts ?? []).filter((r: ObjectValue) => !events.has(normalizedID(r.paymentEventID)));
        const expectedBasis = available.length ? available.reduce((sum: number, r: ObjectValue) => sum + cents(r.paymentAmount), 0)
          : (!oldIDs.has(invoiceID) && invoiceID !== rootID ? cents(current.amountPaid) : 0);
        if (basis !== expectedBasis || !sameIDs(check.receiptIDs, available.map((r: ObjectValue) => r.id)) ||
            !sameIDs(check.paymentEventIDs, available.map((r: ObjectValue) => r.paymentEventID)) ||
            (!available.length && (oldIDs.has(invoiceID) || invoiceID === rootID))) throw new Error("stale_collection_verification");
        check.verifiedBy = identity.memberID; check.verifiedAt = now;
      }
      for (const receiptID of check.receiptIDs) {
        const key = normalizedID(receiptID); if (receiptIDs.has(key)) throw new Error("duplicate_payment_evidence"); receiptIDs.add(key);
      }
      for (const eventID of check.paymentEventIDs) {
        const key = normalizedID(eventID); if (events.has(key)) throw new Error("duplicate_payment_evidence"); events.add(key);
        if (index >= prior.pool.verifications.length) addedEvents.push(key);
      }
      verified.set(id, amount); recorded.set(id, basis); collected += amount;
    }
    for (const [invoiceID, member] of members) {
      const missing = (member.invoice.receipts ?? []).some((r: ObjectValue) => !events.has(normalizedID(r.paymentEventID)));
      const legacyMissing = !oldIDs.has(invoiceID) && invoiceID !== rootID && !checks.some(c => normalizedID(c.sourceInvoiceID) === invoiceID) &&
        (cents(member.invoice.amountPaid) > 0 || member.invoice.status === "Paid");
      if (missing || legacyMissing) throw new Error("missing_collection_verification");
    }
    for (let index = 0; index < pool.adjustments.length; index++) {
      const adjustment = pool.adjustments[index], id = normalizedID(adjustment.id), target = normalizedID(adjustment.verificationID);
      if (verificationIDs.has(id) || !verified.has(target) || typeof adjustment.amountChange !== "number" || adjustment.amountChange === 0 ||
          typeof adjustment.reason !== "string" || !adjustment.reason.trim()) throw new Error("invalid_collection_adjustment");
      verificationIDs.add(id);
      const change = cents(Math.abs(adjustment.amountChange)) * Math.sign(adjustment.amountChange), amount = verified.get(target)! + change;
      if (amount < 0 || amount > recorded.get(target)!) throw new Error("invalid_collection_adjustment");
      verified.set(target, amount); collected += change;
      if (index >= prior.pool.adjustments.length) { adjustment.correctedBy = identity.memberID; adjustment.correctedAt = now; }
    }
    if (!Number.isSafeInteger(collected) || collected < 0) throw new Error("invalid_invoice_amount");
    const selected = body.originalInvoices.filter((s: ObjectValue) => retainedIDs.includes(normalizedID(s.id)));
    const independent = body.originalInvoices.filter((s: ObjectValue) => !retainedIDs.includes(normalizedID(s.id)));
    const totals = new Map<string, number>(independent.map((s: ObjectValue) => [normalizedID(s.id), cents(s.total)]));
    if (selected.length) totals.set(rootID, selected.reduce((sum: number, s: ObjectValue) => sum + cents(s.total), 0));
    if (!Array.isArray(redistribution.allocations) || !sameIDs(redistribution.allocations.map((a: ObjectValue) => a.invoiceID), [...totals.keys()])) throw new Error("invalid_payment_allocation");
    let allocated = 0;
    const allocations = new Map<string, number>();
    for (const allocation of redistribution.allocations) {
      const id = normalizedID(allocation.invoiceID), amount = cents(allocation.appliedAmount);
      if (cents(allocation.invoiceTotal) !== totals.get(id) || amount > totals.get(id)!) throw new Error("invalid_payment_allocation");
      allocated += amount; allocations.set(id, amount);
    }
    if (!Number.isSafeInteger(allocated) || allocated > collected) throw new Error("allocation_exceeds_collected_funds");
    redistribution.preparedBy = identity.memberID; redistribution.preparedAt = now;
    const expectedLines = selected.flatMap((s: ObjectValue) => s.lineItems.map((line: ObjectValue) => ({ source: s, line })));
    if (!Array.isArray(body.lines) || body.lines.length !== expectedLines.length || body.lines.length > 500) throw new Error("invalid_combined_line_items");
    const lineIDs = new Set<string>();
    body.lines.forEach((entry: ObjectValue, index: number) => {
      const { source, line } = expectedLines[index], id = normalizedID(entry.item.id);
      if (lineIDs.has(id) || normalizedID(entry.sourceInvoiceID) !== normalizedID(source.id) ||
          normalizedID(entry.sourceLineItemID) !== normalizedID(line.id) || !equal({ ...entry.item, id: line.id }, line)) throw new Error("invalid_combined_line_items");
      lineIDs.add(id);
    });
    const correction = { id: body.requestID, rootInvoiceID: root.id, originalInvoices: body.originalInvoices,
      retainedInvoiceIDs: body.retainedInvoiceIDs, history: [...history, redistribution] };
    function appliedInvoice(invoice: ObjectValue, amount: number): ObjectValue {
      const total = cents(invoice.total), status = amount > 0 ? (amount >= total ? "Paid" : "Partially Paid") : "Draft";
      return { ...invoice, amountPaid: amount / 100, balanceDue: (total - amount) / 100, status,
        paidDate: status === "Paid" ? (invoice.paidDate ?? now) : undefined, paymentCorrection: correction };
    }
    let updatedRoot: ObjectValue;
    if (selected.length) {
      const jobs = [...new Set(selected.map((s: ObjectValue) => String(s.jobNumber ?? "")).filter(Boolean))];
      updatedRoot = appliedInvoice({ ...root, customerNumber: customer.customerNumber, jobNumber: jobs[0] ?? "", associatedJobNumbers: jobs,
        subtotal: selected.reduce((sum: number, s: ObjectValue) => sum + cents(s.subtotal), 0) / 100,
        discount: selected.reduce((sum: number, s: ObjectValue) => sum + cents(s.discount), 0) / 100,
        total: totals.get(rootID)! / 100, lineItems: body.lines.map((line: ObjectValue) => line.item),
        combination: { ...root.combination, billingCustomerNumber: customer.customerNumber,
          sourceInvoices: selected, lines: body.lines, paymentRedistribution: redistribution } }, allocations.get(rootID)!);
    } else {
      updatedRoot = { ...root, status: "Void", amountPaid: 0, balanceDue: 0, paidDate: undefined,
        jobNumber: "", associatedJobNumbers: [], paymentCorrection: correction };
    }
    const records: { invoice: ObjectValue; revision: string }[] = [{ invoice: updatedRoot, revision: crypto.randomUUID() }];
    for (const original of body.originalInvoices) {
      const id = normalizedID(original.id), current = members.get(id)!.invoice;
      const base = { ...original, receipts: current.receipts, notes: current.notes,
        issueDate: current.issueDate, dueDate: current.dueDate, lifecycleStatus: current.lifecycleStatus,
        paymentCorrection: correction };
      records.push({ invoice: retainedIDs.includes(id)
        ? { ...base, status: "Void", balanceDue: 0, combinedIntoInvoiceID: root.id }
        : appliedInvoice({ ...base, combinedIntoInvoiceID: undefined }, allocations.get(id)!), revision: crypto.randomUUID() });
    }
    const result = { invoiceID: root.id, records };
    const statements = [env.DB.prepare("INSERT INTO invoice_payment_corrections VALUES (?1, ?2, ?3, ?4, ?5, ?6)")
      .bind(identity.tenantID, requestID, rootID, hash, JSON.stringify(result), now)];
    const guards = [...body.sources.map((s: ObjectValue) => ({ type: "invoice", id: normalizedID(s.id), revision: s.revision })),
      { type: "customer", id: customerID, revision: customerRow.revision }];
    for (const guard of guards) statements.push(env.DB.prepare(
      `INSERT INTO invoice_payment_correction_guards VALUES (?1, ?2, ?3, ?4,
       CASE WHEN EXISTS (SELECT 1 FROM synchronized_records WHERE tenant_id = ?1 AND entity_type = ?3 AND entity_id = ?4 AND revision = ?5) THEN 1 ELSE 0 END)`,
    ).bind(identity.tenantID, requestID, guard.type, guard.id, guard.revision));
    for (const id of originalIDs.filter((id: string) => !oldIDs.has(id))) statements.push(env.DB.prepare("INSERT INTO invoice_combination_sources VALUES (?1, ?2, ?3, 1)")
      .bind(identity.tenantID, id, initialCommit.id));
    for (const id of addedEvents) statements.push(env.DB.prepare("INSERT INTO invoice_combination_payment_events VALUES (?1, ?2, ?3)")
      .bind(identity.tenantID, id, initialCommit.id));
    for (const record of records) {
      const id = normalizedID(record.invoice.id), operationID = crypto.randomUUID();
      const operation = { id: operationID, idempotencyKey: `correct:${requestID}:${id}`, sequenceNumber: 0,
        type: "recordMutation", entityType: "invoice", entityID: id, actionName: "upsertRecord", createdAt: now,
        payload: { schemaVersion: 1, contentType: "application/json", body: encode({ schemaVersion: 2,
          operationID, entityType: "invoice", recordID: id, mutationKind: "wholeRecord", changedFields: [],
          recordData: encode(record.invoice), clientCreatedAt: now, deviceModifiedAt: now }) }, metadata: { invoicePaymentCorrectionID: requestID } };
      const json = JSON.stringify(operation);
      statements.push(env.DB.prepare(`UPDATE synchronized_records SET revision = ?3, operation_json = ?4,
        updated_by_member_id = ?5, updated_by_device_id = ?6, updated_at = ?7 WHERE tenant_id = ?1 AND entity_type = 'invoice' AND entity_id = ?2`)
        .bind(identity.tenantID, id, record.revision, json, identity.memberID, identity.deviceID, now));
      statements.push(env.DB.prepare(`INSERT INTO synchronized_operations (id, tenant_id, device_id, idempotency_key, operation_type,
        entity_type, entity_id, action_name, payload_json, created_at, accepted_at, revision)
        VALUES (?1, ?2, ?3, ?4, 'recordMutation', 'invoice', ?5, 'upsertRecord', ?6, ?7, ?7, ?8)`)
        .bind(operationID, identity.tenantID, identity.deviceID, operation.idempotencyKey, id, json, now, record.revision));
      statements.push(env.DB.prepare(`INSERT INTO synchronization_change_log (tenant_id, tenant_sequence, operation_id, device_id, revision, payload_json, accepted_at)
        SELECT ?1, COALESCE(MAX(tenant_sequence), 0) + 1, ?2, ?3, ?4, ?5, ?6 FROM synchronization_change_log WHERE tenant_id = ?1`)
        .bind(identity.tenantID, operationID, identity.deviceID, record.revision, json, now));
    }
    await env.DB.batch(statements);
    return response(result, 201);
  } catch (error) {
    const winner = await committed();
    if (winner?.hash === hash) return response(JSON.parse(winner.result));
    const message = error instanceof Error ? error.message : "invalid_invoice_correction";
    const validation = /^[a-z_]+$/.test(message);
    return response({ error: validation ? message : "invoice_correction_sources_changed" }, validation ? 400 : 409);
  }
}
