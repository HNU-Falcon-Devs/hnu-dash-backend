import {createRequire} from 'node:module';
import {execFileSync,spawn} from 'node:child_process';
import {readFileSync} from 'node:fs';
import {resolve} from 'node:path';
import {randomBytes,randomUUID} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
class QaFailure extends Error {}
const check=(label,ok)=>{if(!ok)throw new QaFailure(label)};
const pass=(label,details={})=>console.log('QA PASS',label,JSON.stringify(details));
const temp=process.env.RUNNER_TEMP;
check('isolated runner',process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted'&&process.env.GITHUB_REF==='refs/heads/qa/onboarding-004-browser'&&process.env.HNU_DASH_ISOLATED_TEST_DB==='1');
const cfg=JSON.parse(readFileSync(resolve(temp,'onboarding-004-local.json'),'utf8'));
const url=cfg.API_URL,anon=cfg.ANON_KEY||cfg.PUBLISHABLE_KEY,service=cfg.SERVICE_ROLE_KEY||cfg.SECRET_KEY;
check('local credentials only',/^http:\/\/(127\.0\.0\.1|localhost):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const web=resolve('qa-web'),oldWeb=resolve('qa-old-web'),origin='http://127.0.0.1:3000',oldOrigin='http://127.0.0.1:3001';
const req=createRequire(resolve(web,'package.json'));
const {createClient}=req('@supabase/supabase-js'),{createServerClient}=req('@supabase/ssr');
const {chromium}=createRequire(resolve(temp,'onboarding-004-tools/package.json'))('playwright');
const args=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=(sql,vars={})=>{try{return execFileSync('docker',[...args,...Object.entries(vars).flatMap(([k,v])=>['-v',k+'='+String(v)])],{input:sql,encoding:'utf8',timeout:15000,stdio:['pipe','pipe','pipe']}).trim()}catch{throw Error('isolated SQL failed')}};
const num=(sql,vars)=>Number(db(sql,vars));
const row=(o,u)=>JSON.parse(db("select coalesce((select row_to_json(m) from public.organization_memberships m where organization_id=:'o' and user_id=:'u'),'null'::json)",{o,u}));
const count=(o,u)=>num("select count(*) from public.organization_memberships where organization_id=:'o' and user_id=:'u'",{o,u});
const audits=(a)=>num("select count(*) from membership_private.operation_audit where actor_uid=:'a'",{a:a.id});
const receipts=(a,o)=>num("select count(*) from membership_private.operation_audit where actor_uid=:'a' and organization_id=:'o' and request_id is not null",{a:a.id,o});
const org=()=>{const id=randomUUID();db("insert into public.organizations(id,slug,name) values(:'id',:'slug','Synthetic Onboarding')",{id,slug:'qa-'+id});return id};
const privileged=createClient(url,service,{auth:{persistSession:false,autoRefreshToken:false}});
const actor=async(name,admin=false)=>{
 const email='qa004-'+name+'-'+randomBytes(4).toString('hex')+'@hnu.edu.ph',password=randomBytes(24).toString('hex')+'aA1!';
 const created=await privileged.auth.admin.createUser({email,password,email_confirm:true});
 check('synthetic Auth account',!created.error&&!!created.data.user);
 const jar=new Map();
 const client=createServerClient(url,anon,{cookies:{getAll:()=>Array.from(jar,([name,value])=>({name,value})),setAll:entries=>{for(const {name,value} of entries){if(value)jar.set(name,value);else jar.delete(name)}}}});
 const signed=await client.auth.signInWithPassword({email,password});
 check('real password session',!signed.error&&!!signed.data.session);
 const id=created.data.user.id;
 check('synthetic UUID',/^[0-9a-f-]{36}$/.test(id));
 if(admin)db("insert into public.platform_admins(user_id) values(:'a')",{a:id});
 const verify=await client.rpc('is_platform_admin');check('admin authority',!verify.error&&verify.data===admin);
 return {id,email,client,jar};
};
const seedMember=(o,u,a,role='staff')=>db("insert into public.organization_memberships(organization_id,user_id,role,granted_by) values(:'o',:'u',:'role',:'a')",{o,u,role,a});
let browser,stage='preflight';const servers=[];let controls=[];
const waitFor=async(label,fn,ms=20000)=>{const end=Date.now()+ms;while(Date.now()<end){if(await fn())return;await sleep(100)}throw Error(label)};
const visible=async locator=>locator.waitFor({state:'visible',timeout:15000});
const start=async(cwd,port)=>{
 const env={...process.env,NEXT_PUBLIC_SUPABASE_URL:url,NEXT_PUBLIC_SUPABASE_PUBLISHABLE_KEY:anon};
 try{execFileSync('npm',['run','build'],{cwd,env,stdio:'ignore',timeout:180000})}catch{throw Error('pinned Web build failed')}
 const s=spawn('npm',['run','start','--','--hostname','127.0.0.1','--port',String(port)],{cwd,env,stdio:'ignore',detached:true});servers.push(s);
 await waitFor('pinned Web readiness',async()=>{try{return (await fetch('http://127.0.0.1:'+port+'/login')).ok}catch{return false}});
};
const pageFor=async(who,base=origin)=>{
 const context=await browser.newContext({viewport:{width:1280,height:900}});
 await context.addCookies(Array.from(who.jar,([name,value])=>({name,value,url:base})));
 const page=await context.newPage();page.setDefaultTimeout(15000);
 return page;
};
const visit=async(who,o,base=origin)=>{const page=await pageFor(who,base);await page.goto(base+'/organizations/'+o,{waitUntil:'networkidle'});return page};
const form=p=>p.getByRole('form',{name:'Assign organization member'});
const edit=(p,u)=>p.getByRole('form',{name:'Edit membership '+u});
const monitor=(p,o,base=origin)=>{
 const m={posts:0,prepares:0,assigns:0,updates:0};
 p.on('request',r=>{
   if(r.method()!=='POST'||!r.url().startsWith(base+'/organizations/'+o))return;
   m.posts++;
   const body=r.postData()||'';
   if(body.includes('"requestId"'))m.assigns++;
   else if(body.includes('"revision"'))m.updates++;
   else if(body.includes('"email"'))m.prepares++;
 });
 return m;
};
const review=async(p,email,role='staff')=>{
 const f=form(p);await f.getByLabel('HNU email address').fill(email);await f.getByLabel('Role').selectOption(role);
 await f.getByRole('button',{name:'Review assignment'}).click();
 await visible(f.getByText(/Assign .* as .* in Synthetic Onboarding/));
 check('explicit confirm disabled before acknowledgment',await f.getByRole('button',{name:'Confirm assignment'}).isDisabled());
};
const confirm=async(p,double=false)=>{const f=form(p);await f.getByRole('checkbox').check();const button=f.getByRole('button',{name:'Confirm assignment'});if(double)await button.evaluate(el=>{el.click();el.click()});else await button.click()};
const newReview=async p=>{await form(p).getByRole('button',{name:'Review another assignment'}).click()};
const expectMessage=async(p,message)=>visible(form(p).getByText(message,{exact:true}));
const lockRow=async(id)=>{
 const p=spawn('docker',args,{stdio:['pipe','pipe','pipe']});let out='',closed=false;
 p.stdout.on('data',d=>out+=d.toString());p.stderr.on('data',()=>{});p.stdin.on('error',()=>{});p.on('close',()=>closed=true);
 check('synthetic target UUID',/^[0-9a-f-]{36}$/.test(id));
 const release=async()=>{if(!closed){p.stdin.end('rollback;\n\\q\n');await waitFor('lock cleanup',()=>closed,5000)}};
 controls.push(release);
 p.stdin.write("begin; select id from auth.users where id='"+id+"'::uuid for update;\n\\echo QA_LOCKED\n");
 await waitFor('independent target lock',()=>out.includes('QA_LOCKED'),5000);
 return release;
};
try{
 stage='pinned migrations and builds';
 const migrations=db('select version from supabase_migrations.schema_migrations order by version').split('\n');
 check('nine exact migrations',migrations.join(',')==='20261106122400,20261108150500,20261108150600,20261123110600,20261124061908,20261124152537,20261124154829,20261127054432,20261127105700');
 check('fresh synthetic stack',db('select count(*) from auth.users')==='0'&&db('select count(*) from membership_private.signing_keys')==='0');
 db("insert into membership_private.signing_keys(audience,secret,signing) values('qa-onboarding-004',extensions.gen_random_bytes(32),true)");
 await start(web,3000);await start(oldWeb,3001);browser=await chromium.launch({headless:true});
 pass(stage,{browser:browser.version(),migrations:9,backend:'07055c9ef6bdc531990b0ca403c061ee8aae27c6',web:'9a621390d76919b646455ee2d6322cf7fbeef7aa',legacyWeb:'14db11483b59c847e902f440843e12beee36eff6'});
 stage='real browser confirmation, assignment and conflict';
 const a=await actor('admin',true),b=await actor('editor',true),ordinary=await actor('ordinary'),target=await actor('target'),pending=await actor('pending'),ambiguous=await actor('ambiguous'),lost=await actor('lost'),reloadTarget=await actor('reload'),busyTarget=await actor('busy'),rateTarget=await actor('rate');
 const o=org();seedMember(o,ordinary.id,a.id);
 db("update auth.users set email_confirmed_at=null where id=:'u'",{u:pending.id});
 db("insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_sso_user,created_at,updated_at) values(:'id','00000000-0000-0000-0000-000000000000','authenticated','authenticated',:'email',now(),true,now(),now())",{id:randomUUID(),email:ambiguous.email});
 const p=await visit(a,o),m=monitor(p,o);const denied=await visit(ordinary,o);
 check('ordinary browser no assignment or update form',await form(denied).count()===0&&await denied.getByRole('form',{name:/Edit membership/}).count()===0);await denied.context().close();
 const raw=await ordinary.client.rpc('prepare_org_member_assignment',{p_organization_id:o,p_email:target.email,p_role:'staff'});
 check('ordinary actual RPC denied',raw.error?.code==='42501');pass('nonadmin denial');
 await review(p,busyTarget.email,'leader');
 await form(p).getByRole('button',{name:'Edit details'}).click();
 check('cancelled confirmation did not prepare',m.posts===0&&count(o,busyTarget.id)===0);
 await review(p,target.email);
 check('zero preconfirmation POSTs or DB writes',m.posts===0&&count(o,target.id)===0&&audits(a)===0);
 await confirm(p,true);await expectMessage(p,'Backend confirmed the membership assignment.');
 await visible(p.getByRole('list',{name:'Organization memberships'}).getByText(target.id,{exact:true}));
 check('one prepare/assignment and durable receipt',m.posts===2&&m.prepares===1&&m.assigns===1&&row(o,target.id)?.revision===1&&receipts(a,o)===1);
 await newReview(p);await review(p,target.email,'leader');await confirm(p);
 await expectMessage(p,'This account is already a member. Review the existing membership.');
 check('explicit conflict no overwrite',row(o,target.id)?.role==='staff'&&row(o,target.id)?.revision===1&&receipts(a,o)===2);
 pass(stage,{preConfirmPosts:0,prepare:1,assign:1,duplicateConflict:true});
 stage='indistinguishable unavailable';
 for(const email of ['absent-'+randomBytes(4).toString('hex')+'@hnu.edu.ph',pending.email,ambiguous.email]){
   await newReview(p);await review(p,email);await confirm(p);
   await expectMessage(p,'Account unavailable for assignment or membership change.');
 }
 check('no pending or ambiguous grants',count(o,pending.id)===0&&count(o,ambiguous.id)===0);
 pass(stage,{cases:3});
 stage='actual committed assignment response lost and exact replay';
 await newReview(p);await review(p,lost.email);
 let lostBody=null,replayedBody=null,dropped=false;
 const routePattern=origin+'/organizations/'+o;
 const intercept=async route=>{
   const request=route.request(),body=request.postData()||'';
   if(request.method()!=='POST'||!body.includes('"requestId"')){await route.continue();return}
   if(!dropped){
     lostBody=body;const response=await route.fetch();check('real action response',response.ok());
     check('actual grant committed before loss',count(o,lost.id)===1);dropped=true;await route.abort('failed');
   }else{replayedBody=body;await route.continue()}
 };
 await p.route(routePattern,intercept);
 const before=m.posts;await confirm(p);await visible(form(p).getByText(/Assignment outcome unknown/));
 check('no optimistic success; input frozen',await form(p).getByLabel('HNU email address').isDisabled()&&await form(p).getByText('Backend confirmed the membership assignment.',{exact:true}).count()===0&&dropped);
 const receiptBefore=receipts(a,o);await form(p).getByRole('button',{name:'Retry exact intent'}).click();
 await visible(form(p).getByText(/Historical receipt only/));
 await visible(p.getByRole('list',{name:'Organization memberships'}).getByText(lost.id,{exact:true}));
 check('exact retry, no remint/new receipt',m.posts===before+3&&lostBody===replayedBody&&receipts(a,o)===receiptBefore&&count(o,lost.id)===1);
 await p.unroute(routePattern,intercept);lostBody=null;replayedBody=null;
 pass(stage,{actualCommitBeforeDrop:true,sameRequestBody:true,receiptUnchanged:true,refresh:true});
 stage='lost token after reload';
 await newReview(p);await review(p,reloadTarget.email);
 let dropReload=false;
 const reloadIntercept=async route=>{
   if(route.request().method()==='POST'&&(route.request().postData()||'').includes('"requestId"')&&!dropReload){
     const r=await route.fetch();check('actual committed response',r.ok()&&count(o,reloadTarget.id)===1);dropReload=true;await route.abort('failed');
   }else await route.continue();
 };
 await p.route(routePattern,reloadIntercept);await confirm(p);await visible(form(p).getByText(/Assignment outcome unknown/));
 const beforeReload=m.posts,oldReceipt=receipts(a,o);
 await p.unroute(routePattern,reloadIntercept);await p.reload({waitUntil:'networkidle'});
 await visible(form(p).getByText(/earlier assignment was uncertain or its intent was lost/));
 check('reload does not silently mint or write',m.posts===beforeReload&&receipts(a,o)===oldReceipt&&await form(p).getByRole('button',{name:'Retry exact intent'}).count()===0);
 await review(p,reloadTarget.email);check('new confirmation requires reconciliation acknowledgment',await form(p).getByRole('button',{name:'Confirm assignment'}).isDisabled());await form(p).getByRole('button',{name:'Edit details'}).click();
 pass(stage,{committedBeforeReload:true,noAutoMint:true});
 stage='busy result and revision conflict';
 const release=await lockRow(busyTarget.id);
 try{await review(p,busyTarget.email);await confirm(p);await visible(form(p).getByText(/Membership management is busy/));check('busy no grant or retry button',count(o,busyTarget.id)===0&&await form(p).getByRole('button',{name:'Retry exact intent'}).count()===0)}finally{await release()}
 const e=edit(p,target.id);await e.getByLabel('Role').selectOption('leader');await e.getByRole('button',{name:'Review changes'}).click();
 const ext=await b.client.rpc('update_org_member',{p_organization_id:o,p_user_id:target.id,p_role:'staff',p_active:false,p_expected_revision:'1'});check('independent revision update',!ext.error&&ext.data.status==='updated');
 await e.getByRole('button',{name:'Confirm changes'}).click();await visible(e.getByText(/Membership changed since/));
 check('stale role change did not overwrite',row(o,target.id)?.revision===2&&row(o,target.id)?.role==='staff'&&!row(o,target.id)?.active);
 await e.getByRole('button',{name:'Review current membership'}).click();
 await waitFor('refresh current revision',async()=>await e.getByLabel('Status').inputValue()==='false'&&await e.getByRole('button',{name:'Review changes'}).isEnabled());
 const oInactive=org(),deact=await actor('deact');seedMember(oInactive,deact.id,a.id);
 db("update public.organizations set active=false where id=:'o'; update auth.users set email_confirmed_at=null where id=:'u'",{o:oInactive,u:deact.id});
 const pDeact=await visit(b,oInactive),de=edit(pDeact,deact.id);
 await de.getByLabel('Status').selectOption('false');await de.getByRole('button',{name:'Review changes'}).click();await de.getByRole('button',{name:'Confirm changes'}).click();
 await visible(de.getByText('Backend confirmed the membership update.',{exact:true}));
 check('pure deactivation allowed inactive org/unverified target',row(oInactive,deact.id)?.revision===2&&!row(oInactive,deact.id)?.active);
 await pDeact.context().close();
 pass(stage,{busy:true,revisionConflict:true,pureDeactivation:true});
 stage='rate limit, exact recovery and expired local intent';
 const rate=await actor('rate-admin',true),ro=org(),rp=await visit(rate,ro),rm=monitor(rp,ro);
 for(let i=0;i<10;i++){
   const r=await rate.client.rpc('assign_verified_org_member',{p_organization_id:ro,p_email:rateTarget.email,p_role:'staff',p_request_id:randomUUID(),p_intent_token:'invalid'});
   check('actual seed budget',!r.error&&r.data.status==='invalid_input');
 }
 await review(rp,rateTarget.email);await confirm(rp);await visible(form(rp).getByText(/Rate limited/));
 check('rate no grant or bound receipt',count(ro,rateTarget.id)===0&&receipts(rate,ro)===0&&rm.posts===2);
 db("update membership_private.operation_audit set occurred_at=clock_timestamp()-interval '61 seconds' where actor_uid=:'a' and admitted",{a:rate.id});
 await form(rp).getByRole('button',{name:'Retry exact intent'}).click();await expectMessage(rp,'Backend confirmed the membership assignment.');
 check('same token retry no remint',rm.prepares===1&&rm.assigns===2&&count(ro,rateTarget.id)===1&&receipts(rate,ro)===1);
 // A separate valid intent is blocked by quota, then the browser's clock is
 // advanced only for UI expiry recovery. Server expiry was verified in Backend CI.
 const re=await actor('expiry-admin',true),eo=org(),ep=await visit(re,eo),em=monitor(ep,eo);
 for(let i=0;i<10;i++){const r=await re.client.rpc('assign_verified_org_member',{p_organization_id:eo,p_email:rateTarget.email,p_role:'staff',p_request_id:randomUUID(),p_intent_token:'invalid'});check('expiry budget seed',!r.error&&r.data.status==='invalid_input')}
 await review(ep,rateTarget.email);await confirm(ep);await visible(form(ep).getByText(/Rate limited/));
 await ep.clock.setFixedTime(new Date(Date.now()+360000));
 await form(ep).getByRole('button',{name:'Retry exact intent'}).click();await visible(form(ep).getByText(/intent window may have expired/));
 check('expired UI blocks retry and new mint',em.posts===2&&await form(ep).getByRole('button',{name:'Start a new review'}).isDisabled()&&count(eo,rateTarget.id)===0);
 pass(stage,{rateLimited:true,unchangedRetry:true,clientClockExpiryGuard:true,serverClockNotChanged:true});
 stage='old Web/new Backend fail safe';
 const legacyOrg=org(),lp=await visit(b,legacyOrg,oldOrigin);
 const lf=lp.getByRole('form',{name:'Assign organization member'});
 await lf.getByLabel('Existing Auth user UUID').fill(target.id);await lf.getByRole('button',{name:'Assign member'}).click();
 await visible(lf.getByText('Could not assign membership. Try again.',{exact:true}));
 check('old client direct INSERT denied',count(legacyOrg,target.id)===0);
 seedMember(legacyOrg,target.id,b.id);
 await lp.reload({waitUntil:'networkidle'});
 const le=edit(lp,target.id);await le.getByLabel('Status').selectOption('false');await le.getByRole('button',{name:'Save changes'}).click();
 await visible(le.getByText('Could not update membership. Try again.',{exact:true}));
 check('old client direct UPDATE denied',row(legacyOrg,target.id)?.revision===1&&row(legacyOrg,target.id)?.active);
 pass(stage,{insertDenied:true,updateDenied:true});
 stage='new Web/old Backend fail safe';
 await browser.close();browser=await chromium.launch({headless:true});
 // Disposable schema reset, not a down migration or restoration of grants on candidate.
 try{execFileSync('./node_modules/.bin/supabase',['db','reset','--version','20261127054432'],{stdio:'ignore',timeout:180000})}catch{throw Error('legacy disposable reset failed')}
 check('legacy exact migration count',db('select count(*) from supabase_migrations.schema_migrations')==='8');
 check('new RPC absent',db("select (to_regprocedure('public.prepare_org_member_assignment(uuid,text,text)') is null)::text")==='true');
 const la=await actor('legacy-admin',true),lt=await actor('legacy-target'),lo=org(),np=await visit(la,lo),nm=monitor(np,lo);
 await review(np,lt.email);await confirm(np);await expectMessage(np,'Could not prepare assignment. No assignment was sent. Review and confirm again.');
 check('no fallback or assignment dispatch',nm.posts===1&&nm.prepares===1&&nm.assigns===0&&count(lo,lt.id)===0);
 pass(stage,{missingRpc:true,noFallback:true});
 console.log('ONBOARDING_004_BROWSER_RESULT PASS synthetic actual Chromium, real Auth, Server Actions and independent PostgreSQL; not production/OAuth');
}catch(e){console.error('QA FAIL stage='+stage+' type='+e.name);if(e instanceof QaFailure)console.error('QA CHECK FAILED: '+e.message);process.exitCode=1}
finally{for(const release of controls.reverse())try{await release()}catch{process.exitCode=1}if(browser)await browser.close();for(const s of servers.reverse())if(s.pid){try{process.kill(-s.pid,'SIGTERM')}catch{}}}
