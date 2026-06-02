#include <Arduino.h>
#include <Preferences.h>
#include <WiFi.h>
#include <WebServer.h>
#include <ESPmDNS.h>

#ifndef WIFI_SSID
#define WIFI_SSID ""
#endif
#ifndef WIFI_PASSWORD
#define WIFI_PASSWORD ""
#endif
#ifndef FRAME_IP
#define FRAME_IP "192.168.1.86"
#endif
#ifndef BRIDGE_PORT
#define BRIDGE_PORT 5555
#endif
#ifndef FRAME_ADB_PORT
#define FRAME_ADB_PORT 5555
#endif

static Preferences prefs;
static WebServer http(80);
static WiFiServer *bridgeServer = nullptr;

static String cfgSsid;
static String cfgPass;
static String cfgFrameIp;
static uint16_t cfgBridgePort = BRIDGE_PORT;
static uint16_t cfgFramePort = FRAME_ADB_PORT;

static bool wifiReady = false;
static unsigned long lastStatusMs = 0;

static void saveConfig() {
  prefs.begin("bridge", false);
  prefs.putString("ssid", cfgSsid);
  prefs.putString("pass", cfgPass);
  prefs.putString("frame_ip", cfgFrameIp);
  prefs.putUInt("bridge_port", cfgBridgePort);
  prefs.putUInt("frame_port", cfgFramePort);
  prefs.end();
}

static void loadConfig() {
  prefs.begin("bridge", true);
  cfgSsid = prefs.getString("ssid", WIFI_SSID);
  cfgPass = prefs.getString("pass", WIFI_PASSWORD);
  cfgFrameIp = prefs.getString("frame_ip", FRAME_IP);
  cfgBridgePort = (uint16_t)prefs.getUInt("bridge_port", BRIDGE_PORT);
  cfgFramePort = (uint16_t)prefs.getUInt("frame_port", FRAME_ADB_PORT);
  prefs.end();
}

static void startSetupAp() {
  const char *apSsid = "PictureFrame-Bridge";
  WiFi.mode(WIFI_AP_STA);
  WiFi.softAP(apSsid);
  Serial.printf("Setup AP: %s (open) -> http://192.168.4.1/\n", apSsid);
}

static bool connectWifi() {
  if (cfgSsid.isEmpty()) {
    startSetupAp();
    return false;
  }

  WiFi.mode(WIFI_STA);
  WiFi.begin(cfgSsid.c_str(), cfgPass.c_str());
  Serial.printf("Wi-Fi connecting to %s", cfgSsid.c_str());

  for (int i = 0; i < 40; i++) {
    if (WiFi.status() == WL_CONNECTED) {
      Serial.printf("\nWi-Fi OK: %s\n", WiFi.localIP().toString().c_str());
      wifiReady = true;
      if (MDNS.begin("frame-bridge")) {
        MDNS.addService("adb", "tcp", cfgBridgePort);
        Serial.println("mDNS: frame-bridge.local");
      }
      return true;
    }
    delay(250);
    Serial.print(".");
  }
  Serial.println("\nWi-Fi failed; starting setup AP");
  startSetupAp();
  return false;
}

static void handleRoot() {
  String body = "<html><body><h1>Picture Frame Bridge</h1><pre>";
  body += "IP: " + WiFi.localIP().toString() + "\n";
  body += "Frame: " + cfgFrameIp + ":" + String(cfgFramePort) + "\n";
  body += "Bridge port: " + String(cfgBridgePort) + "\n";
  body += "Wi-Fi: " + cfgSsid + "\n";
  body += "</pre><form method='POST' action='/config'>";
  body += "SSID <input name='ssid' value='" + cfgSsid + "'><br>";
  body += "Password <input name='pass' type='password' value='" + cfgPass + "'><br>";
  body += "Frame IP <input name='frame_ip' value='" + cfgFrameIp + "'><br>";
  body += "Bridge port <input name='bridge_port' value='" + String(cfgBridgePort) + "'><br>";
  body += "<button type='submit'>Save &amp; reboot</button></form></body></html>";
  http.send(200, "text/html", body);
}

