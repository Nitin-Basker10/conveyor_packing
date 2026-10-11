# Packing Conveyor — As-Built PRD (v3)

**Status:** As-built. Describes what is actually implemented in this repo today.
**Owner:** Nitin.
**Supersedes / merges:** `docs/PRD.md` (v1, local HTTP control) and `docs/PRD_v2.md` (v2, Supabase cloud + Stitch UI).
**Purpose of this document:** single source of truth to write a fresh spec from. Sections 1–8 describe the built system; section 9 lists **known gaps and deviations** from v1/v2 — that is where most new work will land.

> Where v1 and v2 disagree, this document follows the **code**. Line references point at the exact implementation.

---

## 1. Overview

A miniature packing conveyor driven by an ESP32. An IR sensor detects a box, the belt stops, a servo pushes the box sideways, then the cycle repeats. Every 10 boxes moved fills one large collection box.

Two ways to monitor/control it:

- **Local mode (v1):** a Flutter app on the same Wi-Fi hotspot talks directly to the ESP32 HTTP API.
- **Cloud mode (v2):** the ESP32 syncs to Supabase over HTTPS roughly once per second; the Flutter app signs in with Supabase Auth, reads live status over Realtime, and writes commands.

Goals:

1. Start, stop, set belt speed (20–100%), clear fault, and read live telemetry.
2. Monitor and control from anywhere (cloud mode), not just the same Wi-Fi.
3. Count boxes moved, large boxes filled, and current large-box fill (n/10).
4. Keep a short client-side history of live values and derived events.

---

## 2. Architecture (as-built)

```text
Flutter app  <---- Supabase Auth / Realtime / PostgREST ---->  Supabase
   |  \                                                          Postgres + RLS
   |   \  insert commands                                        Edge Function: device-sync
   |    \                                                            ^
   |     \  (cloud status via realtime device_status)               | HTTPS POST ~1/s
   |                                                                 | x-device-token
   \---- local HTTP (same Wi-Fi) ---------------------------------> ESP32 (WebServer :80)
              GET /status /speed /start /stop /clear-fault
```

- The ESP32 **never** talks to the database directly. It calls one Edge Function, `device-sync`, with a device token; the function stores status and returns pending commands.
- The app resolves one `device` for the signed-in user, streams `device_status`, and inserts into `commands`.
- One `ConveyorRepository` interface hides which mode is active; the UI never knows.
- All belt/servo sequencing stays on the ESP32. App and Supabase only monitor and send commands.

---

## 3. Hardware & firmware (as-built)

Source: `firmware/packing_conveyor/packing_conveyor.ino` (550 lines). Secrets in git-ignored `firmware/secrets.h` (template: `firmware/secrets.h.example`).

### 3.1 Pins

| Function | Pin |
|---|---|
| IR box sensor (FC-51, active LOW) | 4 |
| Roller slot speed sensor | 14 |
| Buzzer | 18 |
| Motor PWM (ENA) | 25 |
| Motor IN1 / IN2 | 26 / 27 |
| Servo pusher | 13 |
| Push button (INPUT_PULLUP) | 32 |
| OLED SDA / SCL | 21 / 22 |

### 3.2 Key constants

| Constant | Value | Notes |
|---|---|---|
| `BATCH_SIZE` | 1 | one detected box per cycle |
| `BOXES_PER_LARGE_BOX` | 10 | **counting rule** |
| `SPEED_SENSOR_SLOTS_PER_REVOLUTION` | 10 | RPM = pps × 60 / 10 |
| `SENSOR_DEBOUNCE_US` | 80000 | IR debounce |
| `SPEED_DEBOUNCE_US` | 1200 | slot debounce |
| `SPEED_SAMPLE_MS` | 500 | RPM sample window |
| `PUSH_OUT_MS` / `PUSH_RETURN_MS` | 900 / 900 | servo dwell |
| `SERVO_HOME_ANGLE` / `SERVO_PUSH_ANGLE` | 30 / 90 | **not both used — see §9** |
| `CLOUD_SYNC_PERIOD_MS` | 1000 | cloud sync cadence |
| `CLOUD_HTTP_TIMEOUT_MS` | 4000 | HTTPS timeout |
| `CLOUD_MAX_ACKS` | 16 | ack buffer |

### 3.3 State machine (actual)

`CycleState { RUNNING, PUSHING_OUT, PUSHING_HOME }` plus the reachable `POSITIONING` label. Reported states are computed by `stateText()` (`:203`):

