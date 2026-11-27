import assert from 'node:assert/strict';
import { execFileSync } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import os from 'node:os';

const BASE='43dcb7febd5cdc1b50bb249487f92f1fe66fa21d';
const MIGRATION='supabase/migrations/20261127054432_optimize_checkpoint_coverage.sql';
const check=(label,ok)=>{if(!ok)throw Error(label);};
const eq=(a,b)=>assert.deepEqual(a,b);
const log=(tag,value)=>console.log('COVERAGE002 '+tag+' '+JSON.stringify(value));
const temp=process.env.RUNNER_TEMP;
check('runner guard',process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted'&&process.env.GITHUB_REF==='refs/heads/fix/coverage-perf-002'&&process.env.HNU_DASH_ISOLATED_TEST_DB==='1'&&!!temp);
const cfg=JSON.parse(readFileSync(resolve(temp,'coverage-perf-002-local.json'),'utf8'));
const url=cfg.API_URL,anon=cfg.ANON_KEY||cfg.PUBLISHABLE_KEY,service=cfg.SERVICE_ROLE_KEY||cfg.SECRET_KEY;
check('isolated loopback API',/^http:\/\/(localhost|127\.0\.0\.1):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const args=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=sql=>{try{return execFileSync('docker',args,{input:sql,encoding:'utf8',timeout:20000,stdio:['pipe','pipe','pipe'],maxBuffer:4000000}).trim();}catch(e){throw Error('isolated SQL '+(String(e.stderr).includes('statement timeout')?'statement timeout':'failed'));}};
const json=sql=>JSON.parse(db(sql)),q=v=>"'"+String(v).replaceAll("'","''")+"'",tup=xs=>'('+xs.map(q).join(',')+')';
const id=randomUUID,iso=t=>new Date(t).toISOString(),sid=n=>'SYNTHETIC-'+String(n).padStart(4,'0');
const now=()=>Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
let stage='preflight',calls=0,plans=0,samples=[],planReports=[],overTarget=[];
const budget=()=>{check('coverage execution ceiling 64',calls+plans<64);};
const request=async(path,token,key,body)=>{
  const t=performance.now();
  const response=await fetch(url+path,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(12000)});
  const data=await response.json();
  return {ok:response.ok,status:response.status,data,ms:performance.now()-t};
};
const rpc=async(who,name,body)=>{
  const r=await request('/rest/v1/rpc/'+name,who.token,anon,body);
  check('setup RPC '+name+' '+(r.data?.code||''),r.ok);return r.data;
};
const actor=async(kind)=>{
  const email='coverage002-'+kind+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph',password=randomBytes(24).toString('hex')+'Aa1!';
  const c=await request('/auth/v1/admin/users',service,service,{email,password,email_confirm:true});
  check('synthetic Auth create',c.ok&&!!c.data.id);
  const a=await request('/auth/v1/token?grant_type=password',anon,anon,{email,password});
  check('actual password Auth login',a.ok&&a.data.user?.id===c.data.id&&!!a.data.access_token);
  const claims=JSON.parse(Buffer.from(a.data.access_token.split('.')[1],'base64url').toString('utf8'));
  check('actual JWT',claims.role==='authenticated'&&claims.sub===c.data.id);
  const who={id:c.data.id,token:a.data.access_token,claims,kind};
  eq(await rpc(who,'hnu_verified_user',{}),true);return who;
};
const fixture={eid:id(),org:id(),otherOrg:id(),cp:[id(),id()]};
const expected=(f,n,offset,limit=200,studentCount=600)=>{
  const length=Math.max(0,Math.min(limit,studentCount*f.cp.length-offset));
  return Array.from({length},(_,i)=>{
    const pos=offset+i,student=Math.floor(pos/f.cp.length)+1,cp=pos%f.cp.length,accepted=cp===0&&student<=n;
    return {student_id:sid(student),checkpoint_id:f.cp[cp],checkpoint_label:cp===0?'Synthetic IN':'Synthetic OUT',checkpoint_direction:cp===0?'IN':'OUT',checkpoint_sort_order:cp+1,has_accepted_scan:accepted,accepted_received_at:accepted?f.received:null};
  });
};
const normalize=data=>data.map(r=>({...r,accepted_received_at:r.accepted_received_at===null?null:new Date(r.accepted_received_at).toISOString()}));
const coverage=async(label,who,body,expectedRows=null,expectedCode=null,measure=true)=>{
  budget();calls++;
  const r=await request('/rest/v1/rpc/get_event_checkpoint_coverage',who.token,anon,body);
  const code=r.ok?'ok':r.data?.code||'unknown';
  const record={label,actor:who.kind,offset:body.p_offset??0,limit:body.p_limit??200,http:r.status,code,ms:Math.round(r.ms*100)/100,rows:r.ok?r.data.length:null};
  log('RPC',record);
  if(expectedCode){check('denial '+label,!r.ok&&[expectedCode].flat().includes(code));return;}
  check('coverage RPC '+label+' '+code,r.ok&&Array.isArray(r.data));
  eq(normalize(r.data),expectedRows);
  if(measure){samples.push(record);if(r.ms>1000)overTarget.push(record);}
  return r.data;
};
const page=async(label,who,f,n,offset,limit=200)=>coverage(label,who,{eid:f.eid,p_limit:limit,p_offset:offset},expected(f,n,offset,limit));
const sweep=async(label,who,f,n)=>{
  const rows=[];
  for(let off=0;off<=1200;off+=200)rows.push(...await page(label,who,f,n,off));
  eq(rows.length,1200);eq(new Set(rows.map(r=>r.student_id+'/'+r.checkpoint_id)).size,1200);eq(rows.filter(r=>r.has_accepted_scan).length,n);
  log('SWEEP_PASS',{label,actor:who.kind,pages:7,rows:1200,accepted:n,emptyEnd:true});
};
const seed=(start,end,dupStart,dupEnd,rejStart,rejEnd,staff)=>{
  const rows=[],receipt=(student,outcome)=>tup([id(),fixture.eid,fixture.cp[0],student,staff.id,fixture.received,outcome]);
  for(let i=start;i<=end;i++)rows.push(receipt(sid(i),'accepted'));
  for(let i=dupStart;i<=dupEnd;i++)rows.push(receipt(sid(i),'duplicate'));
  for(let i=rejStart;i<=rejEnd;i++)rows.push(receipt('SYNTHETIC-OUTSIDE-'+i,'rejected'));
  db("insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values "+rows.join(',')+";");
};
const counts=eid=>json("select coalesce(json_object_agg(outcome,n),'{}'::json) from (select outcome,count(*) n from public.attendance_scans where event_id="+q(eid)+" group by outcome) s");
const inner=readFileSync(MIGRATION,'utf8').match(/return query\s+([\s\S]*?);/i)?.[1];
check('exact inner query',!!inner);
const capturePlan=(label,who,offset)=>{
  budget();plans++;
  const query=inner.replace(/\beid\b/g,q(fixture.eid)+'::uuid').replace(/\bp_limit\b/g,'200').replace(/\bp_offset\b/g,String(offset));
  const sql="begin read only;\nset local track_functions='all';\nset local role authenticated;\nset local \"request.jwt.claims\"="+q(JSON.stringify(who.claims))+";\nset local statement_timeout='8s';\nset local search_path='';\n"+
    "\\echo CONTEXT\nselect json_build_object('role',current_user,'row_security',current_setting('row_security'),'timeout',current_setting('statement_timeout'),'uid_matches',auth.uid()="+q(who.id)+"::uuid,'verified',public.hnu_verified_user(),'manages_org',public.can_manage_org("+q(fixture.org)+"::uuid));\n"+
    "\\echo PLAN\nEXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT JSON) "+query+";\n"+
    "\\echo FUNCTIONS\nselect coalesce(json_agg(row_to_json(s)),'[]'::json) from (select schemaname,funcname,calls,total_time,self_time from pg_stat_xact_user_functions where schemaname in ('public','auth') order by calls desc,funcname) s;\n\\echo END\nrollback;";
  let out;try{out=db(sql);}catch(e){log('PLAN_INCONCLUSIVE',{label,reason:e.message});return false;}
  const m=out.match(/CONTEXT\n([\s\S]*?)\nPLAN\n([\s\S]*?)\nFUNCTIONS\n([\s\S]*?)\nEND/);
  check('plan sections',!!m);const ctx=JSON.parse(m[1]),p=JSON.parse(m[2])[0],functions=JSON.parse(m[3]);
  check('authenticated RLS context',ctx.role==='authenticated'&&ctx.row_security==='on'&&ctx.timeout==='8s'&&ctx.uid_matches&&ctx.verified&&ctx.manages_org);
  eq(p.Plan['Actual Rows'],200);
  const report={label,offset,executionMs:p['Execution Time'],planningMs:p['Planning Time'],sharedHits:p.Plan['Shared Hit Blocks'],sharedReads:p.Plan['Shared Read Blocks'],functions,context:ctx};planReports.push(report);log('PLAN',report);log('EXPLAIN_JSON',{label,plan:p});return true;
};
const stat=()=>json("select row_to_json(s) from (select xact_commit,xact_rollback,deadlocks,blks_read,blks_hit from pg_stat_database where datname=current_database()) s");
const offlineRegression=async(manager,admin,staff)=>{
  const f={eid:id(),cp:[id()]},assignment=id(),prep=id(),claim=id(),dupe=id(),unreviewed=id(),online=id(),t=now(),h=n=>iso(t+n*3600000);
  f.received=h(-24);
  // Independent tiny historical fixture, no clock manipulation and no offline workload.
  db("begin; select set_config('request.jwt.claim.sub',"+q(manager.id)+",true);"+
    "insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,created_at,target_year_levels) values ("+[f.eid,fixture.org,manager.id,'Synthetic offline coverage',h(-30),h(-25),h(-32)].map(q).join(',')+",array[1]::smallint[]);"+
    "insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values "+tup([f.cp[0],f.eid,'Synthetic IN','IN',h(-29),h(-25),1])+";"+
    "insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at) select "+q(f.eid)+",student_id,full_name,program_code,year_level,"+q(h(-31))+" from public.students where student_id in ("+[1,2,3].map(n=>q(sid(n))).join(',')+");"+
    "update public.events set roster_frozen_at="+q(h(-31))+",offline_enabled=true where id="+q(f.eid)+";"+
    "update public.events set state='OPEN',opened_at="+q(h(-30))+" where id="+q(f.eid)+";"+
    "insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by) values "+tup([assignment,f.eid,staff.id,h(-30),manager.id])+";"+
    "insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values "+tup([prep,id(),f.eid,assignment,staff.id,h(-28),h(-25)])+";"+
    "insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible) values "+[tup([claim,prep,f.eid,f.cp[0],sid(1),h(-27),f.received,true]),tup([dupe,prep,f.eid,f.cp[0],sid(2),h(-27),f.received,true]),tup([unreviewed,prep,f.eid,f.cp[0],sid(3),h(-27),f.received,true])].join(',')+";"+
    "insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values "+tup([online,f.eid,f.cp[0],sid(2),staff.id,h(-27),'accepted'])+";"+
    "update public.events set state='SYNCING',closed_at="+q(h(-25))+",closed_by="+q(manager.id)+" where id="+q(f.eid)+";commit;");
  const expectedOffline=(promoted)=>expected(f,0,0,200,3).map((r,i)=>({...r,has_accepted_scan:i===1||(i===0&&promoted),accepted_received_at:i===1?h(-27):i===0&&promoted?f.received:null}));
  await coverage('offline_before_promotion',manager,{eid:f.eid},expectedOffline(false),null,false);
  await rpc(manager,'seal_offline_uploads',{eid:f.eid});
  const a=await rpc(manager,'review_offline_capture',{eid:f.eid,p_capture_id:claim,p_decision:'approve',p_reason:'Synthetic coverage accepted'});
  const d=await rpc(manager,'review_offline_capture',{eid:f.eid,p_capture_id:dupe,p_decision:'approve',p_reason:'Synthetic coverage duplicate'});
  eq(a.receipt_outcome,'accepted');eq(d.receipt_outcome,'duplicate');
  for(const actor of [manager,admin])await coverage('offline_after_promotion',actor,{eid:f.eid},expectedOffline(true),null,false);
  eq(counts(f.eid),{accepted:2,duplicate:1});
  log('OFFLINE_PASS',{actualPromotion:true,accepted:2,duplicate:1,unreviewedExcluded:true,timestampExact:true,roles:['leader','platform_admin']});
};
try{
  eq(db("select version from supabase_migrations.schema_migrations order by version").split('\n'),['20261106122400','20261108150500','20261108150600','20261123110600','20261124061908','20261124152537','20261124154829','20261127054432']);
  check('fresh isolated fixture',db("select ((select count(*) from auth.users)=0 and (select count(*) from public.events)=0 and (select count(*) from public.students)=0 and (select count(*) from public.attendance_scans)=0)::text")==='true');
  const installed=db("select prosrc from pg_proc where oid='public.get_event_checkpoint_coverage(uuid,integer,integer)'::regprocedure");
  eq(installed.match(/return query\s+([\s\S]*?);/i)?.[1],inner);
  const contract=json("select json_build_object('invoker',not prosecdef,'stable',provolatile='s','config',proconfig,'args',pg_get_function_arguments(oid),'result',pg_get_function_result(oid),'anonExecute',has_function_privilege('anon',oid,'EXECUTE'),'authenticatedExecute',has_function_privilege('authenticated',oid,'EXECUTE')) from pg_proc where oid='public.get_event_checkpoint_coverage(uuid,integer,integer)'::regprocedure");
  check('unchanged invoker contract',contract.invoker&&contract.stable&&contract.config.includes('search_path=""')&&!contract.anonExecute&&contract.authenticatedExecute);
  const timeouts=json("select json_object_agg(rolname,rolconfig) from pg_roles where rolname in ('authenticated','authenticator')");
  for(const role of ['authenticated','authenticator'])check('normal 8-second timeout '+role,timeouts[role].includes('statement_timeout=8s'));
  log('PINS',{baseline:BASE,candidate:process.env.GITHUB_SHA,db:db('show server_version'),node:process.version,cpu:os.cpus().length,ramBytes:os.totalmem(),contract,timeouts});
  stage='fixture';
  const manager=await actor('leader'),admin=await actor('platform-admin'),staff=await actor('staff'),foreign=await actor('foreign-leader'),unverified=await actor('unverified');
  const t=now(),unfrozen=id();
  db("begin; select set_config('request.jwt.claim.sub',"+q(manager.id)+",true);"+
    "insert into public.organizations(id,slug,name) values "+tup([fixture.org,'coverage-two-one','Synthetic Coverage'])+","+tup([fixture.otherOrg,'coverage-two-other','Synthetic Other'])+";"+
    "insert into public.platform_admins(user_id) values ("+q(admin.id)+");"+
    "insert into public.organization_memberships(organization_id,user_id,role,granted_by) values "+[tup([fixture.org,manager.id,'leader',admin.id]),tup([fixture.org,staff.id,'staff',admin.id]),tup([fixture.otherOrg,foreign.id,'leader',admin.id]),tup([fixture.org,unverified.id,'leader',admin.id])].join(',')+";"+
    "update auth.users set email_confirmed_at=null where id="+q(unverified.id)+";"+
    "insert into public.students(student_id,full_name,program_code,year_level) select 'SYNTHETIC-'||lpad(n::text,4,'0'),'Synthetic Coverage '||n,'BSIT',1 from generate_series(1,600) n;"+
    "insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,target_year_levels) values "+[fixture.eid,unfrozen].map(e=>"("+[e,fixture.org,manager.id,'Synthetic Coverage',iso(t-600000),iso(t+1200000)].map(q).join(',')+",array[1]::smallint[])").join(',')+";"+
    "insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values "+[tup([fixture.cp[0],fixture.eid,'Synthetic IN','IN',iso(t-60000),iso(t+600000),1]),tup([fixture.cp[1],fixture.eid,'Synthetic OUT','OUT',iso(t+601000),iso(t+1190000),2])].join(',')+";commit;");
  eq(await rpc(unverified,'hnu_verified_user',{}),false);
  eq(await rpc(manager,'freeze_event_roster',{eid:fixture.eid}),600);
  await rpc(manager,'assign_event_staff',{eid:fixture.eid,staff_uid:staff.id});
  eq(await rpc(staff,'can_access_assigned_event',{eid:fixture.eid}),true);
  eq((await rpc(manager,'open_event',{eid:fixture.eid}))[0].event_state,'OPEN');
  fixture.received=iso(now());
  const before=stat();
  stage='low';
  seed(1,2,1,1,1,0,staff);eq(counts(fixture.eid),{accepted:2,duplicate:1});
  log('FIXTURE',{phase:'low',roster:600,checkpoints:2,counts:counts(fixture.eid),seeded:true});
  // First RPC and EXPLAIN use the same low-density fixture as PERF-001.
  await page('low_first',manager,fixture,2,0);
  const lowPlan=capturePlan('low_authenticated_inner',manager,0);
  for(const who of [manager,admin])await sweep('low_all_pages',who,fixture,2);
  stage='populated';
  seed(3,570,2,30,1,6,staff);eq(counts(fixture.eid),{accepted:570,duplicate:30,rejected:6});
  log('FIXTURE',{phase:'populated',roster:600,checkpoints:2,counts:counts(fixture.eid),seeded:true});
  await page('populated_first',manager,fixture,570,0);
  const highPlan=capturePlan('populated_authenticated_inner',manager,0);
  for(const who of [manager,admin])await sweep('populated_all_pages',who,fixture,570);
  for(let i=0;i<3;i++)for(const offset of [0,200,1000])await page('populated_repeat_'+(i+1),manager,fixture,570,offset);
  await page('nonaligned_partial',manager,fixture,570,1197,7);
  await page('odd_offset',manager,fixture,570,1,3);
  await page('beyond_end',manager,fixture,570,1201);
  await coverage('default_arguments',manager,{eid:fixture.eid},expected(fixture,570,0));
  stage='denials';
  for(const who of [foreign,staff,unverified])await coverage('denied_'+who.kind,who,{eid:fixture.eid},null,'42501',false);
  await coverage('denied_anon',{kind:'anon',token:anon},{eid:fixture.eid},null,['42501','PGRST202'],false);
  await coverage('unknown_event',manager,{eid:id()},null,'42501',false);
  await coverage('unfrozen_event',manager,{eid:unfrozen},null,'55000',false);
  for(const [label,body] of [['null_event',{eid:null}],['zero_limit',{eid:fixture.eid,p_limit:0}],['excess_limit',{eid:fixture.eid,p_limit:201}],['null_limit',{eid:fixture.eid,p_limit:null}],['negative_offset',{eid:fixture.eid,p_offset:-1}],['null_offset',{eid:fixture.eid,p_offset:null}]])await coverage(label,manager,body,null,'22023',false);
  stage='offline_regression';await offlineRegression(manager,admin,staff);
  eq(counts(fixture.eid),{accepted:570,duplicate:30,rejected:6});
  eq(db('select count(*) from public.attendance_records'),'0');
  const after=stat();eq(after.deadlocks,before.deadlocks);
  log('DB_STATS',{before,after});
  const sorted=samples.map(r=>r.ms).sort((a,b)=>a-b),pct=p=>sorted[Math.max(0,Math.ceil(sorted.length*p)-1)];
  log('SUMMARY',{calls,plans,cap:64,correctness:true,lowPlan,highPlan,successfulTimedReads:samples.length,p50:pct(.5),p95:pct(.95),p99:pct(.99),max:pct(1),targetMs:1000,overTarget,planReports,rawSamples:samples,scope:'synthetic real Auth/RPC disposable DB; no capacity rerun'});
  if(overTarget.length||!lowPlan||!highPlan)process.exitCode=2;
}catch(e){console.error('COVERAGE002 FAIL '+stage+' '+(e?.name==='AssertionError'?'assertion mismatch':String(e?.message||'unknown').slice(0,160)));process.exitCode=1;}
finally{log('STOP',{stage,calls,plans,rawSamples:samples,overTarget});}
