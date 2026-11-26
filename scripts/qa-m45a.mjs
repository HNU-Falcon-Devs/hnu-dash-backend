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
  process.env.GITHUB_REF === 'refs/heads/qa/m4p5a-offline-lifecycle' &&
  process.env.HNU_DASH_ISOLATED_TEST_DB === '1');
const config = JSON.parse(readFileSync(resolve(temp,'m45a-local.json'),'utf8'));
const url = config.API_URL, anon = config.ANON_KEY || config.PUBLISHABLE_KEY;
const service = config.SERVICE_ROLE_KEY || config.SECRET_KEY;
check('loopback-only API', /^http:\/\/(127\.0\.0\.1|localhost):54321\/?$/.test(url));
check('local keys present', !!anon && !!service && anon !== service);
const origin = 'http://127.0.0.1:3000';
const web = resolve('qa-web');
const requireWeb = createRequire(resolve(web,'package.json'));
const { createClient } = requireWeb('@supabase/supabase-js');
const { createServerClient } = requireWeb('@supabase/ssr');
const { chromium } = createRequire(resolve(temp,'m45a-tools/package.json'))('playwright');
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
  const email='m45a-'+name+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph';
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
const coverage = page=>page.getByRole('table',{name:'Provisional accepted canonical evidence by student and checkpoint'});
const results = page=>page.getByRole('table',{name:'Finalized prototype attendance results'});
const bodyRows = table=>table.locator('tbody tr');
const rows = async table => table.locator('tbody tr').evaluateAll(rs=>rs.map(r=>Array.from(r.querySelectorAll('td'),c=>c.textContent.trim())));
const format = iso=>new Intl.DateTimeFormat('en-PH',{dateStyle:'medium',timeStyle:'short',timeZone:'Asia/Manila'}).format(new Date(iso));
const submit=async(page,name)=>{
  const form=page.getByRole('form',{name,exact:true});
  await form.getByRole('checkbox').check();
  await form.getByRole('button',{name,exact:true}).click();
};