| Reported `state` | Condition |
|---|---|
| `FAULT` | `faultActive` (currently unreachable — §9) |
| `PAUSED` | `!systemEnabled` |
| `RUNNING` | RUNNING |
| `PUSHING` | PUSHING_OUT |
| `RETURNING` | PUSHING_HOME |
| `POSITIONING` | LAST_BOX_TRAVEL (currently unreachable — §9) |

Cycle (`loop()`, `:513`–`:539`):

1. Box detected while RUNNING + enabled + not fault → stop belt, `pusher.write(90)`, → `PUSHING_OUT`.
2. After `PUSH_OUT_MS` → `pusher.write(0)` → `PUSHING_HOME`.
3. After `PUSH_RETURN_MS` → `++totalBoxesPushed`, recompute large-box counters, → RUNNING, resume belt if enabled.

The physical button toggles `systemEnabled` (pause/resume) locally and is debounced 35 ms.

### 3.4 Local HTTP API (unchanged, always works offline)

`WebServer` on port **80**, JSON responses.

| Method/Path | Success | Errors |
|---|---|---|
| `GET /status` | 200 status JSON | — |
| `GET /speed?percent=N` | 200 status JSON (N clamped 20–100) | 400 `{"error":"use percent=20..100"}` if missing |
| `GET /start` | 200 status JSON | — |
| `GET /stop` | 200 status JSON | — |
| `GET /clear-fault` | 200 status JSON | — |
| anything else | — | 404 `{"error":"not found"}` |

Status JSON (`statusJson()`, `:158`):

```json
{"boxes":0,"total":0,"big":0,"speed":0.0,"rpm":0.0,"set":65,"state":"RUNNING","fault":""}
```

| Field | Meaning |
|---|---|
| `boxes` | boxes in the current large box, 0–9 = `total % 10` |
| `total` | boxes pushed since ESP32 restart |
| `big` | completed large boxes = `total / 10` |
| `speed` | raw pulses per second |
| `rpm` | roller RPM |
| `set` | commanded belt speed 20–100 |
| `state` | one of the six values |
| `fault` | human-readable fault text, normally `""` |

### 3.5 Cloud sync task

- Separate FreeRTOS task pinned to **core 0** (`cloudSyncTask`, `:379`), so a slow HTTPS call cannot stall `loop()`.
- Every 1 s (backoff 1/2/5/10 s on failure), copies `gStatus` under a mutex, POSTs to `SUPABASE_FUNCTION_URL` with `x-device-token`, parses the response, pushes commands into a 16-deep FreeRTOS queue.
- Acks are included in the POST and cleared only after HTTP 200.
- `loop()` drains the queue and applies commands through the **same functions** the HTTP handlers use (`startConveyor/stopConveyor/setBeltSpeed/clearFault`), then acks each.
- TLS certificate validation is **disabled** (`client.setInsecure()`, `:334`) — flagged prototype shortcut.
- OLED shows `Cloud: OK` / `Cloud: --`.

### 3.6 Large-box counting rule

`packing_conveyor.ino:533`–`:535`:

```cpp
++totalBoxesPushed;
boxCount       = totalBoxesPushed % BOXES_PER_LARGE_BOX;  // 0-9
bigBoxesFilled = totalBoxesPushed / BOXES_PER_LARGE_BOX;  // completed large boxes
```

---

## 4. Supabase backend (as-built)

### 4.1 Schema — `supabase/migrations/0001_init.sql`

- `devices(id uuid pk, owner_id → auth.users, name, token_hash, last_seen_at, created_at)`
- `device_status(device_id pk → devices, boxes, total, big, speed_pps, rpm, set_percent 20–100, state ∈ 6 values, fault, updated_at)`
- `commands(id bigint identity pk, device_id, type ∈ start|stop|speed|clear_fault, value 20–100 null, status ∈ pending|delivered|done|failed, created_at, delivered_at, done_at)` + index `(device_id, status, id)`
- `events(id bigint identity pk, device_id, type ∈ box_pushed|large_box_filled|fault|fault_cleared|online, payload jsonb, created_at)` + index `(device_id, created_at desc)`

### 4.2 Row Level Security

RLS on all four tables. Clients: **select** their own device rows; **insert** only `status='pending'` commands. No update/delete policies. Only the Edge Function (service role) writes status/events/command state.

### 4.3 Realtime

`supabase_realtime` publication includes `device_status`, `commands`, `events`.

### 4.4 Edge Function `device-sync` — `supabase/functions/device-sync/index.ts`

Deploy **`--no-verify-jwt`** (device authenticates with its own token). Constants: `STALE_COMMAND_SECONDS = 30`, `OFFLINE_GAP_SECONDS = 30`, `MAX_COMMANDS = 10`.

