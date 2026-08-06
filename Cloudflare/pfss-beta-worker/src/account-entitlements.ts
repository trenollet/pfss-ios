export type SubscriptionLifecycleStatus =
  | "pending"
  | "trialing"
  | "active"
  | "pastDue"
  | "suspended"
  | "cancelled";

export type AccountAccessSource =
  | "appStoreSubscription"
  | "betaGrant"
  | "internalTesting"
  | "internalBusinessGrant"
  | "promotionalGrant";

export interface AccountEntitlements {
  userLimit: number;
  deviceLimit: number;
  recordLimits: {
    leads: number | null;
    customers: number | null;
    jobs: number | null;
  };
  modules: string[];
}

export interface PublishedPlanDefinition {
  code: string;
  displayName: string;
  billing: "complimentary" | "appStore" | "directEnterprise";
  durationDays: number | null;
  monthlyPriceUSD: number | null;
  entitlements: AccountEntitlements;
}

const allModules = ["sales", "service", "dispatch", "reporting"];

export const PFSS_PLAN_CATALOG: ReadonlyArray<PublishedPlanDefinition> = [
  {
    code: "beta-90-day",
    displayName: "Beta Test",
    billing: "complimentary",
    durationDays: 90,
    monthlyPriceUSD: null,
    entitlements: {
      userLimit: 5,
      deviceLimit: 10,
      recordLimits: { leads: 1_000, customers: 1_000, jobs: 3_000 },
      modules: allModules,
    },
  },
  {
    code: "trial-14-day",
    displayName: "Trial",
    billing: "appStore",
    durationDays: 14,
    monthlyPriceUSD: 0,
    entitlements: {
      userLimit: 2,
      deviceLimit: 4,
      recordLimits: { leads: 5, customers: 5, jobs: 10 },
      modules: allModules,
    },
  },
  {
    code: "base-monthly",
    displayName: "Base",
    billing: "appStore",
    durationDays: null,
    monthlyPriceUSD: 7.99,
    entitlements: {
      userLimit: 3,
      deviceLimit: 6,
      recordLimits: { leads: 1_000, customers: 1_000, jobs: 3_000 },
      modules: allModules,
    },
  },
  {
    code: "pro-monthly",
    displayName: "Pro",
    billing: "appStore",
    durationDays: null,
    monthlyPriceUSD: 14.99,
    entitlements: {
      userLimit: 5,
      deviceLimit: 10,
      recordLimits: { leads: 3_000, customers: 3_000, jobs: 9_000 },
      modules: allModules,
    },
  },
  {
    code: "expert-monthly",
    displayName: "Expert",
    billing: "appStore",
    durationDays: null,
    monthlyPriceUSD: 29.99,
    entitlements: {
      userLimit: 10,
      deviceLimit: 20,
      recordLimits: { leads: 10_000, customers: 10_000, jobs: 50_000 },
      modules: allModules,
    },
  },
];

export interface AccountEntitlementSnapshot {
  planCode: string;
  accessSource: AccountAccessSource;
  subscriptionStatus: SubscriptionLifecycleStatus;
  accessMode: "full" | "readOnly" | "blocked";
  entitlements: AccountEntitlements;
  effectiveAt: string;
  expiresAt: string | null;
}

interface AllocationRow {
  planCode: string;
  accessSource: AccountAccessSource;
  entitlementsJSON: string;
  effectiveAt: string;
  expiresAt: string | null;
  subscriptionStatus: SubscriptionLifecycleStatus | null;
}

const complimentarySources = new Set<AccountAccessSource>([
  "betaGrant",
  "internalTesting",
  "internalBusinessGrant",
  "promotionalGrant",
]);

function positiveInteger(value: unknown): number | null {
  return typeof value === "number" && Number.isSafeInteger(value) && value > 0
    ? value
    : null;
}

function limitOrUnlimited(value: unknown): number | null | undefined {
  if (value === null) return null;
  return positiveInteger(value) ?? undefined;
}

function parseEntitlements(value: string): AccountEntitlements | null {
  try {
    const parsed = JSON.parse(value) as Record<string, unknown>;
    const legacyEmployeeLimit = positiveInteger(parsed.employeeLimit);
    const legacyOwnerLimit = positiveInteger(parsed.ownerLimit);
    const userLimit = positiveInteger(parsed.userLimit) ??
      (legacyEmployeeLimit && legacyOwnerLimit
        ? legacyEmployeeLimit + legacyOwnerLimit
        : null);
    const deviceLimit = positiveInteger(parsed.deviceLimit);
    const recordLimits = parsed.recordLimits as Record<string, unknown> | undefined;
    const leads = limitOrUnlimited(recordLimits?.leads ?? parsed.leadLimit);
    const customers = limitOrUnlimited(
      recordLimits?.customers ?? parsed.customerLimit,
    );
    const jobs = limitOrUnlimited(recordLimits?.jobs ?? parsed.jobLimit);
    const modules = Array.isArray(parsed.modules)
      ? parsed.modules.filter((module): module is string =>
        typeof module === "string" && module.trim().length > 0
      )
      : [];
    if (!userLimit || !deviceLimit || leads === undefined ||
        customers === undefined || jobs === undefined) return null;
    return {
      userLimit,
      deviceLimit,
      recordLimits: { leads, customers, jobs },
      modules: [...new Set(modules.map((module) => module.trim()))],
    };
  } catch {
    return null;
  }
}

function accessMode(
  source: AccountAccessSource,
  status: SubscriptionLifecycleStatus,
): AccountEntitlementSnapshot["accessMode"] {
  if (complimentarySources.has(source)) return "full";
  if (status === "active" || status === "trialing") return "full";
  if (status === "pastDue" || status === "cancelled") return "readOnly";
  return "blocked";
}

export async function resolveAccountEntitlements(
  db: D1Database,
  tenantID: string,
  now = new Date(),
): Promise<AccountEntitlementSnapshot | null> {
  const row = await db.prepare(
    `SELECT allocation.plan_code AS planCode,
            allocation.access_source AS accessSource,
            allocation.entitlements_json AS entitlementsJSON,
            allocation.effective_at AS effectiveAt,
            allocation.expires_at AS expiresAt,
            account.status AS subscriptionStatus
       FROM plan_allocations AS allocation
       LEFT JOIN subscription_accounts AS account
         ON account.id = allocation.subscription_account_id
      WHERE allocation.tenant_id = ?1
        AND allocation.revoked_at IS NULL
        AND allocation.effective_at <= ?2
        AND (allocation.expires_at IS NULL OR allocation.expires_at > ?2)
      ORDER BY allocation.effective_at DESC, allocation.created_at DESC
      LIMIT 1`,
  ).bind(tenantID, now.toISOString()).first<AllocationRow>();
  if (!row) return null;

  const entitlements = parseEntitlements(row.entitlementsJSON);
  if (!entitlements) return null;
  const subscriptionStatus = row.subscriptionStatus ??
    (complimentarySources.has(row.accessSource) ? "active" : "pending");
  return {
    planCode: row.planCode,
    accessSource: row.accessSource,
    subscriptionStatus,
    accessMode: accessMode(row.accessSource, subscriptionStatus),
    entitlements,
    effectiveAt: row.effectiveAt,
    expiresAt: row.expiresAt,
  };
}

export function limitReached(
  currentCount: number,
  limit: number,
): boolean {
  return currentCount >= limit;
}
