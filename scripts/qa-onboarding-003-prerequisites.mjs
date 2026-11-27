import { execFileSync, spawn } from 'node:child_process';
import { readFileSync } from 'node:fs';
import { randomUUID, randomBytes } from 'node:crypto';
import { setTimeout as sleep } from 'node:timers/promises';
const check=(label,ok)=>{if(!ok)throw Error(label);};
const log=(label,data)=>console.log('ONBOARDING '+label+' '+JSON.stringify(data));
const tmp=process.env.RUNNER_TEMP;
check('isolation',process.env.GITHUB_ACTIONS==='true'&&process.env.RUNNER_ENVIRONMENT==='github-hosted'&&process.env.GITHUB_REF==='refs/heads/qa/onboarding-003-prerequisites'&&process.env.HNU_DASH_ISOLATED_TEST_DB==='1'&&!!tmp);
const cfg=JSON.parse(readFileSync(tmp+'/onboarding-003-local.json','utf8'));
const url=cfg.API_URL,anon=cfg.ANON_KEY||cfg.PUBLISHABLE_KEY,service=cfg.SERVICE_ROLE_KEY||cfg.SECRET_KEY;
check('loopback',/^http:\/\/(localhost|127\.0\.0\.1):54321\/?$/.test(url)&&!!anon&&!!service&&anon!==service);
const args=['exec','-i','supabase_db_hnu-dash-backend','psql','-X','-qAt','-v','ON_ERROR_STOP=1','-U','postgres','-d','postgres'];
const db=sql=>{try{return execFileSync('docker',args,{input:sql,encoding:'utf8',timeout:12000,stdio:['pipe','pipe','pipe']}).trim();}catch{throw Error('disposable SQL failed; raw output withheld');}};
const j=sql=>JSON.parse(db(sql)),q=x=>"'"+String(x).replaceAll("'","''")+"'";
const req=async(path,token,key,body,method='POST')=>{
 const t=performance.now();
 const r=await fetch(url+path,{method,headers:{apikey:key,Authorization:'Bearer '+token,'Content-Type':'application/json'},body:JSON.stringify(body),signal:AbortSignal.timeout(10000)});
 const data=await r.json();
 return {ok:r.ok,status:r.status,data,ms:performance.now()-t};
};
const login=async a=>req('/auth/v1/token?grant_type=password',anon,anon,{email:a.email,password:a.password});
const actor=async(label)=>{
 const a={email:'onboarding-'+label+'-'+randomBytes(6).toString('hex')+'@hnu.edu.ph',password:randomBytes(24).toString('hex')+'Aa1!'};
 const c=await req('/auth/v1/admin/users',service,service,{email:a.email,password:a.password,email_confirm:true});
 check('Auth create '+label,c.ok&&!!c.data.id);a.id=c.data.id;
 const x=await login(a);check('Auth login '+label,x.ok&&x.data.user?.id===a.id&&!!x.data.access_token);a.token=x.data.access_token;
 return a;
};
const rpc=(a,body)=>req('/rest/v1/rpc/qa_onboarding_003_probe',a.token,anon,body);
const openTx=async(sql)=>{
 const p=spawn('docker',args,{stdio:['pipe','pipe','pipe']});let out='',closed=false;
 p.stderr.on('data',()=>{});p.stdin.on('error',()=>{});p.on('close',()=>{closed=true;});
 p.stdout.on('data',d=>{out+=d.toString();});
 p.stdin.write(sql+'\n\\echo QA_READY\n');
 const deadline=Date.now()+5000;
 while(!out.includes('QA_READY')){if(closed||Date.now()>deadline){p.kill('SIGTERM');throw Error('transaction barrier failed');}await sleep(25);}
 return {read:()=>out,finish:async()=>{p.stdin.end('rollback;\n\\q\n');const end=Date.now()+5000;while(!closed&&Date.now()<end)await sleep(25);if(!closed){p.kill('SIGTERM');throw Error('transaction teardown');}}};
};
let phase='catalog';
const locks=[];
try {
 const images=execFileSync('docker',['ps','--format','{{.Names}} {{.Image}}'],{encoding:'utf8'}).trim().split('\n').filter(l=>/^supabase_(db|auth|rest)_/.test(l));
 const digests=images.map(l=>{const image=l.split(' ')[1];return {image,id:execFileSync('docker',['image','inspect',image,'--format','{{.Id}}'],{encoding:'utf8'}).trim()};});
 const catalog=j("select json_build_object('version',current_setting('server_version'),'isolation',current_setting('transaction_isolation'),'indexes',(select json_agg(json_build_object('name',c.relname,'valid',i.indisvalid,'unique',i.indisunique,'immediate',i.indimmediate,'definition',pg_get_indexdef(i.indexrelid))) from pg_index i join pg_class c on c.oid=i.indexrelid where i.indrelid='auth.users'::regclass),'auth_owner',(select pg_get_userbyid(relowner) from pg_class where oid='auth.users'::regclass),'definer',current_user,'definer_select',has_table_privilege(current_user,'auth.users','SELECT'),'definer_update',has_any_column_privilege(current_user,'auth.users','UPDATE'),'auth_role_select',has_table_privilege('authenticated','auth.users','SELECT'),'auth_role_update',has_any_column_privilege('authenticated','auth.users','UPDATE'),'crypto',(select n.nspname from pg_extension e join pg_namespace n on n.oid=e.extnamespace where e.extname='pgcrypto'))");
 log('CATALOG',{...catalog,images:digests});
 check('READ COMMITTED',catalog.isolation==='read committed');
 check('no Auth client SELECT/UPDATE',!catalog.auth_role_select&&!catalog.auth_role_update);
 check('definer privilege',catalog.definer_select&&catalog.definer_update);
 check('pgcrypto installed',typeof catalog.crypto==='string'&&/^[a-z_][a-z0-9_]*$/.test(catalog.crypto));
 const crypto=catalog.crypto;
 phase='auth fixtures';
 const admin=await actor('admin'),target=await actor('target'),other=await actor('other');
 db("insert into public.platform_admins(user_id) values ("+q(admin.id)+");");
 log('AUTH_FIXTURES',{created:3,confirmed_password_login:3,scope:'disposable local Auth API'});
 phase='crypto and HTTP probe';
 // QA-only objects in the disposable stack, not application migrations.
 // Fixed-work comparison: exactly 32 bytes, no data-dependent early exit.
 // This demonstrates behavior and source shape, not a formal timing guarantee.
 db("create schema qa_onboarding_003; revoke all on schema qa_onboarding_003 from public,anon,authenticated;"+
 "create table qa_onboarding_003.keys(id integer primary key, secret bytea not null, verify_only boolean not null); revoke all on qa_onboarding_003.keys from public,anon,authenticated;"+
 "insert into qa_onboarding_003.keys values(1,"+crypto+".gen_random_bytes(32),false);"+
 "create function qa_onboarding_003.eq32(a bytea,b bytea) returns boolean language plpgsql immutable strict set search_path='' as $$ declare acc int:=0; i int; begin if octet_length(a)<>32 or octet_length(b)<>32 then return false; end if; for i in 0..31 loop acc:=acc | (get_byte(a,i) # get_byte(b,i)); end loop; return acc=0; end $$; revoke all on function qa_onboarding_003.eq32(bytea,bytea) from public,anon,authenticated;"+
 "create function public.qa_onboarding_003_probe(p_target uuid,p_mode text) returns jsonb language plpgsql volatile security definer set search_path='' set statement_timeout='2s' set lock_timeout='250ms' as $$ declare k bytea; tag bytea; matches int; begin if not public.is_platform_admin() then raise exception 'forbidden' using errcode='42501'; end if; if p_mode='timeout' then perform pg_sleep(3); elsif p_mode='wait' then perform 1 from auth.users where id=p_target for share; elsif p_mode='lock' then perform 1 from auth.users where id=p_target for share nowait; elsif p_mode='crypto' then select secret into strict k from qa_onboarding_003.keys where id=1; tag:="+crypto+".hmac(convert_to('synthetic-payload','UTF8'),k,'sha256'); return jsonb_build_object('same',qa_onboarding_003.eq32(tag,tag),'first',not qa_onboarding_003.eq32(tag,set_byte(tag,0,get_byte(tag,0)#1)),'last',not qa_onboarding_003.eq32(tag,set_byte(tag,31,get_byte(tag,31)#1)),'short',not qa_onboarding_003.eq32(tag,substring(tag from 1 for 31))); end if; return jsonb_build_object('isolation',current_setting('transaction_isolation'),'statement_timeout',current_setting('statement_timeout'),'lock_timeout',current_setting('lock_timeout'),'actor_verified',public.is_platform_admin()); end $$; revoke all on function public.qa_onboarding_003_probe(uuid,text) from public,anon,authenticated; grant execute on function public.qa_onboarding_003_probe(uuid,text) to authenticated; notify pgrst,'reload schema';");
 const access=j("select json_build_object('schema',has_schema_privilege('authenticated','qa_onboarding_003','USAGE'),'key_select',has_table_privilege('authenticated','qa_onboarding_003.keys','SELECT'),'key_write',has_table_privilege('authenticated','qa_onboarding_003.keys','UPDATE'),'helper',has_function_privilege('authenticated','qa_onboarding_003.eq32(bytea,bytea)','EXECUTE'),'anon_rpc',has_function_privilege('anon','public.qa_onboarding_003_probe(uuid,text)','EXECUTE'))");
 log('PRIVATE_ACL',access);check('private ACL',Object.values(access).every(x=>x===false));
 let x;
 for(let i=0;i<10;i++){x=await rpc(admin,{p_target:target.id,p_mode:'crypto'});if(x.ok)break;await sleep(250);}
 check('crypto actual authenticated RPC',x.ok&&['same','first','last','short'].every(k=>x.data[k]===true));log('HMAC_FIXED_WORK',x.data);
 const denied=await rpc(other,{p_target:target.id,p_mode:'crypto'});check('nonadmin forbidden',!denied.ok&&denied.data.code==='42501');log('NONADMIN',{status:denied.status,code:denied.data.code});
 // Key lifecycle proof, no material ever leaves SQL.
 const lifecycle=j("with old as (update qa_onboarding_003.keys set verify_only=true where id=1 returning id), newkey as (insert into qa_onboarding_003.keys values(2,"+crypto+".gen_random_bytes(32),false) returning id) select json_build_object('old_retained',(select count(*)=1 from old),'new_active',(select count(*)=1 from newkey))");
 check('key rotation',lifecycle.old_retained&&lifecycle.new_active);db("delete from qa_onboarding_003.keys where id=1;");check('old revoked',db("select count(*) from qa_onboarding_003.keys where id=1")==='0');log('KEY_LIFECYCLE',{...lifecycle,old_revoked:true,key_material_exported:false});
 x=await rpc(admin,{p_target:target.id,p_mode:'lock'});check('actual RPC row lock and settings',x.ok&&x.data.actor_verified&&x.data.isolation==='read committed');log('RPC_SETTINGS',x.data);
 phase='effective deadline';
 x=await rpc(admin,{p_target:target.id,p_mode:'timeout'});log('STATEMENT_TIMEOUT',{status:x.status,code:x.data?.code||null,ms:x.ms});check('effective two second deadline',!x.ok&&x.data?.code==='57014'&&x.ms<3500);
 phase='lock contention';
 let tx=await openTx("begin; select 1 from auth.users where id="+q(target.id)+" for update;");locks.push(tx);
 x=await rpc(admin,{p_target:target.id,p_mode:'lock'});log('NOWAIT',{status:x.status,code:x.data?.code||null,ms:x.ms});check('actual NOWAIT',!x.ok&&x.data?.code==='55P03'&&x.ms<2000);
 x=await rpc(admin,{p_target:target.id,p_mode:'wait'});log('LOCK_TIMEOUT',{status:x.status,code:x.data?.code||null,ms:x.ms});check('effective lock timeout',!x.ok&&x.data?.code==='55P03'&&x.ms<2000);
 await tx.finish();locks.pop();
 phase='Auth writer contention';
 const baseline=[];for(let i=0;i<5;i++){const z=await login(other);check('baseline unrelated login',z.ok);baseline.push(z.ms);}
 tx=await openTx("begin; select 1 from auth.users where id="+q(target.id)+" for share;");locks.push(tx);
 const held=[];for(let i=0;i<5;i++){const z=await login(other);check('unrelated login while target locked',z.ok);held.push(z.ms);}
 let completed=false;
 const changed='onboarding-changed-'+randomBytes(6).toString('hex')+'@hnu.edu.ph';
 const writer=req('/auth/v1/admin/users/'+target.id,service,service,{email:changed,email_confirm:true},'PUT').then(v=>{completed=true;return v;});
 await sleep(400);check('same-row Auth writer waits',!completed);
 await tx.finish();locks.pop();
 const wr=await writer;check('actual Auth writer completes after release',wr.ok);
 check('changed stored target',db("select (email="+q(changed)+")::text from auth.users where id="+q(target.id))==='true');
 const max=a=>Math.max(...a),added=max(held)-max(baseline);
 log('AUTH_CONTENTION',{baselineMs:baseline,heldMs:held,p95AddedApproxMs:added,sameRowWaited:true,writerMs:wr.ms});check('bounded unrelated Auth sample',added<=100);
 phase='phantom boundary';
 const dup=randomUUID(), key="lower(btrim(email) collate \"C\")="+q(changed.toLowerCase());
 const count="select count(*) from auth.users where "+key;
 check('initial exact match',db(count)==='1');
 tx=await openTx("begin isolation level read committed; select 1 from auth.users where id="+q(target.id)+" for share; "+count+";");locks.push(tx);
 check('final snapshot before phantom',tx.read().split('\n').filter(Boolean).slice(-2)[0]==='1');
 // Deliberate synthetic SQL writer models an independent SSO-like row;
 // not an assertion that hosted SSO is enabled or that this is real SSO flow.
 db("insert into auth.users(id,instance_id,aud,role,email,email_confirmed_at,is_sso_user,created_at,updated_at) values("+q(dup)+",'00000000-0000-0000-0000-000000000000','authenticated','authenticated',"+q(changed)+",now(),true,now(),now());");
 check('phantom committed while target held',db(count)==='2');
 await tx.finish();locks.pop();
 check('fresh snapshot sees ambiguity',db(count)==='2');db("delete from auth.users where id="+q(dup)+";");
 log('PHANTOM',{initial:1,independentInsertCommittedWhileTargetLocked:true,freshSnapshot:2,writer:'synthetic direct SQL SSO-like row',noGlobalCommitTimeUniqueness:true});
 log('RESULT',{status:'PREREQUISITE_PROBES_COMPLETE',limit:'fixed-work PL/pgSQL comparison is not independently proven constant-time; production provider/permissions/key lifecycle remain unverified',runtimeAuthSSO:'not exercised',actualOAuth:'not exercised'});
 // A true constant-time implementation and complete actual Auth writer evidence
 // require independent support; do not silently pass this gate based on test vectors.
 process.exitCode=2;
} catch(e){log('BLOCKED',{phase,reason:e instanceof Error?e.message:'unknown failure'});process.exitCode=1;}
finally{for(const tx of locks.reverse()){try{await tx.finish();}catch{process.exitCode=1;}}}
