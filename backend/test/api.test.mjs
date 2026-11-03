import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker from '../src/index.js';
const migration = readFileSync(new URL('../migrations/0001_initial.sql', import.meta.url), 'utf8');
let sql, env;
const originalFetch = globalThis.fetch;
const today = () => new Intl.DateTimeFormat('en-CA', { timeZone:'Asia/Jakarta', year:'numeric', month:'2-digit', day:'2-digit' }).format(new Date());
const sensor = (extra={}) => ({reading_id:'r1',device_id:'solar-001',timestamp:new Date().toISOString(),voltage_v:12,current_a:2,interval_seconds:60,...extra});
const forecast = (extra={}) => ({device_id:'solar-001',prediction_date:'2026-11-03',predicted_energy_wh:125.75,...extra});
function binding() {
 return { prepare(query) {
  return { bind(...values) {
   const stmt = sql.prepare(query);
   return { async all(){return {success:true,results:stmt.all(...values)};}, async first(){return stmt.get(...values)??null;}, async run(){const result=stmt.run(...values);return {success:true,meta:{changes:Number(result.changes)}};} };
  }};
 }};
}
async function request(path,{method='GET',body,key,headers={}}={},configuration=env) {
 return worker.fetch(new Request('https://worker.invalid'+path,{method,headers:{...(body!==undefined?{'Content-Type':'application/json'}:{}),...(key?{'x-api-key':key}:{}),...headers},...(body!==undefined?{body:typeof body==='string'?body:JSON.stringify(body)}:{})}),configuration);
}
const postSensor = body => request('/api/v1/monitoring',{method:'POST',body,key:env.IOT_API_KEY});
const postPrediction = body => request('/api/v1/ai/predictions',{method:'POST',body,key:env.AI_API_KEY});
beforeEach(()=>{
 sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(migration);
 sql.prepare('INSERT INTO devices(device_id) VALUES (?), (?)').run('solar-001','solar-002');
 env={DB:binding(),IOT_API_KEY:'mock-iot',AI_API_KEY:'mock-ai',PUBLIC_DEVICE_IDS:'["solar-001","solar-002"]'};
 globalThis.fetch=async()=>{throw new Error('Network forbidden in tests');};
});
afterEach(()=>{sql.close();globalThis.fetch=originalFetch;});

