import { test, beforeEach, afterEach } from 'node:test';
import assert from 'node:assert/strict';
import { DatabaseSync } from 'node:sqlite';
import { readFileSync } from 'node:fs';
import worker from '../src/index.js';
const migration = readFileSync(new URL('../migrations/0001_initial.sql', import.meta.url), 'utf8');
const receivedAtMigration = readFileSync(new URL('../migrations/0002_sensor_received_at.sql', import.meta.url), 'utf8');
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
 sql=new DatabaseSync(':memory:');sql.exec('PRAGMA foreign_keys=ON');sql.exec(migration);sql.exec(receivedAtMigration);
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

async function seedHistoryDay() {
 const samples=[['outside-before','2026-11-01T16:59:00Z',9],['midnight','2026-11-01T17:00:00Z',1],['morning','2026-11-02T07:30:00+07:00',2],['night','2026-11-02T16:59:00Z',3],['outside-after','2026-11-02T17:00:00Z',9]];
 for(const [id,timestamp,current]of samples)assert.equal((await postSensor(sensor({reading_id:id,timestamp,current_a:current}))).status,200);
}
test('history date filter uses WIB with stable limit/offset pagination and legacy shape',async()=>{
 await seedHistoryDay();
 const first=await (await request('/api/v1/monitoring/history?date=2026-11-02&limit=2&offset=0')).json();
 assert.equal(first.count,2);assert.deepEqual(first.data.map(r=>r.reading_id),['night','morning']);assert.equal(first.has_more,true);assert.equal(first.next_offset,2);
 const next=await (await request('/api/v1/monitoring/history?date=2026-11-02&limit=2&offset=2')).json();
 assert.deepEqual(next.data.map(r=>r.reading_id),['midnight']);assert.equal(next.has_more,false);assert.equal(next.next_offset,null);
 assert.equal(next.data[0].voltage_v,12);assert.equal(next.data[0].current_a,1);assert.equal(next.data[0].energy_wh,0.2);
 const beyond=await (await request('/api/v1/monitoring/history?date=2026-11-02&offset=100')).json();assert.deepEqual(beyond.data,[]);
 const legacy=await (await request('/api/v1/monitoring/history')).json();assert.deepEqual(Object.keys(legacy).sort(),['count','data','device_id']);
});
test('daily summary adds sample averages with existing energy/power fields',async()=>{
 await seedHistoryDay();const body=await (await request('/api/v1/monitoring/daily-summary?date=2026-11-02')).json();
 assert.deepEqual(body,{device_id:'solar-001',timezone:'Asia/Jakarta',data:{date:'2026-11-02',total_energy_wh:1.2,reading_count:3,avg_voltage_v:12,avg_current_a:2,avg_power_w:24,max_power_w:36}});
});
test('hourly summary returns all 24 WIB hours including zeros and boundary data',async()=>{
 await seedHistoryDay();const body=await (await request('/api/v1/monitoring/hourly-summary?date=2026-11-02')).json();
 assert.equal(body.timezone,'Asia/Jakarta');assert.equal(body.count,24);assert.equal(body.data.length,24);
 assert.deepEqual(body.data[0],{hour:0,total_energy_wh:0.2,reading_count:1});assert.equal(body.data[7].total_energy_wh,0.4);assert.equal(body.data[23].total_energy_wh,0.6);assert.equal(body.data[1].total_energy_wh,0);
 assert.ok(Math.abs(body.data.reduce((sum,r)=>sum+r.total_energy_wh,0)-1.2)<1e-9);
});
test('daily history supports inclusive weekly/monthly ranges and fills missing dates',async()=>{
 await seedHistoryDay();
 for(const [start,end,count]of [['2026-11-02','2026-11-08',7],['2026-11-01','2026-11-30',30]]){
 const r=await request(`/api/v1/monitoring/daily-history?start_date=${start}&end_date=${end}`);assert.equal(r.status,200);const body=await r.json();assert.equal(body.count,count);assert.equal(body.data[0].date,start);assert.equal(body.data.at(-1).date,end);
 assert.equal(body.data.find(row=>row.date==='2026-11-02').total_energy_wh,1.2);assert.equal(body.data.find(row=>row.date==='2026-11-08').reading_count,0);}
 const legacy=await (await request('/api/v1/monitoring/daily-history?days=1')).json();assert.equal(legacy.start_date,undefined);assert.equal(legacy.data.length,0);
});
test('period summary aggregates raw samples rather than averaging daily averages',async()=>{
 await postSensor(sensor({reading_id:'a',timestamp:'2026-11-02T01:00:00+07:00',voltage_v:10,current_a:1}));
 await postSensor(sensor({reading_id:'b',timestamp:'2026-11-03T01:00:00+07:00',voltage_v:20,current_a:2}));
 await postSensor(sensor({reading_id:'c',timestamp:'2026-11-03T02:00:00+07:00',voltage_v:30,current_a:3}));
 const r=await request('/api/v1/monitoring/period-summary?start_date=2026-11-02&end_date=2026-11-03');assert.equal(r.status,200);const body=await r.json();
 assert.equal(body.data.reading_count,3);assert.equal(body.data.avg_voltage_v,20);assert.equal(body.data.avg_current_a,2);assert.equal(body.data.avg_power_w,46.666666667);assert.equal(body.data.total_energy_wh,2.333333333);
});
test('empty history endpoints return consistent zero and empty results',async()=>{
 for(const path of ['daily-summary','hourly-summary']){const body=await (await request(`/api/v1/monitoring/${path}?date=2026-11-02`)).json();if(path==='hourly-summary')assert.ok(body.data.every(row=>row.total_energy_wh===0&&row.reading_count===0));else assert.equal(body.data.avg_voltage_v,0);}
 const period=await (await request('/api/v1/monitoring/period-summary?start_date=2026-11-02&end_date=2026-11-02')).json();assert.deepEqual(period.data,{total_energy_wh:0,reading_count:0,avg_voltage_v:0,avg_current_a:0,avg_power_w:0});
 const history=await (await request('/api/v1/monitoring/history?date=2026-11-02')).json();assert.equal(history.has_more,false);assert.deepEqual(history.data,[]);
});
test('all history endpoints reject invalid dates, bad pagination and oversized ranges',async()=>{
 for(const path of ['history','daily-summary','hourly-summary'])for(const date of ['2026-02-30','02-11-2026','0000-01-01',''])assert.equal((await request(`/api/v1/monitoring/${path}?date=${date}`)).status,422);
 for(const query of ['offset=-1','offset=1.5','offset=1000001','offset=9007199254740992','limit=0','limit=1001','limit=','offset=abc'])assert.equal((await request('/api/v1/monitoring/history?'+query)).status,422);
 for(const path of ['daily-history','period-summary']){
 for(const query of ['start_date=2026-11-02','end_date=2026-11-02','start_date=bad&end_date=2026-11-02'])assert.equal((await request(`/api/v1/monitoring/${path}?${query}`)).status,422);
 assert.equal((await request(`/api/v1/monitoring/${path}?start_date=2026-11-03&end_date=2026-11-02`)).status,400);
 assert.equal((await request(`/api/v1/monitoring/${path}?start_date=2025-01-01&end_date=2026-11-02`)).status,400);}
 assert.equal((await request('/api/v1/monitoring/hourly-summary')).status,422);
});
test('large day pagination and aggregates include every reading without response truncation',async()=>{
 const stmt=sql.prepare('INSERT INTO sensor_readings (device_id,reading_date,document_id,reading_id,timestamp,timestamp_ms,voltage_v,current_a,power_w,energy_wh,interval_seconds) VALUES (?,?,?,?,?,?,?,?,?,?,?)');
 for(let i=0;i<1440;i++){const timestamp=new Date(Date.parse('2026-11-02T00:00:00+07:00')+i*60000).toISOString();stmt.run('solar-001','2026-11-02','bulk-'+i,'bulk-'+i,timestamp,Date.parse(timestamp),12,2,24,0.4,60);}
 const ids=[];for(let offset=0;offset<1440;offset+=1000){const body=await (await request(`/api/v1/monitoring/history?date=2026-11-02&limit=1000&offset=${offset}`)).json();ids.push(...body.data.map(r=>r.reading_id));}
 assert.equal(new Set(ids).size,1440);
 const daily=await (await request('/api/v1/monitoring/daily-summary?date=2026-11-02')).json();assert.equal(daily.data.reading_count,1440);assert.equal(daily.data.total_energy_wh,576);
 const hourly=await (await request('/api/v1/monitoring/hourly-summary?date=2026-11-02')).json();assert.ok(hourly.data.every(row=>row.reading_count===60&&row.total_energy_wh===24));
});
test('pagination tie-breaker is stable and histories stay isolated by device',async()=>{
 for(const id of ['a','b','c'])await postSensor(sensor({reading_id:id,timestamp:'2026-11-02T00:00:00+07:00'}));
 await postSensor(sensor({device_id:'solar-002',timestamp:'2026-11-02T00:00:00+07:00',current_a:9}));
 const ids=[];for(let offset=0;offset<3;offset++){const body=await (await request(`/api/v1/monitoring/history?date=2026-11-02&limit=1&offset=${offset}`)).json();ids.push(body.data[0].reading_id);}assert.deepEqual(ids,['c','b','a']);
 for(const path of ['hourly-summary?date=2026-11-02','period-summary?start_date=2026-11-02&end_date=2026-11-02']){const r=await request('/api/v1/monitoring/'+path+'&device_id=private');assert.equal(r.status,404);}
 const period=await (await request('/api/v1/monitoring/period-summary?device_id=solar-001&start_date=2026-11-02&end_date=2026-11-02')).json();assert.equal(period.data.reading_count,3);
});
test('range date precedence, leap-year bounds and supported maximum date',async()=>{
 const leap=await request('/api/v1/monitoring/daily-history?start_date=2024-01-01&end_date=2024-12-31&days=invalid');assert.equal(leap.status,200);assert.equal((await leap.json()).count,366);
 const max=await request('/api/v1/monitoring/daily-history?start_date=9999-12-31&end_date=9999-12-31');assert.equal(max.status,200);assert.equal((await max.json()).count,1);
});

