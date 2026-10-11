-- Packing Conveyor — initial schema
-- Source: PRD_v2 section 4 (data model), 4.1 (RLS), 4.2 (Realtime)

create table public.devices (
  id uuid primary key default gen_random_uuid(),
  owner_id uuid not null references auth.users(id) on delete cascade,
  name text not null default 'Packing Conveyor',
  token_hash text not null,                 -- sha256 hex of the device token
  last_seen_at timestamptz,
  created_at timestamptz not null default now()
);

create table public.device_status (
  device_id uuid primary key references public.devices(id) on delete cascade,
  boxes int not null default 0,             -- boxes in the current large box (0-9)
  total int not null default 0,             -- boxes pushed since ESP32 restart
  big int not null default 0,               -- completed large boxes since ESP32 restart
  speed_pps numeric(8,1) not null default 0,
  rpm numeric(8,1) not null default 0,
  set_percent int not null default 65 check (set_percent between 20 and 100),
  state text not null default 'PAUSED'
    check (state in ('RUNNING','PAUSED','PUSHING','RETURNING','POSITIONING','FAULT')),
  fault text not null default '',
  updated_at timestamptz not null default now()
);

create table public.commands (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  type text not null check (type in ('start','stop','speed','clear_fault')),
  value int check (value between 20 and 100),
  status text not null default 'pending'
    check (status in ('pending','delivered','done','failed')),
  created_at timestamptz not null default now(),
  delivered_at timestamptz,
  done_at timestamptz,
  constraint speed_needs_value check (type <> 'speed' or value is not null)
);
create index commands_device_status_idx on public.commands (device_id, status, id);

create table public.events (
  id bigint generated always as identity primary key,
  device_id uuid not null references public.devices(id) on delete cascade,
  type text not null
    check (type in ('box_pushed','large_box_filled','fault','fault_cleared','online')),
  payload jsonb not null default '{}',
  created_at timestamptz not null default now()
);
create index events_device_time_idx on public.events (device_id, created_at desc);

-- 4.1 Row Level Security
alter table public.devices enable row level security;
alter table public.device_status enable row level security;
alter table public.commands enable row level security;
alter table public.events enable row level security;

create policy devices_owner_select on public.devices
  for select using (owner_id = auth.uid());

create policy status_owner_select on public.device_status
  for select using (exists (select 1 from public.devices d
    where d.id = device_id and d.owner_id = auth.uid()));

create policy events_owner_select on public.events
  for select using (exists (select 1 from public.devices d
    where d.id = device_id and d.owner_id = auth.uid()));

create policy commands_owner_select on public.commands
  for select using (exists (select 1 from public.devices d
    where d.id = device_id and d.owner_id = auth.uid()));

create policy commands_owner_insert on public.commands
  for insert with check (
    status = 'pending'
    and exists (select 1 from public.devices d
      where d.id = device_id and d.owner_id = auth.uid()));

-- No update or delete policies exist for clients. Do not add any.

-- 4.2 Realtime
alter publication supabase_realtime add table public.device_status, public.commands, public.events;
