export type PFSSDeploymentEnvironment = "local" | "staging" | "production";
export type ManagedIdentityEnvironment = "staging" | "production";

export interface ManagedIdentityConfiguration {
  providerKey: "workos";
  deploymentEnvironment: PFSSDeploymentEnvironment;
  providerEnvironment: ManagedIdentityEnvironment;
  clientID: string;
  apiKey: string;
  apiBaseURL: string;
  issuer: string;
  redirectURIs: readonly string[];
}

export interface ManagedIdentityConfigurationBindings {
  PFSS_ENVIRONMENT?: string;
  WORKOS_ENVIRONMENT?: string;
  WORKOS_CLIENT_ID?: string;
  WORKOS_API_KEY?: string;
  WORKOS_API_BASE_URL?: string;
  WORKOS_ISSUER?: string;
  WORKOS_REDIRECT_URIS?: string;
}

export interface IdentityAuthorizationStart {
  state: string;
  codeChallenge: string;
  redirectURI: string;
  emailHint?: string;
}

export interface IdentityAuthorizationSession {
  authorizationURL: string;
  state: string;
  expiresAt: string;
}

export interface VerifiedManagedIdentity {
  providerKey: "workos";
  providerSubject: string;
  verifiedEmail: string;
  displayName: string;
  authenticationMethod: string;
}

export interface ManagedOwnerIdentityProvider {
  startAuthorization(
    request: IdentityAuthorizationStart,
  ): Promise<IdentityAuthorizationSession>;
  exchangeAuthorizationCode(
    code: string,
    codeVerifier: string,
    redirectURI: string,
  ): Promise<VerifiedManagedIdentity>;
}

export class IdentityConfigurationError extends Error {}

export class IdentityProviderResponseError extends Error {}

function isHTTPSURL(value: string): boolean {
  try {
    return new URL(value).protocol === "https:";
  } catch {
    return false;
  }
}

export function validateManagedIdentityConfiguration(
  configuration: ManagedIdentityConfiguration,
): void {
  if (configuration.deploymentEnvironment === "local") {
    throw new IdentityConfigurationError(
      "Local development must use the local identity adapter.",
    );
  }
  if (configuration.deploymentEnvironment !== configuration.providerEnvironment) {
    throw new IdentityConfigurationError(
      "PFSS and managed identity environments must match.",
    );
  }
  if (!/^client_[A-Za-z0-9_-]{8,}$/.test(configuration.clientID)) {
    throw new IdentityConfigurationError("Invalid managed identity client ID.");
  }
  if (!/^sk_[A-Za-z0-9_-]{16,}$/.test(configuration.apiKey)) {
    throw new IdentityConfigurationError("Invalid managed identity API key.");
  }
  if (!isHTTPSURL(configuration.apiBaseURL) ||
      !isHTTPSURL(configuration.issuer) ||
      configuration.redirectURIs.length === 0 ||
      configuration.redirectURIs.some((value) => !isHTTPSURL(value))) {
    throw new IdentityConfigurationError(
      "Managed identity endpoints must use explicit HTTPS URLs.",
    );
  }
  if (new Set(configuration.redirectURIs).size !==
      configuration.redirectURIs.length) {
    throw new IdentityConfigurationError("Redirect URIs must be unique.");
  }
}

export function managedIdentityConfigurationFromBindings(
  bindings: ManagedIdentityConfigurationBindings,
): ManagedIdentityConfiguration {
  const deploymentEnvironment = bindings.PFSS_ENVIRONMENT;
  const providerEnvironment = bindings.WORKOS_ENVIRONMENT;
  if (deploymentEnvironment !== "staging" &&
      deploymentEnvironment !== "production") {
    throw new IdentityConfigurationError(
      "PFSS_ENVIRONMENT must be staging or production.",
    );
  }
  if (providerEnvironment !== "staging" &&
      providerEnvironment !== "production") {
    throw new IdentityConfigurationError(
      "WORKOS_ENVIRONMENT must be staging or production.",
    );
  }
  let redirectURIs: unknown;
  try {
    redirectURIs = JSON.parse(bindings.WORKOS_REDIRECT_URIS ?? "");
  } catch {
    throw new IdentityConfigurationError(
      "WORKOS_REDIRECT_URIS must be a JSON string array.",
    );
  }
  if (!Array.isArray(redirectURIs) ||
      redirectURIs.some((value) => typeof value !== "string")) {
    throw new IdentityConfigurationError(
      "WORKOS_REDIRECT_URIS must be a JSON string array.",
    );
  }
  const configuration: ManagedIdentityConfiguration = {
    providerKey: "workos",
    deploymentEnvironment,
    providerEnvironment,
    clientID: bindings.WORKOS_CLIENT_ID ?? "",
    apiKey: bindings.WORKOS_API_KEY ?? "",
    apiBaseURL: bindings.WORKOS_API_BASE_URL ?? "",
    issuer: bindings.WORKOS_ISSUER ?? "",
    redirectURIs,
  };
  validateManagedIdentityConfiguration(configuration);
  return configuration;
}

interface WorkOSAuthenticationResponse {
  user?: {
    id?: unknown;
    email?: unknown;
    email_verified?: unknown;
    first_name?: unknown;
    last_name?: unknown;
  };
  authentication_method?: unknown;
}

type IdentityFetch = (
  input: RequestInfo | URL,
  init?: RequestInit,
) => Promise<Response>;