test('snapshot pagination excludes new and late-buffer readings without skipping original rows',async()=>{
 for(const [id,time]of [['a','01:00'],['b','02:00'],['c','03:00']])await postSensor(sensor({reading_id:id,timestamp:`2026-11-02T${time}:00+07:00`}));
 const first=await (await request('/api/v1/monitoring/history?date=2026-11-02&limit=1&offset=0')).json();assert.equal(first.data[0].reading_id,'c');assert.ok(first.snapshot);
 await postSensor(sensor({reading_id:'newer',timestamp:'2026-11-02T04:00:00+07:00'}));
 await postSensor(sensor({reading_id:'buffered',timestamp:'2026-11-02T01:30:00+07:00'}));
 const ids=[first.data[0].reading_id];let offset=first.next_offset;
 while(offset!==null){const page=await (await request(`/api/v1/monitoring/history?date=2026-11-02&limit=1&offset=${offset}&snapshot=${first.snapshot}`)).json();assert.equal(page.snapshot,first.snapshot);ids.push(...page.data.map(row=>row.reading_id));offset=page.next_offset;}
 assert.deepEqual(ids,['c','b','a']);assert.equal(new Set(ids).size,3);
 const refreshed=await (await request('/api/v1/monitoring/history?date=2026-11-02&limit=100&offset=0')).json();assert.equal(refreshed.count,5);
});
test('snapshot validation binds device/date and rejects malformed tokens',async()=>{
 await seedHistoryDay();const first=await (await request('/api/v1/monitoring/history?date=2026-11-02')).json();
 for(const query of [`device_id=solar-002&date=2026-11-02&snapshot=${first.snapshot}`,`date=2026-11-03&snapshot=${first.snapshot}`,`snapshot=${first.snapshot}`,'snapshot=broken','snapshot='])assert.equal((await request('/api/v1/monitoring/history?'+query)).status,422);
});
test('history snapshot freezes default date window across midnight WIB',async()=>{
 const { handleHistory }=await import('../src/history.js');
 await postSensor(sensor({timestamp:'2026-11-02T23:59:00+07:00'}));
 const first=await (await handleHistory(env,'solar-001','/api/v1/monitoring/history',new URLSearchParams('offset=0&limit=1'),'2026-11-02')).json();
 const next=await (await handleHistory(env,'solar-001','/api/v1/monitoring/history',new URLSearchParams('offset=0&limit=1&snapshot='+first.snapshot),'2026-11-03')).json();
 assert.deepEqual(next.data,first.data);assert.equal(next.snapshot,first.snapshot);
});
test('hourly and period endpoints reject wrong methods, private devices and stay SQL-indexed',async()=>{
 for(const path of ['/api/v1/monitoring/hourly-summary?date=2026-11-02','/api/v1/monitoring/period-summary?start_date=2026-11-02&end_date=2026-11-02']){
 assert.equal((await request(path,{method:'POST'})).status,405);assert.equal((await request(path+'&device_id=private')).status,404);}
 const plan=sql.prepare('EXPLAIN QUERY PLAN SELECT SUM(energy_wh) FROM sensor_readings WHERE device_id=? AND reading_date BETWEEN ? AND ?').all('solar-001','2026-11-01','2026-11-30');assert.ok(plan.some(row=>row.detail.includes('INDEX')));
});

