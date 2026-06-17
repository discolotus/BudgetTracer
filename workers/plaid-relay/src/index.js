const PLAID_BASE_URLS = {
  sandbox: "https://sandbox.plaid.com",
  development: "https://development.plaid.com",
  production: "https://production.plaid.com"
};

const APPLE_KEYS_URL = "https://appleid.apple.com/auth/keys";

let appleKeysCache = {
  expiresAt: 0,
  keys: []
};

export default {
  async fetch(request, env, ctx) {
    return handleRequest(request, env, ctx);
  }
};

export async function handleRequest(request, env) {
  const url = new URL(request.url);
  const host = url.hostname.toLowerCase();

  if (request.method === "OPTIONS") {
    return emptyResponse(204);
  }

  if (request.method === "GET" && url.pathname === "/health") {
    return jsonResponse({
      status: "ok",
      service: "budgettracer-plaid-relay",
      plaid_environment: plaidEnvironment(env)
    });
  }

  if (request.method === "GET" && url.pathname === "/.well-known/apple-app-site-association") {
    if (!hostAllowed(host, env.LINK_HOSTS)) {
      return jsonResponse({ error: "Not found." }, 404);
    }
    return jsonResponse(appleAppSiteAssociation(env), 200, {
      "Content-Type": "application/json"
    });
  }

  if (request.method === "GET" && url.pathname === "/plaid/oauth") {
    if (!hostAllowed(host, env.LINK_HOSTS)) {
      return jsonResponse({ error: "Not found." }, 404);
    }
    return htmlResponse("Return to BudgetTracer to continue connecting your account.");
  }

  if (!url.pathname.startsWith("/v1/plaid/")) {
    return jsonResponse({ error: "Not found." }, 404);
  }

  if (!hostAllowed(host, env.API_HOSTS)) {
    return jsonResponse({ error: "Not found." }, 404);
  }

  if (request.method !== "POST") {
    return jsonResponse({ error: "Method not allowed." }, 405);
  }

  let subject;
  try {
    subject = await verifyAuthorization(request, env);
  } catch (error) {
    return jsonResponse({ error: error.message }, 401);
  }

  try {
    switch (url.pathname) {
    case "/v1/plaid/link-token":
      return jsonResponse(await createLinkToken(request, env, subject));
    case "/v1/plaid/exchange-public-token":
      return jsonResponse(await exchangePublicToken(request, env));
    case "/v1/plaid/accounts/get":
      return jsonResponse(await proxyAccessTokenRequest(request, env, "/accounts/get"));
    case "/v1/plaid/transactions/sync":
      return jsonResponse(await syncTransactions(request, env));
    case "/v1/plaid/item/remove":
      return jsonResponse(await proxyAccessTokenRequest(request, env, "/item/remove"));
    default:
      return jsonResponse({ error: "Not found." }, 404);
    }
  } catch (error) {
    return plaidErrorResponse(error);
  }
}

function appleAppSiteAssociation(env) {
  const appIDs = splitList(env.APPLE_APP_SITE_ASSOCIATION_APP_IDS);
  return {
    applinks: {
      apps: [],
      details: appIDs.map((appID) => ({
        appIDs: [appID],
        components: [
          {
            "/": "/plaid/oauth*",
            comment: "Plaid OAuth redirect back to BudgetTracer."
          }
        ]
      }))
    }
  };
}

async function createLinkToken(request, env, subject) {
  const body = await jsonBody(request);
  const requestBody = {
    client_name: env.PLAID_CLIENT_NAME || "BudgetTracer",
    user: {
      client_user_id: body.client_user_id || subject
    },
    products: splitList(env.PLAID_PRODUCTS || "transactions"),
    country_codes: splitList(env.PLAID_COUNTRY_CODES || "US"),
    language: env.PLAID_LANGUAGE || "en",
    transactions: {
      days_requested: numberFromEnv(env.PLAID_TRANSACTIONS_DAYS_REQUESTED, 730)
    }
  };

  if (env.PLAID_REDIRECT_URI) {
    requestBody.redirect_uri = env.PLAID_REDIRECT_URI;
  }

  return plaidPost(env, "/link/token/create", requestBody);
}

