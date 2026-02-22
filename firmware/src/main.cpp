/*
 * ═══════════════════════════════════════════════════════════════
 *  Nixo Soft PC Checker Dongle — ESP32-S3 Firmware
 *  LILYGO T-Dongle-S3 (ESP32-S3 + ST7735 LCD + USB HID)
 *  
 *  Flow:
 *  1. Boot → LCD splash → Start WiFi AP
 *  2. Show QR code on LCD (→ 192.168.4.1)
 *  3. Phone connects → opens dashboard
 *  4. User taps "Scan" → ESP32 types commands via USB HID
 *  5. Diagnostic script runs on PC → POSTs results to ESP32
 *  6. Dashboard shows scores + report
 * ═══════════════════════════════════════════════════════════════
 */

#include <Arduino.h>
#include <WiFi.h>
#include <ESPAsyncWebServer.h>
#include <SPIFFS.h>
#include <TFT_eSPI.h>
#include <qrcode.h>
#include "USB.h"
#include "USBHIDKeyboard.h"

// ─── Config ─────────────────────────────────────────────────
#define WIFI_SSID     "NixoSoft-Check"
#define WIFI_PASS     ""  // Open network for easy phone connect
#define WEB_PORT      80
#define DASHBOARD_URL "http://192.168.4.1"
#define FW_VERSION    "1.0.0"

// LCD colors (RGB565)
#define COLOR_BG      0x0841  // #030712 approx
#define COLOR_GOLD    0xD4E3  // #D4A843 approx
#define COLOR_WHITE   0xFFFF
#define COLOR_DIM     0x4228  // dim gray
#define COLOR_GREEN   0x07E0
#define COLOR_RED     0xF800

// ─── Globals ────────────────────────────────────────────────
TFT_eSPI tft = TFT_eSPI();
AsyncWebServer server(WEB_PORT);
USBHIDKeyboard keyboard;

// State
enum State { 
  STATE_BOOT, 
  STATE_READY,      // Waiting for phone connection
  STATE_CONNECTED,  // Phone connected, waiting for scan command
  STATE_TYPING,     // Typing commands on target PC
  STATE_SCANNING,   // Waiting for diagnostic results
  STATE_RESULTS,    // Results received
  STATE_ERROR 
};

State currentState = STATE_BOOT;
String diagnosticResults = "{}";
String detectedOS = "unknown";
bool phoneConnected = false;
unsigned long lastPhonePing = 0;
int connectedClients = 0;

// ─── LCD Helpers ────────────────────────────────────────────
void lcdClear() {
  tft.fillScreen(COLOR_BG);
}

void lcdText(int x, int y, const char* text, uint16_t color, uint8_t size = 1) {
  tft.setTextColor(color, COLOR_BG);
  tft.setTextSize(size);
  tft.setCursor(x, y);
  tft.print(text);
}

void lcdCenterText(int y, const char* text, uint16_t color, uint8_t size = 1) {
  tft.setTextSize(size);
  int16_t w = tft.textWidth(text);
  int16_t x = (tft.width() - w) / 2;
  lcdText(x, y, text, color, size);
}

// ─── QR Code on LCD ─────────────────────────────────────────
void showQRCode(const char* url) {
  QRCode qrcode;
  uint8_t qrcodeData[qrcode_getBufferSize(6)];
  qrcode_initText(&qrcode, qrcodeData, 6, ECC_LOW, url);
  
  lcdClear();
  
  // Calculate QR positioning (center on screen)
  int moduleSize = min(tft.width(), tft.height() - 30) / qrcode.size;
  if (moduleSize < 1) moduleSize = 1;
  int qrWidth = qrcode.size * moduleSize;
  int offsetX = (tft.width() - qrWidth) / 2;
  int offsetY = 5;
  
  // Draw white background for QR
  tft.fillRect(offsetX - 4, offsetY - 4, qrWidth + 8, qrWidth + 8, COLOR_WHITE);
  
  // Draw QR modules
  for (uint8_t y = 0; y < qrcode.size; y++) {
    for (uint8_t x = 0; x < qrcode.size; x++) {
      if (qrcode_getModule(&qrcode, x, y)) {
        tft.fillRect(offsetX + x * moduleSize, offsetY + y * moduleSize, 
                     moduleSize, moduleSize, TFT_BLACK);
      }
    }
  }
  
  // Label below QR
  int labelY = offsetY + qrWidth + 10;
  lcdCenterText(labelY, "SCAN ME", COLOR_GOLD, 1);
  lcdCenterText(labelY + 12, "NixoSoft", COLOR_DIM, 1);
}

