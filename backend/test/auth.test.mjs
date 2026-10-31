import { test, before, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { requireOwnedDevice } from "../src/device-reference.js";

// All identities and credentials below are synthetic. No network request is allowed.
const env = {
  FIREBASE_PROJECT_ID: "mock-project", FIREBASE_WEB_API_KEY: "mock-web-key",
  FIREBASE_CLIENT_EMAIL: "worker@example.invalid",
  FIREBASE_DATABASE_URL: "https://mock-database.invalid", IOT_API_KEY: "mock-iot-key", AI_API_KEY: "mock-ai-key"
};
const uid = "mock-firebase-uid";
const username = "solar_user";
const email = "test@example.invalid";
const password = "Mock-password-123";
const originalFetch = globalThis.fetch;
let state;
let calls;
const json = (body, status = 200) => Response.json(body, { status });
function idToken(overrides = {}) {
  const now = Math.floor(Date.now() / 1000);
  const claims = { sub: uid, aud: env.FIREBASE_PROJECT_ID,
    iss: `https://securetoken.google.com/${env.FIREBASE_PROJECT_ID}`,
    iat: now - 30, auth_time: now - 30, exp: now + 3600, ...overrides };
  // Synthetic token: Firebase verification is mocked, not bypassed in application code.
  return `mock.${Buffer.from(JSON.stringify(claims)).toString("base64url")}.mock`;
}
function indexRecord(status = "active", extra = {}) {
  return { uid, username, email, status, auth_provider: "firebase_auth", ...extra };
}
function profile(extra = {}) {
  return { username, email, role: "user", created_at: "2026-01-01T00:00:00.000Z", ...extra };
}
function account() {
  return { localId: uid, email, idToken: idToken(), refreshToken: "mock-refresh", expiresIn: "3600" };
}
async function request(path, { method = "GET", body, token, iot = false, headers = {} } = {}) {
  return worker.fetch(new Request(`https://worker.invalid${path}`, {
    method, headers: {
      ...(body !== undefined ? { "Content-Type": "application/json" } : {}),
      ...(token ? { Authorization: `Bearer ${token}` } : {}),
      ...(iot ? { "x-api-key": env.IOT_API_KEY } : {}), ...headers
    }, ...(body !== undefined ? { body: typeof body === "string" ? body : JSON.stringify(body) } : {})
  }), env);
}
before(async () => {
  const keys = await crypto.subtle.generateKey(
    { name: "RSASSA-PKCS1-v1_5", modulusLength: 2048, publicExponent: new Uint8Array([1, 0, 1]), hash: "SHA-256" }, true, ["sign", "verify"]
  );
  const der = await crypto.subtle.exportKey("pkcs8", keys.privateKey);
  env.FIREBASE_PRIVATE_KEY = `-----BEGIN PRIVATE KEY-----\n${Buffer.from(der).toString("base64")}\n-----END PRIVATE KEY-----`;
});
beforeEach(() => {
  state = { profile: null, authError: null, readFail: false, writeFail: false, rollbackFail: false };
  calls = [];
  globalThis.fetch = async (input, options = {}) => {
    const url = new URL(input);
    const body = options.body ? JSON.parse(options.body instanceof URLSearchParams ? "{}" : options.body) : null;
    calls.push({ url, options, body });
    if (url.origin === "https://oauth2.googleapis.com") return json({ access_token: "mock-oauth", expires_in: 3600 });
    if (url.origin === "https://identitytoolkit.googleapis.com") {
      if (url.pathname.endsWith(":delete")) {
        if (state.rollbackFail) throw new Error("mock network failure");
        return json({});
      }
      if (state.authError) return json({ error: { message: state.authError } }, state.authStatus || 400);
      if (url.pathname.endsWith(":lookup")) return json({ users: [{ localId: uid, email, emailVerified: false, ...state.lookup }] });
      if (url.pathname.endsWith(":signUp") && state.simultaneous) {
        state.signupCount = (state.signupCount || 0) + 1;
        return json({ ...account(), localId: state.signupCount === 1 ? uid : `${uid}-other`,
          idToken: idToken({ sub: state.signupCount === 1 ? uid : `${uid}-other` }) });
      }
      return json(account());
    }
    if (url.origin === env.FIREBASE_DATABASE_URL) {
      if (url.pathname.startsWith("/recommendations/")) {
        if (state.recommendationFail) return json({}, 503);
        if (state.recommendationNetworkFail) throw new Error("private recommendation failure");
        const [, , deviceId, date] = url.pathname.replace(/\.json$/, "").split("/");
        assert.equal(deviceId, "solar-001");
        if (options.method === "PUT") {
          state.recommendations ??= {};
          state.recommendations[date] = body;
          return json(body);
        }
        return json(state.recommendations?.[date] ?? null);
      }
      if (url.pathname.startsWith("/devices/")) {
        if (state.deviceFail) return json({}, 503);
        return json(state.device ?? null);
      }
      if (url.pathname.startsWith("/energy_predictions/")) {
        if (state.predictionFail) return json({}, 503);
        if (state.predictionNetworkFail) throw new Error("private upstream details");
        const parts = url.pathname.replace(/\.json$/, "").split("/");
        assert.equal(parts[2], "solar-001");
        if (options.method === "PUT") {
          assert.equal(options.headers["if-match"], "null_etag");
          state.predictions ??= {};
          if (state.predictions[parts[3]]) return json({}, 412);
          state.predictions[parts[3]] = body;
          return json(body);
        }
        if (parts[3]) return json(state.predictions?.[parts[3]] ?? null);
        assert.equal(url.searchParams.get("orderBy"), '"$key"');
        let entries = Object.entries(state.predictions || {}).sort(([a], [b]) => a.localeCompare(b));
        if (url.searchParams.has("limitToLast")) {
          assert.equal(url.searchParams.get("limitToLast"), "1");
          entries = entries.slice(-1);
        } else {
          const start = JSON.parse(url.searchParams.get("startAt"));
          const end = JSON.parse(url.searchParams.get("endAt"));
          entries = entries.filter(([date]) => date >= start && date <= end);
        }
        return json(Object.fromEntries(entries));
      }
      if (url.pathname === "/device_reference.json") {
        if (state.referenceFail) return json({}, 503);
        return json(state.references ?? null);
      }
      if (url.pathname.startsWith("/device_reference/")) {
        if (state.referenceFail) return json({}, 503);
        const id = url.pathname.split("/")[2].replace(".json", "");
        if (options.method === "PUT") {
          assert.equal(options.headers["if-match"], "null_etag");
          if (state.referenceDuplicate || state.references?.[id]) return json({}, 412);
          state.references ??= {};
          state.references[id] = body;
          return json(body);
        }
        return json(state.references?.[id] ?? null);
      }
      if (url.pathname.startsWith("/usernames/")) {
        assert.match(url.pathname, /^\/usernames\/[^/]+\.json$/);
        const existing = state.index !== undefined ? state.index : (state.profile ? indexRecord() : null);
        if (options.method === "PUT") {
          if (state.indexWriteFail) return json({}, 503);
          if (state.finalizeFail && body.status === "active") return json({}, 503);
          const match = options.headers["if-match"];
          if (match === "null_etag" && existing !== null) return json({}, 412);
          if (match !== "null_etag" && match !== '"mock-etag"') return json({}, 412);
          state.index = body;
          if (state.lostIndexResponse) { state.lostIndexResponse = false; throw new Error("mock lost index response"); }
          return json(body);
        }
        if (state.indexReadFail) return json({}, 503);
        return Response.json(existing, { headers: { etag: '"mock-etag"' } });
      }
      if (url.pathname.startsWith("/users/")) {
        assert.equal(url.pathname, `/users/${uid}.json`);
        if (options.method === "PUT") {
          assert.equal(options.headers["if-match"], "null_etag");
          if (state.writeFail) return json({}, 503);
          if (state.profile !== null) return json({}, 412);
          if (state.race) { state.profile = state.race; return json({}, 412); }
          state.profile = body;
          if (state.lostWriteResponse) throw new Error("mock lost write response");
          return json(body);
        }
        if (state.readFail) return json({}, 503);
        return json(state.profile);
      }
      if (url.pathname.startsWith("/sensor_readings/")) {
        if (options.method === "PUT") {
          state.sensorWrite = { path: url.pathname, body, headers: options.headers };
          return json({}, state.sensorStatus || 200);
        }
        const date = url.pathname.split("/")[3]?.replace(".json", "");
        return json(date === today() ? { reading: reading() } : null);
      }
    }
    throw new Error("Unexpected outbound request blocked by mock");
  };
});
afterEach(() => { globalThis.fetch = originalFetch; });

test("register creates Firebase UID profile without password/token and returns 201", async () => {
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 201);
  const result = await response.json();
  assert.equal(result.user.uid, uid);
  assert.equal(result.user.username, username);
  assert.equal(state.index.uid, uid);
  assert.equal(state.index.status, "active");
  assert.deepEqual(Object.keys(state.profile).sort(), ["created_at", "email", "role", "username"]);
  assert.equal(state.profile.role, "user");
  for (const field of ["password", "password_hash", "idToken", "refreshToken"]) assert.equal(state.profile[field], undefined);
  assert.equal(result.id_token, undefined);
  assert.equal(calls.find(c => c.url.pathname.endsWith(":signUp")).body.password, password);
});
test("duplicate email returns 409 without database write", async () => {
  state.authError = "EMAIL_EXISTS";
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } })).status, 409);
  assert.equal(state.profile, null);
});
test("invalid input, malformed JSON, media type and oversize body are rejected before Firebase", async () => {
  for (const [body, status] of [
    [{ username, email: "bad", password }, 422], [{ username, email, password: "short" }, 422],
    [{ username, email, password, role: "admin" }, 422], [[], 422], [null, 422], ["{", 400],
    [{ username, email, password: "x".repeat(5000) }, 413]
  ]) {
    assert.equal((await request("/api/v1/auth/register", { method: "POST", body })).status, status);
  }
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: "{}", headers: { "Content-Type": "text/plain" } })).status, 415);
  assert.equal(calls.length, 0);
});
test("Firebase password policy and invalid email errors are sanitized", async () => {
  for (const error of ["WEAK_PASSWORD : policy details", "PASSWORD_DOES_NOT_MEET_REQUIREMENTS", "INVALID_EMAIL"]) {
    state.authError = error;
    const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
    assert.equal(response.status, 422);
    assert.ok(!(await response.text()).includes("policy details"));
  }
});
test("login returns Firebase session and allowlisted profile", async () => {
  state.profile = profile({ refresh_token: "sensitive-field" });
  const response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.id_token, account().idToken);
  assert.equal(result.refresh_token, "mock-refresh");
  assert.equal(result.expires_in, 3600);
  assert.equal(result.user.uid, uid);
  assert.equal(result.user.password_hash, undefined);
  assert.equal(result.user.refresh_token, undefined);
  assert.equal(response.headers.get("Cache-Control"), "no-store");
});
test("wrong password, unknown email and disabled user return same safe error", async () => {
  state.profile = profile();
  let expected;
  for (const error of ["INVALID_PASSWORD", "EMAIL_NOT_FOUND", "INVALID_LOGIN_CREDENTIALS", "USER_DISABLED"]) {
    state.authError = error;
    const response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
    assert.equal(response.status, 401);
    const text = await response.text();
    expected ??= text;
    assert.equal(text, expected);
  }
});
test("me sends ID token to Firebase verification and uses verified UID", async () => {
  state.profile = profile({ arbitrary: "private" });
  const token = idToken();
  const response = await request("/api/v1/auth/me?uid=attacker", { token });
  assert.equal(response.status, 200);
  assert.equal(calls.find(c => c.url.pathname.endsWith(":lookup")).body.idToken, token);
  assert.equal((await response.json()).user.uid, uid);
  assert.equal(state.profile.username, username);
});
test("me rejects missing or malformed bearer before outbound requests", async () => {
  for (const authorization of ["", "Basic abc", "Bearer a b"]) {
    const response = await request("/api/v1/auth/me", { headers: { Authorization: authorization } });
    assert.equal(response.status, 401);
  }
  assert.equal(calls.length, 0);
});
test("Firebase rejects invalid token even with otherwise valid decoded claims", async () => {
  state.authError = "INVALID_ID_TOKEN";
  const response = await request("/api/v1/auth/me", { token: idToken() });
  assert.equal(response.status, 401);
  assert.equal(calls.filter(c => c.url.origin === env.FIREBASE_DATABASE_URL).length, 0);
});
test("me rejects expired, wrong project, wrong UID, future and revoked tokens", async () => {
  for (const claims of [
    { exp: 1 }, { aud: "other-project" }, { iss: "other-issuer" }, { sub: "attacker" },
    { iat: 9999999999 }, { auth_time: 9999999999 }, { exp: "9999999999" }
  ]) assert.equal((await request("/api/v1/auth/me", { token: idToken(claims) })).status, 401);
  state.lookup = { validSince: String(Math.floor(Date.now() / 1000)) };
  assert.equal((await request("/api/v1/auth/me", { token: idToken() })).status, 401);
  state.lookup = { disabled: true };
  assert.equal((await request("/api/v1/auth/me", { token: idToken() })).status, 401);
});
test("legacy profile conflict never overwrites existing user", async () => {
  state.profile = { user_id: uid, username: "old-user", password_hash: "old-hash", role: "admin" };
  state.index = null;
  const original = structuredClone(state.profile);
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 503);
  assert.deepEqual(state.profile, original);
  assert.ok(!calls.some(c => c.options.method === "PUT" && c.url.pathname.startsWith("/users/")));
});
test("profile failure leaves pending reservation and login recovers it", async () => {
  state.writeFail = true;
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "REGISTRATION_RECOVERY_REQUIRED");
  assert.equal(state.index.status, "pending");
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
  state.writeFail = false;
  const login = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(login.status, 200);
  assert.equal(state.profile.username, username);
  assert.equal(state.index.status, "active");
});
test("login profile failure never deletes existing Auth account", async () => {
  state.index = indexRecord();
  state.readFail = true;
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { username, password } })).status, 503);
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("lost profile write response remains recoverable without deletion", async () => {
  state.lostWriteResponse = true;
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } })).status, 503);
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { username, password } })).status, 200);
  assert.equal(state.profile.username, username);
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("unknown profile state keeps account recoverable without blind deletion", async () => {
  state.readFail = true;
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "REGISTRATION_RECOVERY_REQUIRED");
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("conditional profile creation handles concurrent creation safely", async () => {
  state.race = profile();
  state.index = indexRecord("pending");
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { username, password } })).status, 200);
  assert.deepEqual(state.profile, state.race);
});
test("missing profile on me does not silently write database", async () => {
  assert.equal((await request("/api/v1/auth/me", { token: idToken() })).status, 409);
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});
test("upstream errors and rate limits do not expose provider details", async () => {
  state.profile = profile();
  state.authError = "sensitive-provider-message";
  let response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes(state.authError));
  state.authError = "TOO_MANY_ATTEMPTS_TRY_LATER";
  response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(response.status, 429);
});
test("unknown username and incorrect password return identical generic errors", async () => {
  const unknown = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(unknown.status, 401);
  const expected = await unknown.json();
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":signInWithPassword")));
  state.profile = profile();
  state.authError = "INVALID_PASSWORD";
  const wrong = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(wrong.status, 401);
  assert.deepEqual(await wrong.json(), expected);
});
test("login accepts username/password only and uses email internally", async () => {
  state.profile = profile();
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { username, email, password } })).status, 422);
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { email, password } })).status, 422);
  const response = await request("/api/v1/auth/login", { method: "POST", body: { username: ' SOLAR_USER ', password } });
  assert.equal(response.status, 200);
  const internal = calls.find(c => c.url.pathname.endsWith(":signInWithPassword"));
  assert.deepEqual(internal.body, { email, password, returnSecureToken: true });
});
test("duplicate normalized username preserves existing owner and removes losing Auth account", async () => {
  state.index = indexRecord("active", { uid: "another-uid" });
  const original = structuredClone(state.index);
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username: ' SOLAR_USER ', email, password } });
  assert.equal(response.status, 409);
  assert.equal((await response.json()).code, "USERNAME_EXISTS");
  assert.deepEqual(state.index, original);
  assert.equal(state.profile, null);
  assert.ok(calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("simultaneous registrations have exactly one owner and one successful response", async () => {
  state.simultaneous = true;
  const responses = await Promise.all([email, "second@example.invalid"].map(registrationEmail => request("/api/v1/auth/register", { method: "POST", body: { username, email: registrationEmail, password } })));
  assert.deepEqual(responses.map(r => r.status).sort(), [201, 409]);
  assert.equal(state.index.uid, uid);
  assert.equal(state.profile.username, username);
  assert.equal(calls.filter(c => c.url.pathname.endsWith(":delete")).length, 1);
});
test("legacy scalar username mapping is rejected without attempting Firebase login", async () => {
  state.index = "old-fastapi-uuid";
  const response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(response.status, 401);
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":signInWithPassword")));
  const registered = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(registered.status, 409);
  assert.equal(state.index, "old-fastapi-uuid");
});
test("failed username write compensates Auth creation without writing profile", async () => {
  state.indexWriteFail = true;
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 503);
  assert.equal(state.profile, null);
  assert.ok(calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("failed losing-account cleanup returns recovery error and never touches winner", async () => {
  state.index = indexRecord("active", { uid: "another-uid" });
  state.rollbackFail = true;
  const response = await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } });
  assert.equal(response.status, 503);
  assert.equal((await response.json()).code, "REGISTRATION_RECOVERY_REQUIRED");
  assert.equal(state.index.uid, "another-uid");
});
test("ambiguous username claim is reconciled without deleting successful registration", async () => {
  state.lostIndexResponse = true;
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } })).status, 201);
  assert.equal(state.index.status, "active");
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("unknown username write outcome is reported without blind compensation", async () => {
  state.indexWriteFail = true;
  state.indexReadFail = true;
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } })).status, 503);
  assert.ok(!calls.some(c => c.url.pathname.endsWith(":delete")));
});
test("failed finalization keeps pending index recoverable on next authenticated login", async () => {
  state.finalizeFail = true;
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password } })).status, 503);
  assert.equal(state.index.status, "pending");
  state.finalizeFail = false;
  assert.equal((await request("/api/v1/auth/login", { method: "POST", body: { username, password } })).status, 200);
  assert.equal(state.index.status, "active");
});
test("login rejects mismatched Firebase UID without releasing credentials", async () => {
  state.profile = profile();
  state.index = indexRecord("active", { uid: "another-uid" });
  const response = await request("/api/v1/auth/login", { method: "POST", body: { username, password } });
  assert.equal(response.status, 401);
  assert.equal((await response.json()).id_token, undefined);
});
test("invalid username and missing registration email are rejected locally", async () => {
  for (const name of ["ab", "a".repeat(31)]) {
    assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username: name, email, password } })).status, 422);
  }
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, password } })).status, 422);
  assert.equal(calls.length, 0);
});
test("user-chosen symbols, spaces and Unicode work through register, login and me", async () => {
  for (const name of ["a.b", "a/b", "a#$[]", "Nama Saya", "用户名字", "☀️solar", "😀".repeat(30), "a".repeat(3), "z".repeat(30), "~YWJj"]) {
    state.profile = null;
    state.index = null;
    const normalized = name.trim().toLowerCase();
    const registered = await request("/api/v1/auth/register", { method: "POST", body: { username: name, email, password } });
    assert.equal(registered.status, 201, name);
    assert.equal((await registered.json()).user.username, normalized);
    assert.equal(state.profile.username, normalized);
    const login = await request("/api/v1/auth/login", { method: "POST", body: { username: name, password } });
    assert.equal(login.status, 200, name);
    const me = await request("/api/v1/auth/me", { token: idToken() });
    assert.equal(me.status, 200, name);
    assert.equal((await me.json()).user.username, normalized);
  }
});
test("special-character username keys are safe, distinct and consistent on read/write", async () => {
  const paths = new Set();
  for (const name of ["a/b", "a.b", "~YS9i", "a?b", "a#b"]) {
    state.profile = null;
    state.index = null;
    calls = [];
    assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username: name, email, password } })).status, 201);
    const indexCalls = calls.filter(c => c.url.pathname.startsWith("/usernames/"));
    const path = indexCalls[0].url.pathname;
    assert.match(path, /^\/usernames\/~[A-Za-z0-9_-]+\.json$/);
    assert.ok(indexCalls.every(c => c.url.pathname === path));
    assert.ok(!paths.has(path));
    paths.add(path);
  }
  for (const name of ["😀".repeat(2), "😀".repeat(31)]) {
    assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username: name, email, password } })).status, 422);
  }
});
test("auth methods are enforced without IOT key", async () => {
  assert.equal((await request("/api/v1/auth/login")).status, 405);
  assert.equal((await request("/api/v1/auth/me", { method: "POST" })).status, 405);
  assert.equal(calls.length, 0);
});