async function exchangePublicToken(request, env) {
  const body = await jsonBody(request);
  if (!body.public_token) {
    throw new BadRequestError("public_token is required.");
  }

  const exchange = await plaidPost(env, "/item/public_token/exchange", {
    public_token: body.public_token
  });
  return {
    access_token: exchange.access_token,
    item_id: exchange.item_id,
    plaid_item_id: exchange.item_id,
    request_id: exchange.request_id
  };
}

async function proxyAccessTokenRequest(request, env, path) {
  const body = await jsonBody(request);
  if (!body.access_token) {
    throw new BadRequestError("access_token is required.");
  }

  return plaidPost(env, path, {
    access_token: body.access_token
  });
}

async function syncTransactions(request, env) {
  const body = await jsonBody(request);
  if (!body.access_token) {
    throw new BadRequestError("access_token is required.");
  }

  return plaidPost(env, "/transactions/sync", {
    access_token: body.access_token,
    cursor: body.cursor || undefined
  });
}

async function plaidPost(env, path, body) {
  const response = await fetch(`${plaidBaseURL(env)}${path}`, {
    method: "POST",
    headers: {
      "Content-Type": "application/json"
    },
    body: JSON.stringify({
      client_id: required(env, "PLAID_CLIENT_ID"),
      secret: plaidSecret(env),
      ...body
    })
  });

  const responseBody = await response.json().catch(() => ({}));
  if (!response.ok) {
    throw new PlaidAPIError(response.status, responseBody);
  }

  return responseBody;
}

async function verifyAuthorization(request, env) {
  const token = bearerToken(request);
  if (plaidEnvironment(env) !== "production" && env.DEV_BEARER_TOKEN && token === env.DEV_BEARER_TOKEN) {
    return "dev-user";
  }

  const jwt = parseJWT(token);
  const header = JSON.parse(base64URLToText(jwt.header));
  const claims = JSON.parse(base64URLToText(jwt.payload));

  validateAppleClaims(claims, required(env, "APPLE_AUDIENCE"));

  if (header.alg !== "RS256" || !header.kid) {
    throw new Error("The Sign in with Apple token header is invalid.");
  }

  const key = await applePublicKey(header.kid);
  const verified = await crypto.subtle.verify(
    "RSASSA-PKCS1-v1_5",
    key,
    base64URLToBytes(jwt.signature),
    new TextEncoder().encode(`${jwt.header}.${jwt.payload}`)
  );

  if (!verified) {
    throw new Error("The Sign in with Apple token signature is invalid.");
  }

  return claims.sub;
}

async function applePublicKey(kid) {
  const now = Date.now();
  if (appleKeysCache.expiresAt < now || !appleKeysCache.keys.length) {
    const response = await fetch(APPLE_KEYS_URL);
    if (!response.ok) {
      throw new Error("Could not load Apple public keys.");
    }
    const jwks = await response.json();
    appleKeysCache = {
      expiresAt: now + 6 * 60 * 60 * 1000,
      keys: jwks.keys || []
    };
  }

  const jwk = appleKeysCache.keys.find((key) => key.kid === kid);
  if (!jwk) {
    throw new Error("No Apple public key matched the Sign in with Apple token.");
  }

  return crypto.subtle.importKey(
    "jwk",
    jwk,
    { name: "RSASSA-PKCS1-v1_5", hash: "SHA-256" },
    false,
    ["verify"]
  );
}

