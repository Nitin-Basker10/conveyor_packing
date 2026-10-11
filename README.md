# conveyor_packing

ESP32 packing conveyor: an IR sensor detects each box, the belt stops, and a
servo pushes the box sideways; every 10 boxes fill one large collection box.
A Flutter app (web + Android) provides live telemetry and control.

## Layout

- `firmware/` — ESP32 sketches (local HTTP API, optional Supabase cloud sync)
- `app/` — Flutter app (local Wi-Fi mode and Supabase cloud mode)
- `supabase/` — schema, RLS, Edge Function (`device-sync`), device seed
- `design/` — design system (Bench Instrument System)
- `docs/` — product requirements (`PRD.md`, `PRD_v2.md`, `PRD_v3.md`)

## Configuration

- App: pass `--dart-define=SUPABASE_URL=... --dart-define=SUPABASE_ANON_KEY=...`
- Firmware: copy `firmware/secrets.h.example` to `firmware/secrets.h`.

Secrets (`.env`, `secrets.h`) are git-ignored and must never be committed.
