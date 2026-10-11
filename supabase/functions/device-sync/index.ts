// Supabase Edge Function: device-sync
// Source: PRD_v2 section 5.
// Deploy with JWT verification OFF: supabase functions deploy device-sync --no-verify-jwt
//
// The ESP32 authenticates with its own device token (x-device-token). The service
// role key is read from the function environment and never leaves the function.

import { createClient } from "https://esm.sh/@supabase/supabase-js@2";

const ALLOWED_STATES = [
  "RUNNING",
  "PAUSED",
  "PUSHING",
  "RETURNING",
  "POSITIONING",
  "FAULT",
];

const STALE_COMMAND_SECONDS = 30;
const OFFLINE_GAP_SECONDS = 30;
const MAX_COMMANDS = 10;

function json(body: unknown, status = 200): Response {
  return new Response(JSON.stringify(body), {
    status,
    headers: { "Content-Type": "application/json" },
  });
}

async function sha256Hex(input: string): Promise<string> {
  const data = new TextEncoder().encode(input);
  const digest = await crypto.subtle.digest("SHA-256", data);
  return Array.from(new Uint8Array(digest))
    .map((b) => b.toString(16).padStart(2, "0"))
    .join("");
}

function isIntInRange(v: unknown, min: number, max: number): boolean {
  return typeof v === "number" && Number.isInteger(v) && v >= min && v <= max;
}