Request:

```http
POST /functions/v1/device-sync
Content-Type: application/json
x-device-token: <device token>

{ "device_id":"uuid",
  "status": { "boxes":4,"total":34,"big":3,"speed":24.0,"rpm":144.0,"set":65,"state":"RUNNING","fault":"" },
  "acks":[12,13], "fw":"2.0.0" }
```

Behaviour:

1. Look up device; compare `sha256(x-device-token)` to `token_hash`; 401 on mismatch.
2. Validate body (num/range checks; state in the 6 values; `set` 20–100); 400 with `{"error":...}`.
3. Read previous `device_status`.
4. Upsert `device_status` (`set`→`set_percent`, `speed`→`speed_pps`) and set `devices.last_seen_at = now()`.
5. Derive events vs previous: `total`↑→`box_pushed`; `big`↑→`large_box_filled`; →FAULT→`fault`; FAULT→other→`fault_cleared`; last seen >30 s ago→`online`. If counters went down (reboot) skip counter-derived events.
6. Mark `acks` done.
7. Mark `pending` older than 30 s `failed` (a stale `start` never runs late).
8. Select up to 10 pending commands, mark `delivered`, return them.

Response:

```json
{ "commands":[{"id":14,"type":"speed","value":80},{"id":15,"type":"start","value":null}],
  "server_time":"2026-10-11T10:00:00Z" }
```

### 4.5 Seed — `supabase/seed/create_device.sql`

Generates a random 32-byte token, stores its sha256 in `devices.token_hash`, inserts the `device_status` row, and prints the plain token + device id **once** via `RAISE NOTICE`. Set `v_owner` to the `auth.users` id.

---

## 5. Flutter app (as-built)

Source: `app/lib/`. Stack: Flutter, `flutter_riverpod`, `supabase_flutter`, `http`, `shared_preferences`, `google_fonts` (`app/pubspec.yaml`).

### 5.1 Configuration (`Env`, `providers.dart`)

- `SUPABASE_URL`, `SUPABASE_ANON_KEY` supplied via `--dart-define`.
- `Env.hasCloud` true only when both are non-empty. If false, the app is local-only and never initializes Supabase (`main.dart:16`).

`AppConfig` (`settings.dart`), persisted in `shared_preferences`:

| Field | Default | Notes |
|---|---|---|
| `mode` | cloud (local if no cloud build) | `ConnectionMode.cloud|local` |
| `espIp` | `''` | normalized to `http://<ip>` |
| `autoRefresh` | true | when false, manual fetch only |
| `refreshSeconds` | 1 | 1 / 2 / 5 |
| `themeMode` | dark | dark / light |

### 5.2 Repository interface (`repository.dart`)

```dart
abstract class ConveyorRepository {
  Stream<ConveyorStatus> watchStatus();
  Future<ConveyorStatus> fetchStatus();
  Future<void> start();
  Future<void> stop();
  Future<void> setSpeed(int percent);
  Future<void> clearFault();
  Future<void> refresh();
  Future<void> dispose();
}
```

- **`LocalHttpRepository`** (`local_http_repository.dart`): normalizes `192.168.1.50`, `http://...`, trailing slash → `http://192.168.1.50`; polls `GET /status` at the configured interval; 4 s timeout; fast 400 ms poll while PUSHING/RETURNING; maps errors to `ConveyorException` with the exact PRD v1 §7 wording (unreachable/timeout/invalidResponse/http).
- **`SupabaseRepository`** (`supabase_repository.dart`): resolves the first `devices.id` for the user; `watchStatus()` streams `device_status` via `.stream(primaryKey:['device_id'])`; commands insert a `pending` row then poll it up to 5 s for `done` (throws "Command failed. Try again." on `failed`/timeout).

### 5.3 Providers (`providers.dart`, `history.dart`)

`settingsStoreProvider`, `configProvider` (StateNotifier), `supabaseClientProvider`, `authStateProvider`, `repositoryProvider` (rebuilt on mode/ip/interval change), `statusProvider` (live, disabled if `autoRefresh` off), `manualStatusProvider` (one-shot), `historyProvider` (client-side samples + events).

### 5.4 Screens & navigation

