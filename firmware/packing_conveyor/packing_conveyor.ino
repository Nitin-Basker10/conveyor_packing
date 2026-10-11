// Packing Conveyor — ESP32 firmware
//
// Cloud + local control. The local HTTP API (/status, /speed, /start, /stop,
// /clear-fault) is unchanged and keeps working with no internet. A separate
// FreeRTOS task on core 0 syncs with Supabase (~1/s) and pulls commands.
// See docs/PRD_v2.md section 6.

#include <Arduino.h>
#include <Wire.h>
#include <WiFi.h>
#include <WiFiClientSecure.h>
#include <HTTPClient.h>
#include <WebServer.h>
#include <Adafruit_GFX.h>
#include <Adafruit_SSD1306.h>
#include <ESP32Servo.h>
#include <ArduinoJson.h>  // built against ArduinoJson v6
#include <freertos/FreeRTOS.h>
#include <freertos/task.h>
#include <freertos/queue.h>
#include <freertos/semphr.h>

#include "secrets.h"  // Wi-Fi + Supabase + device identity (git-ignored)

constexpr int IR_PIN = 4;
constexpr int SPEED_PIN = 14;
constexpr int BUZZER_PIN = 18;
constexpr int MOTOR_PWM_PIN = 25;
constexpr int MOTOR_IN1_PIN = 26;
constexpr int MOTOR_IN2_PIN = 27;
constexpr int SERVO_PIN = 13;
constexpr int BUTTON_PIN = 32;
constexpr int OLED_SDA_PIN = 21;
constexpr int OLED_SCL_PIN = 22;

constexpr uint8_t OLED_ADDRESS = 0x3C;
constexpr int SCREEN_WIDTH = 128;
constexpr int SCREEN_HEIGHT = 64;
constexpr uint8_t BATCH_SIZE = 1;  // One detected box is transferred per cycle.
constexpr uint8_t BOXES_PER_LARGE_BOX = 10;  // Every 10 boxes fills one large collection box.
constexpr uint8_t SPEED_SENSOR_SLOTS_PER_REVOLUTION = 10; // Set this to the number of slots in the roller disc.
constexpr uint32_t SENSOR_DEBOUNCE_US = 80000;
constexpr uint32_t SPEED_DEBOUNCE_US = 1200;
constexpr uint32_t SPEED_SAMPLE_MS = 500;
constexpr uint32_t STALL_TIMEOUT_MS = 1200;
constexpr uint32_t MOTOR_START_GRACE_MS = 2200;
constexpr float PULSES_PER_SECOND_AT_FULL_SPEED = 80.0f;
constexpr float MINIMUM_SPEED_FRACTION = 0.45f;
constexpr uint32_t LAST_BOX_TRAVEL_MS = 1500;
constexpr uint32_t PUSH_OUT_MS = 900;
constexpr uint32_t PUSH_RETURN_MS = 900;
// Keep the pusher within a 90-degree travel so it does not drive into a mechanical stop.
constexpr int SERVO_HOME_ANGLE = 30;
// Match the known-good 90-degree position from the standalone servo test.
constexpr int SERVO_PUSH_ANGLE = 90;

// Cloud sync timing (PRD_v2 6.2).
constexpr uint32_t CLOUD_SYNC_PERIOD_MS = 1000;
constexpr uint32_t CLOUD_HTTP_TIMEOUT_MS = 4000;
constexpr uint8_t CLOUD_MAX_ACKS = 16;

Adafruit_SSD1306 display(SCREEN_WIDTH, SCREEN_HEIGHT, &Wire, -1);
Servo pusher;
WebServer server(80);

