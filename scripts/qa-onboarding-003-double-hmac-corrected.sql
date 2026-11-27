
begin;
set local check_function_bodies = on;
create schema qa_onboarding_crypto;
revoke all on schema qa_onboarding_crypto from public,anon,authenticated;
create table qa_onboarding_crypto.keys(id integer primary key, secret bytea not null check(octet_length(secret)=32), verify_only boolean not null);
create unique index qa_one_active on qa_onboarding_crypto.keys(verify_only) where not verify_only;
create table qa_onboarding_crypto.receipts(actor_id uuid not null, request_id uuid not null, primary key(actor_id,request_id));
create table qa_onboarding_crypto.rng_fixture(force_error boolean not null);
alter table qa_onboarding_crypto.keys enable row level security;
alter table qa_onboarding_crypto.receipts enable row level security;
alter table qa_onboarding_crypto.rng_fixture enable row level security;
revoke all on all tables in schema qa_onboarding_crypto from public,anon,authenticated;
insert into qa_onboarding_crypto.keys values (1,extensions.gen_random_bytes(32),false),(2,extensions.gen_random_bytes(32),true);
insert into qa_onboarding_crypto.rng_fixture values(false);
-- QA-only fault injection, not an application interface. A native RNG error
-- propagates; no comparison or receipt write follows. Not an OS entropy failure test.
create function qa_onboarding_crypto.random_blind() returns bytea
language plpgsql volatile set search_path='' as $qa$
declare force_error boolean;
begin
 select r.force_error into strict force_error from qa_onboarding_crypto.rng_fixture r;
 return extensions.gen_random_bytes(case when force_error then -1 else 32 end);
end; $qa$;
create function qa_onboarding_crypto.blinded_equal(a bytea,b bytea) returns boolean
language plpgsql volatile set search_path='' as $qa$
declare blind_key bytea;
begin
 if a is null or b is null or octet_length(a)<>32 or octet_length(b)<>32 then return false; end if;
 blind_key:=qa_onboarding_crypto.random_blind();
 if blind_key is null or octet_length(blind_key)<>32 then raise exception 'comparison unavailable'; end if;
 -- No raw MAC equality or secret-dependent prefix precomparison.
 return coalesce(extensions.hmac(a,blind_key,'sha256')=extensions.hmac(b,blind_key,'sha256'),false);
end; $qa$;
revoke all on all functions in schema qa_onboarding_crypto from public,anon,authenticated;
-- QA-only RPC: exercises comparator through actual JWT, no real identity lookup.
create function public.qa_onboarding_crypto_probe(p_mode text,p_payload text,p_request_id uuid,p_key_id integer,p_tag text)
returns jsonb language plpgsql volatile security definer set search_path='' as $qa$
declare key_material bytea; expected bytea; input_tag bytea; rid uuid; kid integer; inserted integer; canonical bytea;
begin
 if not public.is_platform_admin() then raise exception 'forbidden' using errcode='42501'; end if;
 if p_mode is null or p_mode not in ('mint','verify') or p_payload is null or octet_length(p_payload) not between 1 and 254 then return jsonb_build_object('status','invalid'); end if;
 if p_mode='mint' then
   if p_request_id is not null or p_key_id is not null or p_tag is not null then return jsonb_build_object('status','invalid'); end if;
   rid:=gen_random_uuid();
   select k.id,k.secret into strict kid,key_material from qa_onboarding_crypto.keys k where not k.verify_only;
 else
   if p_request_id is null or p_key_id is null or p_tag is null or octet_length(p_tag)<>64 or p_tag collate "C" !~ '^[0-9a-f]{64}$' then return jsonb_build_object('status','invalid'); end if;
   rid:=p_request_id; kid:=p_key_id;
   select k.secret into key_material from qa_onboarding_crypto.keys k where k.id=kid;
   if not found then return jsonb_build_object('status','invalid'); end if;
   input_tag:=decode(p_tag,'hex');
 end if;
 canonical:=convert_to(jsonb_build_array('qa-only-v1',auth.uid()::text,rid::text,kid,p_payload)::text,'UTF8');
 expected:=extensions.hmac(canonical,key_material,'sha256');
 if p_mode='mint' then return jsonb_build_object('status','issued','request_id',rid,'key_id',kid,'tag',encode(expected,'hex')); end if;
 if not qa_onboarding_crypto.blinded_equal(input_tag,expected) then return jsonb_build_object('status','invalid'); end if;
 insert into qa_onboarding_crypto.receipts(actor_id,request_id) values(auth.uid(),rid) on conflict do nothing;
 get diagnostics inserted=row_count;
 return jsonb_build_object('status',case when inserted=1 then 'verified' else 'replayed' end);
end; $qa$;
revoke all on function public.qa_onboarding_crypto_probe(text,text,uuid,integer,text) from public,anon,authenticated;
grant execute on function public.qa_onboarding_crypto_probe(text,text,uuid,integer,text) to authenticated;
notify pgrst,'reload schema';
commit;