| File | Purpose |
|---|---|
| `main.dart` | `_Root` → `ConnectScreen` if not ready, else `HomeShell` |
| `screens/connect_screen.dart` | Rack-style header, ESP32 IP entry + Connect, recent address, diagnostics tiles, local-mode instruction notice, optional Supabase sign-in panel |
| `screens/connecting_screen.dart` | Handshake overlay (animated dots, progress, CANCEL) shown while probing/connecting |
| `screens/home_shell.dart` | Bottom nav: **Telemet / States / Config** (IndexedStack) |
| `screens/dashboard_screen.dart` | Telemet dashboard (see 5.5/5.6) |
| `screens/states_screen.dart` | Status report, roller speed graph, packing logic bar, event log, state-machine matrix, fault annunciator |
| `screens/settings_screen.dart` | Network config, polling & refresh, theme, packaging batch (read-only), bench diagnostics, cloud account |
| `address_entry.dart` | Modal to type + probe an IP and switch to local mode |

### 5.5 Dashboard data binding

| UI element | Source |
|---|---|
| Header strip label | `CLOUD` / `CONNECTED` / `OFFLINE` |
| State row | `device_status.state` |
| ROLLER SPEED | `rpm` (1 decimal + "RPM") |
| BELT SETTING | `set`/`set_percent` (%) |
| BOXES MOVED | `total` |
| LARGE BOXES FILLED | `big` |
| CURRENT LARGE BOX | `boxes` as "n / 10" + `LargeBoxBar` |
| Fault banner | shown when `state == FAULT` |

Cloud online = `now − updated_at < 10 s` (`dashboard_screen.dart:90`).

### 5.6 Controls & command flow

- Start / Stop / Speed / Clear fault call the repository.
- Speed applied on slider release (`onChangeEnd`), clamped 20–100.
- While a command is in flight, a "Working" banner shows; on success a "Confirmed" banner; on failure a "Not sent" banner (3 s auto-dismiss for success).
- Start and Stop are disabled only while a command is pending. Clear fault enabled only when `state == FAULT`.

### 5.7 Client-side history (`history.dart`, `speed_graph.dart`)

`HistoryNotifier` subscribes to the status stream and keeps:
- up to **60** `SpeedSample`s (rpm/pps/set/state) → rendered as a custom-painted sparkline;
- up to **50** derived `ConveyorEvent`s (link established, state change, box sorted, large box filled, fault).

This is independent of the Supabase `events` table and is not persisted.

### 5.8 Design system

`theme.dart` + `widgets.dart` implement the Stitch "Bench Instrument System" (`design/DESIGN.md`, `design/design-tokens.json`):

- Palette extension `Palette` with dark + light variants (surface `#1E1A23`, hairline `#3A3342`, text `#EDE8E3`, accent `#E88A3C`, running `#8FAE8A`, paused `#8A8494`, motion `#7C93A6`, fault `#C25B56`).
- Fonts: JetBrains Mono (tabular figures) for numerics, Barlow Condensed for labels/body/buttons.
- Reusable widgets: `Panel`, `Hairline`, `SubHeaderStrip`, `TagChip`, `InputWell`, `SegmentedSelector`, `PanelHeader`, `ReadoutRow`, `ReadoutTable`, `StateRow`, `LargeBoxBar`, `ActionButton` (primary/secondary/emergency), `IndustrialSwitch`, `MetricTile`.

---

## 6. Data contracts summary

- **Device → cloud:** `{device_id, status{boxes,total,big,speed,rpm,set,state,fault}, acks[], fw}` + `x-device-token` → `{commands[], server_time}`.
- **App ↔ local device:** `GET /status` (and the command endpoints) returning the status JSON in §3.4.
- **App ↔ cloud:** reads `device_status` (Realtime + one-shot select); inserts `commands(type,value,status='pending',device_id)`.

---

## 7. Configuration the user must provide

| Value | Where |
|---|---|
| Supabase project URL | app `--dart-define=SUPABASE_URL`, firmware `secrets.h` |
| Supabase anon key | app `--dart-define=SUPABASE_ANON_KEY` only |
| Device id + plain device token | firmware `secrets.h` (from seed output) |
| Wi-Fi SSID + password | firmware `secrets.h` |
| Supabase service_role key | Edge Function env only (never in repo) |

Never commit: `.env`, `secrets.h`, service_role key, device token (`.gitignore`).

---

## 8. Security (as-built)

- RLS on every table; clients cannot write status/events/command state.
- Device token stored only as sha256; rotate by re-seeding and updating `secrets.h`.
- Local HTTP API is unauthenticated → trusted LAN only (PRD v1 §11).
- **Gap:** firmware TLS validation is disabled (`setInsecure()`).

---

## 9. As-built deviations & known gaps (spec targets)

These are factual differences between the code and PRD v1/v2 intent. This is the working list for the next spec.

### Firmware