volatile bool boxEdgePending = false;
// One box may hold the FC-51 output LOW for longer than the pusher cycle.
// Do not accept another trigger until that box has cleared the sensor.
volatile bool boxSensorArmed = true;
volatile uint32_t lastSensorEdgeUs = 0;
volatile uint32_t lastSpeedEdgeUs = 0;
volatile uint32_t speedPulses = 0;
volatile uint32_t lastSpeedPulseMs = 0;
uint8_t boxCount = 0;              // Boxes in the current large box (0-9).
uint32_t totalBoxesPushed = 0;     // Boxes pushed since ESP32 restart.
uint32_t bigBoxesFilled = 0;       // Completed large boxes since restart.
uint8_t beltSpeedPercent = 65;
float actualSpeed = 0; // Sensor pulses per second.
float beltRpm = 0;      // Roller speed derived from the slotted-disc pulse count.
bool faultActive = false;
String faultText;
uint32_t motorStartedMs = 0;
uint32_t lastSpeedSampleMs = 0;
uint32_t previousSpeedPulses = 0;
bool systemEnabled = true;
bool displayReady = false;
bool previousButton = HIGH;
uint32_t lastButtonChangeMs = 0;
uint32_t shownTotalBoxes = UINT32_MAX;
uint8_t shownSpeedPercent = 255;
int shownRpmTenth = -1;
bool shownCloudOnline = false;
String shownState;
String shownIp;
bool wifiAddressShown = false;

bool cloudOnline = false;

enum CycleState { RUNNING, LAST_BOX_TRAVEL, PUSHING_OUT, PUSHING_HOME };
CycleState cycleState = RUNNING;
uint32_t stateStartedMs = 0;

// --- Cloud sync shared state (PRD_v2 6.2 / 6.3) ---
struct StatusSnapshot {
  int boxes;
  int total;
  int big;
  float speed;
  float rpm;
  int set;
  char state[16];
  char fault[96];
};

struct CommandItem {
  uint32_t id;
  char type[12];
  int value;
};

StatusSnapshot gStatus;
uint32_t ackIds[CLOUD_MAX_ACKS];
uint8_t ackCount = 0;
SemaphoreHandle_t statusMutex = nullptr;
QueueHandle_t commandQueue = nullptr;

const char *stateText();
void updateDisplay(bool force = false);
void refreshStatusSnapshot();

// --- Forward declarations for refactored command functions (PRD_v2 6.3) ---
void startConveyor();
void stopConveyor();
void setBeltSpeed(int percent);
void clearFault();

void IRAM_ATTR onBoxDetected() {
  const uint32_t now = micros();
  if (boxSensorArmed && now - lastSensorEdgeUs >= SENSOR_DEBOUNCE_US) {
    lastSensorEdgeUs = now;
    boxSensorArmed = false;
    boxEdgePending = true;
  }
}
void IRAM_ATTR onSpeedPulse() {
  const uint32_t now = micros();
  if (now - lastSpeedEdgeUs >= SPEED_DEBOUNCE_US) { lastSpeedEdgeUs = now; ++speedPulses; lastSpeedPulseMs = now / 1000; }
}

void setBeltRunning(bool running) {
  const bool allowed = running && systemEnabled && !faultActive;
  digitalWrite(MOTOR_IN1_PIN, HIGH);
  digitalWrite(MOTOR_IN2_PIN, LOW);
  ledcWrite(MOTOR_PWM_PIN, allowed ? map(beltSpeedPercent, 0, 100, 0, 255) : 0);
  if (allowed) motorStartedMs = millis();
}

String statusJson() {
  return "{\"boxes\":" + String(boxCount) + ",\"total\":" + String(totalBoxesPushed) + ",\"big\":" + String(bigBoxesFilled) + ",\"speed\":" + String(actualSpeed, 1) + ",\"rpm\":" + String(beltRpm, 1) + ",\"set\":" + String(beltSpeedPercent) + ",\"state\":\"" + stateText() + "\",\"fault\":\"" + faultText + "\"}";
}
void publishStatus() { }

// --- Refactored command functions, shared by the HTTP API and the cloud queue ---
void stopForFault(const char *reason) { if (faultActive) return; faultActive = true; faultText = reason; setBeltRunning(false); ledcWriteTone(BUZZER_PIN, 2300); updateDisplay(true); }

