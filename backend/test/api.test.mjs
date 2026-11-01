// Prototype API regression tests: every external request is mocked.
import { test, before, beforeEach, afterEach } from "node:test";
import assert from "node:assert/strict";
import worker from "../src/index.js";
import { requirePrototypeDevice } from "../src/api.js";
const env = { FIREBASE_CLIENT_EMAIL: "mock@example.invalid", FIREBASE_DATABASE_URL: "https://mock.invalid", IOT_API_KEY: "mock-iot", AI_API_KEY: "mock-ai", PUBLIC_DEVICE_IDS: '["solar-001","solar-002"]' };
const originalFetch = globalThis.fetch;
let state, calls;
const json = (body,status=200)=>Response.json(body,{status});
const aiHeaders={"x-api-key":env.AI_API_KEY};
const predictionRoot="/api/v1/ai/predictions";
const predictionInput={device_id:"solar-001",prediction_date:"2026-11-02",predicted_energy_wh:125.75};
function prediction(date,extra={}) {return {...predictionInput,prediction_date:date,model_name:"Linear Regression",created_at:"2026-11-01T00:00:00Z",...extra};}
function today(){return new Intl.DateTimeFormat("en-CA",{timeZone:"Asia/Jakarta",year:"numeric",month:"2-digit",day:"2-digit"}).format(new Date());}
function reading(){return {reading_id:"mock-reading",device_id:"solar-001",timestamp:new Date().toISOString(),voltage_v:12,current_a:2,interval_seconds:60,power_w:24,energy_wh:0.4};}
async function request(path,{method="GET",body,token,iot=false,headers={}}={}) {
 return worker.fetch(new Request("https://worker.invalid"+path,{method,headers:{...(body!==undefined?{"Content-Type":"application/json"}:{}),...(token?{Authorization:"Bearer "+token}:{}),...(iot?{"x-api-key":env.IOT_API_KEY}:{}),...headers},...(body!==undefined?{body:typeof body==="string"?body:JSON.stringify(body)}:{})}),env);
}
before(async()=>{const k=await crypto.subtle.generateKey({name:"RSASSA-PKCS1-v1_5",modulusLength:2048,publicExponent:new Uint8Array([1,0,1]),hash:"SHA-256"},true,["sign","verify"]);env.FIREBASE_PRIVATE_KEY="-----BEGIN PRIVATE KEY-----\n"+Buffer.from(await crypto.subtle.exportKey("pkcs8",k.privateKey)).toString("base64")+"\n-----END PRIVATE KEY-----";});
beforeEach(()=>{
 state={};calls=[];
 globalThis.fetch=async(input,options={})=>{
  const url=new URL(input);const body=options.body && !(options.body instanceof URLSearchParams)?JSON.parse(options.body):null;
  calls.push({url,options,body});
  if(url.origin==="https://oauth2.googleapis.com")return json({access_token:"mock-oauth",expires_in:3600});
  assert.equal(url.origin,env.FIREBASE_DATABASE_URL,"Unexpected network blocked");
  assert.equal(options.headers.Authorization,"Bearer mock-oauth");
  if(url.pathname.startsWith("/devices/"))return json(state.device??null,state.deviceFail?503:200);
  if(url.pathname.startsWith("/energy_predictions/")){
   if(state.predictionFail)return json({},503);
   if(state.predictionNetworkFail)throw new Error("private upstream details");
   const parts=url.pathname.replace(/\.json$/,'').split('/');
   assert.ok(["solar-001", "solar-002"].includes(parts[2]));
   if(options.method==="PUT") {assert.equal(options.headers["if-match"],"null_etag");state.predictions??={};if(state.predictions[parts[3]])return json({},412);state.predictions[parts[3]]=body;return json(body);}
   assert.equal(url.searchParams.get("orderBy"),'"$key"');
   let entries=Object.entries(state.predictionsByDevice?.[parts[2]] ?? state.predictions ?? {}).sort(([a],[b])=>a.localeCompare(b));
   if(url.searchParams.has("limitToLast")){assert.equal(url.searchParams.get("limitToLast"),"1");entries=entries.slice(-1);}
   else {const start=JSON.parse(url.searchParams.get("startAt")),end=JSON.parse(url.searchParams.get("endAt"));entries=entries.filter(([d])=>d>=start&&d<=end);}
   return json(Object.fromEntries(entries));
  }
  if(url.pathname.startsWith("/sensor_readings/")){
   if(options.method==="PUT"){state.sensorWrite={path:url.pathname,body,headers:options.headers};return json({},state.sensorStatus||200);}
   if(state.sensorFail)return json({},503);
   const date=url.pathname.split('/')[3]?.replace('.json','');
   const deviceId = url.pathname.split('/')[2];
   return json(!state.empty&&date===today()?{reading:{...reading(), device_id:deviceId}}:null);
  }
  throw new Error("Unexpected database access blocked");
 };
});
afterEach(()=>{globalThis.fetch=originalFetch;});

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
  state.device = { device_id: "solar-001" };
  const responses = await Promise.all([1, 2].map(() => request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })));
  assert.deepEqual(responses.map(r => r.status).sort(), [201, 409]);
  const original = structuredClone(state.predictions);
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: { ...predictionInput, predicted_energy_wh: 999 } })).status, 409);
  assert.deepEqual(state.predictions, original);
});