// ─── Boot Splash ────────────────────────────────────────────
void showSplash() {
  lcdClear();
  lcdCenterText(30, "NIXO", COLOR_GOLD, 2);
  lcdCenterText(55, "SOFT", COLOR_GOLD, 2);
  lcdCenterText(85, "PC Checker", COLOR_WHITE, 1);
  lcdCenterText(100, FW_VERSION, COLOR_DIM, 1);
  delay(1500);
}

// ─── Status Screen ──────────────────────────────────────────
void showStatus(const char* line1, const char* line2, uint16_t color) {
  lcdClear();
  lcdCenterText(40, line1, color, 1);
  lcdCenterText(60, line2, COLOR_DIM, 1);
}

// ─── USB HID Keyboard Typing ────────────────────────────────
// Platform-specific command sequences to open terminal + run script

void typeWindows() {
  // Win+R → powershell command
  keyboard.press(KEY_LEFT_GUI);
  keyboard.press('r');
  keyboard.releaseAll();
  delay(500);
  
  // Type PowerShell command that downloads and runs the diagnostic script
  keyboard.print("powershell -ExecutionPolicy Bypass -Command \"irm http://192.168.4.1/scan.ps1 | iex\"");
  delay(200);
  keyboard.press(KEY_RETURN);
  keyboard.releaseAll();
}

void typeLinux() {
  // Ctrl+Alt+T to open terminal (works on most Linux DEs)
  keyboard.press(KEY_LEFT_CTRL);
  keyboard.press(KEY_LEFT_ALT);
  keyboard.press('t');
  keyboard.releaseAll();
  delay(1000);
  
  keyboard.print("curl -s http://192.168.4.1/scan.sh | bash");
  delay(200);
  keyboard.press(KEY_RETURN);
  keyboard.releaseAll();
}

void typeMac() {
  // Cmd+Space → Terminal
  keyboard.press(KEY_LEFT_GUI);
  keyboard.press(' ');
  keyboard.releaseAll();
  delay(500);
  keyboard.print("Terminal");
  delay(300);
  keyboard.press(KEY_RETURN);
  keyboard.releaseAll();
  delay(1000);
  
  keyboard.print("curl -s http://192.168.4.1/scan.sh | bash");
  delay(200);
  keyboard.press(KEY_RETURN);
  keyboard.releaseAll();
}

void typeCommandsForOS(const String& os) {
  currentState = STATE_TYPING;
  showStatus("TYPING...", os.c_str(), COLOR_GOLD);
  
  delay(500); // Give USB HID time to be recognized
  
  if (os == "windows") {
    typeWindows();
  } else if (os == "linux") {
    typeLinux();
  } else if (os == "mac") {
    typeMac();
  }
  
  currentState = STATE_SCANNING;
  showStatus("SCANNING", "Waiting for data", COLOR_GOLD);
}

// ─── WiFi AP Setup ──────────────────────────────────────────
void setupWiFi() {
  WiFi.mode(WIFI_AP);
  WiFi.softAP(WIFI_SSID, WIFI_PASS);
  delay(500);
  
  IPAddress ip = WiFi.softAPIP();
  Serial.printf("AP started: %s\n", WIFI_SSID);
  Serial.printf("IP: %s\n", ip.toString().c_str());
}