void startConveyor() {
  if (faultActive) return;
  systemEnabled = true;
  setBeltRunning(cycleState == RUNNING || cycleState == LAST_BOX_TRAVEL);
  updateDisplay(true);
}

void stopConveyor() {
  systemEnabled = false;
  setBeltRunning(false);
  updateDisplay(true);
}

void setBeltSpeed(int percent) {
  beltSpeedPercent = constrain(percent, 20, 100);
  setBeltRunning(cycleState == RUNNING || cycleState == LAST_BOX_TRAVEL);
  updateDisplay(true);
}

void clearFault() {
  faultActive = false;
  faultText = "";
  ledcWriteTone(BUZZER_PIN, 0);
  if (systemEnabled) setBeltRunning(cycleState == RUNNING || cycleState == LAST_BOX_TRAVEL);
  updateDisplay(true);
}

void sendJsonStatus() { server.send(200, "application/json", statusJson()); }
void setSpeedFromApi() {
  if (!server.hasArg("percent")) { server.send(400, "application/json", "{\"error\":\"use percent=20..100\"}"); return; }
  setBeltSpeed(server.arg("percent").toInt());
  sendJsonStatus();
}
void startFromApi() { startConveyor(); sendJsonStatus(); }
void stopFromApi() { stopConveyor(); sendJsonStatus(); }
void clearFaultFromApi() { clearFault(); sendJsonStatus(); }

const char *stateText() {
  if (faultActive) return "FAULT";
  if (!systemEnabled) return "PAUSED";
  switch (cycleState) {
    case RUNNING: return "RUNNING";
    case LAST_BOX_TRAVEL: return "POSITIONING";
    case PUSHING_OUT: return "PUSHING";
    case PUSHING_HOME: return "RETURNING";
  }
  return "";
}

void updateDisplay(bool force) {
  if (!displayReady) return;

  const String state = stateText();
  const String ip = WiFi.status() == WL_CONNECTED ? WiFi.localIP().toString() : "Connecting...";
  const int rpmTenth = static_cast<int>(beltRpm * 10.0f + 0.5f);
  if (!force && shownTotalBoxes == totalBoxesPushed && shownSpeedPercent == beltSpeedPercent &&
      shownRpmTenth == rpmTenth && shownState == state && shownIp == ip &&
      shownCloudOnline == cloudOnline) return;

  shownTotalBoxes = totalBoxesPushed;
  shownSpeedPercent = beltSpeedPercent;
  shownRpmTenth = rpmTenth;
  shownState = state;
  shownIp = ip;
  shownCloudOnline = cloudOnline;

  display.clearDisplay();
  display.setTextColor(SSD1306_WHITE);
  display.setTextSize(1);
  display.setCursor(0, 0);
  display.print("PACKING CONVEYOR");
  display.drawFastHLine(0, 9, SCREEN_WIDTH, SSD1306_WHITE);

  display.setCursor(0, 14);
  display.print("Status: ");
  display.print(state);

  display.setCursor(0, 25);
  display.print("Belt: ");
  display.print(beltSpeedPercent);
  display.print("%");
  display.setCursor(70, 25);
  display.print("RPM: ");
  display.print(beltRpm, 1);

  display.setCursor(0, 36);
  display.print("Boxes moved: ");
  display.print(totalBoxesPushed);

  display.setCursor(0, 47);
  if (WiFi.status() == WL_CONNECTED) {
    display.print("IP: ");
    display.print(ip);
  } else {
    display.print("WiFi: connecting...");
  }

  display.setCursor(0, 56);
  display.print("Cloud: ");
  display.print(cloudOnline ? "OK" : "--");
  display.display();
}

void startAutomaticCycle() {
  boxCount = totalBoxesPushed % BOXES_PER_LARGE_BOX;
  bigBoxesFilled = totalBoxesPushed / BOXES_PER_LARGE_BOX;
  cycleState = RUNNING;
  pusher.write(SERVO_HOME_ANGLE);
  if (systemEnabled) setBeltRunning(true);
  updateDisplay(true);
}

