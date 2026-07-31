import { randomBytes, randomUUID, createHash } from "node:crypto";
import { spawnSync } from "node:child_process";

const displayName = process.argv.slice(2).join(" ").trim();
if (!displayName) {
  console.error('Usage: pnpm tenant:create -- "Business Name"');
  process.exit(2);
}

const sqlText = (value) => `'${value.replaceAll("'", "''")}'`;
const tenantID = randomUUID();
const memberID = randomUUID();
const enrollmentCode = `PFSS-${randomBytes(18).toString("base64url")}`;
const codeHash = createHash("sha256").update(enrollmentCode).digest("hex");
const createdAt = new Date();
const expiresAt = new Date(createdAt.getTime() + 7 * 24 * 60 * 60 * 1000);
const sql = [
  `INSERT INTO tenants (id, display_name, status, created_at) VALUES (${sqlText(tenantID)}, ${sqlText(displayName)}, 'active', ${sqlText(createdAt.toISOString())});`,
  `INSERT INTO tenant_members (id, tenant_id, display_name, role, status, created_at, activated_at) VALUES (${sqlText(memberID)}, ${sqlText(tenantID)}, ${sqlText(`${displayName} Owner`)}, 'owner', 'active', ${sqlText(createdAt.toISOString())}, ${sqlText(createdAt.toISOString())});`,
  `INSERT INTO enrollment_codes (code_hash, tenant_id, expires_at, redeemed_at, created_at, member_id) VALUES (${sqlText(codeHash)}, ${sqlText(tenantID)}, ${sqlText(expiresAt.toISOString())}, NULL, ${sqlText(createdAt.toISOString())}, ${sqlText(memberID)});`,
].join(" ");

const wrangler = process.platform === "win32"
  ? "./node_modules/.bin/wrangler.cmd"
  : "./node_modules/.bin/wrangler";
const result = spawnSync(
  wrangler,
  ["d1", "execute", "pfss-beta", "--remote", "--command", sql],
  { cwd: process.cwd(), stdio: "inherit" },
);

if (result.error) {
  console.error(result.error.message);
  process.exit(1);
}
if (result.status !== 0) process.exit(result.status ?? 1);

console.log("\nPFSS beta tenant created.");
console.log(`Business: ${displayName}`);
console.log(`Tenant ID: ${tenantID}`);
console.log(`Owner membership ID: ${memberID}`);
console.log(`Enrollment code: ${enrollmentCode}`);
console.log(`Expires: ${expiresAt.toISOString()}`);
console.log("\nThe clear-text enrollment code was not stored in Cloudflare.");
console.log("Enter it once on the device's Data Management screen.");