// ─── Web Server Routes ──────────────────────────────────────
void setupWebServer() {
  // Serve dashboard and assets from SPIFFS
  server.serveStatic("/", SPIFFS, "/").setDefaultFile("index.html");
  
  // API: Get device status
  server.on("/api/status", HTTP_GET, [](AsyncWebServerRequest *request) {
    String json = "{";
    json += "\"state\":\"" + String(currentState) + "\",";
    json += "\"version\":\"" FW_VERSION "\",";
    json += "\"clients\":" + String(connectedClients) + ",";
    json += "\"ssid\":\"" WIFI_SSID "\",";
    json += "\"ip\":\"" + WiFi.softAPIP().toString() + "\",";
    json += "\"hasResults\":" + String(diagnosticResults != "{}") + ",";
    json += "\"detectedOS\":\"" + detectedOS + "\"";
    json += "}";
    request->send(200, "application/json", json);
  });
  
  // API: Trigger scan (called from phone dashboard)
  server.on("/api/scan", HTTP_POST, [](AsyncWebServerRequest *request) {
    // Get OS parameter
    if (request->hasParam("os", true)) {
      detectedOS = request->getParam("os", true)->value();
    } else {
      detectedOS = "windows"; // Default
    }
    
    request->send(200, "application/json", "{\"ok\":true,\"typing\":true}");
    
    // Type commands after response is sent
    delay(100);
    typeCommandsForOS(detectedOS);
  });
  
  // API: Receive diagnostic results (called from PC script)
  server.on("/api/results", HTTP_POST, 
    [](AsyncWebServerRequest *request) {},
    NULL,
    [](AsyncWebServerRequest *request, uint8_t *data, size_t len, size_t index, size_t total) {
      if (index == 0) {
        diagnosticResults = "";
      }
      diagnosticResults += String((char*)data).substring(0, len);
      
      if (index + len == total) {
        currentState = STATE_RESULTS;
        showStatus("COMPLETE", "View on phone", COLOR_GREEN);
        request->send(200, "application/json", "{\"ok\":true}");
        Serial.printf("Results received: %d bytes\n", total);
      }
    }
  );
  
  // API: Get diagnostic results (phone fetches this)
  server.on("/api/results", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(200, "application/json", diagnosticResults);
  });
  
  // API: Reset (start over)
  server.on("/api/reset", HTTP_POST, [](AsyncWebServerRequest *request) {
    diagnosticResults = "{}";
    detectedOS = "unknown";
    currentState = STATE_READY;
    showQRCode(DASHBOARD_URL);
    request->send(200, "application/json", "{\"ok\":true}");
  });
  
  // API: Firmware info
  server.on("/api/info", HTTP_GET, [](AsyncWebServerRequest *request) {
    String json = "{";
    json += "\"firmware\":\"" FW_VERSION "\",";
    json += "\"chip\":\"ESP32-S3\",";
    json += "\"flash\":" + String(ESP.getFlashChipSize()) + ",";
    json += "\"heap\":" + String(ESP.getFreeHeap()) + ",";
    json += "\"uptime\":" + String(millis() / 1000);
    json += "}";
    request->send(200, "application/json", json);
  });

  // Serve diagnostic scripts
  server.on("/scan.ps1", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(SPIFFS, "/scan.ps1", "text/plain");
  });
  
  server.on("/scan.sh", HTTP_GET, [](AsyncWebServerRequest *request) {
    request->send(SPIFFS, "/scan.sh", "text/plain");
  });
  
  // CORS headers for all responses
  DefaultHeaders::Instance().addHeader("Access-Control-Allow-Origin", "*");
  DefaultHeaders::Instance().addHeader("Access-Control-Allow-Methods", "GET, POST, OPTIONS");
  DefaultHeaders::Instance().addHeader("Access-Control-Allow-Headers", "Content-Type");
  
  server.begin();
  Serial.println("Web server started on port 80");
}

// ─── Setup ──────────────────────────────────────────────────
void setup() {
  Serial.begin(115200);
  Serial.println("\n═══ Nixo Soft PC Checker Dongle ═══");
  
  // Init LCD
  tft.init();
  tft.setRotation(1); // Landscape for T-Dongle-S3
  pinMode(TFT_BL, OUTPUT);
  digitalWrite(TFT_BL, HIGH);
  
  // Boot splash
  currentState = STATE_BOOT;
  showSplash();
  
  // Init SPIFFS
  if (!SPIFFS.begin(true)) {
    Serial.println("SPIFFS failed!");
    showStatus("ERROR", "SPIFFS fail", COLOR_RED);
    return;
  }
  Serial.printf("SPIFFS: %d bytes used / %d total\n", SPIFFS.usedBytes(), SPIFFS.totalBytes());
  
  // Init USB HID
  keyboard.begin();
  USB.begin();
  Serial.println("USB HID keyboard initialized");
  
  // Start WiFi AP
  setupWiFi();
  
  // Start web server
  setupWebServer();
  
  // Show QR code
  currentState = STATE_READY;
  showQRCode(DASHBOARD_URL);
  
  Serial.println("Ready! Scan QR code to begin.");
}

// ─── Main Loop ──────────────────────────────────────────────
void loop() {
  // Track connected WiFi clients
  int clients = WiFi.softAPgetStationNum();
  if (clients != connectedClients) {
    connectedClients = clients;
    Serial.printf("WiFi clients: %d\n", clients);
    
    if (clients > 0 && currentState == STATE_READY) {
      // Phone connected — still show QR but update status
      phoneConnected = true;
    }
  }
  
  // Periodically refresh LCD based on state
  static unsigned long lastLCDUpdate = 0;
  if (millis() - lastLCDUpdate > 5000) {
    lastLCDUpdate = millis();
    
    switch (currentState) {
      case STATE_SCANNING:
        // Blink to show we're waiting
        showStatus("SCANNING", "Waiting...", COLOR_GOLD);
        break;
      default:
        break;
    }
  }
  
  delay(10);
}
