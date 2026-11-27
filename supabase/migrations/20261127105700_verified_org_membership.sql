-- HNU-DASH-ONBOARDING-003: synthetic-only approved R1/R2 membership contract.
-- No changes to managed Auth tables or coverage functions.
begin;
alter table public.organization_memberships add column revision bigint not null default 1 check (revision > 0);
revoke insert, update, delete on public.organization_memberships from public, anon, authenticated;
revoke insert (organization_id,user_id,role), update (role,active) on public.organization_memberships from public, anon, authenticated;
drop policy memberships_insert on public.organization_memberships;
drop policy memberships_update on public.organization_memberships;

create schema membership_private;
revoke all on schema membership_private from public, anon, authenticated;
-- Operators provision synthetic keys separately. Never seed a real key in a migration.
create table membership_private.signing_keys (
  key_id uuid primary key default gen_random_uuid(),
  audience text not null check (audience collate "C" ~ '^[a-zA-Z0-9_-]{1,64}$'),
  secret bytea not null check (octet_length(secret)=32),
  signing boolean not null,
  verify_until timestamptz,
  check ((signing and verify_until is null) or (not signing and verify_until is not null))
);
create unique index membership_one_signer on membership_private.signing_keys(signing) where signing;

create table membership_private.operation_audit (
  audit_id uuid primary key default gen_random_uuid(),
  occurred_at timestamptz not null,
  actor_uid uuid not null,
  operation text not null check (operation in ('assign','update','rate_summary','deactivation_summary')),
  request_id uuid,
  organization_id uuid,
  target_uid uuid,
  requested_role text check (requested_role in ('staff','leader')),
  outcome text not null check (outcome in ('assigned','already_member','updated','unchanged','state_conflict','membership_unavailable','account_unavailable','organization_unavailable','invalid_input','request_mismatch','request_expired','rate_limited','busy','deactivation_summary')),
  admitted boolean not null default false,
  membership jsonb,
  before_state jsonb,
  coarse_count bigint,
  first_denied_at timestamptz,
  last_denied_at timestamptz,
  check (request_id is null or operation='assign'),
  unique (actor_uid,request_id)
);
create index membership_audit_budget on membership_private.operation_audit(actor_uid,occurred_at) where admitted;
create index membership_audit_retention on membership_private.operation_audit(occurred_at);
create table membership_private.rate_state (
  actor_uid uuid primary key,
  last_seen_at timestamptz not null,
  minute_start timestamptz not null,
  denied_count bigint not null default 0 check (denied_count>=0),
  first_denied_at timestamptz,
  last_denied_at timestamptz,
  quiet_count bigint not null default 0 check (quiet_count>=0),
  first_quiet_at timestamptz,
  last_quiet_at timestamptz
);
alter table membership_private.signing_keys enable row level security;
alter table membership_private.operation_audit enable row level security;
alter table membership_private.rate_state enable row level security;
revoke all on all tables in schema membership_private from public, anon, authenticated;

create function membership_private.normalized(p_email text)
returns text language sql immutable strict set search_path='' as $fn$
 select lower(btrim(p_email,E' \t\r\n') collate "C")
