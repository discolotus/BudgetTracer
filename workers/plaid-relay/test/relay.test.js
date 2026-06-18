import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest, testInternals } from "../src/index.js";

const env = {
  RATE_LIMIT_SCOPE: "test",
  PLAID_ENVIRONMENT: "sandbox",
  PLAID_CLIENT_ID: "client-id",
  PLAID_SANDBOX_SECRET: "sandbox-secret",
  PLAID_CLIENT_NAME: "BudgetTracer Dev",
  PLAID_PRODUCTS: "transactions",
  PLAID_COUNTRY_CODES: "US",
  PLAID_REDIRECT_URI: "https://budgettracer-plaid-relay-dev.example.workers.dev/plaid/oauth",
  APPLE_AUDIENCES: "com.budgettracer.ios,com.budgettracer.mac",
  APPLE_APP_SITE_ASSOCIATION_APP_IDS: "TEAMID.com.budgettracer.ios,TEAMID.com.budgettracer.mac",
  DEV_BEARER_TOKEN: "local-dev-bearer-token-at-least-16-chars"
};

test("health exposes relay status", async () => {
  const response = await handleRequest(new Request("https://relay.example/health"), env);
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.status, "ok");
  assert.equal(body.plaid_environment, "sandbox");
});

test("serves Apple app site association for configured app IDs", async () => {
  const response = await handleRequest(
    new Request("https://app.example/.well-known/apple-app-site-association"),
    env
  );
  const body = await response.json();

  assert.equal(response.status, 200);
  assert.equal(body.applinks.details.length, 2);
  assert.deepEqual(body.applinks.details[0].appIDs, ["TEAMID.com.budgettracer.ios"]);
});

test("restricts owned-domain link routes to configured link hosts", async () => {
  const response = await handleRequest(
    new Request("https://api.budgettracer.app/.well-known/apple-app-site-association"),
    { ...env, LINK_HOSTS: "app.budgettracer.com" }
  );

  assert.equal(response.status, 404);
});

test("requires authorization for Plaid relay routes", async () => {
  const response = await handleRequest(
    new Request("https://relay.example/v1/plaid/link-token", {
      method: "POST",
      body: "{}"
    }),
    env
  );

  assert.equal(response.status, 401);
});

test("rate limits Plaid relay requests before auth", async () => {
  const preAuthLimiter = fakeRateLimiter(false);
  const response = await handleRequest(
    new Request("https://relay.example/v1/plaid/link-token", {
      method: "POST",
      headers: {
        "CF-Connecting-IP": "203.0.113.10"
      },
      body: "{}"
    }),
    {
      ...env,
      PLAID_RELAY_PREAUTH_RATE_LIMITER: preAuthLimiter
    }
  );
  const body = await response.json();

  assert.equal(response.status, 429);
  assert.equal(response.headers.get("Retry-After"), "60");
  assert.match(body.error, /Too many/);
  assert.deepEqual(preAuthLimiter.keys, ["test:preauth:203.0.113.10:/v1/plaid/link-token"]);
});

test("rate limits Plaid relay requests after auth by subject and route", async () => {
  const preAuthLimiter = fakeRateLimiter(true);
  const authLimiter = fakeRateLimiter(false);
  const response = await handleRequest(
    new Request("https://relay.example/v1/plaid/link-token", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.DEV_BEARER_TOKEN}`,
        "CF-Connecting-IP": "203.0.113.10"
      },
      body: "{}"
    }),
    {
      ...env,
      PLAID_RELAY_PREAUTH_RATE_LIMITER: preAuthLimiter,
      PLAID_RELAY_AUTH_RATE_LIMITER: authLimiter
    }
  );

  assert.equal(response.status, 429);
  assert.deepEqual(preAuthLimiter.keys, ["test:preauth:203.0.113.10:/v1/plaid/link-token"]);
  assert.deepEqual(authLimiter.keys, ["test:auth:dev-user:/v1/plaid/link-token"]);
});

test("accepts configured iOS and macOS Apple token audiences", () => {
  const audiences = testInternals.requiredAppleAudiences(env);
  assert.deepEqual(audiences, ["com.budgettracer.ios", "com.budgettracer.mac"]);

  const now = Math.floor(Date.now() / 1000);
  assert.doesNotThrow(() => testInternals.validateAppleClaims({
    iss: "https://appleid.apple.com",
    aud: "com.budgettracer.ios",
    exp: now + 300,
    iat: now
  }, audiences));
  assert.doesNotThrow(() => testInternals.validateAppleClaims({
    iss: "https://appleid.apple.com",
    aud: "com.budgettracer.mac",
    exp: now + 300,
    iat: now
  }, audiences));
  assert.throws(() => testInternals.validateAppleClaims({
    iss: "https://appleid.apple.com",
    aud: "com.other.app",
    exp: now + 300,
    iat: now
  }, audiences), /audience/);
});

test("keeps legacy single Apple audience configuration working", () => {
  assert.deepEqual(
    testInternals.requiredAppleAudiences({ APPLE_AUDIENCE: "com.budgettracer.ios" }),
    ["com.budgettracer.ios"]
  );
});

test("restricts owned-domain API routes to configured API hosts", async () => {
  const response = await handleRequest(
    new Request("https://app.budgettracer.com/v1/plaid/link-token", {
      method: "POST",
      headers: {
        Authorization: `Bearer ${env.DEV_BEARER_TOKEN}`
      },
      body: "{}"
    }),
    { ...env, API_HOSTS: "api.budgettracer.app" }
  );

  assert.equal(response.status, 404);
});

test("creates a Plaid link token using dev bearer bypass outside production", async () => {
  const originalFetch = globalThis.fetch;
  globalThis.fetch = async (url, init) => {
    assert.equal(url, "https://sandbox.plaid.com/link/token/create");
    const body = JSON.parse(init.body);
    assert.equal(body.client_id, "client-id");
    assert.equal(body.secret, "sandbox-secret");
    assert.equal(body.user.client_user_id, "dev-user");
    assert.equal(body.redirect_uri, env.PLAID_REDIRECT_URI);
    return Response.json({
      link_token: "link-sandbox-test",
      expiration: "2026-06-17T00:00:00Z",
      request_id: "request-1"
    });
  };

  try {
    const response = await handleRequest(
      new Request("https://relay.example/v1/plaid/link-token", {
        method: "POST",
        headers: {
          Authorization: `Bearer ${env.DEV_BEARER_TOKEN}`
        },
        body: "{}"
      }),
      env
    );
    const body = await response.json();

    assert.equal(response.status, 200);
    assert.equal(body.link_token, "link-sandbox-test");
  } finally {
    globalThis.fetch = originalFetch;
  }
});

function fakeRateLimiter(success) {
  return {
    keys: [],
    async limit({ key }) {
      this.keys.push(key);
      return { success };
    }
  };
}
