import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { execFileSync, execFile, spawn } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import { createServer } from 'node:http';
import os from 'node:os';

const BASE='3a1f3a11a0db1cab2bc0716949fa5a7ab761cae3', WEB='064c82367bb5d06da40b92ff6908329bde6631f4', MOBILE='2893ece79e1fd66159bb0e1700dddd6473461acd';
const check=(label,ok)=>{if(!ok)throw Error(label);};
const log=(label,data={})=>console.log('CAPACITY '+label+' '+JSON.stringify(data));
const temp=process.env.RUNNER_TEMP;
check('runner isolation',process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted'&&process.env.GITHUB_REF==='refs/heads/qa/capacity-002'&&process.env.HNU_DASH_ISOLATED_TEST_DB==='1'&&!!temp);
const config=JSON.parse(readFileSync(resolve(temp,'capacity-002-local.json'),'utf8'));
const url=config.API_URL, anon=config.ANON_KEY||config.PUBLISHABLE_KEY, service=config.SERVICE_ROLE_KEY||config.SECRET_KEY;
check('loopback API and isolated keys',/^http:\/\/(127\.0\.0\.1|localhost):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const requireWeb=createRequire(resolve('qa-web/package.json'));
const {createClient}=requireWeb('@supabase/supabase-js');
const {createServerClient}=requireWeb('@supabase/ssr');
let chromium;try{({chromium}=createRequire(resolve(temp,'capacity-002-tools/package.json'))('playwright'));}catch{}
const opts={auth:{persistSession:false,autoRefreshToken:false}};
const admin=createClient(url,service,opts);
const dbArgs=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=sql=>{try{return execFileSync('docker',dbArgs,{input:sql,encoding:'utf8',timeout:15000,stdio:['pipe','pipe','pipe']}).trim();}catch{throw Error('isolated SQL assertion failed');}};
const j=sql=>JSON.parse(db(sql)), uuid=randomUUID, q=v=>"'"+String(v).replaceAll("'","''")+"'", tuple=xs=>'('+xs.map(q).join(',')+')';
const sid=n=>'SYNTHETIC-'+String(n).padStart(4,'0');
const iso=n=>new Date(n).toISOString(), now=()=>Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
const cnt=(t,w='true')=>Number(db('select count(*) from public.'+t+' where '+w));
const rows=(t,w)=>j("select coalesce(json_agg(t),'[]'::json) from (select * from public."+t+" where "+w+") t");
const eq=(a,b)=>assert.deepEqual(a,b);
const wait=async(fn,limit=15000)=>{const end=Date.now()+limit;while(Date.now()<end){if(await fn())return;await sleep(100);}throw Error('bounded wait timed out');};
const until=async(t)=>{while(true){const left=t-now();if(left<=0)return;await sleep(Math.min(left+30,1000));}};
let stopped=false;
const all=async(ps)=>{const r=await Promise.allSettled(ps.map(p=>Promise.resolve(p).catch(e=>{stopped=true;throw e;})));const bad=r.find(x=>x.status==='rejected');if(bad)throw bad.reason;return r.map(x=>x.value);};
let attempts=0, direct=0, browserRPC=0, authUsers=0, phase='preflight', browser, server, proxy, observer, sampling=false;
let browserTimes=[], paceSamples=[], perf=[], contention=[], samplesFailed=0, inFlight=0, maxInFlight=0;
const budget=(web=false)=>{check('stop after unexpected failure',!stopped);check('6000 RPC budget',attempts<6000);attempts++;if(web)browserRPC++;else direct++;};
const active=new Set();
const rpc=async(who,name,args,{code=null,tag='control',discard=false,delay=0,adversarial=false}={})=>{
  budget();const staff=who.kind==='staff';
  if(staff&&!adversarial){check('one outstanding Staff request',!active.has(who.id));active.add(who.id);}
  inFlight++;maxInFlight=Math.max(maxInFlight,inFlight);check('concurrency ceiling',inFlight<=10);
  const start=performance.now();
  try{
    if(delay)await sleep(delay);
    let res;try{res=await fetch(url+'/rest/v1/rpc/'+name,{method:'POST',headers:{apikey:anon,Authorization:'Bearer '+who.token,'Content-Type':'application/json'},body:JSON.stringify(args),signal:AbortSignal.timeout(12000)});}catch{throw Error('unexpected transport failure '+name);}
    if(discard){check('committed HTTP success '+name,res.ok);await res.body?.cancel();perf.push({phase,name,tag:'discard',ms:performance.now()-start,outcome:'discard'});return null;}
    let data;try{data=await res.json();}catch{throw Error('invalid RPC response '+name);}
    const result=res.ok?'ok':data?.code||'unknown';
    perf.push({phase,name,tag,ms:performance.now()-start,outcome:result});
    if(code!==null){const allowed=Array.isArray(code)?code:[code];check('unexpected result '+name+' '+result,allowed.includes(result));}
    else check('unexpected RPC error '+name+' '+result,res.ok);
    return res.ok?data:{denied:result};
  }catch(e){stopped=true;throw e;}finally{inFlight--;if(staff&&!adversarial)active.delete(who.id);}
};
const table=async(label,p)=>{const r=await p;check(label+' '+(r.error?.code||''),!r.error);return r.data;};
const actor=async(kind,n)=>{
  const email='capacity-'+kind+'-'+n+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph', password=randomBytes(24).toString('hex')+'aA1!';
  const created=await admin.auth.admin.createUser({email,password,email_confirm:true});
  check('isolated Auth create',!created.error&&!!created.data.user);
  const jar=new Map(),client=createServerClient(url,anon,{cookies:{getAll:()=>Array.from(jar,([name,value])=>({name,value})),setAll:es=>{for(const {name,value} of es){if(value)jar.set(name,value);else jar.delete(name);}}}});
  const signed=await client.auth.signInWithPassword({email,password});
  check('real password Auth',!signed.error&&!!signed.data.session);
  const a={kind,id:created.data.user.id,token:signed.data.session.access_token,client,jar};
  check('real identity',(await client.auth.getUser()).data.user?.id===a.id);authUsers++;
  check('verified HNU identity',await rpc(a,'hnu_verified_user',{})===true);
  return a;
};
const oid=uuid(), foreignOrg=uuid();
let leader,other,foreign,staff=[];
const startObserver=()=>{
  sampling=true;
  const tick=async()=>{
    if(!sampling)return;
    try{
      const sql="select json_build_object('active',count(*) filter (where state='active'),'lock_wait',count(*) filter (where wait_event_type='Lock'),'blocked',coalesce(json_agg(json_build_object('pid',pid,'blockers',pg_blocking_pids(pid))) filter(where cardinality(pg_blocking_pids(pid))>0),'[]'::json),'locks_waiting',(select count(*) from pg_locks where not granted)) from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid() and backend_type='client backend'";
      const r=await promisify(execFile)('docker',[...dbArgs,'-c',sql],{timeout:4000,maxBuffer:65536});
      contention.push({phase,at:Date.now(),...JSON.parse(r.stdout)});
    }catch{samplesFailed++;}
    if(sampling)observer=setTimeout(tick,200);
  };
  void tick();
};
const stopObserver=()=>{sampling=false;if(observer)clearTimeout(observer);};
const dbStats=()=>j("select row_to_json(s) from (select xact_commit,xact_rollback,deadlocks,blks_read,blks_hit from pg_stat_database where datname=current_database()) s");
const resources=async()=>{try{const r=await promisify(execFile)('docker',['stats','--no-stream','--format','{{.Name}} {{.CPUPerc}} {{.MemUsage}}','supabase_db_hnu-dash-backend'],{timeout:8000});return r.stdout.trim();}catch{return 'unavailable';}};
const makeEvent=async(mixed,one=false)=>{
  const id=(await table('create event',leader.client.from('events').insert({organization_id:oid,title:'Synthetic capacity '+(one?'race':mixed?'mixed':'control'),starts_at:iso(Date.now()-60000),ends_at:iso(Date.now()+900000),target_year_levels:[1]}).select('id').single())).id;
  const t=now()+8000, w=one?18000:150000, second=t+w+1000;
  const specs=[{event_id:id,label:'Synthetic IN',direction:'IN',opens_at:iso(t),closes_at:iso(t+w),sort_order:1}];
  if(!one)specs.push({event_id:id,label:'Synthetic OUT',direction:'OUT',opens_at:iso(second),closes_at:iso(second+w),sort_order:2});
  const cps=(await table('create checkpoints',leader.client.from('event_checkpoints').insert(specs).select('id,sort_order,opens_at,closes_at'))).sort((a,b)=>a.sort_order-b.sort_order);
  check('freeze 800',await rpc(leader,'freeze_event_roster',{eid:id})===800);
  for(const s of staff)await rpc(leader,'assign_event_staff',{eid:id,staff_uid:s.id});
  if(mixed)check('enable offline',await rpc(leader,'enable_event_offline',{eid:id})===true);
  const open=await rpc(leader,'open_event',{eid:id});check('opened',open[0]?.event_state==='OPEN');
  check('roster and assignments',cnt('event_roster','event_id='+q(id))===800&&cnt('event_staff','event_id='+q(id))===8);
  log('EVENT_READY',{phase,roster:800,checkpoints:cps.length,staff:8,windowSeconds:w/1000});
  return {id,cps,mixed};
};
const payload=(e,cp,student,id=uuid())=>({p_scan_id:id,p_event_id:e.id,p_checkpoint_id:e.cps[cp].id,p_student_id:student});
const scanRows=e=>rows('attendance_scans','event_id='+q(e.id));
const claimRows=e=>rows('offline_capture_claims','event_id='+q(e.id));
const sameTime=(a,b)=>Date.parse(a)===Date.parse(b);
const readReceipt=id=>rows('attendance_scans','scan_id='+q(id))[0];
const readClaim=id=>rows('offline_capture_claims','capture_id='+q(id))[0];
const state=e=>rows('events','id='+q(e.id))[0].state;
const expectedSlots=new Set(Array.from({length:760},(_,i)=>'0/'+sid(i+1)).concat(Array.from({length:720},(_,i)=>'1/'+sid(i+1))));
const checkScans=(e,ledger,canonicalExpected)=>{
  const actual=scanRows(e), online=actual.filter(r=>r.source==='online');
  eq(online.length,ledger.length);
  const map=new Map(online.map(r=>[r.scan_id,r]));
  for(const l of ledger){const r=map.get(l.p.p_scan_id);check('exact online ledger',!!r&&r.event_id===e.id&&r.checkpoint_id===l.p.p_checkpoint_id&&r.student_id===l.p.p_student_id&&r.submitted_by===l.who.id&&r.outcome===l.outcome&&sameTime(r.received_at,l.at));}
  const counts=Object.fromEntries(['accepted','duplicate','rejected'].map(k=>[k,actual.filter(r=>r.outcome===k).length]));
  eq(counts,canonicalExpected);
  const slots=actual.filter(r=>r.outcome==='accepted').map(r=>e.cps.findIndex(c=>c.id===r.checkpoint_id)+'/'+r.student_id);
  eq(new Set(slots).size,slots.length);return new Set(slots);
};
const submitOnline=async(l,{lost=false,delay=0,adversarial=false}={})=>{
  let a=await rpc(l.who,'ingest_attendance_scan',l.p,{tag:delay?'injected':'new',discard:lost,delay,adversarial});
  if(lost){
    const durable=readReceipt(l.p.p_scan_id);check('lost online receipt durable',!!durable);
    a=await rpc(l.who,'ingest_attendance_scan',l.p,{tag:'replay',adversarial});
    check('lost online exact replay',a.replayed===true&&a.outcome===durable.outcome&&sameTime(a.received_at,durable.received_at));
  }else check('new online receipt',a.replayed===false);
  check('online receipt id',a.scan_id===l.p.p_scan_id);
  l.at=a.received_at;l.outcome=a.outcome;l.lost=lost;
  if(l.expected)eq(l.outcome,l.expected);
  return l;
};
const replayOnline=async l=>{const a=await rpc(l.who,'ingest_attendance_scan',l.p,{tag:'replay'});check('online replay immutable',a.replayed===true&&a.scan_id===l.p.p_scan_id&&a.outcome===l.outcome&&sameTime(a.received_at,l.at));};
const checkPages=async(e,final=false)=>{
  const name=final?'get_event_finalized_results':'get_event_checkpoint_coverage', expected=final?800:1600, result=[];
  for(let off=0;off<=expected;off+=200){const page=await rpc(leader,name,{eid:e.id,p_limit:200,p_offset:off},{tag:'manager-read'});eq(page.length,Math.min(200,expected-off));result.push(...page);}
  if(final){
    for(let i=0;i<800;i++){const r=result[i],n=i+1;eq(r.student_id,sid(n));eq(r.status,n<=720?'PRESENT':n<=760?'INCOMPLETE':'ABSENT');eq(r.required_checkpoint_count,2);eq(r.accepted_checkpoint_count,n<=720?2:n<=760?1:0);}
  }else{
    const expectedOrder=Array.from({length:800},(_,i)=>[0,1].map(cp=>cp+'/'+sid(i+1))).flat();
    eq(result.map(r=>e.cps.findIndex(c=>c.id===r.checkpoint_id)+'/'+r.student_id),expectedOrder);
    const actual=new Map(scanRows(e).filter(r=>r.outcome==='accepted').map(r=>[e.cps.findIndex(c=>c.id===r.checkpoint_id)+'/'+r.student_id,r.received_at]));
    for(const r of result){const key=e.cps.findIndex(c=>c.id===r.checkpoint_id)+'/'+r.student_id;eq(r.has_accepted_scan,actual.has(key));if(actual.has(key))check('coverage exact timestamp',sameTime(r.accepted_received_at,actual.get(key)));else eq(r.accepted_received_at,null);}
  }
  return result.length;
};
const finalize=async e=>{
  const a=await rpc(leader,'finalize_event',{eid:e.id},{tag:'finalize'});eq(a.record_count,800);check('finalized',state(e)==='FINALIZED'&&!a.replayed);
  const before=rows('attendance_records','event_id='+q(e.id)).sort((a,b)=>a.student_id.localeCompare(b.student_id));
  const r=await rpc(leader,'finalize_event',{eid:e.id},{tag:'replay'});
  check('finalize replay',r.replayed&&r.record_count===a.record_count&&sameTime(r.finalized_at,a.finalized_at)&&r.finalized_by===a.finalized_by);
  eq(rows('attendance_records','event_id='+q(e.id)).sort((a,b)=>a.student_id.localeCompare(b.student_id)),before);
  eq(await checkPages(e,true),800);
  log('FINAL',{phase,records:800,present:720,incomplete:40,absent:40});
};
const onlinePhase=async(e,workers,cp,ledger)=>{
  const end=Date.parse(e.cps[cp].closes_at),start=Date.parse(e.cps[cp].opens_at);
  await until(start+150);
  const lo=e.mixed?161:1,hi=cp===0?760:720;
  const make=(n,who,expected)=>({p:payload(e,cp,typeof n==='number'?sid(n):n),who,expected});
  const race=[make(lo,workers[0],null),make(lo,workers[1],null)];
  await all(race.map(l=>submitOnline(l)));eq(race.map(l=>l.outcome).sort(),['accepted','duplicate']);ledger.push(...race);
  const primary=Array.from({length:hi-lo},(_,i)=>make(lo+i+1,workers[i%workers.length],'accepted'));
  const other=Array.from({length:39},(_,i)=>make(lo+i,workers[i%workers.length],'duplicate')).concat(Array.from({length:8},(_,i)=>make('SYNTHETIC-OUTSIDE-'+cp+'-'+i,workers[(39+i)%workers.length],'rejected')));
  // Two bounded paced samples, each 60 unique primary calls.
  for(const [segment,step,offset] of [['baseline',500,0],['peak',375,60]]){
    const paced=primary.slice(offset,offset+60), pacedStart=performance.now();let maxLag=0, maxBacklog=0, managerRead;
    for(let i=0;i<paced.length;i++){
      const due=pacedStart+i*step;await sleep(Math.max(0,due-performance.now()));
      maxLag=Math.max(maxLag,performance.now()-due);maxBacklog=Math.max(maxBacklog,Math.floor(Math.max(0,performance.now()-due)/step));
      if(i===0)managerRead=rpc(leader,'get_event_checkpoint_coverage',{eid:e.id,p_limit:200,p_offset:0},{tag:'manager-read'}).then(()=>null,e=>e);
      await submitOnline(paced[i],{lost:offset===0&&i<8});ledger.push(paced[i]);
      if(managerRead&&i===0){const error=await managerRead;if(error)throw error;}
    }
    const elapsed=(performance.now()-pacedStart)/1000;
    const pace={phase,checkpoint:cp,segment,offered:1000/step,unique:60,elapsedSeconds:elapsed,achieved:60/elapsed,maxLagMs:maxLag,maxBacklog,finalLagMs:Math.max(0,performance.now()-(pacedStart+60*step))};paceSamples.push(pace);log('STEADY',pace);
  }
  const burstStart=performance.now();
  for(let i=120;i<primary.length;i+=workers.length){
    const batch=primary.slice(i,i+workers.length);await all(batch.map(l=>submitOnline(l)));ledger.push(...batch);
  }
  log('BURST',{phase,checkpoint:cp,workers:workers.length,unique:primary.length-120,elapsedSeconds:(performance.now()-burstStart)/1000});
  for(let i=0;i<other.length;i+=workers.length){
    const batch=other.slice(i,i+workers.length);await all(batch.map(l=>submitOnline(l,{delay:i===0?250:0})));ledger.push(...batch);
  }
  // 8 controlled lost responses + 72 explicit replays per checkpoint.
  const retry=primary.slice(8,80);
  for(let i=0;i<retry.length;i+=workers.length)await all(retry.slice(i,i+workers.length).map(replayOnline));
  await rpc(leader,'get_event_checkpoint_coverage',{eid:e.id,p_limit:200,p_offset:0},{tag:'manager-read'});
  const captured=now();check('workload inside real checkpoint window',captured<end);log('CHECKPOINT_DONE',{phase,checkpoint:cp,ledger:ledger.length,remainingWindowMs:end-captured,resource:await resources()});
  return captured;
};
const close=async e=>{await until(Date.parse(e.cps.at(-1).closes_at)+100);const a=await rpc(leader,'close_event',{eid:e.id});eq(a.event_state,'SYNCING');};
const onlineNegatives=async(e,l)=>{
  await rpc(foreign,'ingest_attendance_scan',l.p,{code:'42501',tag:'denial'});
  await rpc(l.who,'ingest_attendance_scan',{...l.p,p_student_id:sid(800)},{code:'23505',tag:'denial'});
};
const offlinePlan=(e,preps,claimed)=>{
  const result=[];
  for(let cp=0;cp<2;cp++){
    const spec=[
      ...Array.from({length:160},(_,i)=>({student:sid(i+1),eligible:true,decision:'approve',outcome:'accepted'})),
      ...Array.from({length:16},(_,i)=>({student:sid(161+i),eligible:true,decision:'approve',outcome:'duplicate'})),
      ...Array.from({length:8},(_,i)=>({student:'SYNTHETIC-OFFLINE-OUTSIDE-'+cp+'-'+i,eligible:false,decision:'reject',outcome:null})),
      ...Array.from({length:8},(_,i)=>({student:sid((cp===0?761:721)+i),eligible:true,decision:'reject',outcome:null}))
    ];
    spec.forEach((s,i)=>{const ix=i%4,p=preps[ix];result.push({...s,cp,ix,who:staff[ix+4],p:{p_preparation_id:p.preparation_id,p_capture_id:uuid(),p_checkpoint_id:e.cps[cp].id,p_student_id:s.student,p_claimed_at:iso(claimed[cp])},reason:'Synthetic individual '+s.decision+' '+(s.outcome||'no receipt')});});
  }
  return result;
};
const upload=async(l,lost=false,delay=0)=>{
  let a=await rpc(l.who,'submit_offline_capture',l.p,{tag:delay?'injected':'new',discard:lost,delay});
  if(lost){const d=readClaim(l.p.p_capture_id);check('lost claim durable',!!d);a=await rpc(l.who,'submit_offline_capture',l.p,{tag:'replay'});check('lost claim replay',a.replayed&&sameTime(a.received_at,d.received_at));}
  else eq(a.replayed,false);
  eq(Object.keys(a).sort(),['capture_id','preparation_id','received_at','replayed','status'].sort());eq(a.capture_id,l.p.p_capture_id);eq(a.preparation_id,l.p.p_preparation_id);eq(a.status,'submitted');l.at=a.received_at;
};
const replayClaim=async l=>{const a=await rpc(l.who,'submit_offline_capture',l.p,{tag:'replay'});check('claim replay immutable',a.replayed&&a.capture_id===l.p.p_capture_id&&a.preparation_id===l.p.p_preparation_id&&sameTime(a.received_at,l.at));};
const validateClaims=(e,ledger)=>{
  const actual=claimRows(e);eq(actual.length,ledger.length);const m=new Map(actual.map(r=>[r.capture_id,r]));
  for(const l of ledger){const r=m.get(l.p.p_capture_id);check('exact claim ledger',!!r&&r.event_id===e.id&&r.preparation_id===l.p.p_preparation_id&&r.checkpoint_id===l.p.p_checkpoint_id&&r.student_id===l.p.p_student_id&&r.review_eligible===l.eligible&&sameTime(r.claimed_at,l.p.p_claimed_at)&&sameTime(r.received_at,l.at));}
};
const complete=async(p,who,count,code=null)=>rpc(who,'complete_offline_preparation',{p_preparation_id:p.preparation_id,p_acknowledged_count:count},{code,tag:code?'denial':'control'});
const summary=async e=>rpc(leader,'get_event_offline_summary',{eid:e.id},{tag:'manager-read'});
const pageClaims=async e=>{const a=await rpc(leader,'get_event_offline_claims',{eid:e.id,p_limit:200,p_offset:0},{tag:'manager-read'}),b=await rpc(leader,'get_event_offline_claims',{eid:e.id,p_limit:200,p_offset:200},{tag:'manager-read'});eq([a.length,b.length],[200,184]);eq(new Set([...a,...b].map(r=>r.capture_id)).size,384);const empty=await rpc(leader,'get_event_offline_claims',{eid:e.id,p_limit:200,p_offset:400},{tag:'manager-read'});eq(empty.length,0);return [a,b];};
const historical=(live,online,claims,probe=false)=>{
  const id=uuid(),cps=live.cps.map(c=>({id:uuid(),sort_order:c.sort_order})),e={id,cps,mixed:true};
  const anchor=now(), h=n=>iso(anchor+n*3600000), assigns=staff.map(()=>uuid());
  const prep=staff.slice(4).map((s,i)=>({preparation_id:uuid(),request_id:uuid(),assignment_id:assigns[i+4],staff_user_id:s.id}));
  const o=online.map(l=>({...l,p:payload(e,live.cps.findIndex(c=>c.id===l.p.p_checkpoint_id),l.p.p_student_id),at:h(l.p.p_checkpoint_id===live.cps[0].id?-28.5:-26)}));
  const c=claims.map((l,i)=>({...l,p:{...l.p,p_capture_id:uuid(),p_preparation_id:prep[l.ix].preparation_id,p_checkpoint_id:cps[l.cp].id,p_claimed_at:h(l.cp===0?-28.5:-26)},at:iso(anchor-24.5*3600000+i*1000)}));
  const sql="begin; select set_config('request.jwt.claim.sub',"+q(leader.id)+",true);"+
    "insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,created_at,target_year_levels) values ("+[id,oid,leader.id,'Synthetic capacity historical',h(-30),h(-25),h(-32)].map(q).join(',')+",array[1]::smallint[]);"+
    "insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values "+[tuple([cps[0].id,id,'Synthetic IN','IN',h(-29),h(-28),1]),tuple([cps[1].id,id,'Synthetic OUT','OUT',h(-27),h(-25),2])].join(',')+";"+
    "insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at) select "+q(id)+",student_id,full_name,program_code,year_level,"+q(h(-31))+" from public.students"+(probe?" where student_id="+q(sid(1)):"")+";"+
    "update public.events set roster_frozen_at="+q(h(-31))+",offline_enabled=true where id="+q(id)+";"+
    "update public.events set state='OPEN',opened_at="+q(h(-30))+" where id="+q(id)+";"+
    "insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by) values "+staff.map((s,i)=>tuple([assigns[i],id,s.id,h(-30),leader.id])).join(',')+";"+
    "insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values "+prep.map(p=>tuple([p.preparation_id,p.request_id,id,p.assignment_id,p.staff_user_id,h(-29.5),h(-25)])).join(',')+";"+
    (o.length?"insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values "+o.map(l=>tuple([l.p.p_scan_id,id,l.p.p_checkpoint_id,l.p.p_student_id,l.who.id,l.at,l.outcome])).join(',')+";":"")+
    "insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible) values "+c.map(l=>tuple([l.p.p_capture_id,l.p.p_preparation_id,id,l.p.p_checkpoint_id,l.p.p_student_id,l.p.p_claimed_at,l.at,l.eligible])).join(',')+";"+
    "update public.events set state='SYNCING',closed_at="+q(h(-25))+",closed_by="+q(leader.id)+" where id="+q(id)+";commit;";
  db(sql);check('historical real cutoff',db("select (offline_upload_cutoff=(select max(closes_at)+interval '24 hours' from public.event_checkpoints where event_id=events.id) and clock_timestamp()>=offline_upload_cutoff)::text from public.events where id="+q(id))==='true');
  validateClaims(e,c);checkScans(e,o,probe?{accepted:0,duplicate:0,rejected:0}:{accepted:1160,duplicate:80,rejected:16});eq(cnt('attendance_records','event_id='+q(id)),0);
  log('HISTORICAL_SEED',{roster:probe?1:800,online:o.length,claims:c.length,preparations:4,probe,source:'separately seeded equivalent ledger; no clock change'});
  return {e,o,c,prep};
};
const reviewArgs=(e,l)=>({eid:e.id,p_capture_id:l.p.p_capture_id,p_decision:l.decision,p_reason:l.reason});
const review=async(e,l,who=leader)=>{const a=await rpc(who,'review_offline_capture',reviewArgs(e,l),{tag:'manager-review'});check('review outcome',a.decision===l.decision&&a.reason===l.reason&&a.receipt_outcome===l.outcome&&(l.decision==='approve'?!!a.receipt_id:a.receipt_id===null));return a;};
const browserOrigin='http://127.0.0.1:3000', proxyOrigin='http://127.0.0.1:54329';
let proxyFailure=false;
const startBrowser=async()=>{check('browser tooling available',!!chromium);
  // Only Web goes through this loopback counting proxy; direct RPC timings exclude it.
  proxy=createServer(async(req,res)=>{
    try{
      const target=new URL(req.url,url);check('proxy only local API',target.origin===new URL(url).origin);
      if(target.pathname.startsWith('/rest/v1/rpc/'))budget(true);
      const headers={...req.headers};delete headers.host;delete headers.connection;delete headers['content-length'];delete headers['transfer-encoding'];
      const chunks=[];for await(const c of req)chunks.push(c);
      const response=await fetch(target,{method:req.method,headers,body:['GET','HEAD'].includes(req.method)?undefined:Buffer.concat(chunks),redirect:'manual',signal:AbortSignal.timeout(12000)});
      const out=Object.fromEntries(response.headers);delete out['content-length'];delete out['content-encoding'];delete out['transfer-encoding'];delete out.connection;
      res.writeHead(response.status,out);res.end(Buffer.from(await response.arrayBuffer()));
    }catch{proxyFailure=true;res.writeHead(503);res.end('isolated proxy failure');}
  });
  await new Promise((ok,fail)=>{proxy.once('error',fail);proxy.listen(54329,'127.0.0.1',ok);});
  const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:proxyOrigin,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:anon};
  try{execFileSync('npm',['run','build'],{cwd:resolve('qa-web'),env,stdio:'ignore',timeout:180000});}catch{throw Error('pinned Web build failed');}
  server=spawn('npm',['run','start','--','--hostname','127.0.0.1','--port','3000'],{cwd:resolve('qa-web'),env,stdio:'ignore',detached:true});
  await wait(async()=>{try{return (await fetch(browserOrigin+'/login',{signal:AbortSignal.timeout(3000)})).ok;}catch{return false;}},30000);
  browser=await chromium.launch({headless:true});
};
const browserReview=async(e,claimPages,ledger,excluded)=>{
  const ctx=await browser.newContext({viewport:{width:1280,height:900}});
  await ctx.addCookies(Array.from(leader.jar,([name,value])=>({name,value,url:browserOrigin})));
  const pg=await ctx.newPage(), byId=new Map(ledger.map(l=>[l.p.p_capture_id,l])), done=new Set();
  try{
    for(let index=0;index<2;index++){
      const candidates=claimPages[index].map(r=>byId.get(r.capture_id)).filter(l=>l&&l.p.p_capture_id!==excluded);
      const picked=[];for(const kind of ['accepted','duplicate',null]){const l=candidates.find(x=>x.outcome===kind&&!picked.includes(x));if(l)picked.push(l);}
      for(const l of candidates){if(picked.length>=6)break;if(!picked.includes(l))picked.push(l);}
      eq(picked.length,6);
      for(const l of picked){
        await pg.goto(browserOrigin+'/organizations/'+oid+'/events/'+e.id+'/operations?claims_page='+(index+1),{waitUntil:'networkidle',timeout:20000});
        const form=pg.getByRole('form',{name:'Review offline claim '+l.p.p_capture_id,exact:true});
        await form.waitFor({state:'visible',timeout:12000});
        if(!l.eligible)check('ineligible native option disabled',await form.locator('option[value=approve]').evaluate(x=>x.disabled&&x.matches(':disabled')));
        await form.locator('select[name=choice]').selectOption(l.decision);
        await form.locator('textarea[name=reason]').fill(l.reason);
        await form.getByRole('checkbox').check();
        const t=performance.now();
        await form.getByRole('button',{name:'Review offline claim',exact:true}).click();
        const reload=form.getByRole('button',{name:'Reload authoritative evidence',exact:true});
        await wait(async()=>!(await form.isVisible())||await reload.isVisible(),12000);
        if(await form.isVisible()){check('review acknowledgement not error',await form.getByRole('alert').count()===0);await reload.click();}
        await form.waitFor({state:'hidden',timeout:15000});
        const audit=rows('offline_claim_reviews','capture_id='+q(l.p.p_capture_id))[0];check('browser committed individual decision',audit?.decision===l.decision&&audit.reason===l.reason&&audit.reviewed_by===leader.id);
        browserTimes.push(performance.now()-t);done.add(l.p.p_capture_id);
      }
    }
    log('BROWSER',{individualReviews:done.size,samplesMs:browserTimes,proxyRPC:browserRPC});
    return done;
  }finally{await ctx.close();}
};
const raceFixture=async()=>{
  const e=await makeEvent(false,true);await until(Date.parse(e.cps[0].opens_at)+100);
  const l={who:staff[0],p:payload(e,0,sid(1))};
  const same=await all([rpc(l.who,'ingest_attendance_scan',l.p,{tag:'race',adversarial:true}),rpc(l.who,'ingest_attendance_scan',l.p,{tag:'race',adversarial:true})]);
  check('same UUID race exact one durable',same.every(x=>x.outcome==='accepted')&&same.filter(x=>x.replayed).length===1&&sameTime(same[0].received_at,same[1].received_at)&&scanRows(e).length===1);
  await until(Date.parse(e.cps[0].closes_at)+100);
  const probe=payload(e,0,sid(2)),r=await all([rpc(leader,'close_event',{eid:e.id},{tag:'race'}),rpc(staff[1],'ingest_attendance_scan',probe,{code:['ok','55000'],tag:'race'})]);
  eq(r[0].event_state,'SYNCING');
  check('closure vs scan allowed serial outcome',r[1].denied==='55000'||r[1].outcome==='rejected');eq(scanRows(e).length,r[1].denied?1:2);
  log('RACE',{sameUUID: 'one receipt one replay',closure:r[1].denied||r[1].outcome,isolatedRows:scanRows(e).length});
};
const metricReport=()=>{
  const groups=new Map();
  for(const p of perf){const key=[p.phase,p.name,p.tag,p.outcome].join('|');if(!groups.has(key))groups.set(key,[]);groups.get(key).push(p.ms);}
  const summaries=[];for(const [key,x] of groups){const y=x.slice().sort((a,b)=>a-b), at=k=>Math.round(y[Math.max(0,Math.ceil(y.length*k)-1)]*100)/100;summaries.push({key,n:y.length,p50:at(.5),p95:at(.95),p99:at(.99),max:at(1)});}
  log('METRICS',{attempts,direct,browserRPC,maxInFlight,authUsers,groups:summaries});
  const breaches=[];
  for(const g of summaries){const [p,name,tag,outcome]=g.key.split('|');if(outcome!=='ok')continue;
    if(tag==='new'&&['ingest_attendance_scan','submit_offline_capture'].includes(name)&&(g.p95>500||g.p99>2000||g.max>5000))breaches.push(g);
    if(['manager-read','manager-review'].includes(tag)&&(g.p95>1000||g.p99>3000))breaches.push(g);
    if(tag==='finalize'&&g.max>5000)breaches.push(g);
  }
  if(browserTimes.length){const v=[...browserTimes].sort((a,b)=>a-b);if(v[Math.ceil(v.length*.95)-1]>3000)breaches.push({browserP95:v[Math.ceil(v.length*.95)-1],samples:browserTimes});}
  log('THRESHOLDS',{breaches,paceSamples,drainSeconds:drainMeasured,drainPass:drainMeasured===null?null:drainMeasured<=120});if(!process.exitCode&&(breaches.length||drainMeasured>120))process.exitCode=2;
  const lock=contention.filter(s=>s.lock_wait>0||s.locks_waiting>0), spans=new Map();let longest=0;
  for(const s of contention){const seen=new Set(s.blocked.map(x=>x.pid));for(const pid of [...spans.keys()])if(!seen.has(pid))spans.delete(pid);for(const pid of seen){if(!spans.has(pid))spans.set(pid,s.at);longest=Math.max(longest,s.at-spans.get(pid));}}
  log('CONTENTION',{samples:contention.length,failed:samplesFailed,lockSamples:lock.length,lockFraction:contention.length?lock.length/contention.length:null,longestObservedBlockMs:longest,byPhase:Object.fromEntries([...new Set(contention.map(s=>s.phase))].map(p=>[p,{samples:contention.filter(s=>s.phase===p).length,lockSamples:lock.filter(s=>s.phase===p).length}]))});
};
let statsBefore,drainMeasured=null;
try{
  check('fresh database',['events','students','attendance_scans','offline_preparations','offline_capture_claims','attendance_records'].every(t=>cnt(t)===0)&&db('select count(*) from auth.users')==='0');
  eq(db("select version from supabase_migrations.schema_migrations order by version").split('\n'),['20261106122400','20261108150500','20261108150600','20261123110600','20261124061908','20261124152537','20261124154829','20261127054432','20261127105700']);
  log('PINS',{backend:BASE,web:WEB,mobileReference:MOBILE,harness:process.env.GITHUB_SHA,runner:process.env.RUNNER_OS,node:process.version,cpu:os.cpus().length,ramBytes:os.totalmem(),db:db('show server_version'),dbConfig:db("select current_setting('max_connections')||','||current_setting('shared_buffers')"),supabaseCLI:'2.122.0',resource:await resources()});
  phase='auth/setup';leader=await actor('manager',1);other=await actor('manager',2);foreign=await actor('foreign',1);for(let i=0;i<8;i++)staff.push(await actor('staff',i));
  db("begin; insert into public.organizations(id,slug,name) values "+tuple([oid,'capacity-one','Synthetic Capacity'])+","+tuple([foreignOrg,'capacity-other','Synthetic Foreign'])+";"+
    "insert into public.organization_memberships(organization_id,user_id,role,granted_by) values "+[...([leader,other].map(a=>tuple([oid,a.id,'leader',leader.id]))),...staff.map(a=>tuple([oid,a.id,'staff',leader.id])),tuple([foreignOrg,foreign.id,'leader',foreign.id])].join(',')+";"+
    "insert into public.students(student_id,full_name,program_code,year_level) select 'SYNTHETIC-'||lpad(n::text,4,'0'),'Synthetic Capacity '||n,'BSIT',1 from generate_series(1,800) n;commit;");
  // Build browser before timed workloads; a setup failure does not become an RPC performance result.
  log('SETUP',{authUsers,privilegedFixture:true,membershipRevision:db('select min(revision) from public.organization_memberships'),onboardingRPCs:0,roster:cnt('students')});
  phase='browser-setup';let browserReady=false;try{await startBrowser();browserReady=true;}catch{log('BROWSER_NOT_RUN',{reason:'pinned Web/Playwright setup unavailable'});}
  statsBefore=dbStats();startObserver();
  phase='online-control';const control=await makeEvent(false), controlLedger=[];
  await rpc(foreign,'get_event_checkpoint_coverage',{eid:control.id},{code:'42501',tag:'denial'});await rpc(staff[0],'get_event_checkpoint_coverage',{eid:control.id},{code:'42501',tag:'denial'});log('C01_PASS',{verifiedActors:authUsers,roster:800,staff:8,managerDenials:2});
  for(let cp=0;cp<2;cp++)await onlinePhase(control,staff,cp,controlLedger);
  await close(control);await onlineNegatives(control,controlLedger[0]);await replayOnline(controlLedger[0]);await rpc(leader,'seal_offline_uploads',{eid:control.id},{code:'55000',tag:'denial'});
  eq(controlLedger.length,1576);eq(checkScans(control,controlLedger,{accepted:1480,duplicate:80,rejected:16}),expectedSlots);eq(await checkPages(control),1600);await finalize(control);
  log('ONLINE_CONTROL_PASS',{onlineRows:1576,accepted:1480,duplicate:80,rejected:16,plannedExactRetries:160,extraPostCloseReplay:1});
  phase='mixed-online';const mixed=await makeEvent(true), mixedLedger=[], preps=[];
  for(const s of staff.slice(4)){const p=await rpc(s,'prepare_offline_capture',{p_event_id:mixed.id,p_request_id:uuid()});check('preparation scope',p.event_id===mixed.id&&p.staff_user_id===s.id&&p.checkpoints.length===2&&!('roster' in p));preps.push(p);}
  const claimed=[];for(let cp=0;cp<2;cp++)claimed.push(await onlinePhase(mixed,staff.slice(0,4),cp,mixedLedger));
  const claims=offlinePlan(mixed,preps,claimed);eq(claims.length,384);eq(new Set(claims.map(l=>l.p.p_capture_id)).size,384);eq(claims.filter(l=>l.outcome==='accepted').length,320);eq(claims.filter(l=>l.outcome==='duplicate').length,32);eq(claims.filter(l=>!l.eligible).length,16);eq(claims.filter(l=>l.eligible&&l.decision==='reject').length,16);
  await close(mixed);await onlineNegatives(mixed,mixedLedger[0]);
  await rpc(leader,'seal_offline_uploads',{eid:mixed.id},{code:'55000',tag:'denial'});await rpc(leader,'finalize_event',{eid:mixed.id},{code:'55000',tag:'denial'});
  eq(mixedLedger.length,1256);checkScans(mixed,mixedLedger,{accepted:1160,duplicate:80,rejected:16});
  phase='mixed-offline-drain';const drainStart=performance.now(), queues=staff.slice(4).map((_,i)=>claims.filter(l=>l.ix===i));
  for(const a of queues)eq(a.length,96);
  await all(queues.map(async(queue,ix)=>{
    for(let n=0;n<queue.length;n++){
      if(ix===2&&n===95){
        const r=await all([upload(queue[n]),rpc(staff[ix+4],'complete_offline_preparation',{p_preparation_id:preps[ix].preparation_id,p_acknowledged_count:96},{code:['ok','22023'],tag:'race',adversarial:true})]);
        check('completion/upload allowed serialization',r[1].denied==='22023'||r[1].uploaded_count===96);
        log('COMPLETION_UPLOAD_RACE',{outcome:r[1].denied||r[1].disposition});
      }else await upload(queue[n],n===0,n===1?2000:0);
    }
    // Exact retry probes: 4 losses + 36 additional = 40.
    for(let n=2;n<2+9;n++)await replayClaim(queue[n]);
  }));
  const drainSeconds=(performance.now()-drainStart)/1000;drainMeasured=drainSeconds;
  log('DRAIN',{claims:384,exactRetries:40,workers:4,seconds:drainSeconds,uniquePerSecond:384/drainSeconds});
  validateClaims(mixed,claims);eq(cnt('attendance_scans','event_id='+q(mixed.id)),1256);eq(cnt('attendance_records','event_id='+q(mixed.id)),0);
  for(let i=0;i<4;i++){const s=await rpc(staff[i+4],'get_offline_preparation_status',{p_preparation_id:preps[i].preparation_id});eq(s.uploaded_count,96);check('status no oracle',!('review_eligible' in s)&&!('decision' in s));}
  await complete(preps[0],staff[4],95,'22023');
  await all([0,1,2].map(async i=>{const a=await complete(preps[i],staff[i+4],96);eq(a.uploaded_count,96);eq(a.declared_count,96);eq(a.disposition,'completed');}));
  const replay=await complete(preps[0],staff[4],96);check('completion replay',replay.replayed);await complete(preps[0],staff[4],97,'23505');
  const l=queues[0][0];await rpc(l.who,'submit_offline_capture',{...l.p,p_student_id:sid(800)},{code:'23505',tag:'denial'});
  await rpc(staff[5],'submit_offline_capture',l.p,{code:'42501',tag:'denial'});
  await rpc(l.who,'submit_offline_capture',{...l.p,p_capture_id:uuid()},{code:'55000',tag:'denial'});
  await rpc(leader,'revoke_event_staff',{assignment_id:preps[3].assignment_id});
  await rpc(staff[7],'submit_offline_capture',queues[3][0].p,{code:'42501',tag:'denial'});
  validateClaims(mixed,claims);
  const ms=await summary(mixed);eq([ms.claim_count,ms.completed_count,ms.unaccounted_count,ms.reviewed_count],[384,3,1,0]);check('live gates stay closed',!ms.can_confirm&&!ms.can_finalize);
  log('MIXED_LIVE_PASS',{onlineRows:1256,claims:384,completed:3,unaccounted:1,canonicalOffline:0,reviewed:0});
  phase='isolated-races';await raceFixture();
  const probe=historical(mixed,[],[claims[0]],true),pc=probe.c[0];
  const sealRace=await all([rpc(leader,'seal_offline_uploads',{eid:probe.e.id},{tag:'race'}),rpc(other,'review_offline_capture',reviewArgs(probe.e,pc),{code:['ok','55000'],tag:'race'})]);
  check('seal/review serialized',!!sealRace[0].sealed_at&&(sealRace[1].denied==='55000'||sealRace[1].receipt_outcome==='accepted'));
  if(sealRace[1].denied)await review(probe.e,pc,other);
  eq(cnt('offline_claim_reviews','capture_id='+q(pc.p.p_capture_id)),1);eq(scanRows(probe.e).length,1);log('SEAL_REVIEW_RACE',{outcome:sealRace[1].denied||'accepted',durableReviews:1,durableReceipts:1,separateFixture:true});
  phase='historical-reconciliation';const hist=historical(mixed,mixedLedger,claims), e=hist.e;
  const seal=await rpc(leader,'seal_offline_uploads',{eid:e.id});check('sealed',!seal.replayed);
  await rpc(leader,'confirm_offline_reconciliation',{eid:e.id},{code:'55000',tag:'denial'});await rpc(leader,'finalize_event',{eid:e.id},{code:'55000',tag:'denial'});
  const h0=hist.c.find(l=>l.ix===3);await rpc(h0.who,'submit_offline_capture',{...h0.p,p_capture_id:uuid()},{code:'55000',tag:'denial'});await replayClaim(h0);
  for(let i=0;i<3;i++){const a=await complete(hist.prep[i],staff[i+4],96);eq(a.uploaded_count,96);}
  const lossArgs={eid:e.id,p_preparation_id:hist.prep[3].preparation_id,p_disposition:'undrained',p_reason:'Synthetic incomplete preparation declaration; durable claims retained'};
  const loss=await rpc(leader,'account_offline_preparation_loss',lossArgs);eq(loss.uploaded_count,96);eq(loss.declared_count,null);eq(loss.disposition,'undrained');
  const invalid=hist.c.find(l=>!l.eligible);await rpc(leader,'review_offline_capture',{...reviewArgs(e,invalid),p_decision:'approve'},{code:'55000',tag:'denial'});
  await rpc(leader,'confirm_offline_reconciliation',{eid:e.id},{code:'55000',tag:'denial'});await rpc(leader,'finalize_event',{eid:e.id},{code:'55000',tag:'denial'});
  const first=hist.c[0], race=await all([review(e,first,leader),review(e,first,other)]);
  eq(race.filter(a=>a.replayed).length,1);eq(race[0].receipt_id,race[1].receipt_id);check('review race timestamp',sameTime(race[0].reviewed_at,race[1].reviewed_at));
  await rpc(other,'review_offline_capture',{...reviewArgs(e,first),p_reason:first.reason+' changed'},{code:'23505',tag:'denial'});
  await rpc(foreign,'get_event_offline_summary',{eid:e.id},{code:'42501',tag:'denial'});await rpc(staff[0],'get_event_offline_claims',{eid:e.id},{code:'42501',tag:'denial'});
  const pages=await pageClaims(e);let browserDone=new Set();
  if(browserReady){phase='browser-sample';browserDone=await browserReview(e,pages,hist.c,first.p.p_capture_id);check('browser proxy healthy',!proxyFailure);}
  phase='historical-reconciliation';const t=performance.now();
  for(const claim of hist.c){if(claim===first||browserDone.has(claim.p.p_capture_id))continue;await review(e,claim);}
  log('REVIEW_MACHINE',{individualReviews:384,browser:browserDone.size,rpc:384-browserDone.size,sequentialRPCSeconds:(performance.now()-t)/1000,notHumanTime:true});
  validateClaims(e,hist.c);
  const reviews=rows('offline_claim_reviews','capture_id in(select capture_id from public.offline_capture_claims where event_id='+q(e.id)+')');eq(reviews.length,384);
  const scans=scanRows(e), sm=new Map(scans.filter(r=>r.source==='offline').map(r=>[r.offline_capture_id,r]));eq(sm.size,352);
  const rm=new Map(reviews.map(r=>[r.capture_id,r]));
  for(const l of hist.c){const r=rm.get(l.p.p_capture_id),s=sm.get(l.p.p_capture_id);check('individual immutable review',r?.decision===l.decision&&r.reason===l.reason&&[leader.id,other.id].includes(r.reviewed_by));
    if(l.decision==='reject')check('reject no promotion',!s&&r.receipt_id===null);
    else check('canonical provenance',!!s&&s.scan_id!==l.p.p_capture_id&&r.receipt_id===s.scan_id&&s.outcome===l.outcome&&s.student_id===l.student&&s.checkpoint_id===l.p.p_checkpoint_id&&s.submitted_by===l.who.id&&sameTime(s.received_at,l.at));
  }
  eq(checkScans(e,hist.o,{accepted:1480,duplicate:112,rejected:16}),expectedSlots);
  const finalSummary=await summary(e);eq([finalSummary.preparation_count,finalSummary.completed_count,finalSummary.loss_count,finalSummary.unaccounted_count,finalSummary.claim_count,finalSummary.reviewed_count,finalSummary.unreviewed_count],[4,3,1,0,384,384,0]);check('can confirm not finalize',finalSummary.can_confirm&&!finalSummary.can_finalize);
  await rpc(leader,'finalize_event',{eid:e.id},{code:'55000',tag:'denial'});
  await checkPages(e);await rpc(leader,'confirm_offline_reconciliation',{eid:e.id});check('can finalize',(await summary(e)).can_finalize);
  await finalize(e);await review(e,first);eq(cnt('offline_claim_reviews','capture_id in(select capture_id from public.offline_capture_claims where event_id='+q(e.id)+')'),384);
  await pageClaims(e);
  log('HISTORICAL_PASS',{claims:384,reviews:384,approved:352,rejected:32,accepted:1480,duplicate:112,rejectedOnline:16,canonicalRows:1608,accounted:4,coverage:1600,results:800});
  phase='finish';log('DB_STATS',{before:statsBefore,after:dbStats(),resource:await resources()});
  check('zero deadlock delta',dbStats().deadlocks===statsBefore.deadlocks);
  log('COMPLETE',{attempts,maximum:6000,physical:'NOT_RUN',human:'NOT_RUN',historicalSeparate:true,scope:'disposable runner only'});
}catch(e){console.error('CAPACITY FAIL '+phase+' '+(e?.name==='AssertionError'?'assertion mismatch':String(e?.message||'unknown').slice(0,160)));process.exitCode=1;}
finally{
  stopObserver();metricReport();if(statsBefore)try{log('TERMINAL_DB_STATS',{before:statsBefore,after:dbStats(),resource:await resources()});}catch{log('TERMINAL_DB_STATS_UNAVAILABLE');}
  if(browser)await browser.close().catch(()=>{});
  if(server?.pid)try{process.kill(-server.pid,'SIGTERM');}catch{}
  if(proxy)proxy.closeAllConnections();if(proxy)proxy.close();
}