function today() {
  return new Intl.DateTimeFormat("en-CA", { timeZone: "Asia/Jakarta", year: "numeric", month: "2-digit", day: "2-digit" }).format(new Date());
}

const predictionRoot = "/api/v1/ai/predictions";
const predictionInput = { device_id: "solar-001", prediction_date: "2026-11-02", predicted_energy_wh: 125.75 };
const aiHeaders = { "x-api-key": env.AI_API_KEY };
function prediction(date, extra = {}) {
  return { ...predictionInput, prediction_date: date, model_name: "Linear Regression", created_at: "2026-11-01T00:00:00.000Z", ...extra };
}
function ownedDevice() {
  state.profile = profile();
  state.device = { device_id: "solar-001", owner_uid: uid };
}
test("predictions: AI stores actual-energy Wh forecast using compatible contract", async () => {
  state.device = { device_id: "solar-001" };
  const response = await request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput });
  assert.equal(response.status, 201);
  const result = await response.json();
  assert.equal(result.status, "saved");
  assert.equal(result.data.predicted_energy_wh, 125.75);
  assert.equal(result.data.model_name, "Linear Regression");
  assert.equal(result.data.device_id, "solar-001");
  assert.equal(result.data.prediction_date, "2026-11-02");
  assert.deepEqual(state.predictions["2026-11-02"], result.data);
  assert.deepEqual(Object.keys(result.data).sort(), ["created_at", "device_id", "model_name", "predicted_energy_wh", "prediction_date"]);
});
test("predictions: duplicate and simultaneous writes cannot overwrite device/date", async () => {
  ownedDevice();
  const responses = await Promise.all([1, 2].map(() => request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })));
  assert.deepEqual(responses.map(r => r.status).sort(), [201, 409]);
  const original = structuredClone(state.predictions);
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: { ...predictionInput, predicted_energy_wh: 999 } })).status, 409);
  assert.deepEqual(state.predictions, original);
});
test("predictions: latest uses greatest prediction date and excludes private fields", async () => {
  ownedDevice();
  state.predictions = { "2026-11-01": prediction("2026-11-01"), "2026-11-03": prediction("2026-11-03", { private: "hidden" }), "2026-11-02": prediction("2026-11-02") };
  const response = await request(`${predictionRoot}/latest?device_id=solar-001`, { token: idToken() });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.status, "success");
  assert.equal(result.data.prediction_date, "2026-11-03");
  assert.equal(result.data.private, undefined);
});
test("predictions: history is inclusive, ordered and limited to requested date range", async () => {
  ownedDevice();
  state.predictions = Object.fromEntries(["2026-11-03", "2026-11-01", "2026-11-02", "2026-10-31"].map(date => [date, prediction(date)]));
  const response = await request(`${predictionRoot}/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02`, { token: idToken() });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "success", device_id: "solar-001", start_date: "2026-11-01", end_date: "2026-11-02", total_predictions: 2,
    data: [prediction("2026-11-01"), prediction("2026-11-02")] });
});
test("predictions: missing device/latest yields 404; empty history yields empty array", async () => {
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })).status, 404);
  ownedDevice();
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`, { token: idToken() })).status, 404);
  const response = await request(`${predictionRoot}/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-01`, { token: idToken() });
  assert.equal(response.status, 200);
  assert.equal((await response.json()).total_predictions, 0);
});
test("predictions: POST rejects IoT key, user/admin JWT and missing/wrong AI key", async () => {
  ownedDevice();
  state.profile = profile({ role: "admin" });
  for (const options of [{}, { iot: true }, { token: idToken() }, { headers: { "x-api-key": "wrong" } }]) {
    assert.equal((await request(predictionRoot, { method: "POST", body: predictionInput, ...options })).status, 401);
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/energy_predictions/")));
});
test("predictions: absent or reused AI secret fails closed", async () => {
  const invoke = AI_API_KEY => worker.fetch(new Request(`https://worker.invalid${predictionRoot}`, { method: "POST", headers: aiHeaders }), { ...env, AI_API_KEY });
  assert.equal((await invoke(undefined)).status, 503);
  assert.equal((await invoke(env.IOT_API_KEY)).status, 503);
  assert.equal(calls.length, 0);
});
test("predictions: invalid input including negative/nonfinite energy and unsafe IDs", async () => {
  for (const body of [null, [], {}, { ...predictionInput, device_id: "bad/id" }, { ...predictionInput, prediction_date: "2026-02-30" },
    { ...predictionInput, prediction_date: "0000-01-01" }, { ...predictionInput, predicted_energy_wh: -1 },
    { ...predictionInput, predicted_energy_wh: true }, { ...predictionInput, predicted_energy_wh: "10" },
    '{"device_id":"solar-001","prediction_date":"2026-11-02","predicted_energy_wh":1e400}',
    { ...predictionInput, model_name: " " }, { ...predictionInput, owner_uid: uid }]) {
    assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body })).status, 422);
  }
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});
test("predictions: zero energy and explicit model name are accepted", async () => {
  ownedDevice();
  const response = await request(predictionRoot, { method: "POST", headers: aiHeaders, body: { ...predictionInput, predicted_energy_wh: 0, model_name: "Linear Regression v2" } });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).data.predicted_energy_wh, 0);
});
test("predictions: users cannot read unowned/unassigned/missing devices, even as admin", async () => {
  for (const device of [null, { device_id: "solar-001" }, { device_id: "solar-001", owner_uid: "other-user" }]) {
    state.device = device;
    state.profile = profile({ role: "admin" });
    for (const suffix of ["latest?device_id=solar-001", "history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02"]) {
      assert.equal((await request(`${predictionRoot}/${suffix}`, { token: idToken({ uid: "other-user" }) })).status, 404);
    }
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/energy_predictions/")));
});
test("predictions: reads reject missing/expired/invalid tokens and AI/IoT keys alone", async () => {
  ownedDevice();
  for (const suffix of ["latest?device_id=solar-001", "history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02"]) {
    for (const options of [{}, { iot: true }, { headers: aiHeaders }, { token: idToken({ exp: 1 }) }]) {
      assert.equal((await request(`${predictionRoot}/${suffix}`, options)).status, 401);
    }
    state.authError = "INVALID_ID_TOKEN";
    assert.equal((await request(`${predictionRoot}/${suffix}`, { token: idToken() })).status, 401);
    state.authError = null;
  }
});
test("predictions: history rejects bad dates, reversed/oversized ranges and accepts 31 days", async () => {
  ownedDevice();
  for (const [query, status] of [["", 422], ["&start_date=2026-02-30&end_date=2026-03-01", 422],
    ["&start_date=2026-11-02&end_date=2026-11-01", 400], ["&start_date=2026-10-01&end_date=2026-11-01", 400],
    ["&start_date=2026-10-01&end_date=2026-10-31", 200]]) {
    assert.equal((await request(`${predictionRoot}/history?device_id=solar-001${query}`, { token: idToken() })).status, status);
  }
  assert.equal((await request(`${predictionRoot}/latest`, { token: idToken() })).status, 422);
  assert.equal((await request(`${predictionRoot}/latest?device_id=bad.id`, { token: idToken() })).status, 422);
});
test("predictions: upstream failures and corrupt stored predictions fail safely", async () => {
  ownedDevice();
  state.predictionFail = true;
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })).status, 503);
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`, { token: idToken() })).status, 503);
  state.predictionFail = false;
  state.predictionNetworkFail = true;
  const response = await request(`${predictionRoot}/latest?device_id=solar-001`, { token: idToken() });
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes("private upstream"));
  state.predictionNetworkFail = false;
  state.predictions = { "2026-11-02": prediction("2026-11-02", { device_id: "other-device" }) };
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`, { token: idToken() })).status, 503);
});
test("predictions: request size, JSON, media type and HTTP method are enforced", async () => {
  for (const [body, headers, status] of [["{", aiHeaders, 400], [predictionInput, { ...aiHeaders, "Content-Type": "text/plain" }, 415],
    [{ ...predictionInput, model_name: "x".repeat(5000) }, aiHeaders, 413]]) {
    assert.equal((await request(predictionRoot, { method: "POST", body, headers })).status, status);
  }
  assert.equal((await request(predictionRoot)).status, 405);
  assert.equal((await request(`${predictionRoot}/latest`, { method: "POST" })).status, 405);
  assert.equal((await request(`${predictionRoot}/history`, { method: "POST" })).status, 405);
});