test('device status uses server reception time, ignores ESP timestamp and client received_at',async(t)=>{
 const now=Date.parse('2026-11-07T12:00:00Z');t.mock.timers.enable({apis:['Date'],now});
 const response=await postSensor(sensor({timestamp:'2026-11-02T00:00:00Z',received_at:'2000-01-01T00:00:00Z'}));assert.equal(response.status,200);
 const received=sql.prepare('SELECT received_at FROM sensor_readings').get().received_at;assert.equal(received,'2026-11-07T12:00:00.000Z');
 assert.deepEqual(await (await request('/api/v1/devices/solar-001/status')).json(),{device_id:'solar-001',status:'online',last_seen:received,reason:'unknown'});
 t.mock.timers.setTime(now+179999);assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).status,'online');
 t.mock.timers.setTime(now+180000);assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).status,'offline');
 t.mock.timers.setTime(now+600000);assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).status,'offline');
});
test('device status handles no readings and isolates devices',async()=>{
 assert.deepEqual(await (await request('/api/v1/devices/solar-001/status')).json(),{device_id:'solar-001',status:'offline',last_seen:null,reason:'unknown'});
 await postSensor(sensor());assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).status,'online');
 assert.equal((await (await request('/api/v1/devices/solar-002/status')).json()).last_seen,null);
});
test('duplicate reading does not change server receipt time',async(t)=>{
 const now=Date.parse('2026-11-07T12:00:00Z');t.mock.timers.enable({apis:['Date'],now});const body=sensor();await postSensor(body);
 t.mock.timers.setTime(now+180000);assert.equal((await postSensor(body)).status,409);
 const response=await (await request('/api/v1/devices/solar-001/status')).json();assert.equal(response.status,'offline');assert.equal(response.last_seen,'2026-11-07T12:00:00.000Z');
});
test('last_seen follows receipt order rather than measurement order',async(t)=>{
 const now=Date.parse('2026-11-07T12:00:00Z');t.mock.timers.enable({apis:['Date'],now});await postSensor(sensor());
 t.mock.timers.setTime(now+60000);await postSensor(sensor({reading_id:'buffered',timestamp:'2026-11-01T00:00:00Z'}));
 assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).last_seen,'2026-11-07T12:01:00.000Z');
});
test('status access respects public list and rejects invalid IDs, methods and database failures',async()=>{
 assert.equal((await request('/api/v1/devices/private/status')).status,404);
 assert.equal((await request('/api/v1/devices/bad.id/status')).status,422);
 assert.equal((await request('/api/v1/devices/a%2Fb/status')).status,422);
 assert.equal((await request('/api/v1/devices/solar-001/status',{method:'POST'})).status,405);
 assert.equal((await request('/api/v1/devices/solar-001/status',{}, {...env,DB:undefined})).status,503);
});
test('received_at migration preserves existing rows without fabricating last_seen',async()=>{
 const old=new DatabaseSync(':memory:');try{old.exec(migration);old.prepare('INSERT INTO sensor_readings VALUES (?,?,?,?,?,?,?,?,?,?,?)').run('solar-001','2026-11-02','old','old','2026-11-02T00:00:00Z',Date.parse('2026-11-02T00:00:00Z'),12,2,24,0.4,60);old.exec(receivedAtMigration);
 const row=old.prepare('SELECT * FROM sensor_readings').get();assert.equal(row.energy_wh,0.4);assert.equal(row.received_at,null);assert.equal(row.reading_id,'old');}finally{old.close();}
 await postSensor(sensor());sql.exec('UPDATE sensor_readings SET received_at=NULL');assert.equal((await (await request('/api/v1/devices/solar-001/status')).json()).last_seen,null);
});
