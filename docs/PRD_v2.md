# Packing Conveyor — Cloud Backend (Supabase) and Stitch UI Build — PRD v2

**Audience:** the Antigravity coding agent.
**Owner:** Nitin.
**Relationship to PRD v1:** `PRD.md` (v1) defines the conveyor's local HTTP API, state values, UI wording and error messages. If `PRD.md` is in the repo, treat it as the source of truth for those. This document (v2) adds a Supabase backend, the app's data layer, and how to build the UI from the Stitch design.

---

## 0. How to work (read first)

1. Work in the phases in section 11, in order. Finish and verify each phase before starting the next.
2. Never invent credentials, project URLs or keys. Read them from `.env` / `secrets.h`. If a value is missing, stop and ask the user.
3. Never put the Supabase `service_role` key, the Stitch API key, or any password in app code, firmware, or git. See section 9.
4. Do not change the visual design. The Stitch design is the source of truth for look and layout (section 7).
5. Do not remove or change the existing local HTTP endpoints on the ESP32 (`/status`, `/speed`, `/start`, `/stop`, `/clear-fault`). They stay working.
6. Keep all belt and servo sequencing on the ESP32. The app and Supabase only monitor and send commands.

---

## 1. Goal

Let the user monitor and control the ESP32 packing conveyor from anywhere, not only on the same Wi-Fi, and keep a history of what the conveyor did.

- **UI:** built from the "Packing Conveyor" project in Google Stitch.
- **Backend:** Supabase (Postgres, Auth, Realtime, Edge Functions).
- **Device:** the ESP32 syncs with Supabase over HTTPS about once per second.

---

## 2. Current system (facts from the firmware)

- ESP32 with an IR box sensor, a slot-type roller speed sensor, an L298N-style motor driver (PWM on ENA), one servo pusher, a buzzer, an SSD1306 OLED and a push button.
- Cycle: belt runs, IR sensor detects a box, belt stops, servo pushes the box sideways, servo returns, `totalBoxesPushed` increases by 1, belt restarts.
- State values: `RUNNING`, `PAUSED`, `PUSHING`, `RETURNING`, `POSITIONING`, `FAULT`.
- `GET /status` returns `{"boxes","total","big","speed","rpm","set","state","fault"}`.
- Speed-sensor fault shutdown is intentionally disabled; the sensor only reports RPM.
- Counters live in RAM and reset when the ESP32 restarts.
- The current firmware always sends `big = 0` and `boxes = 0`. This is fixed in section 6.4.

**Packing rule:** every 10 boxes moved fill one large collection box. The app shows total boxes moved, large boxes filled, and how full the current large box is (0 to 10).

---

## 3. Architecture

```text
Phone app (Flutter)  <--->  Supabase  <--->  ESP32
  Auth (user)               Postgres           HTTPS POST ~1/s to the
  Realtime subscribe        RLS                Edge Function "device-sync"
  insert commands           Edge Function
```

- The ESP32 never talks to the database directly. It calls one Edge Function, `device-sync`, with a device token. The function stores the status, and returns any pending commands.
- The app signs in with Supabase Auth, reads status and events (with Realtime), and inserts rows into `commands`.
- The app also keeps a **Local mode** (v1): the user types the ESP32's IP shown on the OLED and the app uses the HTTP API directly. Both modes sit behind one `ConveyorRepository` interface (section 7.3).
- The Wi-Fi network or hotspot the ESP32 joins must have internet access.

---

## 4. Supabase data model

Create this as `supabase/migrations/0001_init.sql`.

```sql
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
```

### 4.1 Row Level Security

Enable RLS on all four tables. Clients (the app) get read access to their own device data and may only insert pending commands. Only the Edge Function (using the service role inside Supabase) writes status, events and command state.

```sql
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
```

No update or delete policies exist for clients. Do not add any.

### 4.2 Realtime

```sql
alter publication supabase_realtime add table public.device_status, public.commands, public.events;
```

### 4.3 Seed

Create `supabase/seed/create_device.sql` or a small script that, for a given user id, generates a random device token, stores its sha256 hash in `devices.token_hash`, inserts the `device_status` row, and **prints the plain token once** so the user can put it in `secrets.h`. The plain token is never stored.

---

## 5. Edge Function: `device-sync`

Path: `supabase/functions/device-sync/index.ts`. Deploy with JWT verification **off** (`--no-verify-jwt`), because the device authenticates with its own token.

### 5.1 Request

```http
POST /functions/v1/device-sync
Content-Type: application/json
x-device-token: <device token>
```