const recommendationRoot = "/api/v1/ai/recommendations";
const recommendationItem = { reference_id: "lamp", device_name: "Lampu LED", category: "Penerangan", power_w: 10, estimated_duration_hours: 7.25 };
function recommendationInput(extra = {}) {
  return { device_id: "solar-001", prediction_date: "2026-11-02", recommendations: [{ ...recommendationItem }], ...extra };
}
function prepareRecommendations() {
  ownedDevice();
  state.predictions = { "2026-11-02": prediction("2026-11-02") };
  state.references = { lamp: reference("lamp") };
}
const recommendationQuery = `${recommendationRoot}?device_id=solar-001&prediction_date=2026-11-02`;
test("recommendations: AI-supplied duration is preserved and owner reads compatible response", async () => {
  prepareRecommendations();
  const response = await request(recommendationRoot, { method: "POST", headers: aiHeaders, body: recommendationInput() });
  assert.equal(response.status, 201);
  const saved = await response.json();
  assert.equal(saved.status, "saved");
  assert.equal(saved.data.predicted_energy_wh, 125.75);
  assert.equal(saved.data.recommendations[0].estimated_duration_hours, 7.25);
  assert.deepEqual(Object.keys(saved.data).sort(), ["created_at", "device_id", "predicted_energy_wh", "prediction_date", "recommendations"]);
  const read = await request(recommendationQuery, { token: idToken() });
  assert.equal(read.status, 200);
  assert.deepEqual(await read.json(), { status: "success", data: saved.data });
});
test("recommendations: repeat submissions upsert one device/date as in FastAPI", async () => {
  prepareRecommendations();
  for (const duration of [7.25, 9]) {
    const body = recommendationInput({ recommendations: [{ ...recommendationItem, estimated_duration_hours: duration }] });
    assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body })).status, 201);
  }
  assert.equal(Object.keys(state.recommendations).length, 1);
  assert.equal(state.recommendations["2026-11-02"].recommendations[0].estimated_duration_hours, 9);
});
test("recommendations: missing record, device, prediction and reference are handled", async () => {
  prepareRecommendations();
  assert.equal((await request(recommendationQuery, { token: idToken() })).status, 404);
  for (const field of ["device", "predictions", "references"]) {
    prepareRecommendations();
    state[field] = null;
    assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body: recommendationInput() })).status, 404);
  }
  prepareRecommendations();
  state.references = {};
  assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body: recommendationInput() })).status, 404);
});
test("recommendations: POST requires AI key and rejects user JWT or IoT key", async () => {
  prepareRecommendations();
  for (const options of [{}, { iot: true }, { token: idToken() }, { headers: { "x-api-key": "wrong" } }]) {
    assert.equal((await request(recommendationRoot, { method: "POST", body: recommendationInput(), ...options })).status, 401);
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/recommendations/")));
});
test("recommendations: GET needs valid Firebase token and owns the physical device", async () => {
  prepareRecommendations();
  for (const options of [{}, { headers: aiHeaders }, { iot: true }, { token: idToken({ exp: 1 }) }]) {
    assert.equal((await request(recommendationQuery, options)).status, 401);
  }
  state.authError = "INVALID_ID_TOKEN";
  assert.equal((await request(recommendationQuery, { token: idToken() })).status, 401);
  state.authError = null;
  state.profile = profile({ role: "admin" });
  for (const device of [null, { device_id: "solar-001" }, { device_id: "solar-001", owner_uid: "other-user" }]) {
    state.device = device;
    assert.equal((await request(recommendationQuery, { token: idToken() })).status, 404);
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/recommendations/")));
});
test("recommendations: invalid input, empty items and duplicate references are rejected", async () => {
  prepareRecommendations();
  for (const body of [null, [], {}, recommendationInput({ device_id: "bad/id" }), recommendationInput({ prediction_date: "2026-02-30" }),
    recommendationInput({ recommendations: [] }), recommendationInput({ recommendations: [recommendationItem, recommendationItem] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, estimated_duration_hours: -1 }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, estimated_duration_hours: "7" }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, power_w: 0 }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, reference_id: "bad/id" }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, password: "forbidden" }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, device_name: " " }] }),
    recommendationInput({ predicted_energy_wh: -1 }), recommendationInput({ owner_uid: uid })]) {
    assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body })).status, 422);
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/recommendations/")));
});
test("recommendations: mismatching prediction/reference data cannot be persisted", async () => {
  prepareRecommendations();
  const bodies = [recommendationInput({ predicted_energy_wh: 999 }),
    recommendationInput({ recommendations: [{ ...recommendationItem, power_w: 20 }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, device_name: "Other" }] }),
    recommendationInput({ recommendations: [{ ...recommendationItem, category: "Other" }] })];
  for (const body of bodies) {
    assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body })).status, 422);
  }
  assert.equal(state.recommendations, undefined);
});
test("recommendations: zero duration accepted and AI durations sorted descending", async () => {
  prepareRecommendations();
  state.references.fan = reference("fan", { device_name: "Kipas", power_w: 20 });
  const body = recommendationInput({ predicted_energy_wh: 125.75, recommendations: [
    { ...recommendationItem, estimated_duration_hours: 0 },
    { reference_id: "fan", device_name: "Kipas", category: "Penerangan", power_w: 20, estimated_duration_hours: 10 }
  ] });
  const response = await request(recommendationRoot, { method: "POST", headers: aiHeaders, body });
  assert.equal(response.status, 201);
  assert.deepEqual((await response.json()).data.recommendations.map(r => r.estimated_duration_hours), [10, 0]);
});
test("recommendations: GET validates query and corrupt stored records", async () => {
  prepareRecommendations();
  for (const query of ["", "?device_id=bad.id&prediction_date=2026-11-02", "?device_id=solar-001", "?device_id=solar-001&prediction_date=2026-02-30"]) {
    assert.equal((await request(recommendationRoot + query, { token: idToken() })).status, 422);
  }
  state.recommendations = { "2026-11-02": { ...recommendationInput(), predicted_energy_wh: 125.75, created_at: "2026-11-01T00:00:00Z", device_id: "other-device" } };
  assert.equal((await request(recommendationQuery, { token: idToken() })).status, 503);
});
test("recommendations: upstream failure is sanitized and methods/media/size enforced", async () => {
  prepareRecommendations();
  state.recommendationFail = true;
  assert.equal((await request(recommendationRoot, { method: "POST", headers: aiHeaders, body: recommendationInput() })).status, 503);
  assert.equal((await request(recommendationQuery, { token: idToken() })).status, 503);
  state.recommendationFail = false;
  state.recommendationNetworkFail = true;
  const failed = await request(recommendationQuery, { token: idToken() });
  assert.equal(failed.status, 503);
  assert.ok(!(await failed.text()).includes("private recommendation"));
  for (const [body, headers, status] of [["{", aiHeaders, 400], [recommendationInput(), { ...aiHeaders, "Content-Type": "text/plain" }, 415],
    [recommendationInput({ padding: "x".repeat(5000) }), aiHeaders, 413]]) {
    assert.equal((await request(recommendationRoot, { method: "POST", headers, body })).status, status);
  }
  assert.equal((await request(recommendationRoot, { method: "DELETE" })).status, 405);
});