export class WorkOSManagedOwnerIdentityProvider
implements ManagedOwnerIdentityProvider {
  private readonly configuration: ManagedIdentityConfiguration;
  private readonly request: IdentityFetch;

  constructor(
    configuration: ManagedIdentityConfiguration,
    request?: IdentityFetch,
  ) {
    validateManagedIdentityConfiguration(configuration);
    this.configuration = configuration;
    // Cloudflare's native fetch must be invoked directly. Storing it and later
    // calling it as an object method changes its `this` reference and causes an
    // illegal-invocation error in the Worker runtime.
    this.request = request ?? ((input, init) => fetch(input, init));
  }

  async startAuthorization(
    request: IdentityAuthorizationStart,
  ): Promise<IdentityAuthorizationSession> {
    validateAuthorizationStart(request, this.configuration.redirectURIs);
    const url = new URL(
      "/user_management/authorize",
      this.configuration.apiBaseURL,
    );
    url.searchParams.set("response_type", "code");
    url.searchParams.set("client_id", this.configuration.clientID);
    url.searchParams.set("provider", "authkit");
    url.searchParams.set("redirect_uri", request.redirectURI);
    url.searchParams.set("state", request.state);
    url.searchParams.set("code_challenge", request.codeChallenge);
    url.searchParams.set("code_challenge_method", "S256");
    url.searchParams.set("screen_hint", "sign-up");
    if (request.emailHint) url.searchParams.set("login_hint", request.emailHint);
    return {
      authorizationURL: url.toString(),
      state: request.state,
      expiresAt: new Date(Date.now() + 5 * 60_000).toISOString(),
    };
  }

  async exchangeAuthorizationCode(
    code: string,
    codeVerifier: string,
    redirectURI: string,
  ): Promise<VerifiedManagedIdentity> {
    if (!/^[A-Za-z0-9_-]{20,512}$/.test(code) ||
        !/^[A-Za-z0-9_-]{43,128}$/.test(codeVerifier) ||
        !this.configuration.redirectURIs.includes(redirectURI)) {
      throw new IdentityConfigurationError(
        "Authorization exchange input is invalid.",
      );
    }
    const response = await this.request(new URL(
      "/user_management/authenticate",
      this.configuration.apiBaseURL,
    ), {
      method: "POST",
      headers: { "content-type": "application/json" },
      body: JSON.stringify({
        client_id: this.configuration.clientID,
        client_secret: this.configuration.apiKey,
        grant_type: "authorization_code",
        code,
        code_verifier: codeVerifier,
      }),
    });
    if (!response.ok) {
      throw new IdentityProviderResponseError(
        `Managed identity exchange failed with status ${response.status}.`,
      );
    }
    const body = await response.json<WorkOSAuthenticationResponse>();
    const user = body.user;
    const subject = typeof user?.id === "string" ? user.id : "";
    const email = typeof user?.email === "string"
      ? user.email.trim().toLowerCase()
      : "";
    const authenticationMethod = typeof body.authentication_method === "string"
      ? body.authentication_method
      : "";
    if (!subject.startsWith("user_") || !email ||
        user?.email_verified !== true || !authenticationMethod) {
      throw new IdentityProviderResponseError(
        "Managed identity response was incomplete or unverified.",
      );
    }
    const name = [user?.first_name, user?.last_name]
      .filter((value): value is string => typeof value === "string")
      .map((value) => value.trim())
      .filter(Boolean)
      .join(" ");
    return {
      providerKey: "workos",
      providerSubject: subject,
      verifiedEmail: email,
      displayName: name || email,
      authenticationMethod,
    };
  }
}

export function validateAuthorizationStart(
  request: IdentityAuthorizationStart,
  allowedRedirectURIs: readonly string[],
): void {
  if (!/^[A-Za-z0-9_-]{43,128}$/.test(request.state) ||
      !/^[A-Za-z0-9_-]{43,128}$/.test(request.codeChallenge)) {
    throw new IdentityConfigurationError(
      "Authorization state and PKCE challenge are invalid.",
    );
  }
  if (!allowedRedirectURIs.includes(request.redirectURI)) {
    throw new IdentityConfigurationError("Redirect URI is not allowed.");
  }
}

/// Deterministic local-only adapter for tests. It cannot issue production
/// identities and prevents tests from depending on WorkOS availability.
export class LocalManagedOwnerIdentityProvider
implements ManagedOwnerIdentityProvider {
  async startAuthorization(
    request: IdentityAuthorizationStart,
  ): Promise<IdentityAuthorizationSession> {
    validateAuthorizationStart(request, ["https://local.pfss.test/auth/callback"]);
    const url = new URL("https://local.pfss.test/authorize");
    url.searchParams.set("state", request.state);
    url.searchParams.set("code_challenge", request.codeChallenge);
    return {
      authorizationURL: url.toString(),
      state: request.state,
      expiresAt: new Date(Date.now() + 5 * 60_000).toISOString(),
    };
  }

  async exchangeAuthorizationCode(
    code: string,
    codeVerifier: string,
    redirectURI: string,
  ): Promise<VerifiedManagedIdentity> {
    if (code !== "local-verified-code" || codeVerifier.length < 43 ||
        redirectURI !== "https://local.pfss.test/auth/callback") {
      throw new IdentityConfigurationError("Local authorization failed.");
    }
    return {
      providerKey: "workos",
      providerSubject: "local_test_subject",
      verifiedEmail: "owner@local.pfss.test",
      displayName: "Local Test Owner",
      authenticationMethod: "MagicAuth",
    };
  }
}