const offForm=(pg,name,id)=>pg.getByRole('form',{name:id?name+' '+id:name,exact:true});
const doForm=async(pg,name,id,choice,reason)=>{
  const form=offForm(pg,name,id);
  await visible(form,name);
  if(choice){await form.locator('select[name=choice]').selectOption(choice);await form.locator('textarea[name=reason]').fill(reason);}
  await form.getByRole('checkbox').check();
  await form.getByRole('button',{name,exact:true}).click();
};
const summary=leader=>rpc(leader.client,'get_event_offline_summary',{eid});
const n=(table,where)=>Number(db('select count(*) from public.'+table+' where '+where));
const where=()=> "event_id='"+eid+"'";
const sqlrow=(table,condition)=>json('select row_to_json(t) from public.'+table+' t where '+condition);
const withoutReplay=({replayed,...rest})=>rest;
const upload=(who,p)=>rpc(who.client,'submit_offline_capture',p);
const status=(who,prep)=>rpc(who.client,'get_offline_preparation_status',{p_preparation_id:prep});
const complete=(who,prep,count,code)=>rpc(who.client,'complete_offline_preparation',{p_preparation_id:prep,p_acknowledged_count:count},code);
const online=(who,p)=>rpc(who.client,'ingest_attendance_scan',p);
const makeClaim=(prep,cp,student,claimed,cap=uuid())=>({p_preparation_id:prep,p_capture_id:cap,p_checkpoint_id:cp,p_student_id:student,p_claimed_at:claimed});
const receiptPayload=(cp,student)=>({p_scan_id:uuid(),p_event_id:eid,p_checkpoint_id:cp,p_student_id:student});
const rawClaim=(id)=>sqlrow('offline_capture_claims',"capture_id='"+id+"'");
const ledger = [
  {label:'cross-mode duplicate',staff:0,cp:0,student:sid(1),eligible:true,decision:'approve',outcome:'duplicate',reason:'Synthetic duplicate; retain provenance'},
  {label:'completing slot',staff:0,cp:1,student:sid(1),eligible:true,decision:'approve',outcome:'accepted',reason:'Synthetic eligible complementary checkpoint'},
  {label:'ineligible outside roster',staff:0,cp:0,student:'SYNTH-OUTSIDE',eligible:false,decision:'reject',outcome:null,reason:'Synthetic ineligible evidence'},
  {label:'second student',staff:1,cp:0,student:sid(2),eligible:true,decision:'approve',outcome:'accepted',reason:'Synthetic eligible single checkpoint'},
  {label:'eligible rejected',staff:1,cp:1,student:sid(3),eligible:true,decision:'reject',outcome:null,reason:'Synthetic individual rejection'}
];
const expected=Array.from({length:201},(_,i)=>({student_id:sid(i+1),status:i===0?'PRESENT':i===1?'INCOMPLETE':'ABSENT',required_checkpoint_count:2,accepted_checkpoint_count:i===0?2:i===1?1:0}));
try{
  stage='fresh database and exact migration gate';
  check('fresh fixture', ['public.events','public.students','auth.users','public.offline_capture_claims','public.offline_preparations','public.attendance_scans','public.attendance_records'].every(t=>db('select count(*) from '+t)==='0'));
  assert.deepEqual(db("select version from supabase_migrations.schema_migrations order by version").split('\n'),['20261106122400','20261108150500','20261108150600','20261123110600','20261124061908','20261124152537','20261124154829']);
  pass(stage,{harness:process.env.GITHUB_SHA,backend:'7475aa4e64be57f36399bbaa2166a00700f0abb5',web:'7701aa097cc959127519665b0efd7f82e3d060ab',mobileReference:'e2b1d4edcdf4e42e25d0953831825a97ac8c2493'});
  stage='pinned Web build and isolated Auth';
  const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:anon};
  try{execFileSync('npm',['run','build'],{cwd:web,env,stdio:'ignore',timeout:180000});}catch{throw Error('Web build failed');}
  server=spawn('npm',['run','start','--','--hostname','127.0.0.1','--port','3000'],{cwd:web,env,stdio:'ignore',detached:true});
  await waitFor('Web readiness',async()=>{try{return (await fetch(origin+'/login')).ok;}catch{return false;}},30000);
  browser=await chromium.launch({headless:true});
  const leader=await actor('leader'),staff=await actor('staff'),second=await actor('second'),foreign=await actor('foreign');
  const staffers=[staff,second];
  db("begin; insert into public.organizations(id,slug,name) values ('"+oid+"','m45a-one','Synthetic M45A'),('"+foreignOrg+"','m45a-other','Synthetic Other');"+
    "insert into public.organization_memberships(organization_id,user_id,role,granted_by) values ('"+oid+"','"+leader.id+"','leader','"+leader.id+"'),('"+oid+"','"+staff.id+"','staff','"+leader.id+"'),('"+oid+"','"+second.id+"','staff','"+leader.id+"'),('"+foreignOrg+"','"+foreign.id+"','leader','"+foreign.id+"');"+
    "insert into public.students(student_id,full_name,program_code,year_level) select lpad(n::text,11,'0'),'Synthetic QA '||n,'BSIT',1 from generate_series(1,201) n; commit;");
  check('scoped actors',await rpc(leader.client,'can_manage_org',{org_id:oid})===true&&await rpc(staff.client,'can_manage_org',{org_id:oid})===false&&await rpc(foreign.client,'can_manage_org',{org_id:oid})===false);
  check('no platform admins',db('select count(*) from public.platform_admins')==='0');
  const pg=await pageFor(leader);
  pass(stage,{leader:leader.id,staff:staff.id,second:second.id,foreign:foreign.id,roster:201});
  console.log('QA EXPECTED LEDGER',JSON.stringify({onlineAccepted:[[sid(1),0]],claims:ledger,preparations:[{disposition:'completed',count:3},{disposition:'revoked',count:2}],canonical:{accepted:3,duplicate:1},final:{PRESENT:1,INCOMPLETE:1,ABSENT:199}}));
  stage='LIVE DRAFT browser opt-in and activation';
  const now=Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
  const iso=n=>new Date(now+n*1000).toISOString();
  eid=(await tableOk('create draft',leader.client.from('events').insert({organization_id:oid,title:'Synthetic M45A live',starts_at:iso(-60),ends_at:iso(240),target_year_levels:[1]}).select('id').single())).id;
  path='/organizations/'+oid+'/events/'+eid+'/operations';
  const cps=await tableOk('checkpoints',leader.client.from('event_checkpoints').insert([{event_id:eid,label:'Synthetic A',direction:'IN',opens_at:iso(-30),closes_at:iso(120),sort_order:1},{event_id:eid,label:'Synthetic B',direction:'OUT',opens_at:iso(-30),closes_at:iso(120),sort_order:2}]).select('id,sort_order'));
  a=cps.find(c=>c.sort_order===1).id;b=cps.find(c=>c.sort_order===2).id;
  const cp=[a,b];
  check('freeze 201',await rpc(leader.client,'freeze_event_roster',{eid})===201);
  for(const who of staffers)await rpc(leader.client,'assign_event_staff',{eid,staff_uid:who.id});
  await navigate(pg);
  const stale=await pageFor(leader);await navigate(stale);
  await doForm(pg,'Enable offline attendance');
  await waitFor('opt-in',()=>db("select offline_enabled::text from public.events where "+where().replace('event_id','id'))==='true');
  check('draft cutoff null',sqlrow('events',"id='"+eid+"'").offline_upload_cutoff===null);
  const staleForm=offForm(stale,'Activate event');await staleForm.getByRole('checkbox').check();await staleForm.getByRole('button',{name:'Activate DRAFT event'}).click();
  await visible(staleForm.getByRole('alert'),'stale activation denial');
  check('stale leaves DRAFT',state().state==='DRAFT');
  await stale.context().close();
  await navigate(pg);
  const activate=offForm(pg,'Activate event');await activate.getByRole('checkbox').check();await activate.getByRole('button',{name:'Activate DRAFT event'}).click();
  await waitFor('activate commit',()=>state().state==='OPEN');
  check('canonical real cutoff',db("select (offline_upload_cutoff=(select max(closes_at)+interval '24 hours' from public.event_checkpoints where event_id=events.id))::text from public.events where id='"+eid+"'")==='true');
  pass(stage,{event:eid,cutoff:sqlrow('events',"id='"+eid+"'").offline_upload_cutoff,staleDenied:true});
  stage='LIVE genuine Staff RPC and lost acknowledgement';
  const preparations=[];
  for(const who of staffers){
    const p=await rpc(who.client,'prepare_offline_capture',{p_event_id:eid,p_request_id:uuid()});
    check('preparation scope',p.staff_user_id===who.id&&p.event_id===eid&&p.checkpoints.length===2&&!('roster' in p));
    preparations.push(p);
  }
  const firstOnline=receiptPayload(a,sid(1));const onlineReceipt=await online(staff,firstOnline);check('online accepted',onlineReceipt.outcome==='accepted');
  const liveClaims=ledger.map(l=>makeClaim(preparations[l.staff].preparation_id,cp[l.cp],l.student,preparations[l.staff].issued_at));
  const first=liveClaims[0];
  // Real HTTP request commits. Simulate transport loss to the caller only after independent durable-row confirmation.
  const session=(await staff.client.auth.getSession()).data.session;
  let lost=false,upstreamStatus=0;
  try{
    const response=await fetch(url+'/rest/v1/rpc/submit_offline_capture',{method:'POST',headers:{apikey:anon,Authorization:'Bearer '+session.access_token,'Content-Type':'application/json'},body:JSON.stringify(first)});
    upstreamStatus=response.status;
    check('upstream successful',response.ok);
    check('committed before response discarded',n('offline_capture_claims',where())===1);
    await response.body?.cancel();
    lost=true;throw Error('controlled response discarded');
  }catch(e){if(!lost)throw e;}
  const replay=await upload(staff,first);
  check('identical replay',replay.replayed===true&&replay.status==='submitted'&&replay.capture_id===first.p_capture_id&&Date.parse(replay.received_at)===Date.parse(rawClaim(first.p_capture_id).received_at));
  await rpc(staff.client,'submit_offline_capture',{...first,p_student_id:sid(2)},'23505');
  await rpc(second.client,'submit_offline_capture',first,'42501');
  check('unchanged one durable claim',n('offline_capture_claims',where())===1);
  for(let i=1;i<liveClaims.length;i++){
    const r=await upload(staffers[ledger[i].staff],liveClaims[i]);
    check('generic acknowledgement',r.status==='submitted'&&!r.replayed&&JSON.stringify(Object.keys(r).sort())===JSON.stringify(Object.keys(replay).sort())&&!('review_eligible' in r)&&!('outcome' in r));
    check('private eligibility independently matches plan',rawClaim(liveClaims[i].p_capture_id).review_eligible===ledger[i].eligible);
  }
  check('claims not canonical',n('offline_capture_claims',where())===5&&n('attendance_scans',where())===1&&records().length===0);
  const scoped=await status(staff,preparations[0].preparation_id);
  check('durable count no oracle',scoped.uploaded_count===3&&!('review_eligible' in scoped)&&!('decision' in scoped));
  await complete(staff,preparations[0].preparation_id,2,'22023');
  const done=await complete(staff,preparations[0].preparation_id,3);
  const again=await complete(staff,preparations[0].preparation_id,3);
  assert.deepEqual(withoutReplay(again),withoutReplay(done));check('completion replay',again.replayed===true);
  await complete(staff,preparations[0].preparation_id,4,'23505');
  await rpc(staff.client,'submit_offline_capture',makeClaim(preparations[0].preparation_id,a,sid(4),preparations[0].issued_at),'55000');
  await rpc(leader.client,'revoke_event_staff',{assignment_id:preparations[1].assignment_id});
  await rpc(second.client,'submit_offline_capture',liveClaims[3],'42501');
  await rpc(second.client,'get_offline_preparation_status',{p_preparation_id:preparations[1].preparation_id},'42501');
  pass(stage,{event:eid,claims:liveClaims.map((p,i)=>({id:p.p_capture_id,eligible:ledger[i].eligible})),count:5,canonical:1,upstreamStatus,responseDiscarded:true,replay:true,completionCount:3,revoked:true});
  stage='LIVE server-clock closure and early gates';
  await waitFor('all windows ended',()=>db("select (clock_timestamp()>=max(closes_at))::text from public.event_checkpoints where event_id='"+eid+"'")==='true',135000);
  await navigate(pg);await submit(pg,'Close event');await waitFor('closed',()=>state().state==='SYNCING');
  await navigate(pg);
  await rpc(leader.client,'seal_offline_uploads',{eid},'55000');await rpc(leader.client,'finalize_event',{eid},'55000');
  check('no early browser seal or finalization',await offForm(pg,'Seal offline uploads').count()===0&&await offForm(pg,'Finalize offline attendance').count()===0);
  check('no automatic review',n('offline_claim_reviews',"capture_id in (select capture_id from public.offline_capture_claims where "+where()+")")===0&&records().length===0);
  pass(stage,{event:eid,closed:state().closed_at,cutoff:sqlrow('events',"id='"+eid+"'").offline_upload_cutoff,claims:5,canonical:1});
  stage='HISTORICAL fixture: separate event, not elapsed live time';
  const liveEvent=eid;
  eid=uuid();a=uuid();b=uuid();path='/organizations/'+oid+'/events/'+eid+'/operations';
  const historicalCP=[a,b],assign=[uuid(),uuid()],prep=[uuid(),uuid()],req=[uuid(),uuid()],historicalClaims=ledger.map(l=>({...l,id:uuid()})),historicalOnline=uuid();
  const hnow=Number(db('select floor(extract(epoch from clock_timestamp())*1000)::bigint'));
  const h=hours=>new Date(hnow+hours*3600000).toISOString();
  const q=x=>"'"+String(x).replaceAll("'","''")+"'";
  const tuple=xs=>'('+xs.map(q).join(',')+')';
  // All inserts occur before real reconciliation; no immutable-row edits or clock changes.
  db("begin; select set_config('request.jwt.claim.sub',"+q(leader.id)+",true);"+
    "insert into public.events(id,organization_id,created_by,title,starts_at,ends_at,created_at,target_year_levels) values ("+[eid,oid,leader.id,'Synthetic M45A historical',h(-30),h(-25),h(-32)].map(q).join(",")+",array[1]::smallint[]);"+
    "insert into public.event_checkpoints(id,event_id,label,direction,opens_at,closes_at,sort_order) values "+[tuple([a,eid,'Synthetic A','IN',h(-29),h(-25),1]),tuple([b,eid,'Synthetic B','OUT',h(-29),h(-25),2])].join(',')+";"+
    "insert into public.event_roster(event_id,student_id,student_name,program_code,year_level,frozen_at) select "+q(eid)+",student_id,full_name,program_code,year_level,"+q(h(-31))+" from public.students;"+
    "update public.events set roster_frozen_at="+q(h(-31))+",offline_enabled=true where id="+q(eid)+";"+
    "update public.events set state='OPEN',opened_at="+q(h(-30))+" where id="+q(eid)+";"+
    "insert into public.event_staff(id,event_id,staff_user_id,assigned_at,assigned_by) values "+staffers.map((s,i)=>tuple([assign[i],eid,s.id,h(-30),leader.id])).join(',')+";"+
    "insert into public.offline_preparations(id,request_id,event_id,assignment_id,staff_user_id,issued_at,expires_at) values "+staffers.map((s,i)=>tuple([prep[i],req[i],eid,assign[i],s.id,h(-28),h(-25)])).join(',')+";"+
    "insert into public.offline_capture_claims(capture_id,preparation_id,event_id,checkpoint_id,student_id,claimed_at,received_at,review_eligible) values "+historicalClaims.map(l=>tuple([l.id,prep[l.staff],eid,historicalCP[l.cp],l.student,h(-27),h(-24),l.eligible])).join(',')+";"+
    "insert into public.attendance_scans(scan_id,event_id,checkpoint_id,student_id,submitted_by,received_at,outcome) values "+tuple([historicalOnline,eid,a,sid(1),staff.id,h(-27),'accepted'])+";"+
    "insert into public.offline_preparation_accounting(preparation_id,disposition,uploaded_count,declared_count,accounted_at,accounted_by) values "+tuple([prep[0],'completed',3,3,h(-23),staff.id])+";"+
    "update public.event_staff set revoked_at="+q(h(-22))+",revoked_by="+q(leader.id)+" where id="+q(assign[1])+";"+
    "update public.events set state='SYNCING',closed_at="+q(h(-25))+",closed_by="+q(leader.id)+" where id="+q(eid)+"; commit;");
  check('canonical historical cutoff',db("select (offline_upload_cutoff=(select max(closes_at)+interval '24 hours' from public.event_checkpoints where event_id=events.id) and clock_timestamp()>=offline_upload_cutoff)::text from public.events where id='"+eid+"'")==='true');
  check('seed counts',n('offline_capture_claims',where())===5&&n('offline_preparations',where())===2&&n('attendance_scans',where())===1&&records().length===0);
  pass(stage,{liveEvent,historicalEvent:eid,cutoff:sqlrow('events',"id='"+eid+"'").offline_upload_cutoff,seededClaims:historicalClaims.map(l=>({id:l.id,...l})),preparations:prep,online:historicalOnline});
  stage='HISTORICAL real browser seal and gating';
  const startReview=Date.now();
  await navigate(pg);await doForm(pg,'Seal offline uploads');await waitFor('seal commit',()=>n('offline_upload_seals',where())===1);
  await navigate(pg);
  const sealed=sqlrow('offline_upload_seals',where());check('seal audit',sealed.sealed_by===leader.id&&Date.parse(sealed.sealed_at)>=Date.parse(sqlrow('events',"id='"+eid+"'").offline_upload_cutoff));
  const sealReplay=await rpc(leader.client,'seal_offline_uploads',{eid});check('seal replay',sealReplay.replayed&&Date.parse(sealReplay.sealed_at)===Date.parse(sealed.sealed_at));
  await rpc(leader.client,'confirm_offline_reconciliation',{eid},'55000');await rpc(leader.client,'finalize_event',{eid},'55000');
  check('unaccounted and unreviewed',await summary(leader).then(s=>s.unaccounted_count===1&&s.unreviewed_count===5&&!s.can_confirm&&!s.can_finalize));
  check('browser gates',await offForm(pg,'Confirm offline reconciliation').count()===0&&await offForm(pg,'Finalize offline attendance').count()===0);
  pass(stage,{sealed,unaccounted:1,unreviewed:5});
  stage='HISTORICAL browser session loss and review response loss';
  const lossReason='Synthetic revoked session; evidence retained';
  await doForm(pg,'Record session loss',prep[1],'revoked',lossReason);
  await waitFor('loss commit',()=>n('offline_preparation_accounting',"preparation_id='"+prep[1]+"'")===1);
  const loss=sqlrow('offline_preparation_accounting',"preparation_id='"+prep[1]+"'");
  check('loss exact audit',loss.disposition==='revoked'&&loss.uploaded_count===2&&loss.declared_count===null&&loss.reason===lossReason&&loss.accounted_by===leader.id);
  const lossArgs={eid,p_preparation_id:prep[1],p_disposition:'revoked',p_reason:lossReason};
  check('loss replay',(await rpc(leader.client,'account_offline_preparation_loss',lossArgs)).replayed);
  await rpc(leader.client,'account_offline_preparation_loss',{...lossArgs,p_reason:lossReason+' changed'},'23505');
  await navigate(pg);await rpc(leader.client,'confirm_offline_reconciliation',{eid},'55000');
  const invalid=historicalClaims[2];
  check('ineligible option disabled',await offForm(pg,'Review offline claim',invalid.id).locator('option[value=approve]').isDisabled());
  await rpc(leader.client,'review_offline_capture',{eid,p_capture_id:invalid.id,p_decision:'approve',p_reason:invalid.reason},'55000');
  let posts=0,withheld=false,interceptionError='';
  const lostReview=historicalClaims[0];
  await pg.route('**/operations**',async route=>{
    const r=route.request();if(r.method()!=='POST'||!r.headers()['next-action'])return route.continue();
    posts++;if(posts!==1)return route.abort('failed');
    try{const response=await route.fetch({timeout:30000,maxRedirects:0,maxRetries:0});check('upstream review response',response.ok());check('review committed before response loss',n('offline_claim_reviews',"capture_id='"+lostReview.id+"'")===1);await sleep(500);withheld=true;await route.abort('failed');await response.dispose();}
    catch(e){interceptionError=e.message;try{await route.abort('failed');}catch{}}
  });
  await doForm(pg,'Review offline claim',lostReview.id,lostReview.decision,lostReview.reason);
  await waitFor('withheld review',()=>withheld||!!interceptionError,40000);check('lost review '+interceptionError,withheld&&!interceptionError);
  const lostForm=offForm(pg,'Review offline claim',lostReview.id);
  await visible(lostForm.getByRole('button',{name:'Reload authoritative evidence'}),'reload after lost response');
  check('unconfirmed status',/unconfirmed|could not be confirmed/i.test(await lostForm.getByRole('alert').innerText()));
  check('disabled resubmit',await lostForm.getByRole('button',{name:'Review offline claim',exact:true}).isDisabled());
  await sleep(500);check('no blind retry',posts===1);
  await pg.unroute('**/operations**');await lostForm.getByRole('button',{name:'Reload authoritative evidence'}).click();
  await waitFor('review read-only after reload',async()=>await lostForm.count()===0);
  for(const l of historicalClaims.slice(1)){
    await doForm(pg,'Review offline claim',l.id,l.decision,l.reason);
    await waitFor('review commit',()=>n('offline_claim_reviews',"capture_id='"+l.id+"'")===1);
    await navigate(pg);
  }
  for(const l of historicalClaims){
    const review=sqlrow('offline_claim_reviews',"capture_id='"+l.id+"'");
    check('exact review audit',review.decision===l.decision&&review.reason===l.reason&&review.reviewed_by===leader.id);
    if(l.outcome){
      const scan=sqlrow('attendance_scans',"scan_id='"+review.receipt_id+"'");
      check('canonical provenance',scan.source==='offline'&&scan.offline_capture_id===l.id&&scan.outcome===l.outcome&&scan.submitted_by===staffers[l.staff].id&&scan.checkpoint_id===historicalCP[l.cp]&&scan.student_id===l.student&&Date.parse(scan.received_at)===Date.parse(rawClaim(l.id).received_at));
    }else check('rejected no receipt',review.receipt_id===null);
    const args={eid,p_capture_id:l.id,p_decision:l.decision,p_reason:l.reason};
    check('review replay',(await rpc(leader.client,'review_offline_capture',args)).replayed);
    await rpc(leader.client,'review_offline_capture',{...args,p_reason:l.reason+' changed'},'23505');
  }
  assert.deepEqual(counts(),{accepted:3,duplicate:1});
  check('online receipt unchanged',sqlrow('attendance_scans',"scan_id='"+historicalOnline+"'").source==='online');
  check('all accounting and reviews',await summary(leader).then(s=>s.completed_count===1&&s.loss_count===1&&s.unaccounted_count===0&&s.claim_count===5&&s.reviewed_count===5&&s.unreviewed_count===0&&s.can_confirm&&!s.can_finalize));
  pass(stage,{posts,withheld,loss,canonicalCounts:counts(),reviewActions:5,lossActions:1,elapsedMs:Date.now()-startReview});
  stage='HISTORICAL coverage and confirmation before separate finalization';
  let all=[],pageSizes=[];
  for(let i=1;i<=3;i++){await navigate(pg,'?coverage_page='+i);await visible(coverage(pg),'coverage table');const r=await rows(coverage(pg));pageSizes.push(r.length);all.push(...r);}
  assert.deepEqual(pageSizes,[200,200,2]);check('unique coverage and accepted slots',all.length===402&&new Set(all.map(r=>r[0]+'|'+r[1])).size===402&&all.filter(r=>r[3]==='Accepted receipt recorded').length===3&&all[0][0]===sid(1)&&all.at(-1)[0]===sid(201));
  const dbSlots=json("select json_agg(t order by student_id,checkpoint_id) from (select student_id,checkpoint_id from public.attendance_scans where "+where()+" and outcome='accepted') t");
  check('independent accepted slots',dbSlots.length===3&&dbSlots.some(r=>r.student_id===sid(1)&&r.checkpoint_id===a)&&dbSlots.some(r=>r.student_id===sid(1)&&r.checkpoint_id===b)&&dbSlots.some(r=>r.student_id===sid(2)&&r.checkpoint_id===a));
  await rpc(leader.client,'finalize_event',{eid},'55000');
  await navigate(pg);await doForm(pg,'Confirm offline reconciliation');await waitFor('confirm commit',()=>n('offline_reconciliation_confirmations',where())===1);
  check('confirmation is not finalization',state().state==='SYNCING'&&records().length===0);
  const confirmation=sqlrow('offline_reconciliation_confirmations',where());check('confirm audit',confirmation.confirmed_by===leader.id);
  check('confirm replay',(await rpc(leader.client,'confirm_offline_reconciliation',{eid})).replayed);
  await navigate(pg);await doForm(pg,'Finalize offline attendance');await waitFor('finalized',()=>state().state==='FINALIZED');
  assert.deepEqual(records(),expected);
  await navigate(pg);let p1=await rows(results(pg));await navigate(pg,'?results_page=2');let p2=await rows(results(pg));
  assert.deepEqual([p1.length,p2.length],[200,1]);
  assert.deepEqual([...p1,...p2],expected.map(r=>[r.student_id,r.status,String(r.required_checkpoint_count),String(r.accepted_checkpoint_count)]));
  const finalized=state();check('finalization audit',finalized.finalized_by===leader.id&&Date.parse(finalized.finalized_at)>=Date.parse(confirmation.confirmed_at));
  pass(stage,{coverage:pageSizes,acceptedSlots:dbSlots,results:[200,1],distribution:{PRESENT:1,INCOMPLETE:1,ABSENT:199},confirmation,finalized});
  stage='HISTORICAL terminal denials and immutable replay';
  const exact=makeClaim(prep[0],a,sid(1),h(-27),historicalClaims[0].id);
  check('authorized identical upload replay',(await upload(staff,exact)).replayed===true);
  await rpc(staff.client,'submit_offline_capture',makeClaim(prep[0],a,sid(4),h(-27)),'55000');
  await rpc(second.client,'submit_offline_capture',makeClaim(prep[1],a,sid(2),h(-27),historicalClaims[3].id),'42501');
  const anonymous=createClient(url,anon,opts);
  for(const c of [staff.client,foreign.client,anonymous])for(const name of ['get_event_offline_summary','seal_offline_uploads','confirm_offline_reconciliation','finalize_event'])await rpc(c,name,{eid},'42501');
  for(const who of [staff,foreign]){const denied=await pageFor(who);await navigate(denied);check('denied browser',await results(denied).count()===0&&await offForm(denied,'Finalize offline attendance').count()===0);await denied.context().close();}
  const replayFinal=await rpc(leader.client,'finalize_event',{eid});check('finalized replay',replayFinal.replayed===true&&replayFinal.record_count===201&&Date.parse(replayFinal.finalized_at)===Date.parse(finalized.finalized_at));
  assert.deepEqual(records(),expected);assert.deepEqual(state(),finalized);assert.deepEqual(counts(),{accepted:3,duplicate:1});
  check('all immutable evidence retained',n('offline_capture_claims',where())===5&&n('offline_preparations',where())===2&&n('offline_claim_reviews',"capture_id in (select capture_id from public.offline_capture_claims where "+where()+")")===5&&n('offline_preparation_accounting',"preparation_id in (select id from public.offline_preparations where "+where()+")")===2);
  pass(stage,{replay:true,claims:5,preparations:2,reviews:5,accounting:2,records:201});
  console.log('QA COMPLETE: live pre-cutoff and separately seeded historical post-cutoff; no physical Mobile, OAuth, or real data.');
}catch(e){console.error('QA FAIL',stage,e instanceof Error?e.message.split('\n')[0].slice(0,300):'unknown');process.exitCode=1;}
finally{if(browser)await browser.close();if(server?.pid)try{process.kill(-server.pid,'SIGTERM');}catch{}}
