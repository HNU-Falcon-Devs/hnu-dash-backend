import assert from 'node:assert/strict';
import { execFileSync, spawn, execFile } from 'node:child_process';
import { promisify } from 'node:util';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
import os from 'node:os';
const BASE='43dcb7febd5cdc1b50bb249487f92f1fe66fa21d';
const check=(label,value)=>{if(!value)throw Error(label);};
const eq=(a,b)=>assert.deepEqual(a,b);
const log=(tag,obj)=>console.log('COVERAGE '+tag+' '+JSON.stringify(obj));
const temp=process.env.RUNNER_TEMP;
check('runner isolation',process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted'&&process.env.GITHUB_REF==='refs/heads/qa/coverage-perf-001'&&process.env.HNU_DASH_ISOLATED_TEST_DB==='1'&&!!temp);
const cfg=JSON.parse(readFileSync(resolve(temp,'coverage-perf-001-local.json'),'utf8'));
const url=cfg.API_URL,anon=cfg.ANON_KEY||cfg.PUBLISHABLE_KEY,service=cfg.SERVICE_ROLE_KEY||cfg.SECRET_KEY;
check('loopback only',/^http:\/\/(localhost|127\.0\.0\.1):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const dbArgs=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=sql=>{try{return execFileSync('docker',dbArgs,{input:sql,encoding:'utf8',timeout:15000,stdio:['pipe','pipe','pipe']}).trim();}catch{throw Error('isolated fixture or metadata SQL failed');}};
const json=sql=>JSON.parse(db(sql)), q=v=>"'"+String(v).replaceAll("'","''")+"'", tup=xs=>'('+xs.map(q).join(',')+')';
const id=()=>randomUUID(), iso=t=>new Date(t).toISOString(), sid=n=>'SYNTHETIC-'+String(n).padStart(4,'0');
let executions=0, phase='preflight', observed=[], failures=[], sampleErrors=0;
const budget=()=>{check('12 coverage/plan execution cap',executions<12);executions++;};
const request=async(path,token,key,body)=>{
  const t=performance.now();
  const r=await fetch(url+path,{method:'POST',headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(20000)});
  const data=await r.json();
  return {ok:r.ok,status:r.status,data,ms:performance.now()-t};
};
const actor=async(kind)=>{
  const email='coverage-'+kind+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph',password=randomBytes(24).toString('hex')+'Aa1!';
  const c=await request('/auth/v1/admin/users',service,service,{email,password,email_confirm:true});
  check('local Auth user created',c.ok&&!!c.data.id);
  const a=await request('/auth/v1/token?grant_type=password',anon,anon,{email,password});
  check('real local Auth login',a.ok&&a.data.user?.id===c.data.id&&!!a.data.access_token);
  const claims=JSON.parse(Buffer.from(a.data.access_token.split('.')[1],'base64url').toString('utf8'));
  check('real JWT role and subject',claims.sub===c.data.id&&claims.role==='authenticated');
  const who={id:c.data.id,token:a.data.access_token,claims};
  const v=await rpc(who,'hnu_verified_user',{});
  check('verified HNU user',v===true);
  return who;
};
const rpc=async(who,name,args)=>{
  const r=await request('/rest/v1/rpc/'+name,who.token,anon,args);
  check('setup RPC '+name+' '+(r.data?.code||''),r.ok);
  return r.data;
};
const stat=()=>json("select row_to_json(s) from (select xact_commit,xact_rollback,deadlocks,blks_hit,blks_read from pg_stat_database where datname=current_database()) s");
const resource=async()=>{try{return (await promisify(execFile)('docker',['stats','--no-stream','--format','{{.CPUPerc}} {{.MemUsage}}','supabase_db_hnu-dash-backend'],{timeout:6000})).stdout.trim();}catch{return 'unavailable';}};
const sample=async()=>{
  const sql="select json_build_object('active',count(*) filter(where state='active'),'lock_wait',count(*) filter(where wait_event_type='Lock'),'waiting_locks',(select count(*) from pg_locks where not granted),'wait_types',coalesce(json_agg(distinct coalesce(wait_event_type,'CPU_or_running')) filter(where state='active'),'[]'::json)) from pg_stat_activity where datname=current_database() and pid<>pg_backend_pid() and backend_type='client backend'";
  try{return JSON.parse((await promisify(execFile)('docker',[...dbArgs,'-c',sql],{timeout:4000})).stdout);}catch{sampleErrors++;return null;}
};
const measured=async(label,fn)=>{
  const samples=[];let done=false;
  const loop=(async()=>{while(!done){const s=await sample();if(s)samples.push(s);if(!done)await sleep(250);}})();
  const t=performance.now();
  try{return await fn();}finally{done=true;await loop;const report={label,elapsedMs:performance.now()-t,samples:samples.length,lockSamples:samples.filter(s=>s.lock_wait||s.waiting_locks).length,waitTypes:[...new Set(samples.flatMap(s=>s.wait_types))]};observed.push(report);log('OBSERVE',report);}
};
const sqlAsync=sql=>new Promise((ok,fail)=>{
  const p=spawn('docker',dbArgs,{stdio:['pipe','pipe','pipe']});
  let out='',err='';
  const timeout=setTimeout(()=>{p.kill('SIGTERM');fail(Error('diagnostic SQL process deadline'));},75000);
  p.stdout.on('data',d=>{out+=d;if(out.length>4_000_000)p.kill('SIGTERM');});
  p.stderr.on('data',d=>{err+=d;});
  p.on('error',()=>{clearTimeout(timeout);fail(Error('diagnostic SQL process failed'));});
  p.on('close',code=>{clearTimeout(timeout);if(code===0)ok(out.trim());else fail(Error('diagnostic SQL '+(err.includes('statement timeout')?'statement timeout':'failed')+' exit '+code));});
  p.stdin.on('error',()=>{});p.stdin.end(sql);
});
const fixture={eid:id(),org:id(),foreignOrg:id(),cp:[id(),id()]};
const expect=(n,offset)=>Array.from({length:Math.min(200,1200-offset)},(_,i)=>{
  const pos=offset+i,student=Math.floor(pos/2)+1,cp=pos%2,accepted=cp===0&&student<=n;
  return {student_id:sid(student),checkpoint_id:fixture.cp[cp],checkpoint_label:cp===0?'Synthetic IN':'Synthetic OUT',checkpoint_direction:cp===0?'IN':'OUT',checkpoint_sort_order:cp+1,has_accepted_scan:accepted,accepted_received_at:accepted?fixture.received:null};
});
const assertPage=(data,n,offset)=>{
  check('page array',Array.isArray(data));
  const normalize=r=>({...r,accepted_received_at:r.accepted_received_at===null?null:new Date(r.accepted_received_at).toISOString()});
  eq(data.map(normalize),expect(n,offset));
};
const httpRead=async(label,who,n,offset,expectedDenied=false)=>{
  budget();
  const r=await measured(label,()=>request('/rest/v1/rpc/get_event_checkpoint_coverage',who.token,anon,{eid:fixture.eid,p_limit:200,p_offset:offset}));
  const code=r.ok?'ok':r.data?.code||'unknown';
  log('RPC',{label,execution:executions,status:r.status,code,ms:r.ms,rows:r.ok?r.data.length:null,expectedDenied});
  if(expectedDenied){eq(code,'42501');return false;}
  if(r.ok){assertPage(r.data,n,offset);log('PAGE_PASS',{label,rows:r.data.length,offset,accepted:r.data.filter(x=>x.has_accepted_scan).length});return true;}
  if(code==='57014'){failures.push({label,code,ms:r.ms});return false;}
  throw Error('unexpected coverage RPC code '+code);
};
// Derive the exact inner statement from the unchanged migration, not a rewrite.
const migration=readFileSync('supabase/migrations/20261123110600_checkpoint_coverage.sql','utf8');
const inner=migration.match(/return query\s+([\s\S]*?limit p_limit offset p_offset);/i)?.[1];
check('exact source inner query extracted',!!inner);
const query=offset=>inner.replace(/\beid\b/g,q(fixture.eid)+'::uuid').replace(/\bp_limit\b/g,'200').replace(/\bp_offset\b/g,String(offset));
const rolePrefix=(who,privileged=false)=>"\\set VERBOSITY terse\nbegin read only;\nset local track_functions='all';\n"+
  (privileged?'':"set local role authenticated;\nset local \"request.jwt.claims\"="+q(JSON.stringify(who.claims))+";\n")+
  "set local statement_timeout='60s';\nset local search_path='';\n";
const contextSql=privileged=> "select json_build_object('role',current_user,'row_security',current_setting('row_security'),'timeout',current_setting('statement_timeout')"+
  (privileged?"":",'uid_matches',auth.uid()="+q(manager.id)+"::uuid,'verified',public.hnu_verified_user(),'manages_org',public.can_manage_org("+q(fixture.org)+"::uuid)")+
  ");";
let manager,staff,foreign;
const plan=async(label,who,offset,privileged=false)=>{
  budget();
  const sql=rolePrefix(who,privileged)+
    "\\echo CONTEXT\n"+contextSql(privileged)+"\n\\echo PLAN\nEXPLAIN (ANALYZE, BUFFERS, VERBOSE, SETTINGS, FORMAT JSON) "+query(offset)+";\n"+
    "\\echo FUNCTIONS\nselect coalesce(json_agg(row_to_json(s)),'[]'::json) from (select schemaname,funcname,calls,total_time,self_time from pg_stat_xact_user_functions where schemaname in ('public','auth') order by calls desc,funcname) s;\n\\echo END\nrollback;\n";
  let out;
  try{out=await measured(label,()=>sqlAsync(sql));}catch(e){log('PLAN_INCONCLUSIVE',{label,reason:e.message});return null;}
  const m=out.match(/CONTEXT\n([\s\S]*?)\nPLAN\n([\s\S]*?)\nFUNCTIONS\n([\s\S]*?)\nEND/);
  check('plan output sections',!!m);
  const ctx=JSON.parse(m[1]),p=JSON.parse(m[2])[0],fn=JSON.parse(m[3]);
  if(!privileged){eq(ctx.role,'authenticated');check('authenticated RLS context',ctx.row_security==='on'&&ctx.uid_matches&&ctx.verified&&ctx.manages_org);}
  else eq(ctx.role,'postgres');
  const nodes=[];
  const visit=(node,depth=0)=>{nodes.push({depth,node:node['Node Type'],relation:node['Relation Name'],index:node['Index Name'],estimatedRows:node['Plan Rows'],actualRows:node['Actual Rows'],loops:node['Actual Loops'],actualTotalMs:node['Actual Total Time'],removedFilter:node['Rows Removed by Filter'],removedJoin:node['Rows Removed by Join Filter'],sharedHits:node['Shared Hit Blocks'],sharedReads:node['Shared Read Blocks'],filter:node.Filter,indexCond:node['Index Cond'],joinFilter:node['Join Filter'],hashCond:node['Hash Cond'],mergeCond:node['Merge Cond']});for(const sub of node.Plans||[])visit(sub,depth+1);};
  visit(p.Plan);
  log('PLAN',{label,execution:executions,privileged,context:ctx,planningMs:p['Planning Time'],executionMs:p['Execution Time'],nodes,functions:fn,settings:p.Settings||{}});
  // Retain full sanitized plan, including actual loops and nested RLS filters.
  log('EXPLAIN_JSON',{label,plan:p});
  eq(p.Plan['Actual Rows'],200);
  return p;
};
const sqlPage=async(label,n,offset)=>{
  budget();
  const sql=rolePrefix(manager)+"\\echo CONTEXT\n"+contextSql(false)+"\n\\echo ROWS\nselect coalesce(json_agg(row_to_json(v)),'[]'::json) from ("+query(offset)+") v(student_id,checkpoint_id,checkpoint_label,checkpoint_direction,checkpoint_sort_order,has_accepted_scan,accepted_received_at);\n\\echo END\nrollback;\n";
  let out;try{out=await measured(label,()=>sqlAsync(sql));}catch(e){log('SQL_PAGE_INCONCLUSIVE',{label,reason:e.message});return false;}
  const m=out.match(/CONTEXT\n([\s\S]*?)\nROWS\n([\s\S]*?)\nEND/);check('SQL page sections',!!m);
  const ctx=JSON.parse(m[1]);check('SQL page context',ctx.role==='authenticated'&&ctx.row_security==='on'&&ctx.uid_matches&&ctx.verified&&ctx.manages_org);
  const data=JSON.parse(m[2]);assertPage(data,n,offset);
  log('SQL_PAGE_PASS',{label,offset,rows:data.length,accepted:data.filter(x=>x.has_accepted_scan).length,diagnosticTimeout:'60s',notDefaultRpc:true});
  return true;
};
const seed=(acceptedStart,acceptedEnd,dupStart,dupEnd,rejectStart,rejectEnd)=>{
  const values=[];
  const receipt=(student,outcome)=>tup([id(),fixture.eid,fixture.cp[0],student,staff.id,fixture.received,outcome]);
  for(let i=acceptedStart;i<=acceptedEnd;i++)values.push(receipt(sid(i),'accepted'));
  for(let i=dupStart;i<=dupEnd;i++)values.push(receipt(sid(i),'duplicate'));
  for(let i=rejectStart;i<=rejectEnd;i++)values.push(receipt('SYNTHETIC-OUTSIDE-'+i,'rejected'));
  db("insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values "+values.join(',')+";");
};
const counts=()=>json("select coalesce(json_object_agg(outcome,n),'{}'::json) from (select outcome,count(*) n from public.attendance_scans where event_id="+q(fixture.eid)+" group by outcome) s");
const meta=label=>log('RELATIONS',{label,stats:json("select json_agg(row_to_json(s)) from (select relname,n_live_tup,n_dead_tup,last_analyze,last_autoanalyze,seq_scan,idx_scan from pg_stat_user_tables where schemaname='public' and relname in ('event_roster','event_checkpoints','attendance_scans','events','organization_memberships') order by relname) s")});
let before;
try{
  eq(db("select version from supabase_migrations.schema_migrations order by version").split('\n'),['20261106122400','20261108150500','20261108150600','20261123110600','20261124061908','20261124152537','20261124154829']);
  check('fresh DB',db("select ((select count(*) from auth.users)=0 and (select count(*) from public.events)=0 and (select count(*) from public.students)=0 and (select count(*) from public.attendance_scans)=0)::text")==='true');
  const installed=db("select prosrc from pg_proc where oid='public.get_event_checkpoint_coverage(uuid,integer,integer)'::regprocedure");
  check('exact inner SQL matches installed function',installed.match(/return query\s+([\s\S]*?limit p_limit offset p_offset);/i)?.[1]===inner);
  log('PINS',{backend:BASE,harness:process.env.GITHUB_SHA,db:db('show server_version'),node:process.version,cpu:os.cpus().length,ramBytes:os.totalmem(),cli:'2.122.0',resource:await resource()});
  log('TIMEOUT_CONFIG',{sessionDefault:db('show statement_timeout'),roleSettings:json("select json_agg(row_to_json(s)) from (select rolname,array(select v from unnest(coalesce(rolconfig,array[]::text[])) v where v like 'statement_timeout=%') as timeout from pg_roles where rolname in ('authenticator','authenticated','anon','postgres') order by rolname) s"),dbRoleSettings:json("select coalesce(json_agg(row_to_json(s)),'[]'::json) from (select coalesce(r.rolname,'all') role,coalesce(d.datname,'all') database,v setting from pg_db_role_setting a left join pg_roles r on r.oid=a.setrole left join pg_database d on d.oid=a.setdatabase cross join lateral unnest(a.setconfig) v where v like 'statement_timeout=%') s")});
  log('INDEXES',json("select json_agg(row_to_json(s)) from (select tablename,indexname,indexdef from pg_indexes where schemaname='public' and tablename in ('events','event_roster','event_checkpoints','attendance_scans','organization_memberships') order by tablename,indexname) s"));
  log('POLICIES',json("select json_agg(row_to_json(s)) from (select tablename,policyname,roles,qual from pg_policies where schemaname='public' and tablename in ('events','event_roster','event_checkpoints','attendance_scans') and cmd='SELECT' order by tablename,policyname) s"));
  phase='fixture';manager=await actor('leader');staff=await actor('staff');foreign=await actor('foreign');
  const t=Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
  fixture.received=iso(t);
  db("begin; select set_config('request.jwt.claim.sub',"+q(manager.id)+",true);"+
    "insert into public.organizations(id,slug,name) values "+tup([fixture.org,'coverage-one','Synthetic Coverage'])+","+tup([fixture.foreignOrg,'coverage-other','Synthetic Other'])+";"+
    "insert into public.organization_memberships(organization_id,user_id,role,granted_by) values "+[tup([fixture.org,manager.id,'leader',manager.id]),tup([fixture.org,staff.id,'staff',manager.id]),tup([fixture.foreignOrg,foreign.id,'leader',foreign.id])].join(',')+";"+
    "insert into public.students(student_id,full_name,program_code,year_level) select 'SYNTHETIC-'||lpad(n::text,4,'0'),'Synthetic Coverage '||n,'BSIT',1 from generate_series(1,600) n;"+
    "insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,target_year_levels) values ("+[fixture.eid,fixture.org,manager.id,'Synthetic Coverage',iso(t-600000),iso(t+1200000)].map(q).join(',')+",array[1]::smallint[]);"+
    "insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values "+[tup([fixture.cp[0],fixture.eid,'Synthetic IN','IN',iso(t-60000),iso(t+600000),1]),tup([fixture.cp[1],fixture.eid,'Synthetic OUT','OUT',iso(t+601000),iso(t+1190000),2])].join(',')+";commit;");
  eq(await rpc(manager,'freeze_event_roster',{eid:fixture.eid}),600);
  await rpc(manager,'assign_event_staff',{eid:fixture.eid,staff_uid:staff.id});
  const opened=await rpc(manager,'open_event',{eid:fixture.eid});eq(opened[0].event_state,'OPEN');
  // Use a receipt time after real activation, within IN window; no simulated clock.
  fixture.received=iso(Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint')));
  seed(1,2,1,1,1,0);eq(counts(),{accepted:2,duplicate:1});
  log('FIXTURE',{roster:600,checkpoints:2,low:counts(),seeded:true,staffAssigned:true});
  before=stat();
  phase='low';meta('low');
  const low=await httpRead('low_default_manager_page0',manager,2,0);
  const lowPlan=await plan('low_authenticated_inner_plan',manager,0);
  phase='populated';seed(3,570,2,30,1,6);eq(counts(),{accepted:570,duplicate:30,rejected:6});
  log('FIXTURE',{roster:600,checkpoints:2,populated:counts(),seeded:true,identicalEvent:true});meta('populated');
  const high=await httpRead('populated_default_manager_page0',manager,570,0);
  const highPlan=await plan('populated_authenticated_inner_plan',manager,0);
  const compare=await plan('populated_privileged_comparison_plan',manager,0,true);
  const highPage0=await sqlPage('populated_authenticated_page0',570,0);
  const highPage1=await sqlPage('populated_authenticated_page200',570,200);
  if(high)await httpRead('populated_default_manager_page200',manager,570,200);
  phase='scope';
  await httpRead('foreign_manager_denied',foreign,570,0,true);
  await httpRead('assigned_staff_denied',staff,570,0,true);
  eq(counts(),{accepted:570,duplicate:30,rejected:6});
  check('no official attendance mutation',db("select count(*) from public.attendance_records")==='0');
  const after=stat();
  log('DB_STATS',{before,after,deadlockDelta:after.deadlocks-before.deadlocks,resource:await resource(),sampleErrors});eq(after.deadlocks,before.deadlocks);
  log('SUMMARY',{executions,cap:12,lowDefault:low,highDefault:high,lowPlan:!!lowPlan,highPlan:!!highPlan,privilegedComparison:!!compare,highPage0,highPage1,denials:'42501 both',failures,sourceUnchanged:true,seededFixture:true,scope:'isolated read diagnosis'});
  // Reproduced expected 57014 is diagnostic evidence, not a failed harness.
  if(!lowPlan||!highPlan||!highPage0||!highPage1)process.exitCode=2;
}catch(e){console.error('COVERAGE FAIL '+phase+' '+(e?.name==='AssertionError'?'assertion mismatch':String(e?.message||'unknown').slice(0,180)));process.exitCode=1;}
finally{log('STOP',{phase,executions,observations:observed,sampleErrors,failures});}