```json
{
  "device_id": "uuid",
  "status": {
    "boxes": 4, "total": 34, "big": 3,
    "speed": 24.0, "rpm": 144.0, "set": 65,
    "state": "RUNNING", "fault": ""
  },
  "acks": [12, 13],
  "fw": "2.0.0"
}
```

### 5.2 Behaviour

1. Look up the device by `device_id`. Compare `sha256(x-device-token)` to `token_hash`. If it does not match, return `401` and do nothing else.
2. Validate the body. Return `400` with `{"error": "..."}` if `status` fields are missing or out of range (state must be one of the six values, `set` 20..100).
3. Read the previous `device_status` row for this device.
4. Upsert `device_status` from `status` (`set` becomes `set_percent`, `speed` becomes `speed_pps`) and set `updated_at = now()`. Set `devices.last_seen_at = now()`.
5. Write events by comparing previous and new status:
   - `total` increased: insert one `box_pushed` event with payload `{"total": <new>}`.
   - `big` increased: insert one `large_box_filled` event with payload `{"big": <new>}`.
   - state changed to `FAULT`: insert `fault` with payload `{"message": <fault text>}`.
   - state changed from `FAULT` to anything else: insert `fault_cleared`.
   - the previous `last_seen_at` was more than 30 s ago (or null): insert `online`.
   - If the counters went down (ESP32 restarted), do not insert events for that call.
6. Mark every command id in `acks` (belonging to this device) as `done` with `done_at = now()`.
7. Mark `pending` commands older than 30 s as `failed`. A stale "start" must never run after a long outage.
8. Select up to 10 remaining `pending` commands for this device ordered by `id`, mark them `delivered` with `delivered_at = now()`, and return them.

### 5.3 Response

```json
{
  "commands": [
    { "id": 14, "type": "speed", "value": 80 },
    { "id": 15, "type": "start", "value": null }
  ],
  "server_time": "2026-10-11T10:00:00Z"
}
```

Use the service role key from the function's environment (`SUPABASE_SERVICE_ROLE_KEY`). It must never leave the function.

---

## 6. ESP32 firmware changes

Keep the existing sketch structure. Add the following.

### 6.1 Secrets

- Move Wi-Fi SSID and password out of the source file into `firmware/secrets.h` (git-ignored), with a committed `secrets.h.example`.
- `secrets.h` also holds `SUPABASE_FUNCTION_URL` (`https://<project-ref>.supabase.co/functions/v1/device-sync`), `DEVICE_ID` and `DEVICE_TOKEN`.

### 6.2 Cloud sync task

- Use `WiFiClientSecure` + `HTTPClient` + ArduinoJson.
- Run the sync in a **separate FreeRTOS task pinned to core 0**, so a slow HTTPS call can never delay the belt/servo state machine in `loop()`.
- Every 1 s, if Wi-Fi is connected: copy the current status under a mutex, POST it with `acks`, parse the response, and push each command into a FreeRTOS queue. Clear `acks` only after a `200`.
- HTTP timeout about 4 s. On failure, back off 1 s, 2 s, 5 s, 10 s (cap 10 s) and keep operating normally.
- Validate the server certificate (root CA). `setInsecure()` is allowed only as a clearly marked prototype shortcut.
- The belt, servo, OLED and local HTTP API must keep working with no internet.

### 6.3 Applying commands

- `loop()` drains the command queue and applies each command through the **same internal functions** the local HTTP handlers use. Refactor `startFromApi`, `stopFromApi`, `setSpeedFromApi`, `clearFaultFromApi` into plain functions (`startConveyor()`, `stopConveyor()`, `setBeltSpeed(pct)`, `clearFault()`) that the HTTP handlers also call.
- `speed` values are clamped to 20..100.
- After applying a command, add its id to the ack list.
- Optional: show `Cloud: OK` or `Cloud: --` on the OLED.

### 6.4 Large box counting

Add near the other constants:

```cpp
constexpr uint8_t BOXES_PER_LARGE_BOX = 10;
```

In `loop()`, in the `PUSHING_HOME` block, replace `++totalBoxesPushed;` with:

```cpp
++totalBoxesPushed;
boxCount       = totalBoxesPushed % BOXES_PER_LARGE_BOX;  // boxes in the current large box (0-9)
bigBoxesFilled = totalBoxesPushed / BOXES_PER_LARGE_BOX;  // completed large boxes
```

`boxes` now means "boxes in the current large box" and `big` means "completed large boxes". The OLED may also show the large box count.

---

## 7. App (Flutter) and the Stitch UI

### 7.1 Getting the UI from Stitch