$fn$;
create function membership_private.valid_email(p_email text)
returns text language plpgsql immutable strict set search_path='' as $fn$
declare n text:=membership_private.normalized(p_email); localpart text;
begin
 if octet_length(n)>254 or n collate "C" !~ '@hnu[.]edu[.]ph$' then return null; end if;
 localpart:=split_part(n,'@',1);
 if octet_length(localpart) not between 1 and 64 or
    n<>localpart||'@hnu.edu.ph' or
    localpart collate "C" !~ $re$^[a-z0-9!#$%&'*+/=?^_`{|}~-]+([.][a-z0-9!#$%&'*+/=?^_`{|}~-]+)*$$re$ then
   return null;
 end if;
 return n;
end; $fn$;

create function membership_private.require_admin()
returns uuid language plpgsql volatile set search_path='' as $fn$
declare a uuid:=auth.uid();
begin
 if a is null or not public.is_platform_admin() then raise exception 'Forbidden' using errcode='42501'; end if;
 if current_setting('transaction_isolation')<>'read committed' then raise exception 'Unsupported transaction isolation' using errcode='55000'; end if;
 return a;
end; $fn$;
-- Selected rows, not a table-wide Auth lock. Deterministic UUID order.
create function membership_private.lock_authority(a uuid,t uuid)
returns void language plpgsql volatile set search_path='' as $fn$
begin
 perform u.id from auth.users u where u.id=a or u.id=t order by u.id for share nowait;
 perform p.user_id from public.platform_admins p where p.user_id=a for share nowait;
 if auth.uid() is distinct from a or not public.is_platform_admin() then raise exception 'Forbidden' using errcode='42501'; end if;
end; $fn$;
-- A VOLATILE helper executes one fresh statement snapshot, counting ALL matches.
create function membership_private.matches_target(n text,t uuid)
returns boolean language sql volatile set search_path='' as $fn$
 select count(*)=1 and coalesce(bool_and(u.id=t and u.email_confirmed_at is not null
    and lower(coalesce(u.email,'')) ~ '^[^@[:space:]]+@hnu[.]edu[.]ph$'),false)
 from auth.users u where membership_private.normalized(u.email)=n
$fn$;
create function membership_private.snapshot(m public.organization_memberships)
returns jsonb language sql immutable strict set search_path='' as $fn$
 select jsonb_build_object('organization_id',m.organization_id,'user_id',m.user_id,'role',m.role,'active',m.active,'revision',m.revision::text)
$fn$;
create function membership_private.result(s text,m jsonb default null,r boolean default false,retry integer default null)
returns jsonb language sql immutable set search_path='' as $fn$
 select jsonb_build_object('status',s,'membership',m,'replayed',r,'retry_after_seconds',retry)
$fn$;
create function membership_private.preparation_result(s text,r uuid default null,t text default null,e bigint default null,p bigint default null)
returns jsonb language sql stable set search_path='' as $fn$
 select jsonb_build_object('status',s,'request_id',r,'intent_token',t,
   'execute_before',to_char(to_timestamp(e) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'),
   'replay_before',to_char(to_timestamp(p) at time zone 'UTC','YYYY-MM-DD"T"HH24:MI:SS"Z"'))
$fn$;

-- Use only fixed-shape, privacy-minimal records. No request bodies or MACs.
create function membership_private.record_attempt(a uuid,at_time timestamptz,op text,rid uuid,o uuid,rr text,
 s text,admitted_flag boolean,m jsonb,prior jsonb)
returns void language plpgsql volatile set search_path='' as $fn$
begin
 insert into membership_private.operation_audit(actor_uid,occurred_at,operation,request_id,organization_id,target_uid,requested_role,outcome,admitted,membership,before_state)
 values(a,at_time,op,rid,o,
   case when s in ('assigned','already_member','updated') then (m->>'user_id')::uuid end,
   case when rr in ('staff','leader') then rr end,s,admitted_flag,
   case when s in ('assigned','already_member','updated') then m end,
   case when s='updated' then prior end);
end; $fn$;
-- Serialize same-actor admissions and receipts. Roll over coarse summaries
-- only once per actor/minute with traffic; never insert one row per denial.
create function membership_private.lock_rate(a uuid)
returns void language plpgsql volatile set search_path='' as $fn$
declare r membership_private.rate_state%rowtype; now_at timestamptz; minute_at timestamptz;
begin
 now_at:=clock_timestamp(); minute_at:=date_trunc('minute',now_at,'UTC');
 insert into membership_private.rate_state(actor_uid,last_seen_at,minute_start) values(a,now_at,minute_at) on conflict do nothing;
 select * into strict r from membership_private.rate_state where actor_uid=a for update;
 now_at:=clock_timestamp(); minute_at:=date_trunc('minute',now_at,'UTC');
 if now_at<r.last_seen_at then raise exception 'Server clock unavailable' using errcode='55000'; end if;
 if minute_at>r.minute_start then
   if r.denied_count>0 then
     insert into membership_private.operation_audit(actor_uid,occurred_at,operation,outcome,coarse_count,first_denied_at,last_denied_at)
     values(a,r.minute_start,'rate_summary','rate_limited',r.denied_count,r.first_denied_at,r.last_denied_at);
   end if;
   if r.quiet_count>0 then
     insert into membership_private.operation_audit(actor_uid,occurred_at,operation,outcome,coarse_count,first_denied_at,last_denied_at)
     values(a,r.minute_start,'deactivation_summary','deactivation_summary',r.quiet_count,r.first_quiet_at,r.last_quiet_at);
   end if;
   update membership_private.rate_state set minute_start=minute_at,denied_count=0,first_denied_at=null,last_denied_at=null,
     quiet_count=0,first_quiet_at=null,last_quiet_at=null,last_seen_at=now_at where actor_uid=a;
 else
   update membership_private.rate_state set last_seen_at=now_at where actor_uid=a;
 end if;
end; $fn$;
create function membership_private.coarse(a uuid,limited boolean,at_time timestamptz)
returns void language plpgsql volatile set search_path='' as $fn$
begin
 if limited then
   update membership_private.rate_state set denied_count=case when denied_count<9223372036854775807 then denied_count+1 else denied_count end,
     first_denied_at=coalesce(first_denied_at,at_time),last_denied_at=at_time where actor_uid=a;
 else
   update membership_private.rate_state set quiet_count=case when quiet_count<9223372036854775807 then quiet_count+1 else quiet_count end,
     first_quiet_at=coalesce(first_quiet_at,at_time),last_quiet_at=at_time where actor_uid=a;
 end if;
end; $fn$;
create function membership_private.budget(a uuid,at_time timestamptz)
returns integer language plpgsql volatile set search_path='' as $fn$
declare n bigint; oldest timestamptz;
begin
 select count(*),min(occurred_at) into n,oldest from membership_private.operation_audit
 where actor_uid=a and admitted and occurred_at>at_time-interval '60 seconds';
 if n<10 then return 0; end if;
 perform membership_private.coarse(a,true,at_time);
 return greatest(1,ceil(extract(epoch from oldest+interval '60 seconds'-at_time))::integer);
end; $fn$;

-- Canonical byte representation: PG17 JSONB array text in this exact field order,
-- UTF-8, all UUIDs canonical and timestamps integer Unix seconds.
create function membership_private.canonical(a uuid,r uuid,o uuid,n text,rr text,k uuid,aud text,i bigint,e bigint,p bigint)
returns bytea language sql immutable strict set search_path='' as $fn$
 select convert_to(jsonb_build_array('v1',aud,k::text,a::text,r::text,i,e,p,o::text,n,rr)::text,'UTF8')
$fn$;
-- Accepted SYNTHETIC mitigation, not a proof of constant-time runtime.
create function membership_private.blinded_equal(a bytea,b bytea)
returns boolean language plpgsql volatile set search_path='' as $fn$
declare blind bytea;
begin
 if a is null or b is null or octet_length(a)<>32 or octet_length(b)<>32 then return false; end if;
 blind:=extensions.gen_random_bytes(32);
 if blind is null or octet_length(blind)<>32 then raise exception 'Comparison unavailable' using errcode='55000'; end if;
 return coalesce(extensions.hmac(a,blind,'sha256')=extensions.hmac(b,blind,'sha256'),false);
end; $fn$;

create function public.prepare_org_member_assignment(p_organization_id uuid,p_email text,p_role text)
returns jsonb language plpgsql volatile security definer set search_path='' set statement_timeout='2s' set lock_timeout='250ms' as $fn$
declare a uuid; n text; k membership_private.signing_keys%rowtype; r uuid; i bigint; e bigint; p bigint; tag bytea;
begin
 a:=membership_private.require_admin();
 perform membership_private.lock_authority(a,null);
 n:=membership_private.valid_email(p_email);
 if p_organization_id is null or n is null or p_role is null or p_role not in ('staff','leader') then return membership_private.preparation_result('invalid_input'); end if;
 select * into k from membership_private.signing_keys where signing for share nowait;
 if not found then raise exception 'Signing unavailable' using errcode='55000'; end if;
 r:=gen_random_uuid(); i:=floor(extract(epoch from clock_timestamp()))::bigint; e:=i+300; p:=i+2592000;
 tag:=extensions.hmac(membership_private.canonical(a,r,p_organization_id,n,p_role,k.key_id,k.audience,i,e,p),k.secret,'sha256');
 if tag is null or octet_length(tag)<>32 then raise exception 'Signing unavailable' using errcode='55000'; end if;
 return membership_private.preparation_result('intent_issued',r,
   'v1.'||k.audience||'.'||k.key_id::text||'.'||r::text||'.'||i::text||'.'||e::text||'.'||p::text||'.'||encode(tag,'hex'),e,p);
exception when lock_not_available or deadlock_detected then return membership_private.preparation_result('busy');
end; $fn$;

create function public.assign_verified_org_member(p_organization_id uuid,p_email text,p_role text,p_request_id uuid,p_intent_token text)
returns jsonb language plpgsql volatile security definer set search_path='' set statement_timeout='2s' set lock_timeout='250ms' as $fn$
declare
 a uuid; n text; fields text[]; k membership_private.signing_keys%rowtype;
 i bigint; e bigint; p bigint; at_time timestamptz; retry integer; s text;
 receipt membership_private.operation_audit%rowtype; rid uuid;
 t uuid; matches bigint; org_active boolean; m public.organization_memberships%rowtype; snap jsonb;
begin
 a:=membership_private.require_admin();
 perform membership_private.lock_rate(a);
 n:=membership_private.valid_email(p_email);
 -- Public format check before parsing; no lookup or receipt disclosure.
 if p_organization_id is null or n is null or p_role is null or p_role not in ('staff','leader') or p_request_id is null
   or p_intent_token is null or octet_length(p_intent_token)>512
   or p_intent_token collate "C" !~ '^v1[.][a-zA-Z0-9_-]{1,64}[.][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.][0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}[.][0-9]{1,12}[.][0-9]{1,12}[.][0-9]{1,12}[.][0-9a-f]{64}$' then
   s:='invalid_input';
 else
   fields:=string_to_array(p_intent_token,'.');
   i:=fields[5]::bigint; e:=fields[6]::bigint; p:=fields[7]::bigint;
   select * into k from membership_private.signing_keys where key_id=fields[3]::uuid for share nowait;
   if not found or k.audience<>fields[2] or (not k.signing and clock_timestamp()>=k.verify_until) or
      e<>i+300 or p<>i+2592000 or i>extract(epoch from clock_timestamp()) then
     s:='invalid_input';
   elsif fields[4]::uuid<>p_request_id or not membership_private.blinded_equal(decode(fields[8],'hex'),
     extensions.hmac(membership_private.canonical(a,p_request_id,p_organization_id,n,p_role,k.key_id,k.audience,i,e,p),k.secret,'sha256')) then
     s:='request_mismatch';
   elsif extract(epoch from clock_timestamp())>=p then
     s:='request_expired';
   else
     select * into receipt from membership_private.operation_audit where actor_uid=a and request_id=p_request_id;
     if found then
       perform membership_private.lock_authority(a,null);
       if extract(epoch from clock_timestamp())>=p then return membership_private.result('request_expired'); end if;
       return membership_private.result(receipt.outcome,receipt.membership,true);
     elsif extract(epoch from clock_timestamp())>=e then
       s:='request_expired';
     else
       rid:=p_request_id;
     end if;
   end if;
 end if;

 at_time:=clock_timestamp();
 retry:=membership_private.budget(a,at_time);
 if retry>0 then
   perform membership_private.lock_authority(a,null);
   if s='request_expired' then return membership_private.result(s); end if;
   return membership_private.result('rate_limited',null,false,retry);
 end if;
 if s is not null then
   perform membership_private.lock_authority(a,null);
   perform membership_private.record_attempt(a,at_time,'assign',null,p_organization_id,p_role,s,true,null,null);
   return membership_private.result(s);
 end if;
 -- Recheck the execution deadline after admission; no expired intent binds a new receipt.
 if extract(epoch from clock_timestamp())>=e then
   perform membership_private.lock_authority(a,null);
   perform membership_private.record_attempt(a,at_time,'assign',null,p_organization_id,p_role,'request_expired',true,null,null);
   return membership_private.result('request_expired');
 end if;
 begin
   -- Initial active-org check precedes any target resolution. Recheck under lock.
   select o.active into org_active from public.organizations o where o.id=p_organization_id;
   if not coalesce(org_active,false) then
     perform membership_private.lock_authority(a,null);
     s:='organization_unavailable';
   else
     select count(*),min(u.id::text)::uuid into matches,t from auth.users u
       where membership_private.normalized(u.email)=n;
     if matches<>1 then t:=null; end if;
     perform membership_private.lock_authority(a,t);
     select o.active into org_active from public.organizations o where o.id=p_organization_id for share nowait;
     if not coalesce(org_active,false) then s:='organization_unavailable';
     elsif t is null or not membership_private.matches_target(n,t) then s:='account_unavailable';
     else
       insert into public.organization_memberships(organization_id,user_id,role,granted_by)
       values(p_organization_id,t,p_role,a) on conflict (organization_id,user_id) do nothing returning * into m;
       if found then s:='assigned';
       else
         select * into strict m from public.organization_memberships where organization_id=p_organization_id and user_id=t for update nowait;
         s:='already_member';
       end if;
       snap:=membership_private.snapshot(m);
       -- Last fresh MVCC snapshot. A later independent phantom is the accepted
       -- synthetic limitation; selected Auth rows remain locked through commit.
       if not membership_private.matches_target(n,t) then raise exception 'Account unavailable' using errcode='PZ001'; end if;
     end if;
   end if;
 exception when sqlstate 'PZ001' then s:='account_unavailable'; snap:=null;
           when lock_not_available or deadlock_detected then s:='busy'; snap:=null;
 end;
 -- Locks released by a rolled-back inner block must not permit stale authority.
 if s in ('account_unavailable','busy','organization_unavailable') then perform membership_private.lock_authority(a,null); end if;
 perform membership_private.record_attempt(a,at_time,'assign',rid,p_organization_id,p_role,s,true,snap,null);
 return membership_private.result(s,snap);
exception when lock_not_available or deadlock_detected then
 -- Admission/authority lock unavailable: outer rollback, no false durable receipt.
 return membership_private.result('busy');
end; $fn$;

create function public.update_org_member(p_organization_id uuid,p_user_id uuid,p_role text,p_active boolean,p_expected_revision bigint)
returns jsonb language plpgsql volatile security definer set search_path='' set statement_timeout='2s' set lock_timeout='250ms' as $fn$
declare a uuid; initial_m public.organization_memberships%rowtype; m public.organization_memberships%rowtype;
 had_row boolean; exempt boolean; needs_check boolean; at_time timestamptz; retry integer; s text; n text; org_active boolean; snap jsonb; prior jsonb;
begin
 a:=membership_private.require_admin();
 perform membership_private.lock_rate(a);
 -- No target identity lookup for classification; scope is the existing PK.
 select * into initial_m from public.organization_memberships where organization_id=p_organization_id and user_id=p_user_id;
 had_row:=found;
 exempt:=had_row and p_active is false and p_role is not distinct from initial_m.role;
 needs_check:=had_row and p_role is not null and p_active is not null and
   (p_role<>initial_m.role or (p_active and not initial_m.active));
 at_time:=clock_timestamp();
 if not exempt then
   retry:=membership_private.budget(a,at_time);
   if retry>0 then perform membership_private.lock_authority(a,null); return membership_private.result('rate_limited',null,false,retry); end if;
 end if;
 if p_organization_id is null or p_user_id is null or p_role is null or p_role not in ('staff','leader') or p_active is null or p_expected_revision is null or p_expected_revision<=0 then
   perform membership_private.lock_authority(a,null); s:='invalid_input';
 else
   begin
     -- A stale revision cannot become a mutation. Do not resolve target identity
     -- when the initial state already proves no verification-required write.
     if needs_check and initial_m.revision=p_expected_revision then
       select o.active into org_active from public.organizations o where o.id=p_organization_id;
       if coalesce(org_active,false) then
         select membership_private.valid_email(u.email) into n from auth.users u where u.id=p_user_id;
         perform membership_private.lock_authority(a,p_user_id);
       else perform membership_private.lock_authority(a,null);
       end if;
       select o.active into org_active from public.organizations o where o.id=p_organization_id for share nowait;
     else perform membership_private.lock_authority(a,null);
     end if;
     select * into m from public.organization_memberships where organization_id=p_organization_id and user_id=p_user_id for update nowait;
     if not found then s:='membership_unavailable';
     elsif not had_row or m.revision<>p_expected_revision or m.revision<>initial_m.revision or m.role<>initial_m.role or m.active<>initial_m.active then
       s:='state_conflict'; snap:=membership_private.snapshot(m);
     elsif m.role=p_role and m.active=p_active then s:='unchanged'; snap:=membership_private.snapshot(m);
     elsif needs_check and not coalesce(org_active,false) then s:='organization_unavailable';
     elsif needs_check and (n is null or not membership_private.matches_target(n,p_user_id)) then s:='account_unavailable';
     else
       prior:=membership_private.snapshot(m);
       update public.organization_memberships set role=p_role,active=p_active,revision=revision+1
         where organization_id=p_organization_id and user_id=p_user_id and revision=p_expected_revision returning * into strict m;
       snap:=membership_private.snapshot(m); s:='updated';
       if needs_check and not membership_private.matches_target(n,p_user_id) then raise exception 'Account unavailable' using errcode='PZ001'; end if;
     end if;
   exception when sqlstate 'PZ001' then s:='account_unavailable'; snap:=null; prior:=null;
             when lock_not_available or deadlock_detected then s:='busy'; snap:=null; prior:=null;
   end;
 end if;
 if s in ('account_unavailable','busy','organization_unavailable') then perform membership_private.lock_authority(a,null); end if;
 if not exempt or s='updated' then perform membership_private.record_attempt(a,at_time,'update',null,p_organization_id,p_role,s,not exempt,snap,prior);
 else perform membership_private.coarse(a,false,at_time); end if;
 return membership_private.result(s,snap);
exception when lock_not_available or deadlock_detected then return membership_private.result('busy');
end; $fn$;

-- Operator-only bounded maintenance, not automatically scheduled. Retention is
-- synthetic policy; actual institutional use is separately gated.
create function membership_private.prune_telemetry(p_limit integer)
returns jsonb language plpgsql volatile set search_path='' as $fn$
declare now_at timestamptz:=clock_timestamp(); a integer; r integer;
begin
 if p_limit is null or p_limit not between 1 and 1000 then raise exception 'Invalid cleanup limit' using errcode='22023'; end if;
 delete from membership_private.operation_audit where audit_id in
   (select audit_id from membership_private.operation_audit
    where occurred_at < now_at - case when outcome in ('assigned','updated') then interval '365 days' else interval '30 days' end
    order by occurred_at,audit_id limit p_limit for update skip locked);
 get diagnostics a=row_count;
 delete from membership_private.rate_state where actor_uid in
   (select actor_uid from membership_private.rate_state where last_seen_at<now_at-interval '30 days'
    order by last_seen_at,actor_uid limit p_limit for update skip locked);
 get diagnostics r=row_count;
 return jsonb_build_object('audit_rows',a,'rate_rows',r);
end; $fn$;

revoke all on all functions in schema membership_private from public, anon, authenticated;
revoke all on function public.prepare_org_member_assignment(uuid,text,text),
 public.assign_verified_org_member(uuid,text,text,uuid,text), public.update_org_member(uuid,uuid,text,boolean,bigint) from public, anon, authenticated;
grant execute on function public.prepare_org_member_assignment(uuid,text,text),
 public.assign_verified_org_member(uuid,text,text,uuid,text), public.update_org_member(uuid,uuid,text,boolean,bigint) to authenticated;
commit;