// --- Snapshot / ack helpers (PRD_v2 6.2) ---
void refreshStatusSnapshot() {
  const char *st = stateText();
  if (xSemaphoreTake(statusMutex, portMAX_DELAY) != pdTRUE) return;
  gStatus.boxes = boxCount;
  gStatus.total = totalBoxesPushed;
  gStatus.big = bigBoxesFilled;
  gStatus.speed = actualSpeed;
  gStatus.rpm = beltRpm;
  gStatus.set = beltSpeedPercent;
  strncpy(gStatus.state, st, sizeof(gStatus.state) - 1);
  gStatus.state[sizeof(gStatus.state) - 1] = '\0';
  strncpy(gStatus.fault, faultText.c_str(), sizeof(gStatus.fault) - 1);
  gStatus.fault[sizeof(gStatus.fault) - 1] = '\0';
  xSemaphoreGive(statusMutex);
}

void addAck(uint32_t id) {
  if (xSemaphoreTake(statusMutex, portMAX_DELAY) != pdTRUE) return;
  if (ackCount < CLOUD_MAX_ACKS) ackIds[ackCount++] = id;
  xSemaphoreGive(statusMutex);
}

// --- Cloud sync (PRD_v2 6.2) ---
bool cloudSyncOnce() {
  StatusSnapshot snap;
  uint32_t sentAcks[CLOUD_MAX_ACKS];
  uint8_t sentCount;

  xSemaphoreTake(statusMutex, portMAX_DELAY);
  snap = gStatus;
  sentCount = ackCount;
  for (uint8_t i = 0; i < sentCount; i++) sentAcks[i] = ackIds[i];
  xSemaphoreGive(statusMutex);

  StaticJsonDocument<1024> doc;
  doc["device_id"] = DEVICE_ID;
  JsonObject st = doc.createNestedObject("status");
  st["boxes"] = snap.boxes;
  st["total"] = snap.total;
  st["big"] = snap.big;
  st["speed"] = snap.speed;
  st["rpm"] = snap.rpm;
  st["set"] = snap.set;
  st["state"] = snap.state;
  st["fault"] = snap.fault;
  JsonArray acks = doc.createNestedArray("acks");
  for (uint8_t i = 0; i < sentCount; i++) acks.add(sentAcks[i]);
  doc["fw"] = FW_VERSION;

  String body;
  serializeJson(doc, body);

  WiFiClientSecure client;
  // Prototype shortcut: certificate validation is disabled. Replace with the
  // Supabase/Google root CA (client.setCACert(SUPABASE_ROOT_CA)) before field use.
  client.setInsecure();
  client.setTimeout(CLOUD_HTTP_TIMEOUT_MS / 1000);

  HTTPClient https;
  https.setConnectTimeout(CLOUD_HTTP_TIMEOUT_MS);
  https.setTimeout(CLOUD_HTTP_TIMEOUT_MS);
  if (!https.begin(client, SUPABASE_FUNCTION_URL)) return false;
  https.addHeader("Content-Type", "application/json");
  https.addHeader("x-device-token", DEVICE_TOKEN);

  const int code = https.POST(body);
  bool ok = false;

  if (code == 200) {
    String resp = https.getString();
    StaticJsonDocument<1024> rdoc;
    if (deserializeJson(rdoc, resp) == DeserializationError::Ok) {
      for (JsonObject c : rdoc["commands"].as<JsonArray>()) {
        CommandItem item;
        memset(&item, 0, sizeof(item));
        item.id = c["id"] | 0u;
        strncpy(item.type, c["type"] | "", sizeof(item.type) - 1);
        item.value = c["value"] | 0;
        if (item.type[0] != '\0') xQueueSend(commandQueue, &item, 0);
      }
    }
    // Clear only the acks we actually sent, so new ones are not lost.
    xSemaphoreTake(statusMutex, portMAX_DELAY);
    if (sentCount <= ackCount) {
      for (uint8_t i = sentCount; i < ackCount; i++) ackIds[i - sentCount] = ackIds[i];
      ackCount -= sentCount;
    } else {
      ackCount = 0;
    }
    xSemaphoreGive(statusMutex);
    ok = true;
    Serial.printf("[cloud] sync ok, %u cmd(s) returned\n", static_cast<unsigned>(rdoc["commands"].size()));
  } else {
    Serial.printf("[cloud] sync failed, HTTP %d\n", code);
  }

  https.end();
  return ok;
}