const referenceRoot = "/api/v1/device-reference";
const referenceInput = { device_name: "Lampu LED", category: "Penerangan", power_w: 10 };
function reference(id, extra = {}) {
  return { reference_id: id, ...referenceInput, created_at: "2026-01-01T00:00:00.000Z", ...extra };
}
test("device reference: admin creates compatible record and user reads list/detail", async () => {
  state.profile = profile({ role: "admin" });
  const response = await request(referenceRoot, { method: "POST", token: idToken(), body: referenceInput });
  assert.equal(response.status, 201);
  const result = await response.json();
  assert.equal(result.status, "saved");
  assert.match(result.data.reference_id, /^[0-9a-f-]{36}$/);
  assert.equal(result.data.power_w, 10);
  assert.deepEqual(Object.keys(result.data).sort(), ["category", "created_at", "device_name", "power_w", "reference_id"]);
  state.profile = profile();
  const list = await request(referenceRoot, { token: idToken() });
  assert.equal(list.status, 200);
  assert.deepEqual(await list.json(), { status: "success", total_devices: 1, data: [result.data] });
  const detail = await request(`${referenceRoot}/${result.data.reference_id}`, { token: idToken() });
  assert.deepEqual(await detail.json(), { status: "success", data: result.data });
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/devices/")));
});
test("device reference: empty catalog and missing detail", async () => {
  state.profile = profile();
  assert.deepEqual(await (await request(referenceRoot, { token: idToken() })).json(), { status: "success", total_devices: 0, data: [] });
  assert.equal((await request(`${referenceRoot}/missing`, { token: idToken() })).status, 404);
});
test("device reference: list is sorted and private fields are excluded", async () => {
  state.profile = profile();
  state.references = { z: reference("z", { device_name: "Zebra", private: "secret" }), a: reference("a", { device_name: "air" }) };
  const result = await (await request(referenceRoot, { token: idToken() })).json();
  assert.deepEqual(result.data.map(r => r.reference_id), ["a", "z"]);
  assert.equal(result.data[1].private, undefined);
});
test("device reference: all operations reject missing/invalid tokens and IoT key alone", async () => {
  for (const [path, method] of [[referenceRoot, "GET"], [referenceRoot, "POST"], [`${referenceRoot}/abc`, "GET"]]) {
    assert.equal((await request(path, { method, iot: true })).status, 401);
    state.authError = "INVALID_ID_TOKEN";
    assert.equal((await request(path, { method, token: idToken() })).status, 401);
    state.authError = null;
    assert.equal((await request(path, { method, token: idToken({ exp: 1 }) })).status, 401);
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/device_reference")));
});
test("device reference: regular user cannot create or spoof admin", async () => {
  state.profile = profile();
  const response = await request(referenceRoot, { method: "POST", token: idToken({ role: "admin" }), body: { ...referenceInput, role: "admin" } });
  assert.equal(response.status, 403);
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});
test("device reference: invalid input and unsafe IDs are rejected", async () => {
  state.profile = profile({ role: "admin" });
  for (const body of [null, [], {}, { ...referenceInput, device_name: " " },
    { ...referenceInput, device_name: "x".repeat(101) }, { ...referenceInput, category: "" },
    { ...referenceInput, category: "x".repeat(51) }, { ...referenceInput, power_w: 0 },
    { ...referenceInput, power_w: -1 }, { ...referenceInput, power_w: "10" },
    { ...referenceInput, power_w: true }, { ...referenceInput, reference_id: "client-id" }]) {
    assert.equal((await request(referenceRoot, { method: "POST", token: idToken(), body })).status, 422);
  }
  for (const suffix of ["a%2Fb", "bad.id", "%23", "x".repeat(121), "%zz", "a/b"]) {
    assert.equal((await request(`${referenceRoot}/${suffix}`, { token: idToken() })).status, 422);
  }
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});
test("device reference: JSON, content type, body limit and method enforcement", async () => {
  state.profile = profile({ role: "admin" });
  for (const [body, headers, status] of [["{", {}, 400], [referenceInput, { "Content-Type": "text/plain" }, 415],
    [{ ...referenceInput, device_name: "x".repeat(5000) }, {}, 413]]) {
    assert.equal((await request(referenceRoot, { method: "POST", token: idToken(), body, headers })).status, status);
  }
  assert.equal((await request(referenceRoot, { method: "DELETE", token: idToken() })).status, 405);
  assert.equal((await request(`${referenceRoot}/abc`, { method: "POST", token: idToken(), body: referenceInput })).status, 405);
});
test("device reference: duplicate generated ID returns 409 without overwrite", async () => {
  state.profile = profile({ role: "admin" });
  state.referenceDuplicate = true;
  state.references = { old: reference("old") };
  const original = structuredClone(state.references);
  const response = await request(referenceRoot, { method: "POST", token: idToken(), body: referenceInput });
  assert.equal(response.status, 409);
  assert.deepEqual(state.references, original);
});
test("device reference: database failures and malformed stored data fail safely", async () => {
  state.profile = profile({ role: "admin" });
  state.referenceFail = true;
  for (const [path, method, body] of [[referenceRoot, "GET"], [`${referenceRoot}/abc`, "GET"], [referenceRoot, "POST", referenceInput]]) {
    assert.equal((await request(path, { method, body, token: idToken() })).status, 503);
  }
  state.referenceFail = false;
  state.references = { abc: { malformed: true } };
  assert.equal((await request(referenceRoot, { token: idToken() })).status, 503);
  assert.equal((await request(`${referenceRoot}/abc`, { token: idToken() })).status, 503);
});
test("physical device ownership guard accepts only verified UID's assigned devices", async () => {
  const device = { device_id: "solar-001", owner_uid: uid };
  const authenticated = new Request("https://worker.invalid", { headers: { Authorization: `Bearer ${idToken()}` } });
  const readerFor = (stored, status = 200) => async (_env, path) => {
    if (path === `users/${uid}`) return json(profile());
    assert.equal(path, "devices/solar-001");
    return json(stored, status);
  };
  assert.deepEqual(await requireOwnedDevice(authenticated, env, readerFor(device), "solar-001"), device);
  for (const stored of [null, { device_id: "solar-001" }, { owner_uid: "other-user" }]) {
    await assert.rejects(requireOwnedDevice(authenticated, env, readerFor(stored), "solar-001"), e => e.status === 404);
  }
  await assert.rejects(requireOwnedDevice(new Request("https://worker.invalid?uid=" + uid), env, readerFor(device), "solar-001"), e => e.status === 401);
  await assert.rejects(requireOwnedDevice(authenticated, env, readerFor(device), "bad/id"), e => e.status === 422);
  await assert.rejects(requireOwnedDevice(authenticated, env, readerFor({}, 503), "solar-001"), e => e.status === 503);
});
function reading() {
  return { reading_id: "mock-reading", device_id: "solar-001", timestamp: new Date().toISOString(),
    voltage_v: 12, current_a: 2, interval_seconds: 60, power_w: 24, energy_wh: 0.4 };
}
const monitoringReads = ["/api/v1/monitoring/latest", "/api/v1/monitoring/history", "/api/v1/monitoring/daily-summary", "/api/v1/monitoring/daily-history"];
test("monitoring security: all reads require authentic unexpired Firebase tokens", async () => {
  ownedDevice();
  for (const path of monitoringReads) {
    for (const options of [{}, { iot: true }, { headers: aiHeaders }, { token: idToken({ exp: 1 }) }, { token: idToken({ aud: "other-project" }) }]) {
      assert.equal((await request(path, options)).status, 401);
    }
    state.authError = "INVALID_ID_TOKEN";
    assert.equal((await request(path, { token: idToken() })).status, 401);
    state.authError = null;
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/sensor_readings/")));
});
test("monitoring security: missing owner and other owner's device rejected even for admin", async () => {
  ownedDevice();
  state.profile = profile({ role: "admin" });
  for (const device of [null, { device_id: "solar-001" }, { device_id: "solar-001", owner_uid: "other-user" }]) {
    state.device = device;
    for (const path of monitoringReads) {
      assert.equal((await request(`${path}?device_id=solar-001&owner_uid=${uid}&uid=${uid}`, { token: idToken({ role: "admin", owner_uid: "other-user" }) })).status, 404);
    }
  }
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/sensor_readings/")));
});
test("monitoring security: authorization changes take effect on each request", async () => {
  ownedDevice();
  assert.equal((await request(monitoringReads[0], { token: idToken() })).status, 200);
  state.device.owner_uid = "new-owner";
  assert.equal((await request(monitoringReads[0], { token: idToken() })).status, 404);
});
test("monitoring security: missing profile or device backend failure never returns sensor data", async () => {
  ownedDevice();
  state.profile = null;
  assert.equal((await request(monitoringReads[0], { token: idToken() })).status, 409);
  state.profile = profile();
  state.deviceFail = true;
  assert.equal((await request(monitoringReads[0], { token: idToken() })).status, 503);
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/sensor_readings/")));
});
test("sensor security: Firebase tokens and AI key cannot submit readings or change owners", async () => {
  ownedDevice();
  for (const options of [{ token: idToken() }, { token: idToken({ role: "admin" }) }, { headers: aiHeaders }]) {
    assert.equal((await request("/api/v1/monitoring", { method: "POST", body: reading(), ...options })).status, 401);
  }
  const original = structuredClone(state.device);
  const response = await request("/api/v1/monitoring", { method: "POST", iot: true, body: { ...reading(), owner_uid: "attacker" } });
  assert.equal(response.status, 200);
  assert.equal(state.sensorWrite.body.owner_uid, undefined);
  assert.deepEqual(state.device, original);
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/devices/") && c.options.method === "PUT"));
});
test("ownership security: no public endpoint exists to self-assign ownership", async () => {
  ownedDevice();
  for (const path of ["/api/v1/devices/solar-001", "/api/v1/devices/solar-001/claim", "/api/v1/devices/solar-001/owner"]) {
    assert.equal((await request(path, { method: "POST", token: idToken(), body: { owner_uid: uid } })).status, 404);
  }
  assert.equal((await request("/api/v1/auth/register", { method: "POST", body: { username, email, password, owner_uid: uid } })).status, 422);
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});
test("dataset security: only separate AI key can read training dataset", async () => {
  for (const options of [{}, { iot: true }, { token: idToken() }]) {
    assert.equal((await request("/api/v1/ai/dataset", options)).status, 401);
  }
  assert.equal((await request("/api/v1/ai/dataset", { headers: aiHeaders })).status, 200);
});
test("regression: health remains public", async () => {
  const response = await request("/health");
  assert.equal(response.status, 200);
  assert.equal((await response.json()).status, "ok");
  assert.equal(calls.length, 0);
});
test("regression: monitoring POST calculation, storage path and duplicate behavior", async () => {
  const response = await request("/api/v1/monitoring", { method: "POST", body: reading(), iot: true });
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "saved", document_id: "solar-001_mock-reading", power_w: 24, energy_wh: 0.4 });
  assert.equal(state.sensorWrite.path, `/sensor_readings/solar-001/${today()}/solar-001_mock-reading.json`);
  assert.equal(state.sensorWrite.headers["if-match"], "null_etag");
  state.sensorStatus = 412;
  assert.equal((await request("/api/v1/monitoring", { method: "POST", body: reading(), iot: true })).status, 409);
});
test("regression: monitoring reads use owner token and dataset uses AI key with same output", async () => {
  ownedDevice();
  const paths = ["/api/v1/monitoring/latest", "/api/v1/monitoring/history", "/api/v1/monitoring/daily-summary", "/api/v1/monitoring/daily-history", "/api/v1/ai/dataset"];
  for (const path of paths) {
    assert.equal((await request(path)).status, 401);
    assert.equal((await request(path, { iot: true })).status, 401);
    const response = await request(path, path.endsWith("/dataset") ? { headers: aiHeaders } : { token: idToken() });
    assert.equal(response.status, 200, path);
    const result = await response.json();
    assert.equal(result.device_id, "solar-001");
    if (path.endsWith("/latest")) assert.equal(result.data.power_w, 24);
    else if (path.endsWith("/daily-summary")) assert.equal(result.data.total_energy_wh, 0.4);
    else {
      assert.equal(result.count, 1);
      if (path.endsWith("/daily-history")) assert.equal(result.data[0].avg_power_w, 24);
      if (path.endsWith("/dataset")) {
        assert.equal(result.target, "next_day_energy_wh");
        assert.equal(result.data[0].energy_wh, 0.4);
      }
    }
  }
  assert.equal((await request("/api/v1/monitoring", { method: "POST", body: reading() })).status, 401);
});
test("regression: existing validation and routing errors remain", async () => {
  ownedDevice();
  for (const path of ["/api/v1/monitoring/history?limit=0", "/api/v1/monitoring/daily-summary?date=bad", "/api/v1/ai/dataset?days=31", "/api/v1/monitoring/latest?device_id=bad.id"]) {
    assert.equal((await request(path, path.includes("/ai/dataset") ? { headers: aiHeaders } : { token: idToken() })).status, 422);
  }
  assert.equal((await request("/api/v1/monitoring", { method: "POST", body: {}, iot: true })).status, 422);
  assert.equal((await request("/api/v1/monitoring/latest", { method: "POST", iot: true })).status, 405);
  assert.equal((await request("/unknown")).status, 404);
});