test('health is public and independent of D1',async()=>{assert.equal((await request('/health',{},{})).status,200);});
test('sensor insert preserves W/Wh, original timestamp and JSON fields',async()=>{
 const body=sensor();const r=await postSensor(body);assert.equal(r.status,200);
 assert.deepEqual(await r.json(),{status:'saved',document_id:'solar-001_r1',power_w:24,energy_wh:0.4});
 const saved=sql.prepare('SELECT * FROM sensor_readings').get();assert.equal(saved.timestamp,body.timestamp);assert.equal(saved.reading_date,today());
 const latest=await (await request('/api/v1/monitoring/latest')).json();
 assert.deepEqual(latest.data,{...body,power_w:24,energy_wh:0.4});
 assert.equal(latest.data.timestamp_ms,undefined);
});
test('duplicate and simultaneous sensor inserts cannot overwrite',async()=>{
 const responses=await Promise.all([postSensor(sensor()),postSensor(sensor())]);assert.deepEqual(responses.map(r=>r.status).sort(),[200,409]);
 assert.equal((await postSensor(sensor({voltage_v:99}))).status,409);assert.equal(sql.prepare('SELECT power_w FROM sensor_readings').get().power_w,24);
});
test('sensor duplicate scope remains per device and WIB day',async()=>{
 for(const body of [sensor({timestamp:'2026-11-01T16:59:00Z'}),sensor({timestamp:'2026-11-01T17:00:00Z'}),sensor({device_id:'solar-002',timestamp:'2026-11-01T17:00:00Z'})]) assert.equal((await postSensor(body)).status,200);
 assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM sensor_readings').get().n,3);
});
test('WIB boundary aggregation and no cumulative energy double counting',async()=>{
 await postSensor(sensor({reading_id:'before',timestamp:'2026-11-01T16:59:00Z'}));
 await postSensor(sensor({reading_id:'after',timestamp:'2026-11-01T17:00:00Z',voltage_v:6}));
 for(const [date,energy] of [['2026-11-01',0.4],['2026-11-02',0.2]]){
 const result=await (await request('/api/v1/monitoring/daily-summary?date='+date)).json();assert.equal(result.data.total_energy_wh,energy);assert.equal(result.data.reading_count,1);assert.equal(result.timezone,'Asia/Jakarta');}
});
test('all four monitoring GETs stay public and keep response shapes',async()=>{
 await postSensor(sensor());
 for(const path of ['latest','history','daily-summary','daily-history']){
 const r=await request('/api/v1/monitoring/'+path);assert.equal(r.status,200);const body=await r.json();assert.equal(body.device_id,'solar-001');
 if(path==='history')assert.equal(body.count,1);if(path==='daily-history'){assert.equal(body.data[0].total_energy_wh,0.4);assert.equal(body.data[0].avg_power_w,24);}}
});
test('monitoring history sorts real instants across timestamp offsets and respects limit',async()=>{
 const d=today();await postSensor(sensor({reading_id:'early',timestamp:d+'T01:00:00Z'}));await postSensor(sensor({reading_id:'late',timestamp:d+'T09:00:00+07:00'}));
 const result=await (await request('/api/v1/monitoring/history?limit=1')).json();assert.equal(result.count,1);assert.equal(result.data[0].reading_id,'late');
});
test('empty monitoring retains null/zero/empty responses',async()=>{
 assert.equal((await (await request('/api/v1/monitoring/latest')).json()).data,null);
 assert.equal((await (await request('/api/v1/monitoring/history')).json()).count,0);
 assert.equal((await (await request('/api/v1/monitoring/daily-summary')).json()).data.total_energy_wh,0);
 assert.equal((await (await request('/api/v1/monitoring/daily-history')).json()).count,0);
});
test('IoT and AI credentials remain separate',async()=>{
 for(const key of [undefined,'wrong',env.AI_API_KEY])assert.equal((await request('/api/v1/monitoring',{method:'POST',body:sensor(),key})).status,401);
 for(const key of [undefined,'wrong',env.IOT_API_KEY]){assert.equal((await request('/api/v1/ai/dataset',{key})).status,401);assert.equal((await request('/api/v1/ai/predictions',{method:'POST',key,body:forecast()})).status,401);}
 assert.equal((await request('/api/v1/ai/dataset',{key:env.AI_API_KEY},{...env,AI_API_KEY:env.IOT_API_KEY})).status,503);
});
test('dataset keeps daily Wh target and per-device isolation',async()=>{
 await postSensor(sensor());await postSensor(sensor({device_id:'solar-002',voltage_v:6}));
 const r=await request('/api/v1/ai/dataset?device_id=solar-002',{key:env.AI_API_KEY});assert.equal(r.status,200);
 const body=await r.json();assert.equal(body.target,'next_day_energy_wh');assert.equal(body.data[0].energy_wh,0.2);assert.equal(body.data[0].reading_count,1);
});
test('predictions write and latest preserve old JSON contract',async()=>{
 const r=await postPrediction(forecast());assert.equal(r.status,201);const saved=(await r.json()).data;assert.equal(saved.model_name,'Linear Regression');
 assert.deepEqual(await (await request('/api/v1/ai/predictions/latest?device_id=solar-001')).json(),{status:'success',data:saved});
});
test('predictions duplicates are atomic and never overwrite',async()=>{
 const responses=await Promise.all([postPrediction(forecast()),postPrediction(forecast({predicted_energy_wh:99}))]);assert.deepEqual(responses.map(r=>r.status).sort(),[201,409]);
 assert.equal(sql.prepare('SELECT COUNT(*) AS n FROM energy_predictions').get().n,1);
});
test('prediction history is inclusive, ordered, isolated and latest uses greatest date',async()=>{
 for(const date of ['2026-11-03','2026-11-01','2026-11-02'])await postPrediction(forecast({prediction_date:date}));
 await postPrediction(forecast({device_id:'solar-002',predicted_energy_wh:3}));
 const body=await (await request('/api/v1/ai/predictions/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02')).json();
 assert.equal(body.total_predictions,2);assert.deepEqual(body.data.map(r=>r.prediction_date),['2026-11-01','2026-11-02']);
 assert.equal((await (await request('/api/v1/ai/predictions/latest?device_id=solar-001')).json()).data.prediction_date,'2026-11-03');
});
test('prediction empty and missing device handling',async()=>{
 assert.equal((await postPrediction(forecast({device_id:'missing'}))).status,404);
 assert.equal((await request('/api/v1/ai/predictions/latest?device_id=solar-001')).status,404);
 const body=await (await request('/api/v1/ai/predictions/history?device_id=solar-001&start_date=2026-11-01&end_date=2026-11-02')).json();assert.deepEqual(body.data,[]);assert.equal(body.total_predictions,0);
});
test('public allowlist denies unknown/injection IDs and malformed config',async()=>{
 for(const path of ['/api/v1/monitoring/latest','/api/v1/monitoring/history','/api/v1/monitoring/daily-summary','/api/v1/monitoring/daily-history','/api/v1/ai/predictions/latest','/api/v1/ai/predictions/history']){
 assert.equal((await request(path+'?device_id=private')).status,404);assert.equal((await request(path+'?device_id=bad.id')).status,422);
 assert.equal((await request(path+'?device_id=solar-001',{}, {...env,PUBLIC_DEVICE_IDS:'broken'})).status,503);
 assert.equal((await request(path+'?device_id=solar-001',{}, {...env,PUBLIC_DEVICE_IDS:'[]'})).status,404);}
});
test('public multi-device reads do not mix sensor rows',async()=>{
 await postSensor(sensor());await postSensor(sensor({device_id:'solar-002',voltage_v:6}));
 for(const id of ['solar-001','solar-002']){const body=await (await request('/api/v1/monitoring/latest?device_id='+id)).json();assert.equal(body.data.device_id,id);assert.equal(body.data.power_w,id==='solar-001'?24:12);}
});
test('invalid inputs, request limits and query ranges remain rejected',async()=>{
 for(const body of [{},sensor({voltage_v:-1}),sensor({interval_seconds:0}),sensor({device_id:'a/b'}),sensor({timestamp:'bad'})])assert.equal((await postSensor(body)).status,422);
 for(const body of [{},forecast({predicted_energy_wh:-1}),forecast({predicted_energy_wh:true}),forecast({prediction_date:'2026-02-30'}),forecast({device_id:'a/b'})])assert.equal((await postPrediction(body)).status,422);
 assert.equal((await postPrediction(forecast({model_name:'x'.repeat(5000)}))).status,413);
 assert.equal((await request('/api/v1/monitoring/history?limit=0')).status,422);
 assert.equal((await request('/api/v1/monitoring/daily-summary?date=bad')).status,422);
 assert.equal((await request('/api/v1/ai/dataset?days=31',{key:env.AI_API_KEY})).status,422);
 for(const [start,end,status]of [['2026-11-02','2026-11-01',400],['2026-10-01','2026-11-01',400],['2026-10-01','2026-10-31',200],['bad','2026-11-01',422]])assert.equal((await request(`/api/v1/ai/predictions/history?device_id=solar-001&start_date=${start}&end_date=${end}`)).status,status);
});
test('removed routes stay absent and wrong methods remain rejected',async()=>{
 for(const path of ['/api/v1/auth/login','/api/v1/auth/register','/api/v1/auth/me','/api/v1/ai/recommendations','/api/v1/device-reference'])assert.equal((await request(path)).status,404);
 assert.equal((await request('/api/v1/monitoring/latest',{method:'POST'})).status,405);assert.equal((await request('/api/v1/ai/predictions')).status,405);
});
test('database failures are sanitized without credentials or SQL disclosure',async()=>{
 const broken={...env,DB:{prepare(){throw new Error('private SQL details');}}};
 const r=await request('/api/v1/ai/predictions/latest?device_id=solar-001',{},broken);assert.equal(r.status,503);assert.ok(!(await r.text()).includes('private SQL'));
});
test('SQL constraints reject invalid values and foreign prediction devices',()=>{
 assert.throws(()=>sql.prepare('INSERT INTO energy_predictions VALUES (?,?,?,?,?)').run('missing','2026-11-03',1,'Linear Regression','2026-11-02'));
 assert.throws(()=>sql.prepare('INSERT INTO energy_predictions VALUES (?,?,?,?,?)').run('solar-001','2026-11-03',-1,'Linear Regression','2026-11-02'));
});