void cloudSyncTask(void *param) {
  (void)param;
  const uint32_t backoffMs[] = {1000, 2000, 5000, 10000, 10000, 10000};
  uint8_t backoffIndex = 0;
  for (;;) {
    if (WiFi.status() == WL_CONNECTED) {
      const bool ok = cloudSyncOnce();
      cloudOnline = ok;
      if (ok) {
        backoffIndex = 0;
        vTaskDelay(pdMS_TO_TICKS(CLOUD_SYNC_PERIOD_MS));
      } else {
        vTaskDelay(pdMS_TO_TICKS(backoffMs[backoffIndex]));
        if (backoffIndex < (sizeof(backoffMs) / sizeof(backoffMs[0])) - 1) backoffIndex++;
      }
    } else {
      cloudOnline = false;
      vTaskDelay(pdMS_TO_TICKS(CLOUD_SYNC_PERIOD_MS));
    }
  }
}

void applyCommand(const CommandItem &cmd) {
  if (strcmp(cmd.type, "start") == 0) {
    startConveyor();
  } else if (strcmp(cmd.type, "stop") == 0) {
    stopConveyor();
  } else if (strcmp(cmd.type, "speed") == 0) {
    setBeltSpeed(constrain(cmd.value, 20, 100));
  } else if (strcmp(cmd.type, "clear_fault") == 0) {
    clearFault();
  } else {
    return;  // Unknown type: do not ack.
  }
  addAck(cmd.id);
  Serial.printf("[cloud] applied cmd %u (%s)\n", static_cast<unsigned>(cmd.id), cmd.type);
}

void setup() {
  Serial.begin(115200);

  pinMode(IR_PIN, INPUT);
  pinMode(SPEED_PIN, INPUT);
  pinMode(MOTOR_IN1_PIN, OUTPUT);
  pinMode(MOTOR_IN2_PIN, OUTPUT);
  pinMode(BUTTON_PIN, INPUT_PULLUP);

  // Reserve the servo's 50 Hz timing first. The direct IR/servo test proved this exact signal works.
  // The motor-speed and buzzer PWM outputs are attached afterwards so they use separate timing resources.
  pusher.setPeriodHertz(50);
  pusher.attach(SERVO_PIN, 500, 2400);
  pusher.write(0);

  // ENA sets belt speed; the buzzer remains silent in this measurement-only version.
  ledcAttach(MOTOR_PWM_PIN, 20000, 8);
  ledcAttach(BUZZER_PIN, 2000, 8);
  ledcWriteTone(BUZZER_PIN, 0);
  digitalWrite(MOTOR_IN1_PIN, LOW);
  digitalWrite(MOTOR_IN2_PIN, LOW);

  Wire.begin(OLED_SDA_PIN, OLED_SCL_PIN);
  displayReady = display.begin(SSD1306_SWITCHCAPVCC, OLED_ADDRESS);
  if (displayReady) updateDisplay(true);

  // FC-51 normally pulls OUT LOW when a box is detected.
  attachInterrupt(digitalPinToInterrupt(IR_PIN), onBoxDetected, FALLING);
  // The speed sensor is measurement-only for now: no pulse count can stop the belt.
  attachInterrupt(digitalPinToInterrupt(SPEED_PIN), onSpeedPulse, FALLING);

  // Cloud sync primitives must exist before Wi-Fi connects.
  statusMutex = xSemaphoreCreateMutex();
  commandQueue = xQueueCreate(16, sizeof(CommandItem));
  refreshStatusSnapshot();

  WiFi.mode(WIFI_STA);
  WiFi.begin(WIFI_SSID, WIFI_PASSWORD);

  server.on("/status", HTTP_GET, sendJsonStatus);
  server.on("/speed", HTTP_GET, setSpeedFromApi);
  server.on("/start", HTTP_GET, startFromApi);
  server.on("/stop", HTTP_GET, stopFromApi);
  server.on("/clear-fault", HTTP_GET, clearFaultFromApi);
  server.onNotFound([]() { server.send(404, "application/json", "{\"error\":\"not found\"}"); });
  server.enableCORS(true);
  server.begin();

  setBeltRunning(true);
  updateDisplay(true);

  // Cloud sync runs on core 0 so a slow HTTPS call can never stall loop().
  xTaskCreatePinnedToCore(cloudSyncTask, "cloudSync", 16384, nullptr, 1, nullptr, 0);
}