1. The user adds the Stitch MCP server in Antigravity (agent panel menu, MCP servers, manage MCP servers, raw config) using their own Stitch API key. **Do not ask the user to paste the key into the chat**, and never write it into the repo or app.
2. Use the Stitch MCP to list the user's projects, open the **Packing Conveyor** project, and fetch its screens and design tokens (and `DESIGN.md` if present).
3. If the MCP is not available, ask the user to place Stitch's HTML/CSS export or screenshots in `design/`, and build from those.
4. Rebuild each screen as Flutter widgets that match the Stitch result 1:1 (spacing, type, colours, states). Do not use a WebView.

### 7.2 Design reference (verify the Stitch output matches; do not redesign)

| Item | Value |
|---|---|
| Style | Flat, hairline-separated panels, 4 px max corner radius, no shadows or gradients |
| Fonts | Barlow (labels, buttons, body), IBM Plex Mono with tabular figures (numeric readouts) via `google_fonts` |
| Background / surface | `#141019` / `#1D1823` |
| Hairlines | `#3A3342` |
| Text / secondary text | `#EDE8E3` / `#A59FAB` |
| Accent (actions only) | burnt amber `#E88A3C`, navy text on amber |
| Running | sage `#8FAE8A` |
| Paused | grey-violet `#8A8494` |
| Pushing / Returning / Positioning | slate blue `#7C93A6` |
| Fault | muted brick `#C25B56` |
| Light theme | background `#F4F0EA`, surface `#FBF8F3`, text `#141019`, accent `#B8601A`, running `#5E7F5A` |

State wording: `RUNNING` = "Belt running", `PAUSED` = "Belt paused", `PUSHING` = "Moving box sideways", `RETURNING` = "Returning pusher", `POSITIONING` = "Positioning box", `FAULT` = "Fault - belt stopped".

### 7.3 Architecture

- Flutter (Android first), Riverpod, `supabase_flutter`, `http`, `shared_preferences`, `google_fonts`.
- One interface used by all screens:

```dart
abstract class ConveyorRepository {
  Stream<ConveyorStatus> watchStatus();            // live values
  Future<void> start();
  Future<void> stop();
  Future<void> setSpeed(int percent);              // 20..100
  Future<void> clearFault();
}
```

- `SupabaseRepository` (cloud mode) and `LocalHttpRepository` (local mode, v1 API) both implement it. The UI never knows which one is active.
- App config via `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`. The anon key is public by design; RLS protects the data.

### 7.4 Screen mapping (Stitch screens)

| Stitch screen | Flutter route | Notes |
|---|---|---|
| 1 Connect | `/connect` | Cloud mode: sign-in (email + password, "Sign in"). Keep the IP field as a secondary "Local connection (same Wi-Fi)" section. Build the sign-in controls in the same style as the Stitch fields and buttons. |
| 2 Dashboard | `/` | Live values from the repository |
| 3 Dashboard states | `/` | Same screen, driven by `state` |
| 4 Connection problems | overlays/banners | Wording from PRD v1 section 7 |
| 5 Settings | `/settings` | Add "Connection mode: Cloud / Local" |
| 6 Connecting | overlay | While signing in or connecting |
| 7 Dashboard, connection lost | `/` | Phone cannot reach Supabase |
| 8 Command feedback | `/` | See 7.6 |

Add one extra state in the same style as screen 7: **Conveyor offline**, a banner "Conveyor offline. Last seen <time ago>." with readouts dimmed to 50% and controls disabled. Use it when the phone reaches Supabase but `devices.last_seen_at` is more than 10 s old.

### 7.5 Dashboard data binding

| UI element | Source |
|---|---|
| Connection | Cloud reachable and device online (`last_seen_at` within 10 s) |
| State row | `device_status.state` |
| ROLLER SPEED | `rpm` (one decimal, "RPM") |
| BELT SETTING | `set_percent` (%) |
| BOXES MOVED | `total` |
| LARGE BOXES FILLED | `big` |
| CURRENT LARGE BOX | `boxes` shown as "n / 10" with a 10-cell bar, first `boxes` cells filled |
| Fault panel | `fault`, shown only when it is not empty or state is `FAULT` |

Use Supabase Realtime on `device_status`. If the Realtime connection drops, fall back to polling the row every 1 s until it reconnects.

### 7.6 Controls and command flow

- Start, Stop, Speed and Clear fault insert a row into `commands` (`status = 'pending'`).
- Show the "waiting" state on the button (screen 8) until that command becomes `done`, or 5 s pass. If it becomes `failed` or times out: bottom bar "Command failed. Try again."
- Apply a speed change when the slider is released, not while dragging.
- Button rules from PRD v1: Start disabled while `PUSHING` or `RETURNING`; Stop disabled while `PAUSED`; Start and Stop disabled when the conveyor is offline.
- The dashboard shows the real values from the device, not the commanded ones.

### 7.7 Local mode