static void handleConfig() {
  if (http.hasArg("ssid")) cfgSsid = http.arg("ssid");
  if (http.hasArg("pass")) cfgPass = http.arg("pass");
  if (http.hasArg("frame_ip")) cfgFrameIp = http.arg("frame_ip");
  if (http.hasArg("bridge_port")) cfgBridgePort = (uint16_t)http.arg("bridge_port").toInt();
  saveConfig();
  http.send(200, "text/plain", "Saved. Rebooting...");
  delay(500);
  ESP.restart();
}

static void handleStatus() {
  String json = "{";
  json += "\"ip\":\"" + WiFi.localIP().toString() + "\",";
  json += "\"frame_ip\":\"" + cfgFrameIp + "\",";
  json += "\"bridge_port\":" + String(cfgBridgePort) + ",";
  json += "\"frame_adb_port\":" + String(cfgFramePort) + ",";
  json += "\"wifi\":\"" + cfgSsid + "\"";
  json += "}";
  http.send(200, "application/json", json);
}

static void setupHttp() {
  http.on("/", HTTP_GET, handleRoot);
  http.on("/config", HTTP_POST, handleConfig);
  http.on("/status", HTTP_GET, handleStatus);
  http.begin();
}

static void bridgeClient(WiFiClient client) {
  WiFiClient frame;
  if (!frame.connect(cfgFrameIp.c_str(), cfgFramePort)) {
    Serial.println("Bridge: frame connect failed");
    client.stop();
    return;
  }

  Serial.printf("Bridge open -> %s:%u\n", cfgFrameIp.c_str(), cfgFramePort);
  while (client.connected() && frame.connected()) {
    if (client.available()) {
      uint8_t buf[256];
      int n = client.read(buf, sizeof(buf));
      if (n > 0) frame.write(buf, n);
    }
    if (frame.available()) {
      uint8_t buf[256];
      int n = frame.read(buf, sizeof(buf));
      if (n > 0) client.write(buf, n);
    }
    delay(1);
  }
  client.stop();
  frame.stop();
  Serial.println("Bridge closed");
}

static void serviceBridge() {
  if (!bridgeServer) return;
  WiFiClient client = bridgeServer->available();
  if (client) {
    bridgeClient(client);
  }
}

static void handleSerialCli() {
  if (!Serial.available()) return;
  String line = Serial.readStringUntil('\n');
  line.trim();
  if (line.startsWith("set ssid ")) {
    cfgSsid = line.substring(9);
    saveConfig();
    Serial.println("OK ssid");
  } else if (line.startsWith("set pass ")) {
    cfgPass = line.substring(9);
    saveConfig();
    Serial.println("OK pass");
  } else if (line.startsWith("set frame ")) {
    cfgFrameIp = line.substring(10);
    saveConfig();
    Serial.println("OK frame");
  } else if (line == "show") {
    Serial.printf("ssid=%s frame=%s bridge=%u\n", cfgSsid.c_str(), cfgFrameIp.c_str(), cfgBridgePort);
  } else if (line == "reboot") {
    ESP.restart();
  } else {
    Serial.println("Commands: set ssid X | set pass X | set frame IP | show | reboot");
  }
}

void setup() {
  Serial.begin(115200);
  delay(200);
  Serial.println("\nPicture Frame ESP Bridge (Wi-Fi ADB proxy)");

  loadConfig();
  // WebServer binds to lwIP; Wi-Fi must be started first or the chip reboot-loops.
  connectWifi();
  setupHttp();

  if (wifiReady) {
    bridgeServer = new WiFiServer(cfgBridgePort);
    bridgeServer->begin();
    Serial.printf("ADB bridge listening on %u -> %s:%u\n",
                  cfgBridgePort, cfgFrameIp.c_str(), cfgFramePort);
  }
}

void loop() {
  http.handleClient();
  handleSerialCli();
  if (wifiReady) {
    serviceBridge();
  }

  if (millis() - lastStatusMs > 30000) {
    lastStatusMs = millis();
    if (wifiReady) {
      Serial.printf("Status: %s bridge:%u -> %s:%u\n",
                    WiFi.localIP().toString().c_str(), cfgBridgePort,
                    cfgFrameIp.c_str(), cfgFramePort);
    }
  }
}
