import {execFileSync,spawn} from 'node:child_process';
import {randomBytes,randomUUID} from 'node:crypto';
import {setTimeout as sleep} from 'node:timers/promises';
const assert=(label,x)=>{if(!x)throw Error(label);};
const check=(label,x)=>{assert(label,x);console.log('ONBOARDING_PASS '+label);};
const mode=process.argv[2]||'acceptance';
assert('isolated GitHub-hosted DB',process.env.HNU_DASH_ISOLATED_TEST_DB==='1'&&process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted');
const args=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=(sql,vars={})=>{
 const binds=Object.entries(vars).flatMap(([k,v])=>{assert('parameter name',/^[a-z_]+$/.test(k));return ['-v',k+'='+String(v)];});
 try{return execFileSync('docker',[...args,...binds],{input:sql,encoding:'utf8',timeout:12000,stdio:['pipe','pipe','pipe']}).trim();}catch{throw Error('isolated SQL failed; raw output withheld');}
};
const j=(sql,v)=>JSON.parse(db(sql,v)),num=(sql,v)=>Number(db(sql,v));
const cfg=JSON.parse(execFileSync('./node_modules/.bin/supabase',['status','-o','json'],{encoding:'utf8',stdio:['ignore','pipe','pipe'],timeout:15000}));
const url=cfg.API_URL,anon=cfg.ANON_KEY||cfg.PUBLISHABLE_KEY,service=cfg.SERVICE_ROLE_KEY||cfg.SECRET_KEY;
assert('loopback only',/^http:\/\/(localhost|127\.0\.0\.1):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const legacy={o:'e3100000-0000-4000-8000-000000000001',a:'e3200000-0000-4000-8000-000000000001',t:'e3200000-0000-4000-8000-000000000002',p:'e3200000-0000-4000-8000-000000000003'};
if(mode==='upgrade-seed'){
 check('B01 pre-upgrade no revision',num("select count(*) from information_schema.columns where table_schema='public' and table_name='organization_memberships' and column_name='revision'")===0);
 db("insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,created_at,updated_at) values(:'a','00000000-0000-0000-0000-000000000000','authenticated','authenticated','upgrade-synthetic-admin@hnu.edu.ph',now(),now(),now()),(:'t','00000000-0000-0000-0000-000000000000','authenticated','authenticated','upgrade-synthetic-target@hnu.edu.ph',now(),now(),now()),(:'p','00000000-0000-0000-0000-000000000000','authenticated','authenticated','upgrade-synthetic-pending@hnu.edu.ph',null,now(),now()); insert into public.organizations(id,slug,name) values(:'o','onboarding-upgrade','Synthetic upgrade'); insert into public.organization_memberships(organization_id,user_id,role,active,granted_by) values(:'o',:'t','staff',false,:'a'),(:'o',:'p','leader',true,:'a');",legacy);
 check('B01 pre-upgrade rows',num("select count(*) from public.organization_memberships where organization_id=:'o'",legacy)===2);process.exit(0);
}
if(mode==='upgrade-check'){
 const rows=j("select json_agg(row_to_json(m) order by user_id) from public.organization_memberships m where organization_id=:'o'",legacy);
 check('B01 preserves all legacy attributes and revision',rows.length===2&&rows[0].organization_id===legacy.o&&rows[0].user_id===legacy.t&&rows[0].role==='staff'&&rows[0].active===false&&rows[0].granted_by===legacy.a&&rows[0].revision===1&&rows[1].organization_id===legacy.o&&rows[1].user_id===legacy.p&&rows[1].role==='leader'&&rows[1].active===true&&rows[1].granted_by===legacy.a&&rows[1].revision===1);
 check('B01 migration provisions no signing key',num('select count(*) from membership_private.signing_keys')===0);process.exit(0);
}
assert('acceptance mode',mode==='acceptance');
let calls=0;
const req=async(path,token,key,body,method='POST')=>{
 assert('240 HTTP call cap',++calls<=240);
 const r=await fetch(url+path,{method,headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json',Prefer:'return=representation'},body:body===undefined?undefined:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
 const data=await r.json();return {ok:r.ok,status:r.status,data,code:r.ok?null:data?.code};
};
const actor=async(label,isAdmin=false)=>{
 const email='onboarding-'+label+'-'+randomBytes(5).toString('hex')+'@hnu.edu.ph',password=randomBytes(24).toString('hex')+'Aa1!';
 const c=await req('/auth/v1/admin/users',service,service,{email,password,email_confirm:true});assert('Auth fixture '+label,c.ok&&!!c.data.id);
 const a=await req('/auth/v1/token?grant_type=password',anon,anon,{email,password});assert('actual Auth login '+label,a.ok&&a.data.user?.id===c.data.id&&!!a.data.access_token);
 if(isAdmin)db("insert into public.platform_admins(user_id) values(:'a')",{a:c.data.id});
 return {id:c.data.id,email,token:a.data.access_token};
};
const org=active=>{const o=randomUUID();db("insert into public.organizations(id,slug,name,active) values(:'o',:'slug','Synthetic onboarding',:'active'::boolean)",{o,slug:'onboarding-'+o,active});return o;};
const rpc=(a,n,p)=>req('/rest/v1/rpc/'+n,a?.token||anon,anon,p);
const prepare=(o,email,role)=>({p_organization_id:o,p_email:email,p_role:role});
const status=(r,s,label)=>{check(label,r.ok&&r.data?.status===s);return r.data;};
const out=(r,s,label)=>{const d=status(r,s,label);assert('fixed response shape',Object.keys(d).sort().join(',')==='membership,replayed,retry_after_seconds,status');return d;};
const deny=(r,label)=>check(label,!r.ok&&(r.code==='42501'||[401,403,404].includes(r.status)));
const mint=async(a,o,email,role='staff')=>{
 const r=await rpc(a,'prepare_org_member_assignment',prepare(o,email,role));
 assert('issued intent',r.ok&&r.data.status==='intent_issued'&&!!r.data.request_id&&!!r.data.intent_token);
 assert('finite deadlines',Date.parse(r.data.replay_before)-Date.parse(r.data.execute_before)===2591700000);
 return {...prepare(o,email,role),p_request_id:r.data.request_id,p_intent_token:r.data.intent_token};
};
const assign=(a,p)=>rpc(a,'assign_verified_org_member',p);
const update=(a,o,u,role,active,revision)=>rpc(a,'update_org_member',{p_organization_id:o,p_user_id:u,p_role:role,p_active:active,p_expected_revision:revision});
const count=(o,u)=>num("select count(*) from public.organization_memberships where organization_id=:'o' and user_id=:'u'",{o,u});
const member=(o,u)=>j("select row_to_json(m) from public.organization_memberships m where organization_id=:'o' and user_id=:'u'",{o,u});
const receipt=(a,r)=>num("select count(*) from membership_private.operation_audit where actor_uid=:'a' and request_id=:'r'",{a,r});
const noSnapshot=(d,label)=>check(label,d.membership===null&&!d.replayed);
const duplicate=email=>{const id=randomUUID();db("insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_sso_user,created_at,updated_at) values(:'id','00000000-0000-0000-0000-000000000000','authenticated','authenticated',:'email',now(),true,now(),now())",{id,email});return id;};
const drop=id=>db("delete from auth.users where id=:'id'",{id});
const backdated=(a,o,email,offset)=>{
 const r=randomUUID();
 const token=db("with x as(select floor(extract(epoch from clock_timestamp()))::bigint+:'delta'::bigint i), k as(select * from membership_private.signing_keys where signing) select 'v1.'||k.audience||'.'||k.key_id::text||'.'||:'r'||'.'||x.i||'.'||(x.i+300)||'.'||(x.i+2592000)||'.'||encode(extensions.hmac(membership_private.canonical(:'a'::uuid,:'r'::uuid,:'o'::uuid,membership_private.valid_email(:'email'),'staff',k.key_id,k.audience,x.i,x.i+300,x.i+2592000),k.secret,'sha256'),'hex') from x,k",{a:a.id,o,email,delta:offset,r});
 assert('backdated synthetic token formed',token.startsWith('v1.'));
 return {...prepare(o,email,'staff'),p_request_id:r,p_intent_token:token};
};
const transactions=[];
const hold=async(sql)=>{
 const p=spawn('docker',args,{stdio:['pipe','pipe','pipe']});let stdout='',closed=false;
 p.stderr.on('data',()=>{});p.stdin.on('error',()=>{});p.on('close',()=>{closed=true;});p.stdout.on('data',d=>{stdout+=d.toString();});
 p.stdin.write(sql+'\n\\echo QA_READY\n');const end=Date.now()+5000;
 while(!stdout.includes('QA_READY')){if(closed||Date.now()>end){p.kill('SIGTERM');throw Error('barrier setup failed');}await sleep(10);}
 const x={release:async()=>{p.stdin.end('rollback;\n\\q\n');const limit=Date.now()+5000;while(!closed&&Date.now()<limit)await sleep(10);if(!closed){p.kill('SIGTERM');throw Error('barrier release failed');}const idx=transactions.indexOf(x);if(idx>=0)transactions.splice(idx,1);}};
 transactions.push(x);return x;
};
const waitBarrier=async(key)=>{const end=Date.now()+2000;while(Date.now()<end){if(num("select count(*) from pg_locks where locktype='advisory' and classid=0 and objid=:'key'::oid and not granted",{key})>0)return;await sleep(5);}throw Error('advisory barrier not observed');};
let phase='catalog';
try{
 const acl=j("select json_build_object('read',has_table_privilege('authenticated','public.organization_memberships','SELECT'),'insert',has_any_column_privilege('authenticated','public.organization_memberships','INSERT'),'update',has_any_column_privilege('authenticated','public.organization_memberships','UPDATE'),'delete',has_table_privilege('authenticated','public.organization_memberships','DELETE'),'private_schema',has_schema_privilege('authenticated','membership_private','USAGE'),'audit',has_table_privilege('authenticated','membership_private.operation_audit','SELECT'),'key',has_table_privilege('authenticated','membership_private.signing_keys','SELECT'),'rate',has_table_privilege('authenticated','membership_private.rate_state','SELECT'),'auth_read',has_table_privilege('authenticated','auth.users','SELECT'),'auth_write',has_any_column_privilege('authenticated','auth.users','UPDATE'),'anon_prepare',has_function_privilege('anon','public.prepare_org_member_assignment(uuid,text,text)','EXECUTE'),'anon_assign',has_function_privilege('anon','public.assign_verified_org_member(uuid,text,text,uuid,text)','EXECUTE'),'anon_update',has_function_privilege('anon','public.update_org_member(uuid,uuid,text,boolean,bigint)','EXECUTE'))");
 check('B01 legacy/private ACL',acl.read&&Object.entries(acl).filter(([k])=>k!=='read').every(([,v])=>v===false));
 check('B01 read RLS preserved',num("select count(*) from pg_policies where schemaname='public' and tablename='organization_memberships' and policyname='memberships_read' and cmd='SELECT'")===1);
 const a=await actor('a',true),b=await actor('b',true),d=await actor('deny',true),rate=await actor('rate',true),race=await actor('race',true),fault=await actor('fault',true),revoked=await actor('revoked',true),unverified=await actor('unverified-admin',true);
 const ordinary=await actor('ordinary'),target=await actor('target'),other=await actor('other'),pending=await actor('pending'),ambiguous=await actor('ambiguous'),raceTarget=await actor('race-target'),faultTarget=await actor('fault-target'),beforeTarget=await actor('before-phantom'),afterTarget=await actor('after-phantom'),rateTarget=await actor('rate-target');
 const o=org(true),o2=org(true),inactive=org(false);
 db("update auth.users set email_confirmed_at=null where id in (:'p',:'u')",{p:pending.id,u:unverified.id});
 check('R03 no seeded key',num('select count(*) from membership_private.signing_keys')===0);
 check('R03 missing key fails closed',!(await rpc(a,'prepare_org_member_assignment',prepare(o,target.email,'staff'))).ok);
 db("insert into membership_private.signing_keys(audience,secret,signing) values('synthetic-onboarding',extensions.gen_random_bytes(32),true)");
 phase='assignment';
 for(const [who,label] of [[null,'anon'],[ordinary,'ordinary'],[unverified,'unverified admin']]){
   deny(await rpc(who,'prepare_org_member_assignment',prepare(o,target.email,'staff')),'B02 prepare denied '+label);
   deny(await update(who,o,target.id,'staff',true,1),'B02 update denied '+label);
 }
 for(const email of ['no-domain','x@hnu.edu.ph.evil','x..y@hnu.edu.ph','x@hnu.edu.ph@hnu.edu.ph','x'.repeat(65)+'@hnu.edu.ph','x y@hnu.edu.ph'])status(await rpc(a,'prepare_org_member_assignment',prepare(o,email,'staff')),'invalid_input','B02 malformed email');
 status(await rpc(a,'prepare_org_member_assignment',prepare(o,target.email,'admin')),'invalid_input','B02 role elevation denied');
 // Literal plus/percent/underscore accepted as dot-atom syntax, not wildcards.
 status(await rpc(a,'prepare_org_member_assignment',prepare(o,'literal+%_@hnu.edu.ph','staff')),'intent_issued','B02 literal dot-atom punctuation');
 const intent=await mint(a,o,' \t'+target.email.toUpperCase()+'\r\n');
 check('R01 mint has no receipt or membership',count(o,target.id)===0&&receipt(a.id,intent.p_request_id)===0);
 const normalized={...intent,p_email:target.email};
 for(const change of [{p_email:other.email},{p_organization_id:o2},{p_role:'leader'},{p_request_id:randomUUID()}])noSnapshot(out(await assign(a,{...normalized,...change}),'request_mismatch','R01 changed intent rejected'),'R01 mismatch no snapshot');
 deny(await assign(ordinary,normalized),'B02 ordinary assign denied');
 noSnapshot(out(await assign(b,normalized),'request_mismatch','R01 wrong actor rejected'),'R01 wrong actor no snapshot');
 const first=out(await assign(a,normalized),'assigned','B02 exact normalized grant');
 check('B02 target, role and revision',first.membership.user_id===target.id&&first.membership.role==='staff'&&first.membership.active&&first.membership.revision==='1'&&!first.replayed);
 const replay=out(await assign(a,normalized),'assigned','R02 receipt replay');
 check('R02 exact historical snapshot',replay.replayed&&JSON.stringify(replay.membership)===JSON.stringify(first.membership)&&receipt(a.id,intent.p_request_id)===1);
 noSnapshot(out(await assign(a,{...normalized,p_email:other.email}),'request_mismatch','R02 changed payload after receipt'),'R02 changed payload no success');
 const conflict=out(await assign(a,await mint(a,o,target.email,'leader')),'already_member','B02 duplicate conflict');
 check('B02 no overwrite and original grantor',conflict.membership.role==='staff'&&count(o,target.id)===1&&member(o,target.id).granted_by===a.id);
 deny(await req('/rest/v1/organization_memberships',a.token,anon,{organization_id:o,user_id:other.id,role:'staff'}),'B01 direct INSERT denied');
 deny(await req('/rest/v1/organization_memberships?organization_id=eq.'+o+'&user_id=eq.'+target.id,a.token,anon,{active:false},'PATCH'),'B01 direct UPDATE denied');
 deny(await req('/rest/v1/organization_memberships?organization_id=eq.'+o+'&user_id=eq.'+target.id,a.token,anon,undefined,'DELETE'),'B01 direct DELETE denied');
 check('B01 scoped read works',(await req('/rest/v1/organization_memberships?organization_id=eq.'+o+'&select=user_id,role,active,revision',a.token,anon,undefined,'GET')).ok);
 const dup=duplicate(ambiguous.email),absent='absent-'+randomBytes(8).toString('hex')+'@hnu.edu.ph';
 const unavailable=[];for(const email of [absent,pending.email,ambiguous.email])unavailable.push(out(await assign(d,await mint(d,o,email)),'account_unavailable','B02 unavailable'));
 check('B02 unavailable shapes identical',unavailable.every(x=>JSON.stringify(x)===JSON.stringify(unavailable[0])));
 drop(dup);
 out(await assign(d,await mint(d,inactive,other.email)),'organization_unavailable','B02 inactive org');
 out(await assign(d,await mint(d,randomUUID(),other.email)),'organization_unavailable','B02 missing org');
 const rev=await mint(revoked,o,other.email);db("delete from public.platform_admins where user_id=:'a'",{a:revoked.id});deny(await assign(revoked,rev),'B02 revoked admin');
 phase='updates';
 let u=out(await update(b,o,target.id,'leader',true,'1'),'updated','B03 role change bigint string');
 check('B03 revision 2',u.membership.revision==='2');
 out(await update(b,o,target.id,'staff',true,1),'state_conflict','B03 stale revision');
 u=out(await update(b,o,target.id,'leader',true,2),'unchanged','B03 no-op');check('B03 no-op same revision',u.membership.revision==='2');
 db("update auth.users set email_confirmed_at=null where id=:'t'",{t:target.id});
 out(await update(b,o,target.id,'staff',false,2),'account_unavailable','B03 combined role/deactivation needs verification');
 db("update public.organizations set active=false where id=:'o'",{o});
 u=out(await update(b,o,target.id,'leader',false,2),'updated','B03 pure deactivation unverified inactive org');check('B03 revision 3 inactive',u.membership.revision==='3'&&!u.membership.active);
 out(await update(b,o,target.id,'leader',true,3),'organization_unavailable','B03 inactive reactivation denied');
 db("update public.organizations set active=true where id=:'o'",{o});
 out(await update(b,o,target.id,'leader',true,3),'account_unavailable','B03 unverified reactivation denied');
 db("update auth.users set email_confirmed_at=now() where id=:'t'",{t:target.id});
 u=out(await update(b,o,target.id,'leader',true,3),'updated','B03 verified reactivation');check('B03 revision and original grantor',u.membership.revision==='4'&&member(o,target.id).granted_by===a.id);
 deny(await update(target,o,target.id,'staff',true,4),'B02 leader cannot manage membership');
 db("update auth.users set email=:'email' where id=:'t'",{email:'reassigned-'+randomBytes(6).toString('hex')+'@hnu.edu.ph',t:target.id});
 db("update auth.users set email=:'email' where id=:'t'",{email:target.email,t:other.id});
 const historical=out(await assign(a,normalized),'assigned','R02 reassigned email historical receipt');
 check('R02 old target not reassigned',historical.replayed&&historical.membership.user_id===target.id&&count(o,other.id)===0);
 other.email=target.email;
 phase='rate and expiry';
 const rateIntent=await mint(rate,o,rateTarget.email);out(await assign(rate,rateIntent),'assigned','B05 admitted grant');
 for(let i=0;i<9;i++)out(await assign(rate,{...rateIntent,p_intent_token:'malformed'}),'invalid_input','B05 admitted invalid attempt');
 const throttled=await mint(rate,o2,other.email);let z=out(await assign(rate,throttled),'rate_limited','B05 cross-org eleventh blocked');
 check('B05 positive retry/no receipt',z.retry_after_seconds>0&&receipt(rate.id,throttled.p_request_id)===0);
 out(await assign(rate,throttled),'rate_limited','B05 repeated throttle');
 check('B05 replay bypasses quota',out(await assign(rate,rateIntent),'assigned','B05 replay while throttled').replayed);
 out(await update(rate,o,rateTarget.id,'staff',false,1),'updated','B05 pure deactivation while throttled');
 check('B05 10 admissions and two coarse denials',num("select count(*) from membership_private.operation_audit where actor_uid=:'a' and admitted",{a:rate.id})===10&&num("select denied_count+coalesce((select sum(coarse_count) from membership_private.operation_audit where actor_uid=:'a' and operation='rate_summary'),0) from membership_private.rate_state where actor_uid=:'a'",{a:rate.id})===2);
 // Controlled synthetic age fixture (no clock changes).
 db("update membership_private.operation_audit set occurred_at=clock_timestamp()-interval '61 seconds' where actor_uid=:'a' and admitted; update membership_private.rate_state set minute_start=minute_start-interval '1 minute' where actor_uid=:'a'",{a:rate.id});
 out(await assign(rate,throttled),'assigned','B05 rolling budget reopens, same unadmitted intent');
 check('B05 durable summary count',num("select coalesce(sum(coarse_count),0) from membership_private.operation_audit where actor_uid=:'a' and operation='rate_summary'",{a:rate.id})===2);
 const expired=backdated(d,o,other.email,-301);noSnapshot(out(await assign(d,expired),'request_expired','R02 initial expiry'),'R02 expired no snapshot');
 const late=backdated(d,o,other.email,-2678400);
 db("insert into membership_private.operation_audit(occurred_at,actor_uid,operation,request_id,organization_id,requested_role,outcome,admitted) values(clock_timestamp()-interval '31 days',:'a','assign',:'r',:'o','staff','account_unavailable',true)",{a:d.id,r:late.p_request_id,o});
 check('R03 old receipt exists',receipt(d.id,late.p_request_id)===1);
 j('select membership_private.prune_telemetry(1000)');
 check('R03 old receipt purged, live receipt retained',receipt(d.id,late.p_request_id)===0&&receipt(a.id,intent.p_request_id)===1);
 noSnapshot(out(await assign(d,late),'request_expired','R02 expired after purge'),'R02 late replay no new grant');check('R02 no unintended grant',count(o,other.id)===0);
 phase='races and rollback';
 const same=await mint(race,o,raceTarget.email),pair=await Promise.all([assign(race,same),assign(race,same)]);
 check('B04 concurrent same UUID',pair.every(x=>x.ok&&['assigned','busy'].includes(x.data.status))&&pair.some(x=>x.data.status==='assigned'));
 check('B04 exactly one grant/receipt',out(await assign(race,same),'assigned','B04 concurrent replay reconcile').replayed&&count(o,raceTarget.id)===1&&receipt(race.id,same.p_request_id)===1);
 const pA=await mint(race,o2,raceTarget.email,'staff'),pB=await mint(fault,o2,raceTarget.email,'leader'),both=await Promise.all([assign(race,pA),assign(fault,pB)]);
 check('B04 conflicting assignment single winner',both.every(x=>x.ok&&['assigned','already_member','busy'].includes(x.data.status))&&both.filter(x=>x.data.status==='assigned').length===1&&count(o2,raceTarget.id)===1);
 const role=member(o2,raceTarget.id).role==='staff'?'leader':'staff',edits=await Promise.all([update(race,o2,raceTarget.id,role,true,1),update(fault,o2,raceTarget.id,role,true,1)]);
 check('B04 revision race single winner',edits.every(x=>x.ok&&['updated','state_conflict','busy'].includes(x.data.status))&&edits.filter(x=>x.data.status==='updated').length===1&&member(o2,raceTarget.id).revision===2);
 const heldIntent=await mint(fault,o,faultTarget.email);
 assert('fixture UUID safe',/^[0-9a-f-]{36}$/.test(faultTarget.id));
 const lock=await hold("begin; select id from auth.users where id='"+faultTarget.id+"'::uuid for update;");
 out(await assign(fault,heldIntent),'busy','C02 selected row NOWAIT');await lock.release();
 check('C02 busy no mutation and historical receipt',count(o,faultTarget.id)===0&&out(await assign(fault,heldIntent),'busy','C02 terminal busy replay').replayed);
 const faultIntent=await mint(fault,o,faultTarget.email);
 db("create function membership_private.qa_audit_fail() returns trigger language plpgsql set search_path='' as $qa$ begin if new.outcome='assigned' then raise exception 'QA audit failure' using errcode='PZ002'; end if; return new; end; $qa$; create trigger qa_audit_fail before insert on membership_private.operation_audit for each row execute function membership_private.qa_audit_fail();");
 const failed=await assign(fault,faultIntent);check('B05 audit failure atomic rollback',!failed.ok&&count(o,faultTarget.id)===0&&receipt(fault.id,faultIntent.p_request_id)===0);
 db('drop trigger qa_audit_fail on membership_private.operation_audit; drop function membership_private.qa_audit_fail()');
 out(await assign(fault,faultIntent),'assigned','B05 exact retry after confirmed rollback');check('B05 one audit',receipt(fault.id,faultIntent.p_request_id)===1);
 phase='phantom';
 // Test-only app-table barriers; never modify managed Auth schema.
 const before=await mint(race,o,beforeTarget.email);
 db("create function membership_private.qa_barrier() returns trigger language plpgsql set search_path='' as $qa$ begin perform pg_advisory_xact_lock(193731); return new; end; $qa$; create trigger qa_barrier after insert on public.organization_memberships for each row execute function membership_private.qa_barrier();");
 const t1=await hold('begin; select pg_advisory_xact_lock(193731);'),p1=assign(race,before);
 await waitBarrier(193731);const dup1=duplicate(beforeTarget.email);await t1.release();
 out(await p1,'account_unavailable','C03 duplicate committed before final snapshot denied');check('C03 tentative row rolled back',count(o,beforeTarget.id)===0);
 db('drop trigger qa_barrier on public.organization_memberships; drop function membership_private.qa_barrier()');drop(dup1);
 const after=await mint(race,o,afterTarget.email);
 db("create function membership_private.qa_barrier() returns trigger language plpgsql set search_path='' as $qa$ begin if new.outcome='assigned' then perform pg_advisory_xact_lock(193732); end if; return new; end; $qa$; create trigger qa_barrier before insert on membership_private.operation_audit for each row execute function membership_private.qa_barrier();");
 const t2=await hold('begin; select pg_advisory_xact_lock(193732);'),p2=assign(race,after);
 await waitBarrier(193732);const dup2=duplicate(afterTarget.email);await t2.release();
 out(await p2,'assigned','C03 accepted post-snapshot phantom');check('C03 two normalized matches and one grant',count(o,afterTarget.id)===1&&num("select count(*) from auth.users where membership_private.normalized(email)=membership_private.normalized(:'email')",{email:afterTarget.email})===2);
 db('drop trigger qa_barrier on membership_private.operation_audit; drop function membership_private.qa_barrier()');drop(dup2);
 phase='key lifecycle';
 const old=await mint(d,o,other.email);
 db("begin; update membership_private.signing_keys set signing=false,verify_until=clock_timestamp()+interval '30 days' where signing; insert into membership_private.signing_keys(audience,secret,signing) values('synthetic-onboarding',extensions.gen_random_bytes(32),true); commit;");
 out(await assign(d,old),'assigned','R03 old verify-only key valid');
 db("delete from membership_private.signing_keys where not signing");
 out(await assign(d,old),'invalid_input','R03 revoked key denies even prior receipt');
 out(await assign(d,await mint(d,o2,other.email)),'already_member','R03 new key active');
 check('B05 no student/event/admin side effects',num("select count(*) from public.profiles where user_id in (:'t',:'u')",{t:target.id,u:other.id})===0&&num("select count(*) from public.event_staff where staff_user_id in (:'t',:'u')",{t:target.id,u:other.id})===0&&num("select count(*) from public.platform_admins where user_id in (:'t',:'u')",{t:target.id,u:other.id})===0);
 check('B05 audit has no raw email/token/hash fields',num("select count(*) from information_schema.columns where table_schema='membership_private' and table_name='operation_audit' and column_name ~ '(email|token|secret|hash|mac)'")===0);
 check('B05 mutation snapshots and actor attribution',num("select count(*) from membership_private.operation_audit where outcome='updated' and actor_uid is not null and target_uid is not null and before_state is not null and membership is not null")>=3);
 console.log('ONBOARDING_RESULT '+JSON.stringify({status:'PASS',httpCalls:calls,syntheticOnly:true,strictCommitTimeUniqueness:false,sideChannelProof:false}));
}catch(e){console.error('ONBOARDING_FAIL '+phase+': '+(e instanceof Error?e.message:'unknown'));process.exitCode=1;}
finally{for(const t of [...transactions].reverse()){try{await t.release();}catch{process.exitCode=1;}}}