Same as PRD v1: user enters the OLED IP, the app normalizes it to `http://<ip>`, polls `GET /status` every 1 s, and uses `/speed?percent=`, `/start`, `/stop`, `/clear-fault`. Timeouts 3 to 5 s. Error wording from PRD v1.

---

## 8. Safety notes

- This machine has moving parts. Remote commands must never surprise a person standing next to it.
- Commands older than 30 s are never delivered (section 5.2). `stop` is always honoured.
- The physical button on the conveyor must always be able to pause the belt locally.
- Do not add any firmware path that restarts the belt automatically after a reconnect.

---

## 9. Security

- RLS is on for every table; clients cannot write status, events, or command state.
- The device token is stored hashed. Rotate it by generating a new token and updating `devices.token_hash` and `secrets.h`.
- Never commit: `.env`, `secrets.h`, the Supabase `service_role` key, the Stitch API key. Add them to `.gitignore` and commit `.env.example` and `secrets.h.example`.
- The Stitch API key lives only in Antigravity's MCP configuration, never in app or repo code.
- Hotspot and Wi-Fi passwords must not be in the repo.

---

## 10. Configuration the user must provide

| Value | Where it is used |
|---|---|
| Supabase project URL | App (`--dart-define`), firmware `secrets.h` |
| Supabase anon key | App only |
| Device token and device id | Firmware `secrets.h` (from the seed script) |
| Wi-Fi SSID and password | Firmware `secrets.h` |
| Stitch API key | Antigravity MCP config only |

If any value is missing, stop and ask.

---

## 11. Work plan and acceptance criteria

### Phase 0: Setup

- Create the repo structure:

```text
packing-conveyor/
  design/                      # Stitch exports, DESIGN.md
  supabase/
    migrations/0001_init.sql
    functions/device-sync/index.ts
    seed/create_device.sql
  firmware/
    packing_conveyor/packing_conveyor.ino
    secrets.h.example
  app/                         # Flutter
  docs/PRD.md  docs/PRD_v2.md
  .env.example  .gitignore
```

- Connect Stitch MCP (user adds the key) and the Supabase MCP or CLI.
- **Done when:** the agent can list the Stitch project's screens and run SQL against the Supabase project.

### Phase 1: Supabase

- Apply the migration, RLS and Realtime; deploy `device-sync`; create the seed script.
- **Done when:** a `curl` POST with a valid token returns `200` and updates `device_status`; an invalid token returns `401`; a signed-in user can read only their own device rows and cannot update `device_status` or `events`.

### Phase 2: Firmware

- Secrets file, sync task, command queue and acks, refactored command functions, large box counting.
- **Done when:** the Serial Monitor shows a successful sync each second; the belt keeps running when the internet is cut; a test row in `commands` is applied within about 3 s and marked `done`; pushing 10 boxes makes `big` go up by 1 and `boxes` return to 0.

### Phase 3: App

- Design tokens and fonts, all Stitch screens, `ConveyorRepository` with both implementations, Realtime binding, command flow, error and offline states.
- **Done when:** every Stitch screen exists and visually matches the design; the dashboard shows live values; all section 12 tests pass.

### Phase 4: End-to-end

- Run the section 12 checklist on the real conveyor.

---

## 12. Test checklist

1. Sign in on the phone; the dashboard shows the live state, RPM, set speed, total boxes, large boxes and the "n / 10" bar.
2. Press **Stop**: the belt stops and the state shows "Belt paused" within about 3 s. Press **Start**: it resumes.
3. Move the speed slider to 80%: the device reports `set = 80` and the belt speeds up; the slider never goes below 20% or above 100%.
4. Push 10 boxes through: "Boxes moved" goes up by 10, "Large boxes filled" by 1, and "Current large box" returns to 0 / 10.
5. Unplug the ESP32: within about 15 s the app shows "Conveyor offline" with the last-seen time and disables the controls.
6. Turn off the phone's data and Wi-Fi: the app shows "Connection lost" and recovers when the network returns.
7. Cut the ESP32's internet but leave it powered: the belt cycle keeps working and the local HTTP API still answers.
8. Insert a `start` command, then leave the ESP32 offline for 40 s: after reconnect the command is `failed` and the belt does not start.
9. Sign in as a second user: no data from the first user's device is visible.
10. Search the repo and the built app for the service role key, Stitch key, Wi-Fi password and device token: none are found.

---

## 13. Out of scope for this version

- Device pairing in the app (the device is created with the seed script).
- Multiple devices per user, user roles, push notifications.
- An Activity/History screen (events are recorded now so it can be designed in Stitch and added later).
- Over-the-air firmware updates.
- Persisting counters across ESP32 restarts.
