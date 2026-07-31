declare module "cloudflare:workers" {
  interface ProvidedEnv {
    DB: D1Database;
    ARCHIVES: R2Bucket;
    TEST_MIGRATIONS: D1Migration[];
  }
}
