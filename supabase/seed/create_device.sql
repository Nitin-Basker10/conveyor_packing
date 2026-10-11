-- Packing Conveyor — device seed
-- Source: PRD_v2 section 4.3.
--
-- Run once, after the migration, against the Supabase database (SQL editor or
-- `supabase db execute`). Replace OWNER_USER_ID with the auth.users id you want
-- to own the device. The plain device token is printed ONCE by RAISE NOTICE;
-- only its sha256 hash is stored. Put the plain token in firmware/secrets.h.

create extension if not exists pgcrypto;

do $$
declare
  v_owner  uuid := '00000000-0000-0000-0000-000000000000'; -- <-- OWNER_USER_ID
  v_token  text := encode(gen_random_bytes(32), 'hex');
  v_device uuid;
begin
  insert into public.devices (owner_id, name, token_hash)
  values (
    v_owner,
    'Packing Conveyor',
    encode(digest(v_token, 'sha256'), 'hex')
  )
  returning id into v_device;

  insert into public.device_status (device_id) values (v_device);

  raise notice 'device_id       : %', v_device;
  raise notice 'device_token    : %', v_token;
  raise notice 'Store these in firmware/secrets.h. The token is shown once.';
end $$;