function validateAppleClaims(claims, audience) {
  const now = Math.floor(Date.now() / 1000);
  if (claims.iss !== "https://appleid.apple.com") {
    throw new Error("The Sign in with Apple token issuer is invalid.");
  }

  const audiences = Array.isArray(claims.aud) ? claims.aud : [claims.aud];
  if (!audiences.includes(audience)) {
    throw new Error("The Sign in with Apple token audience is invalid.");
  }

  if (typeof claims.exp !== "number" || claims.exp + 60 <= now) {
    throw new Error("The Sign in with Apple token is expired.");
  }

  if (typeof claims.iat === "number" && claims.iat - 60 > now) {
    throw new Error("The Sign in with Apple token was issued in the future.");
  }
}

function parseJWT(token) {
  const parts = token.split(".");
  if (parts.length !== 3 || parts.some((part) => !part)) {
    throw new Error("The bearer token is malformed.");
  }
  return { header: parts[0], payload: parts[1], signature: parts[2] };
}

function bearerToken(request) {
  const authorization = request.headers.get("Authorization") || "";
  if (!authorization.toLowerCase().startsWith("bearer ")) {
    throw new Error("A Sign in with Apple bearer token is required.");
  }

  const token = authorization.slice("Bearer ".length).trim();
  if (!token) {
    throw new Error("The bearer token is invalid.");
  }
  return token;
}

function plaidBaseURL(env) {
  const environment = plaidEnvironment(env);
  return PLAID_BASE_URLS[environment] || PLAID_BASE_URLS.sandbox;
}

function plaidEnvironment(env) {
  return (env.PLAID_ENVIRONMENT || "sandbox").toLowerCase();
}

function plaidSecret(env) {
  const environment = plaidEnvironment(env);
  const key = environment === "production"
    ? "PLAID_PRODUCTION_SECRET"
    : environment === "development"
      ? "PLAID_DEVELOPMENT_SECRET"
      : "PLAID_SANDBOX_SECRET";
  return env[key] || env.PLAID_SECRET || required(env, key);
}

function required(env, key) {
  const value = env[key];
  if (!value) {
    throw new BadRequestError(`${key} is not configured.`);
  }
  return value;
}

async function jsonBody(request) {
  if (!request.body) {
    return {};
  }

  try {
    return await request.json();
  } catch {
    throw new BadRequestError("Request body must be valid JSON.");
  }
}

function numberFromEnv(value, fallback) {
  const parsed = Number(value);
  return Number.isFinite(parsed) && parsed > 0 ? parsed : fallback;
}

function splitList(value) {
  return String(value || "")
    .split(",")
    .map((item) => item.trim())
    .filter(Boolean);
}

function hostAllowed(host, configuredHosts) {
  const hosts = splitList(configuredHosts).map((item) => item.toLowerCase());
  return hosts.length === 0 || hosts.includes(host);
}

function base64URLToBytes(value) {
  const base64 = value.replace(/-/g, "+").replace(/_/g, "/").padEnd(Math.ceil(value.length / 4) * 4, "=");
  const binary = atob(base64);
  return Uint8Array.from(binary, (character) => character.charCodeAt(0));
}

function base64URLToText(value) {
  return new TextDecoder().decode(base64URLToBytes(value));
}

function jsonResponse(body, status = 200, headers = {}) {
  return new Response(JSON.stringify(body), {
    status,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "application/json; charset=utf-8",
      ...headers
    }
  });
}

function htmlResponse(message) {
  return new Response(`<!doctype html><title>BudgetTracer</title><p>${escapeHTML(message)}</p>`, {
    status: 200,
    headers: {
      "Cache-Control": "no-store",
      "Content-Type": "text/html; charset=utf-8"
    }
  });
}

function emptyResponse(status) {
  return new Response(null, { status });
}

function plaidErrorResponse(error) {
  if (error instanceof PlaidAPIError) {
    return jsonResponse(error.body, error.status);
  }

  const status = error instanceof BadRequestError ? 400 : 500;
  return jsonResponse({ error: error.message || "Unexpected relay error." }, status);
}

function escapeHTML(value) {
  return value
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;");
}

class BadRequestError extends Error {}

class PlaidAPIError extends Error {
  constructor(status, body) {
    super("Plaid API request failed.");
    this.status = status;
    this.body = body;
  }
}
