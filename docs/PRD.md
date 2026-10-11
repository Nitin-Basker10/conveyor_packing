# Packing Conveyor Mobile App — Product Requirements Document

## 1. Purpose

Create a simple mobile app to control and monitor the ESP32-based miniature packing conveyor.

The app communicates directly with the ESP32 over the same Wi-Fi hotspot/router using HTTP requests. It does not use a built-in ESP32 webpage or WebSockets.

The ESP32's current IP address is shown on the conveyor OLED screen after it connects to Wi-Fi. The app user enters that address when connecting.

**Example base address:** `http://192.168.1.50`

> Do not add a trailing slash when saving the device address.

---

## 2. User goals

The app must let the user:

1. Connect to the conveyor using the IP address shown on the OLED.
2. View whether the conveyor is running, paused, pushing, returning, positioning, or in a fault state.
3. Start the conveyor.
4. Stop the conveyor.
5. Set belt speed from 20% to 100%.
6. View measured roller RPM.
7. View the number of boxes transferred in the current powered session.
8. Clear a fault if the controller reports one.
9. Show clear connection errors when the ESP32 cannot be reached.

---

## 3. Network requirements

- The phone and ESP32 must be connected to the same Wi-Fi hotspot/router.
- The ESP32 receives its address automatically from the hotspot/router.
- The app must use ordinary HTTP, not HTTPS.
- The ESP32 listens on port `80`.
- No login, password, or API key is currently required by the device.
- The app must not assume the IP address stays the same after a restart or hotspot reconnect.

### Device address entry

Provide a connection screen with:

- Text field: **ESP32 IP address**
- Example placeholder: `192.168.1.50`
- **Connect** button
- Saved recent address, if desired
- Optional button: **Use address shown on OLED**

The app should normalize input such as:

- `192.168.1.50`
- `http://192.168.1.50`
- `192.168.1.50/`

All should be stored internally as:

`http://192.168.1.50`

Remove any trailing slash when normalizing the address.

---

## 4. Main dashboard

### Required information

Show these live values:

| App label | Source | Meaning |
|---|---|---|
| Connection | HTTP request result | Whether the app can reach the ESP32 |
| Conveyor state | `state` | Current operating state |
| Belt speed setting | `set` | Commanded motor speed, percent |
| Roller RPM | `rpm` | Speed measured by the roller slot sensor |
| Boxes moved | `total` | Total completed pusher transfers since ESP32 power-up/reset |
| Current box count | `boxes` | Current batch count; currently expected to be `0` because the system transfers one box per cycle |
| Large boxes filled | `big` | Reserved counter; currently expected to be `0` |
| Fault message | `fault` | Fault text; normally an empty string in the current prototype |

### Conveyor state values

Display API values using readable wording:

| API value | App wording | Suggested color |
|---|---|---|
| `RUNNING` | Belt running | Green |
| `PAUSED` | Belt paused | Gray or amber |
| `PUSHING` | Moving box sideways | Blue |
| `RETURNING` | Returning pusher | Blue |
| `POSITIONING` | Positioning box | Blue |
| `FAULT` | Fault — belt stopped | Red |

### Required controls

- **Start** button
- **Stop** button
- **Speed slider or stepper:** 20% to 100%
- **Clear fault** button
- **Refresh** button
- Optional: automatic refresh enable/disable switch

### Recommended control behaviour

- Disable the Start button while state is `PUSHING` or `RETURNING`.
- Disable the Stop button if state is already `PAUSED`.
- Show the selected speed as a number, for example `65%`.
- Apply a speed change when the user releases the slider, rather than on every tiny slider movement.
- After every successful command, request `/status` again and redraw the screen with the returned values.

---

## 5. HTTP API

**Base URL format:**

```text
http://<ESP32_IP>
```

Example: `http://192.168.1.50`

All API responses are JSON with content type `application/json`.

### 5.1 Read conveyor status

**Request**

```http
GET /status
```

Example: `http://192.168.1.50/status`

**Success response: HTTP 200**

```json
{
  "boxes": 0,
  "total": 12,
  "big": 0,
  "speed": 24.0,
  "rpm": 144.0,
  "set": 65,
  "state": "RUNNING",
  "fault": ""
}
```

**Status fields**

| Field | Type | Description |
|---|---|---|
| `boxes` | integer | Current batch counter. Current firmware transfers one box each cycle, so this is normally 0. |
| `total` | integer | Total number of completed box pushes since ESP32 restart. |
| `big` | integer | Reserved large-collection-box count. Currently normally 0. |
| `speed` | number | Raw speed-sensor reading in pulses per second. |
| `rpm` | number | Roller speed calculated from slot-sensor pulses. |
| `set` | integer | Requested belt speed, from 20 to 100. |
| `state` | string | Conveyor state. See allowed values above. |
| `fault` | string | Empty string when no fault is present; otherwise a human-readable reason. |

### 5.2 Set belt speed

**Request**

```http
GET /speed?percent=<20_to_100>
```

Example: set speed to 65%:

`http://192.168.1.50/speed?percent=65`

**Success response: HTTP 200**

Returns the normal status JSON.

**Missing or invalid value response: HTTP 400**

```json
{
  "error": "use percent=20..100"
}
```

**Rules**

- The app must send whole-number percentages.
- Intended range is 20 through 100.
- The ESP32 clamps values below 20 to 20 and values above 100 to 100.
- The app should prevent invalid values before sending them.

### 5.3 Start conveyor

**Request**

```http
GET /start
```

Example: `http://192.168.1.50/start`

**Success response: HTTP 200**

Returns the normal status JSON.

**Expected result**

- The belt starts when the conveyor is not in a fault state.
- If the pusher is currently moving, the controller finishes its current action before normal running resumes.

### 5.4 Stop conveyor

**Request**

```http
GET /stop
```

Example: `http://192.168.1.50/stop`

**Success response: HTTP 200**

Returns the normal status JSON.

**Expected result**

- The belt motor stops.
- The status becomes `PAUSED` when no box-transfer movement is in progress.
- The servo is not intended to move because of this command alone.

### 5.5 Clear fault

**Request**

```http
GET /clear-fault
```

Example: `http://192.168.1.50/clear-fault`

**Success response: HTTP 200**

Returns the normal status JSON.

**Current prototype note**

Speed-sensor-based shutdown is intentionally disabled in the current conveyor firmware. The RPM sensor reports speed only and does not automatically stop the motor or sound the buzzer if it is missing or stationary. The Clear Fault control should still be included for future use.

### 5.6 Unknown endpoint

**Response: HTTP 404**

```json
{
  "error": "not found"
}
```

---

## 6. Refresh behaviour

### Recommended polling rate

Call `GET /status` every 1 second while the dashboard is open and connected. This is fast enough for a small conveyor display while keeping network traffic light.

### Faster temporary polling

While the state is `PUSHING` or `RETURNING`, the app may poll every 250–500 ms so state changes appear quickly. Return to 1-second polling after the conveyor reaches `RUNNING` or `PAUSED`.

### App lifecycle

- Pause polling when the app is in the background.
- Resume with an immediate `/status` request when the app returns to the foreground.
- Do not send repeated commands if the previous request is still waiting for a reply.

---

## 7. Error handling

### Connection failure

If the app cannot connect, show:

> Cannot reach the conveyor. Make sure the phone and ESP32 are on the same Wi-Fi network, then check the IP address on the OLED screen.

Provide buttons:

- **Retry**
- **Edit IP address**

### Request timeout

Use a request timeout of approximately 3–5 seconds.

Show:

> The conveyor did not reply. Check its power and Wi-Fi connection.

### Invalid response

If a response is not valid JSON, show:

> The conveyor sent an unexpected reply. Refresh the connection.

### HTTP error response

For HTTP 400 or 404, show the returned error text when present.

---

## 8. Suggested app screens

### Screen 1 — Connect

- Title: **Packing Conveyor**
- IP address input
- **Connect** button
- Help text: “Read the IP address from the conveyor OLED screen.”
- Connection status indicator

### Screen 2 — Dashboard

Example layout:

```text
Packing Conveyor                 Connected

State: Belt running
Roller speed: 144.0 RPM
Belt setting: 65%
Boxes moved: 12

[ Start ] [ Stop ]

Speed
20%  -----------●---------  100%
                65%

[ Clear Fault ]       [ Refresh ]
```

### Screen 3 — Settings

Optional settings:

- Saved ESP32 IP address
- Automatic refresh enabled/disabled
- Refresh interval
- App theme

---

## 9. Current conveyor sequence

This describes the current firmware behaviour so the app can explain the state correctly:

1. Conveyor belt runs at the selected speed.
2. The IR box sensor detects a box.
3. The belt motor stops.
4. The servo moves from its home position to the push position.
5. The servo returns home.
6. The completed-box total increases by one.
7. The belt starts again.
8. The IR sensor must become clear before another box can trigger a new cycle.

Timing values may be changed later, so the app must treat `PUSHING` and `RETURNING` as device-controlled states rather than attempting to run its own timing.

---

## 10. Future API ideas — not implemented yet

Do not depend on these until the ESP32 firmware is updated:

- Reset total box counter
- Change servo push/return timing
- Change servo angles
- Configure speed-sensor slots per roller revolution
- Enable stall/slowdown fault protection
- Read motor-current information
- Set batch size greater than one
- Notify when a large collection box is full
- Assign a stable device name instead of manually entering an IP address
- Add authentication before using the system outside a trusted local network

---

## 11. Implementation notes

- Use the IP address displayed on the ESP32 OLED as the source of truth for the current device address.
- The app should not assume the IP address remains constant across restarts or network reconnects.
- Keep all conveyor sequencing and timing on the ESP32; the mobile app is a control and monitoring interface.
- Use HTTP request timeouts and handle network errors without freezing the UI.
- Since the current device has no authentication, use it only on a trusted local network. Do not expose the ESP32 API directly to the public internet.
