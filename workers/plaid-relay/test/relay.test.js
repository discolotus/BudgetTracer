import assert from "node:assert/strict";
import test from "node:test";
import { handleRequest } from "../src/index.js";

const env = {
  PLAID_ENVIRONMENT: "sandbox",
  PLAID_CLIENT_ID: "client-id",
  PLAID_SANDBOX_SECRET: "sandbox-secret",
  PLAID_CLIENT_NAME: "BudgetTracer Dev",
  PLAID_PRODUCTS: "transactions",
  PLAID_COUNTRY_CODES: "US",
  PLAID_REDIRECT_URI: "https://budgettracer-plaid-relay-dev.example.workers.dev/plaid/oauth",
  APPLE_AUDIENCE: "com.budgettracer.ios",
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