Deno.serve(async (req) => {
  if (req.method !== "POST") {
    return json({ error: "method not allowed" }, 405);
  }

  const supabaseUrl = Deno.env.get("SUPABASE_URL");
  const serviceRoleKey = Deno.env.get("SUPABASE_SERVICE_ROLE_KEY");
  if (!supabaseUrl || !serviceRoleKey) {
    return json({ error: "server misconfigured" }, 500);
  }

  const admin = createClient(supabaseUrl, serviceRoleKey, {
    auth: { persistSession: false },
  });

  let body: any;
  try {
    body = await req.json();
  } catch (_e) {
    return json({ error: "invalid json" }, 400);
  }

  const deviceId: string | undefined = body?.device_id;
  const token = req.headers.get("x-device-token") ?? "";
  if (!deviceId || !token) {
    return json({ error: "device_id and x-device-token required" }, 400);
  }

  // 1. Look up the device and compare the token hash.
  const { data: device, error: deviceErr } = await admin
    .from("devices")
    .select("id, token_hash, last_seen_at")
    .eq("id", deviceId)
    .maybeSingle();
  if (deviceErr) return json({ error: "lookup failed" }, 500);
  if (!device) return json({ error: "unknown device" }, 401);

  const tokenHash = await sha256Hex(token);
  if (tokenHash !== device.token_hash) {
    return json({ error: "unauthorized" }, 401);
  }

  // 2. Validate the body.
  const status = body?.status;
  if (!status || typeof status !== "object") {
    return json({ error: "status is required" }, 400);
  }
  if (!isIntInRange(status.boxes, 0, 1000000)) {
    return json({ error: "invalid boxes" }, 400);
  }
  if (!isIntInRange(status.total, 0, 1000000000)) {
    return json({ error: "invalid total" }, 400);
  }
  if (!isIntInRange(status.big, 0, 100000000)) {
    return json({ error: "invalid big" }, 400);
  }
  if (typeof status.speed !== "number") {
    return json({ error: "invalid speed" }, 400);
  }
  if (typeof status.rpm !== "number") {
    return json({ error: "invalid rpm" }, 400);
  }
  if (!isIntInRange(status.set, 20, 100)) {
    return json({ error: "invalid set (20..100)" }, 400);
  }
  if (!ALLOWED_STATES.includes(status.state)) {
    return json({ error: "invalid state" }, 400);
  }
  if (typeof status.fault !== "string") {
    return json({ error: "invalid fault" }, 400);
  }

  const acks: number[] = Array.isArray(body?.acks)
    ? body.acks.filter((n: unknown) => Number.isInteger(n))
    : [];

  // 3. Read the previous status row.
  const { data: prev, error: prevErr } = await admin
    .from("device_status")
    .select("*")
    .eq("device_id", deviceId)
    .maybeSingle();
  if (prevErr) return json({ error: "status read failed" }, 500);

  const nowIso = new Date().toISOString();
  const countersReset = prev != null &&
    (status.total < prev.total || status.big < prev.big);

  // 4. Upsert device_status and touch last_seen_at.
  const { error: upsertErr } = await admin
    .from("device_status")
    .upsert({
      device_id: deviceId,
      boxes: status.boxes,
      total: status.total,
      big: status.big,
      speed_pps: status.speed,
      rpm: status.rpm,
      set_percent: status.set,
      state: status.state,
      fault: status.fault,
      updated_at: nowIso,
    }, { onConflict: "device_id" });
  if (upsertErr) return json({ error: "status write failed" }, 500);

  await admin
    .from("devices")
    .update({ last_seen_at: nowIso })
    .eq("id", deviceId);

  // 5. Derive events by comparing previous and new status.
  //    If counters went down (ESP32 restarted), skip counter-derived events.
  const events: Array<{ device_id: string; type: string; payload: unknown }> = [];
  if (prev && !countersReset) {
    if (status.total > prev.total) {
      events.push({
        device_id: deviceId,
        type: "box_pushed",
        payload: { total: status.total },
      });
    }
    if (status.big > prev.big) {
      events.push({
        device_id: deviceId,
        type: "large_box_filled",
        payload: { big: status.big },
      });
    }
  }
  if (prev) {
    if (status.state === "FAULT" && prev.state !== "FAULT") {
      events.push({
        device_id: deviceId,
        type: "fault",
        payload: { message: status.fault },
      });
    }
    if (prev.state === "FAULT" && status.state !== "FAULT") {
      events.push({ device_id: deviceId, type: "fault_cleared", payload: {} });
    }
  }
  const lastSeenMs = device.last_seen_at ? Date.parse(device.last_seen_at) : null;
  if (lastSeenMs == null || (Date.now() - lastSeenMs) / 1000 > OFFLINE_GAP_SECONDS) {
    events.push({ device_id: deviceId, type: "online", payload: {} });
  }
  if (events.length > 0) {
    const { error: evErr } = await admin.from("events").insert(events);
    if (evErr) return json({ error: "event write failed" }, 500);
  }

  // 6. Mark acked commands done.
  if (acks.length > 0) {
    await admin
      .from("commands")
      .update({ status: "done", done_at: nowIso })
      .eq("device_id", deviceId)
      .in("id", acks);
  }

  // 7. Fail stale pending commands so a late "start" never runs.
  const staleCutoff = new Date(Date.now() - STALE_COMMAND_SECONDS * 1000)
    .toISOString();
  await admin
    .from("commands")
    .update({ status: "failed" })
    .eq("device_id", deviceId)
    .eq("status", "pending")
    .lt("created_at", staleCutoff);

  // 8. Deliver up to MAX_COMMANDS remaining pending commands.
  const { data: pending, error: pendErr } = await admin
    .from("commands")
    .select("id, type, value")
    .eq("device_id", deviceId)
    .eq("status", "pending")
    .order("id", { ascending: true })
    .limit(MAX_COMMANDS);
  if (pendErr) return json({ error: "command read failed" }, 500);

  if (pending && pending.length > 0) {
    const ids = pending.map((c: any) => c.id);
    await admin
      .from("commands")
      .update({ status: "delivered", delivered_at: nowIso })
      .in("id", ids);
  }

  return json({
    commands: (pending ?? []).map((c: any) => ({
      id: c.id,
      type: c.type,
      value: c.value,
    })),
    server_time: nowIso,
  });
});