test("predictions: latest uses greatest prediction date and excludes private fields", async () => {
  state.device = { device_id: "solar-001" };
  state.predictions = { "2026-11-01": prediction("2026-11-01"), "2026-11-03": prediction("2026-11-03", { private: "hidden" }), "2026-11-02": prediction("2026-11-02") };
  const response = await request(`${predictionRoot}/latest?device_id=solar-001`);
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.status, "success");
  assert.equal(result.data.prediction_date, "2026-11-03");
  assert.equal(result.data.private, undefined);
});

test("predictions: history is inclusive, ordered and limited to requested date range", async () => {
  state.device = { device_id: "solar-001" };
  state.predictions = Object.fromEntries(["2026-11-03", "2026-11-01", "2026-11-02", "2026-10-31"].map(date => [date, prediction(date)]));
  const response = await request(`${predictionRoot}/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02`);
  assert.equal(response.status, 200);
  assert.deepEqual(await response.json(), { status: "success", device_id: "solar-001", start_date: "2026-11-01", end_date: "2026-11-02", total_predictions: 2,
    data: [prediction("2026-11-01"), prediction("2026-11-02")] });
});

test("predictions: missing device/latest yields 404; empty history yields empty array", async () => {
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })).status, 404);
  state.device = { device_id: "solar-001" };
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`)).status, 404);
  const response = await request(`${predictionRoot}/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-01`);
  assert.equal(response.status, 200);
  assert.equal((await response.json()).total_predictions, 0);
});

test("predictions: POST rejects IoT key, user/admin JWT and missing/wrong AI key", async () => {
  state.device = { device_id: "solar-001" };
  for (const options of [{}, { iot: true }, { headers: { "x-api-key": "wrong" } }]) {
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
    { ...predictionInput, model_name: " " }, { ...predictionInput, owner_uid: "untrusted-uid" }]) {
    assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body })).status, 422);
  }
  assert.ok(!calls.some(c => c.options.method === "PUT"));
});

test("predictions: zero energy and explicit model name are accepted", async () => {
  state.device = { device_id: "solar-001" };
  const response = await request(predictionRoot, { method: "POST", headers: aiHeaders, body: { ...predictionInput, predicted_energy_wh: 0, model_name: "Linear Regression v2" } });
  assert.equal(response.status, 201);
  assert.equal((await response.json()).data.predicted_energy_wh, 0);
});

test("predictions: history rejects bad dates, reversed/oversized ranges and accepts 31 days", async () => {
  state.device = { device_id: "solar-001" };
  for (const [query, status] of [["", 422], ["&start_date=2026-02-30&end_date=2026-03-01", 422],
    ["&start_date=2026-11-02&end_date=2026-11-01", 400], ["&start_date=2026-10-01&end_date=2026-11-01", 400],
    ["&start_date=2026-10-01&end_date=2026-10-31", 200]]) {
    assert.equal((await request(`${predictionRoot}/history?device_id=solar-001${query}`)).status, status);
  }
  assert.equal((await request(`${predictionRoot}/latest`)).status, 422);
  assert.equal((await request(`${predictionRoot}/latest?device_id=bad.id`)).status, 422);
});

test("predictions: upstream failures and corrupt stored predictions fail safely", async () => {
  state.device = { device_id: "solar-001" };
  state.predictionFail = true;
  assert.equal((await request(predictionRoot, { method: "POST", headers: aiHeaders, body: predictionInput })).status, 503);
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`)).status, 503);
  state.predictionFail = false;
  state.predictionNetworkFail = true;
  const response = await request(`${predictionRoot}/latest?device_id=solar-001`);
  assert.equal(response.status, 503);
  assert.ok(!(await response.text()).includes("private upstream"));
  state.predictionNetworkFail = false;
  state.predictions = { "2026-11-02": prediction("2026-11-02", { device_id: "other-device" }) };
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`)).status, 503);
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

const publicMonitoring = ["/api/v1/monitoring/latest", "/api/v1/monitoring/history", "/api/v1/monitoring/daily-summary", "/api/v1/monitoring/daily-history"];
test("prototype: all monitoring GETs work without user credentials and preserve JSON", async () => {
  for (const path of publicMonitoring) {
    const response = await request(path);
    assert.equal(response.status, 200, path);
    const result = await response.json();
    assert.equal(result.device_id, "solar-001");
    if (path.endsWith("/latest")) assert.equal(result.data.power_w, 24);
    else if (path.endsWith("/daily-summary")) assert.equal(result.data.total_energy_wh, 0.4);
    else { assert.equal(result.count, 1); assert.equal(result.data[0].energy_wh ?? result.data[0].total_energy_wh, 0.4); }
  }
});
test("prototype: public predictions do not require Firebase Auth or owner metadata", async () => {
  state.predictions = { "2026-11-02": prediction("2026-11-02") };
  assert.equal((await request(`${predictionRoot}/latest?device_id=solar-001`)).status, 200);
  assert.equal((await request(`${predictionRoot}/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02`)).status, 200);
  assert.ok(!calls.some(c => c.url.pathname.startsWith("/users/") || c.url.pathname.startsWith("/devices/") || c.url.hostname === "identitytoolkit.googleapis.com"));
});
test("prototype: public access rejects devices outside configured allowlist", async () => {
  for (const path of [...publicMonitoring, `${predictionRoot}/latest`, `${predictionRoot}/history`]) {
    assert.equal((await request(`${path}?device_id=other-device`)).status, 404);
    assert.equal((await request(`${path}?device_id=bad.id`)).status, 422);
  }
  assert.equal(calls.length, 0);
});
test("prototype: every public GET supports multiple configured devices without mixing data", async () => {
  state.predictionsByDevice = Object.fromEntries(["solar-001", "solar-002"].map((id, i) => [id,
    { "2026-11-02": prediction("2026-11-02", { device_id: id, predicted_energy_wh: 100 + i }) }]));
  for (const id of ["solar-001", "solar-002"]) {
    for (const path of publicMonitoring) {
      const response = await request(`${path}?device_id=${id}`);
      assert.equal(response.status, 200, path);
      const result = await response.json();
      assert.equal(result.device_id, id);
      if (path.endsWith("/latest")) assert.equal(result.data.device_id, id);
      if (path.endsWith("/history")) assert.ok(result.data.every(row => row.device_id === id));
    }
    for (const suffix of ["latest", "history"]) {
      const response = await request(`${predictionRoot}/${suffix}?device_id=${id}&start_date=2026-11-01&end_date=2026-11-02`);
      assert.equal(response.status, 200);
      const result = await response.json();
      const rows = Array.isArray(result.data) ? result.data : [result.data];
      assert.ok(rows.every(row => row.device_id === id));
      assert.equal(rows[0].predicted_energy_wh, id === "solar-001" ? 100 : 101);
    }
  }
});
test("prototype: allowlist is exact, server-configured and fails closed on invalid config", async () => {
  assert.doesNotThrow(() => requirePrototypeDevice("solar-001", {}));
  assert.throws(() => requirePrototypeDevice("solar-002", {}), e => e.status === 404);
  for (const config of ["not-json", "null", '{}', '["bad/id"]', '[123]', '"solar-001"']) {
    assert.throws(() => requirePrototypeDevice("solar-001", { PUBLIC_DEVICE_IDS: config }), e => e.status === 503);
  }
  assert.throws(() => requirePrototypeDevice("solar-001", { PUBLIC_DEVICE_IDS: "[]" }), e => e.status === 404);
  assert.throws(() => requirePrototypeDevice("solar-00", env), e => e.status === 404);
  assert.throws(() => requirePrototypeDevice("SOLAR-001", env), e => e.status === 404);
  for (const path of publicMonitoring) {
    assert.equal((await request(`${path}?device_id=other-device&PUBLIC_DEVICE_IDS=[%22other-device%22]`)).status, 404);
  }
  assert.equal(calls.length, 0);
});
test("prototype: invalid and empty allowlists reject public reads before Firebase", async () => {
  for (const path of [...publicMonitoring, `${predictionRoot}/latest`, `${predictionRoot}/history`]) {
    const input = new Request(`https://worker.invalid${path}?device_id=solar-001`);
    assert.equal((await worker.fetch(input, { ...env, PUBLIC_DEVICE_IDS: "broken" })).status, 503);
    assert.equal((await worker.fetch(input, { ...env, PUBLIC_DEVICE_IDS: "[]" })).status, 404);
  }
  assert.equal(calls.length, 0);
});
test("removed auth, reference and recommendation endpoints return 404 without database access", async () => {
  for (const path of ["/api/v1/auth/register", "/api/v1/auth/login", "/api/v1/auth/me", "/api/v1/device-reference", "/api/v1/device-reference/lamp", "/api/v1/ai/recommendations"]) {
    for (const method of ["GET", "POST"]) assert.equal((await request(path, { method, iot: true })).status, 404);
  }
  assert.equal(calls.length, 0);
});
test("sensor POST remains protected and ignores client ownership fields", async () => {
  for (const options of [{}, { token: "old-token" }, { headers: aiHeaders }]) {
    assert.equal((await request("/api/v1/monitoring", { method: "POST", body: reading(), ...options })).status, 401);
  }
  assert.equal((await request("/api/v1/monitoring", { method: "POST", iot: true, body: { ...reading(), owner_uid: "attacker" } })).status, 200);
  assert.equal(state.sensorWrite.body.owner_uid, undefined);
});
test("AI dataset remains private to AI key and keeps JSON format", async () => {
  for (const options of [{}, { iot: true }, { token: "old-token" }]) assert.equal((await request("/api/v1/ai/dataset", options)).status, 401);
  const response = await request("/api/v1/ai/dataset", { headers: aiHeaders });
  assert.equal(response.status, 200);
  const result = await response.json();
  assert.equal(result.target, "next_day_energy_wh");
  assert.equal(result.data[0].energy_wh, 0.4);
});
test("monitoring validation, empty results and method errors remain compatible", async () => {
  for (const path of ["/api/v1/monitoring/history?limit=0", "/api/v1/monitoring/daily-summary?date=bad", "/api/v1/monitoring/daily-history?days=31"]) assert.equal((await request(path)).status, 422);
  assert.equal((await request("/api/v1/ai/dataset?days=31", { headers: aiHeaders })).status, 422);
  assert.equal((await request("/api/v1/monitoring", { method: "POST", body: {}, iot: true })).status, 422);
  assert.equal((await request("/api/v1/monitoring", { method: "POST", body: "{", iot: true })).status, 400);
  for (const path of publicMonitoring) assert.equal((await request(path, { method: "POST" })).status, 405);
  state.empty = true;
  assert.equal((await (await request(publicMonitoring[0])).json()).data, null);
  assert.equal((await (await request(publicMonitoring[1])).json()).count, 0);
  assert.equal((await (await request(publicMonitoring[2])).json()).data.total_energy_wh, 0);
  assert.equal((await (await request(publicMonitoring[3])).json()).count, 0);
});
test("Firebase access uses server OAuth only and never reads removed user nodes", async () => {
  await request(publicMonitoring[0]);
  assert.ok(calls.some(c => c.url.origin === env.FIREBASE_DATABASE_URL));
  assert.ok(calls.filter(c => c.url.origin === env.FIREBASE_DATABASE_URL).every(c => c.options.headers.Authorization === "Bearer mock-oauth"));
  assert.ok(!calls.some(c => /\/(users|usernames|recommendations|device_reference)(\/|\.json)/.test(c.url.pathname)));
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