1. **`FAULT` is unreachable.** `stopForFault()` (`:164`) is the only place `faultActive = true`, and it is never called. Therefore `state` never becomes `FAULT`, and the app's Clear-fault control has no effect on the device. (Speed-sensor shutdown is intentionally disabled per v1 §5.5, but the fault path itself is dead.)
2. **`POSITIONING` is unreachable.** `LAST_BOX_TRAVEL` is never assigned; `LAST_BOX_TRAVEL_MS` is unused.
3. **Dead code / servo angle inconsistency.** `startAutomaticCycle()` (the only user of `SERVO_HOME_ANGLE = 30`) is never called; the loop hardcodes `pusher.write(90)`/`pusher.write(0)`. `SERVO_PUSH_ANGLE` is unused. Effective home angle is 0°, not 30°.
4. **TLS `setInsecure()`** — certificate validation disabled (prototype shortcut called out in code).
5. `fault` text is interpolated into JSON without escaping (safe only while it contains no `"`).
6. Counters reset on reboot (known/accepted).

### App

7. **Local fast-poll never reverts** to the configured interval after PUSHING/RETURNING (`local_http_repository.dart:67` `_scheduleNext` early-returns when the slow interval is wanted, leaving the 400 ms timer running).
8. **Button rules not implemented** (PRD v2 §7.6): Start is *not* disabled during PUSHING/RETURNING and Stop is *not* disabled when PAUSED; both are disabled only while a command is pending.
9. **Cloud "conveyor offline" state incomplete** (PRD v2 §7.4): the header strip shows OFFLINE, but readouts are not dimmed, controls are not disabled, and there is no "Last seen <time ago>" banner.
10. **No Realtime→polling fallback** (PRD v2 §7.5) if the Realtime socket drops.
11. **Command feedback is a banner, not on the button** (screen 8 is only partially realized).
12. **Local mode has no offline handling** — `_online()` returns `true` unconditionally (`dashboard_screen.dart:91`).
13. `SupabaseRepository.offlineAfter` and `_channel` are declared but unused.
14. `ConveyorState.isPushMotion` is unused.
15. **History/States screen is extra scope.** PRD v2 §13 lists history as out of scope; the app builds a client-side sample/event history instead of reading the `events` table.
16. **Design drift:** base canvas `#16121B` in code vs `#141019` in DESIGN.md; `label-micro` is 10 px vs 11 px in tokens. Connect screen shows `PORT // 8080` while the device listens on 80 (cosmetic).

### Backend

17. No device pairing UI; the device is created via the seed script.
18. Single device per user assumed (`_resolveDeviceId` takes the first row).
19. No retention policy on `events`/`commands`.

---

## 10. Test checklist (as-built)

1. Sign in (cloud) or enter the OLED IP (local); dashboard shows state, RPM, set speed, total, big, and the n/10 bar.
2. Push a box: `total` +1; `boxes` cycles 0→9→0; `big` +1 every 10 boxes. *(Currently only for a device flashed with the fixed firmware — see earlier report.)*
3. Press Stop → belt pauses within ~3 s; Start resumes.
4. Move speed slider to 80% → device reports `set = 80`; slider stays within 20–100.
5. Unplug ESP32: cloud shows OFFLINE (currently header-only; see gap 9).
6. Cut phone network: app recovers when network returns.
7. Cut ESP32 internet but keep power: cycle and local HTTP API keep working.
8. Insert a `start`, leave device offline 40 s → command `failed`, belt does not start.
9. Second user sees no data from the first user's device.
10. Repo/build contains no service_role key, device token, or Wi-Fi password.

---

## 11. Out of scope (as-built)

Device pairing; multiple devices per user; roles; push notifications; OTA updates; counter persistence across reboot; server-side history UI; scheduled events.

---

## 12. Repo file map

```text
conveyor_packing2.0/
  app/                         Flutter app (Android first)
    lib/
      main.dart  theme.dart  widgets.dart  models.dart  settings.dart
      repository.dart  local_http_repository.dart  supabase_repository.dart
      providers.dart  history.dart  speed_graph.dart  address_entry.dart
      screens/{connect,connecting,home_shell,dashboard,states,settings}_screen.dart
    test/widget_test.dart
  firmware/
    packing_conveyor/packing_conveyor.ino
    secrets.h.example
  supabase/
    migrations/0001_init.sql
    functions/device-sync/index.ts
    seed/create_device.sql
  design/                      DESIGN.md, design-tokens.json, screens/*
  docs/PRD.md  docs/PRD_v2.md  docs/PRD_v3.md
  .env.example  .gitignore
```