void loop() {
  const uint32_t now = millis();
  server.handleClient();

  // Apply any commands delivered from the cloud queue.
  CommandItem cmd;
  while (xQueueReceive(commandQueue, &cmd, 0) == pdTRUE) {
    applyCommand(cmd);
  }

  // The physical button pauses or resumes the belt; a quick press counts once.
  const bool buttonNow = digitalRead(BUTTON_PIN);
  if (buttonNow != previousButton && now - lastButtonChangeMs >= 35) {
    lastButtonChangeMs = now;
    previousButton = buttonNow;
    if (buttonNow == LOW) {
      systemEnabled = !systemEnabled;
      setBeltRunning(systemEnabled && cycleState == RUNNING);
      updateDisplay(true);
    }
  }

  // Calculate and report roller RPM only. A missing or stationary speed sensor never raises a fault.
  if (now - lastSpeedSampleMs >= SPEED_SAMPLE_MS) {
    noInterrupts();
    const uint32_t pulsesNow = speedPulses;
    interrupts();
    const uint32_t newPulses = pulsesNow - previousSpeedPulses;
    actualSpeed = (newPulses * 1000.0f) / (now - lastSpeedSampleMs);
    beltRpm = (actualSpeed * 60.0f) / SPEED_SENSOR_SLOTS_PER_REVOLUTION;
    previousSpeedPulses = pulsesNow;
    lastSpeedSampleMs = now;
  }

  // Rearm only after the sensor is clear (FC-51 OUT returns HIGH).
  // This makes one passing box produce exactly one pusher cycle.
  if (!boxSensorArmed && digitalRead(IR_PIN) == HIGH) {
    noInterrupts();
    boxSensorArmed = true;
    interrupts();
  }

  if (boxEdgePending && cycleState == RUNNING && systemEnabled && !faultActive) {
    noInterrupts();
    boxEdgePending = false;
    interrupts();
    // Stop first, then perform the identical 0-to-90-degree servo move that was proven in the direct test.
    setBeltRunning(false);
    pusher.write(90);
    cycleState = PUSHING_OUT;
    stateStartedMs = now;
    updateDisplay(true);
  }

  if (cycleState == PUSHING_OUT && now - stateStartedMs >= PUSH_OUT_MS) {
    pusher.write(0);
    cycleState = PUSHING_HOME;
    stateStartedMs = now;
    updateDisplay(true);
  }

  if (cycleState == PUSHING_HOME && now - stateStartedMs >= PUSH_RETURN_MS) {
    ++totalBoxesPushed;
    boxCount = totalBoxesPushed % BOXES_PER_LARGE_BOX;   // boxes in the current large box (0-9)
    bigBoxesFilled = totalBoxesPushed / BOXES_PER_LARGE_BOX;  // completed large boxes
    cycleState = RUNNING;
    if (systemEnabled && !faultActive) setBeltRunning(true);
    updateDisplay(true);
  }

  // Refresh the displayed hotspot address once the ESP32 receives one.
  if (WiFi.status() == WL_CONNECTED && !wifiAddressShown) {
    wifiAddressShown = true;
    updateDisplay(true);
  }

  // Keep the cloud snapshot current, then redraw only when a value changed.
  refreshStatusSnapshot();
  updateDisplay(false);
}
