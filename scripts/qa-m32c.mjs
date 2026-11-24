import assert from 'node:assert/strict';
import { createRequire } from 'node:module';
import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { resolve } from 'node:path';
import { randomUUID, randomBytes } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';

const check = (label, condition) => { if (!condition) throw Error(label); };
const pass = (label, details = {}) => console.log('QA PASS', label, JSON.stringify(details));
const temp = process.env.RUNNER_TEMP;
check('isolated runner guard', process.env.GITHUB_ACTIONS === 'true' &&
  process.env.RUNNER_ENVIRONMENT === 'github-hosted' &&
  process.env.GITHUB_REF === 'refs/heads/qa/m3p2c-online-lifecycle' &&
  process.env.HNU_DASH_ISOLATED_TEST_DB === '1');
const config = JSON.parse(readFileSync(resolve(temp,'m32c-local.json'),'utf8'));
const url = config.API_URL, anon = config.ANON_KEY || config.PUBLISHABLE_KEY;
const service = config.SERVICE_ROLE_KEY || config.SECRET_KEY;
check('loopback-only API', /^http:\/\/(127\.0\.0\.1|localhost):54321\/?$/.test(url));
check('local keys present', !!anon && !!service && anon !== service);
const origin = 'http://127.0.0.1:3000';
const web = resolve('qa-web');
const requireWeb = createRequire(resolve(web,'package.json'));
const { createClient } = requireWeb('@supabase/supabase-js');
const { createServerClient } = requireWeb('@supabase/ssr');
const { chromium } = createRequire(resolve(temp,'m32c-tools/package.json'))('playwright');
const db = (q) => {
  try {
    return execFileSync('docker',['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'],{input:q,encoding:'utf8',timeout:15000,stdio:['pipe','pipe','pipe']}).trim();
  } catch { throw Error('isolated SQL query failed'); }
};
const json = q => JSON.parse(db(q));
const uuid = () => randomUUID();
const sid = n => String(n).padStart(11,'0');
const oid=uuid(), foreignOrg=uuid();
let eid,a,b,path;
const opts={auth:{persistSession:false,autoRefreshToken:false}};
const privileged=createClient(url,service,opts);
let server,browser,stage='preflight';
const rpc = async (client,name,args,code) => {
  const res = await client.rpc(name,args);
  if(code) { check(name+' expected '+code+', got '+(res.error?.code||'success'),res.error?.code===code);return res.error.code; }
  check(name+' unexpected '+(res.error?.code||'success'),!res.error);
  return res.data;
};
const tableOk=async(label,promise)=>{const res=await promise;check(label+' '+(res.error?.code||''),!res.error);return res.data;};
const actor = async name => {
  const email='m32c-'+name+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph';
  const password=randomBytes(24).toString('hex')+'aA1!';
  const created=await privileged.auth.admin.createUser({email,password,email_confirm:true});
  check('local Auth create '+name+' '+(created.error?.code||''),!created.error && !!created.data.user);
  const jar=new Map();
  const client=createServerClient(url,anon,{cookies:{
    getAll:()=>Array.from(jar,([name,value])=>({name,value})),
    setAll:entries=>{for(const {name,value} of entries){if(value)jar.set(name,value);else jar.delete(name);}}
  }});
  const signed=await client.auth.signInWithPassword({email,password});
  check('real password session '+name+' '+(signed.error?.code||''),!signed.error&&!!signed.data.session);
  const verified=await client.auth.getUser();
  check('real identity '+name,verified.data.user?.id===created.data.user.id);
  check('HNU verification '+name,await rpc(client,'hnu_verified_user')===true);
  return {id:created.data.user.id,client,jar};
};
const state = () => json("select row_to_json(e) from (select state,closed_at,closed_by,finalized_at,finalized_by from public.events where id='"+eid+"') e");
const counts = () => json("select coalesce(json_object_agg(outcome,n),'{}'::json) from (select outcome,count(*) n from public.attendance_scans where event_id='"+eid+"' group by outcome) s");
const records = () => json("select coalesce(json_agg(r order by student_id collate \"C\"),'[]'::json) from (select student_id,status,required_checkpoint_count,accepted_checkpoint_count from public.attendance_records where event_id='"+eid+"') r");
const waitFor = async (label,fn,ms=15000) => {
  const end=Date.now()+ms;
  while(Date.now()<end){if(await fn())return;await sleep(250);}
  throw Error(label+' timed out');
};
const pageFor = async who => {
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  if(who) await context.addCookies(Array.from(who.jar,([name,value])=>({name,value,url:origin})));
  return context.newPage();
};
const navigate = async(page,suffix='')=>{await page.goto(origin+path+suffix,{waitUntil:'networkidle'});};
const visible = async (locator,label) => {try{await locator.waitFor({state:'visible',timeout:12000});}catch{throw Error(label+' not visible');}};
const coverage = page=>page.getByRole('table',{name:'Provisional accepted online scan evidence by student and checkpoint'});
const results = page=>page.getByRole('table',{name:'Finalized prototype attendance results'});
const bodyRows = table=>table.locator('tbody tr');
const rows = async table => table.locator('tbody tr').evaluateAll(rs=>rs.map(r=>Array.from(r.querySelectorAll('td'),c=>c.textContent.trim())));
const format = iso=>new Intl.DateTimeFormat('en-PH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Manila'}).format(new Date(iso));
const submit=async(page,name)=>{
  const form=page.getByRole('form',{name,exact:true});
  await form.getByRole('checkbox').check();
  await form.getByRole('button',{name,exact:true}).click();
};
try{
  stage='fresh database identity and migration gate';
  check('no existing fixture data',db('select count(*) from public.events')==='0'&&db('select count(*) from public.students')==='0'&&db('select count(*) from auth.users')==='0');
  check('exact finalization migration applied',db("select count(*) from supabase_migrations.schema_migrations where version='20261124061908'")==='1');
  check('exact coverage migration applied',db("select count(*) from supabase_migrations.schema_migrations where version='20261123110600'")==='1');
  pass(stage,{api:'loopback:54321',db:'supabase_db_hnu-dash-backend',harness:process.env.GITHUB_SHA});
  stage='start pinned Web';
  const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:anon};
  // Suppress application and Auth transport logs; emit only sanitized milestones.
  try{execFileSync('npm',['run','build'],{cwd:web,env,stdio:'ignore',timeout:180000});}catch{throw Error('Web build failed');}
  server=spawn('npm',['run','start','--','--hostname','127.0.0.1','--port','3000'],{cwd:web,env,stdio:'ignore',detached:true});
  await waitFor('Web readiness',async()=>{try{return (await fetch(origin+'/login')).ok;}catch{return false;}},30000);
  browser=await chromium.launch({headless:true});
  pass(stage,{web:'ada5393bf881a38ad9c5b92a5fb65b3020cdabc4'});
  stage='genuine isolated Auth and fixture setup';
  const leader=await actor('leader'),staff=await actor('staff'),foreign=await actor('foreign');
  db("begin; insert into public.organizations(id,slug,name) values ('"+oid+"','m32c-one','Synthetic M32C'),('"+foreignOrg+"','m32c-other','Synthetic Other');"+
    "insert into public.organization_memberships(organization_id,user_id,role,granted_by) values ('"+oid+"','"+leader.id+"','leader','"+leader.id+"'),('"+oid+"','"+staff.id+"','staff','"+leader.id+"'),('"+foreignOrg+"','"+foreign.id+"','leader','"+foreign.id+"');"+
    "insert into public.students(student_id,full_name,program_code,year_level) select lpad(n::text,11,'0'),'Synthetic QA '||n,'BSIT',1 from generate_series(1,201) n; commit;");
  check('scoped leader',await rpc(leader.client,'can_manage_org',{org_id:oid})===true);
  check('staff not manager',await rpc(staff.client,'can_manage_org',{org_id:oid})===false);
  check('foreign not manager',await rpc(foreign.client,'can_manage_org',{org_id:oid})===false);
  check('zero platform admins',db('select count(*) from public.platform_admins')==='0');
  const pg=await pageFor(leader);
  await pg.goto(origin+'/login',{waitUntil:'networkidle'});
  // Compute real server-clock windows only after browser, accounts and app are ready.
  const now=Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
  const iso=n=>new Date(now+n*1000).toISOString();
  const event=await tableOk('leader create DRAFT',leader.client.from('events').insert({
    organization_id:oid,title:'Synthetic M32C lifecycle',starts_at:iso(-60),ends_at:iso(180),target_year_levels:[1]
  }).select('id').single());
  eid=event.id;path='/organizations/'+oid+'/events/'+eid+'/operations';
  const cps=await tableOk('leader create checkpoints',leader.client.from('event_checkpoints').insert([
    {event_id:eid,label:'Synthetic A',direction:'IN',opens_at:iso(-30),closes_at:iso(100),sort_order:1},
    {event_id:eid,label:'Synthetic B',direction:'OUT',opens_at:iso(35),closes_at:iso(100),sort_order:2}
  ]).select('id,sort_order'));
  a=cps.find(c=>c.sort_order===1).id;b=cps.find(c=>c.sort_order===2).id;
  check('freeze 201',await rpc(leader.client,'freeze_event_roster',{eid})===201);
  await rpc(leader.client,'assign_event_staff',{eid,staff_uid:staff.id});
  await rpc(leader.client,'open_event',{eid});
  check('OPEN persisted',state().state==='OPEN');
  check('zero receipts and results',Object.keys(counts()).length===0&&records().length===0);
  pass(stage,{event:eid,roster:201,checkpoints:2,actor:leader.id,serverTime:new Date(now).toISOString(),checkpointBOpens:iso(35),closes:iso(100)});
  stage='OPEN actual browser and early closure';
  await navigate(pg);
  await visible(coverage(pg),'coverage table');
  check('OPEN 200 coverage rows',await bodyRows(coverage(pg)).count()===200);
  check('no verdict before finalization',await results(pg).count()===0);
  const close=pg.getByRole('form',{name:'Close event',exact:true});
  await close.getByRole('checkbox').focus();
  await pg.keyboard.press('Space');
  check('keyboard confirmation',await close.getByRole('checkbox').isChecked());
  await close.getByRole('button',{name:'Cancel confirmation'}).click();
  check('cancel clears confirmation',!(await close.getByRole('checkbox').isChecked()));
  check('cancel leaves event OPEN',state().state==='OPEN');
  await submit(pg,'Close event');
  await visible(close.getByRole('alert'),'early close error');
  check('early close feedback',/checkpoint windows/.test(await close.getByRole('alert').innerText()));
  check('early close unchanged',state().state==='OPEN'&&state().closed_at===null);
  await rpc(leader.client,'close_event',{eid},'55000');
  await rpc(leader.client,'finalize_event',{eid},'55000');
  await rpc(leader.client,'get_event_finalized_results',{eid,p_limit:200,p_offset:0},'55000');
  await close.getByRole('button',{name:'Reload event state'}).click();
  await visible(coverage(pg),'reloaded coverage');
  pass(stage,{sqlstate:'55000',state:'OPEN',cancel:true,keyboard:true});
  stage='Staff genuine ingestion';
  const payload=(cp,n)=>({p_scan_id:uuid(),p_event_id:eid,p_checkpoint_id:cp,p_student_id:sid(n)});
  const first=payload(a,1), second=payload(a,2), dup=payload(a,1), rejected=payload(b,3);
  const receipt=async(p,outcome)=>{let r=await rpc(staff.client,'ingest_attendance_scan',p);check('receipt '+outcome,r.outcome===outcome&&r.replayed===false&&r.scan_id===p.p_scan_id);return r;};
  // Reject C while B has not yet opened. No clock adjustment or direct scan inserts.
  check('reject window still future',db("select (clock_timestamp()<opens_at)::text from public.event_checkpoints where id='"+b+"'")==='true');
  const rejectedReceipt=await receipt(rejected,'rejected');
  const original=await receipt(first,'accepted');
  await receipt(second,'accepted');await receipt(dup,'duplicate');
  await waitFor('B open',()=>db("select (clock_timestamp()>=opens_at)::text from public.event_checkpoints where id='"+b+"'")==='true',45000);
  await receipt(payload(b,1),'accepted');
  assert.deepEqual(counts(),{accepted:3,duplicate:1,rejected:1});
  const persisted=json("select row_to_json(s) from (select outcome,submitted_by,received_at from public.attendance_scans where scan_id='"+first.p_scan_id+"') s");
  check('original server receipt',persisted.submitted_by===staff.id&&persisted.outcome==='accepted'&&Date.parse(persisted.received_at)===Date.parse(original.received_at));
  pass(stage,{counts:counts(),originalReceivedAt:original.received_at,rejectedReceivedAt:rejectedReceipt.received_at});
  stage='M3.1 actual refresh and pagination';
  await pg.getByRole('button',{name:'Refresh checkpoint coverage'}).click();
  await waitFor('accepted refresh',async()=>await coverage(pg).getByText('Accepted receipt recorded',{exact:true}).count()===3);
  check('timestamp Manila',await coverage(pg).getByText(format(original.received_at),{exact:true}).count()>=1);
  let all=await rows(coverage(pg));
  for(const n of [2,3]){
    await pg.getByRole('link',{name:'Next coverage page'}).click();
    await waitFor('coverage page '+n,async()=>new URL(pg.url()).searchParams.get('coverage_page')===String(n)&&await bodyRows(coverage(pg)).count()===(n===2?200:2));
    all.push(...await rows(coverage(pg)));
  }
  check('402 unique pairs',all.length===402&&new Set(all.map(r=>r[0]+'|'+r[1])).size===402);
  check('accepted only',all.filter(r=>r[3]==='Accepted receipt recorded').length===3);
  check('leading zeros',all[0][0]===sid(1)&&all.at(-1)[0]===sid(201));
  await pg.getByRole('button',{name:'Refresh checkpoint coverage'}).click();
  await waitFor('refresh last page',async()=>!(await pg.getByRole('button',{name:'Refresh checkpoint coverage'}).isDisabled()));
  check('refresh preserves page',new URL(pg.url()).searchParams.get('coverage_page')==='3'&&await bodyRows(coverage(pg)).count()===2);
  await navigate(pg,'?coverage_page=invalid');
  check('invalid coverage page normalized',await bodyRows(coverage(pg)).count()===200);
  pass(stage,{pages:[200,200,2],accepted:3,unique:402,manila:true});
  stage='real server-clock closure';
  await waitFor('all windows ended',()=>db("select (clock_timestamp()>=max(closes_at))::text from public.event_checkpoints where event_id='"+eid+"'")==='true',110000);
  await submit(pg,'Close event');
  await waitFor('closure commit',()=>state().state==='SYNCING');
  const closed=state();
  check('closure audit',closed.closed_by===leader.id&&Date.parse(closed.closed_at)>=Date.parse(iso(100)));
  await visible(pg.getByText(/SYNCING — closed to new online evidence/),'SYNCING browser');
  check('no offline completion claim',/not offline synchronization completion/.test(await pg.getByText(/SYNCING — closed to new online evidence/).innerText()));
  await rpc(leader.client,'close_event',{eid},'55000');
  await rpc(staff.client,'ingest_attendance_scan',payload(a,4),'55000');
  const replay=await rpc(staff.client,'ingest_attendance_scan',first);
  check('same original scan',replay.replayed===true&&replay.outcome===original.outcome&&replay.scan_id===original.scan_id&&replay.received_at===original.received_at);
  assert.deepEqual(counts(),{accepted:3,duplicate:1,rejected:1});
  check('no premature records',records().length===0);
  pass(stage,{state:closed.state,closedAt:closed.closed_at,closedBy:closed.closed_by,repeatClose:'55000',newScan:'55000',sameUuidReplay:true,counts:counts()});
  stage='finalization actual browser post-commit response loss';
  await navigate(pg);
  const form=pg.getByRole('form',{name:'Finalize attendance',exact:true});
  await visible(form,'finalization form');
  await form.getByRole('checkbox').check();
  await form.getByRole('button',{name:'Cancel confirmation'}).click();
  check('finalize cancel clears',!(await form.getByRole('checkbox').isChecked())&&state().state==='SYNCING');
  let posts=0, withheld=false, interceptionError='';
  await pg.route('**/operations**',async route=>{
    const req=route.request();
    if(req.method()!=='POST'||!req.headers()['next-action'])return route.continue();
    posts++;
    if(posts!==1)return route.abort('failed');
    try{
      // Hold browser response while the actual Server Action runs upstream.
      const response=await route.fetch({timeout:30000,maxRedirects:0,maxRetries:0});
      check('upstream finalization response',response.ok());
      check('real committed finalization before loss',state().state==='FINALIZED'&&records().length===201);
      await sleep(500);
      withheld=true;
      await route.abort('failed');
      await response.dispose();
    }catch(e){interceptionError=e.message;try{await route.abort('failed');}catch{}}
  });
  await submit(pg,'Finalize attendance');
  await visible(form.getByText('Waiting for Backend confirmation…'),'pending feedback');
  check('pending disabled',await form.getByRole('button',{name:'Submitting…'}).isDisabled());
  await waitFor('response intentionally withheld',()=>withheld||!!interceptionError,40000);
  check('response-loss interception '+interceptionError,withheld&&!interceptionError);
  await visible(form.getByRole('button',{name:'Reload event state'}),'reload recovery');
  check('ambiguous feedback',/could not be confirmed/i.test(await form.getByRole('alert').innerText()));
  check('no misleading success',await form.getByText(/Backend confirmed permanent/).count()===0);
  check('no resubmit control',await form.getByRole('button',{name:'Finalize attendance',exact:true}).count()===0);
  await sleep(800);
  check('no blind retry',posts===1);
  await pg.unroute('**/operations**');
  await form.getByRole('button',{name:'Reload event state'}).click();
  await visible(results(pg),'finalized result after reload');
  const finalized=state();
  const stored=records();
  check('finalization audit',finalized.finalized_by===leader.id&&Date.parse(finalized.finalized_at)>=Date.parse(closed.closed_at));
  check('201 immutable results',stored.length===201&&new Set(stored.map(r=>r.student_id)).size===201);
  const expected=Array.from({length:201},(_,i)=>({student_id:sid(i+1),status:i===0?'PRESENT':i===1?'INCOMPLETE':'ABSENT',required_checkpoint_count:2,accepted_checkpoint_count:i===0?2:i===1?1:0}));
  assert.deepEqual(stored,expected);
  pass(stage,{posts,withheld,pending:true,state:finalized.state,finalizedAt:finalized.finalized_at,finalizedBy:finalized.finalized_by,records:stored.length});
  stage='finalized browser results and independent DB comparison';
  const project=rs=>rs.map(r=>[r.student_id,r.status,String(r.required_checkpoint_count),String(r.accepted_checkpoint_count)]);
  assert.deepEqual(await rows(results(pg)),project(stored.slice(0,200)));
  check('audit actor rendered',(await pg.locator('dd').allTextContents()).includes(leader.id));
  check('audit Manila timestamp',(await pg.locator('time').evaluateAll(ts=>ts.map(t=>({date:t.dateTime,text:t.textContent.trim()})))).some(t=>Date.parse(t.date)===Date.parse(finalized.finalized_at)&&t.text===format(finalized.finalized_at)));
  await pg.setViewportSize({width:390,height:844});
  await pg.getByRole('link',{name:'Next results page'}).focus();
  await pg.keyboard.press('Enter');
  await waitFor('page two',async()=>new URL(pg.url()).searchParams.get('results_page')==='2'&&await bodyRows(results(pg)).count()===1);
  assert.deepEqual(await rows(results(pg)),project(stored.slice(200)));
  check('responsive table scroll',await results(pg).evaluate(t=>{let p=t.parentElement;while(p){if(p.scrollWidth>p.clientWidth&&['auto','scroll'].includes(getComputedStyle(p).overflowX))return true;p=p.parentElement;}return t.getBoundingClientRect().width<=innerWidth;}));
  await navigate(pg,'?results_page=invalid');assert.deepEqual(await rows(results(pg)),project(stored.slice(0,200)));
  await navigate(pg,'?results_page=999');assert.deepEqual(await rows(results(pg)),project(stored.slice(200)));
  const p1=await rpc(leader.client,'get_event_finalized_results',{eid,p_limit:200,p_offset:0});
  const p2=await rpc(leader.client,'get_event_finalized_results',{eid,p_limit:200,p_offset:200});
  assert.deepEqual(project([...p1,...p2]),project(stored));
  check('all audit consistent',[...p1,...p2].every(r=>r.finalized_by===leader.id&&Date.parse(r.finalized_at)===Date.parse(finalized.finalized_at)));
  pass(stage,{pages:[200,1],classification:{PRESENT:1,INCOMPLETE:1,ABSENT:199},leadingZeros:true,manila:true,keyboard:true,responsive:true});
  stage='denial and immutable replay';
  for(const who of [staff,foreign]){
    const denied=await pageFor(who);await navigate(denied);
    await visible(denied.getByText(/Only authorized organization Leaders/),'denial browser');
    check('no data or controls leaked',await results(denied).count()===0&&await coverage(denied).count()===0&&await denied.getByRole('form',{name:'Finalize attendance'}).count()===0);
    for(const name of ['close_event','finalize_event','get_event_finalized_results']){
      const params=name==='get_event_finalized_results'?{eid,p_limit:200,p_offset:0}:{eid};
      await rpc(who.client,name,params,'42501');
      await rpc(who.client,name,{...params,eid:uuid()},'42501');
    }
    await denied.context().close();
  }
  const signedOut=await pageFor(null);await navigate(signedOut);
  check('unauthenticated redirect',new URL(signedOut.url()).pathname==='/login'&&await results(signedOut).count()===0);
  const publicClient=createClient(url,anon,opts);
  for(const name of ['close_event','finalize_event','get_event_finalized_results'])await rpc(publicClient,name,name==='get_event_finalized_results'?{eid,p_limit:200,p_offset:0}:{eid},'42501');
  await rpc(leader.client,'get_event_finalized_results',{eid,p_limit:201,p_offset:0},'22023');
  const repeated=await rpc(leader.client,'finalize_event',{eid});
  check('finalization replay original metadata',repeated.replayed===true&&repeated.record_count===201&&repeated.event_id===eid&&repeated.finalized_by===finalized.finalized_by&&Date.parse(repeated.finalized_at)===Date.parse(finalized.finalized_at));
  await rpc(leader.client,'close_event',{eid},'55000');
  assert.deepEqual(records(),stored);assert.deepEqual(state(),finalized);assert.deepEqual(counts(),{accepted:3,duplicate:1,rejected:1});
  pass(stage,{staff:'42501',foreign:'42501',unknown:'42501',anonymous:'42501',invalidLimit:'22023',replay:true,records:201,unchangedAudit:true});
  console.log('QA COMPLETE: M3.2C browser + genuine Staff RPC + independent SQL; physical Android and Google OAuth NOT_RUN.');
}catch(e){console.error('QA FAIL',stage, e instanceof Error ? e.message.split('\n')[0].slice(0,300):'unknown');process.exitCode=1;}
finally{if(browser)await browser.close();if(server?.pid)try{process.kill(-server.pid,'SIGTERM');}catch{}}
