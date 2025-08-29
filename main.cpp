#include <Arduino.h>
#include <DHT.h>
#include <LiquidCrystal_I2C.h>
#include <Wire.h>
#include <ESP32Servo.h>
#include <WiFi.h>
#include <PubSubClient.h>
#include <WiFiClientSecure.h>

// --- Pins ---
#define PIN_MQ2    34   // MQ2 Gas sensor (Analog)
#define PIN_DHT    15   // DHT11 Data
#define PIN_FLAME  35   // Flame sensor AO (Analog)
#define PIN_SERVO  14   // Servo motor
#define PIN_LED    25   // LED
#define PIN_BUZZ   26   // Buzzer

// --- DHT ---
#define DHTTYPE DHT11
DHT dht(PIN_DHT, DHTTYPE);

// --- Servo ---
Servo myServo;
int servoPos = 0;

// --- LCD ---
LiquidCrystal_I2C lcd(0x27, 16, 2); // I2C address 0x27, 16 chars, 2 lines

// --- WiFi ---
const char* ssid = "Ganna’s iPhone";
const char* password = "11997733";

// HiveMQ Cloud MQTT settings
const char* mqtt_server = "436aa7eaa3cb4577bd3567b46af719b1.s1.eu.hivemq.cloud";
const int mqtt_port = 8883;
const char* mqtt_user = "hivemq.webclient.1756106226262";
const char* mqtt_password = "sC6QPKpD3*cuI%@l81;y";

//Topics
const char* sub_led   = "led";
const char* pub_led   = "led/confirm";
const char* sub_servo = "servo";
const char* pub_servo = "servo/confirm";
const char* sub_buzz  = "buzzer";
const char* pub_buzz  = "buzzer/confirm";
const char* pub_sensors = "sensors/data";

WiFiClientSecure secureClient;
PubSubClient client(secureClient);

// ================== CALLBACK ==================
void callback(char* topic, byte* payload, unsigned int length) {
  String msg;
  for (int i = 0; i < length; i++) {
    msg += (char)payload[i];
  }
  msg.trim();
  Serial.printf("Received [%s]: %s\n", topic, msg.c_str());

  // --- التحكم في LED ---
  if (String(topic) == sub_led) {
    if (msg == "ON") {
      digitalWrite(PIN_LED, HIGH);
      client.publish(pub_led, "LED ON");
    } else {
      digitalWrite(PIN_LED, LOW);
      client.publish(pub_led, "LED OFF");
    }
  }

  // --- التحكم في SERVO ---
  if (String(topic) == sub_servo) {
    int angle = msg.toInt();
    angle = constrain(angle, 0, 180);
    myServo.write(angle);
    delay(5000);
    String confirm = "Servo moved to " + String(angle);
    client.publish(pub_servo, confirm.c_str());
  }

  // --- التحكم في BUZZER ---
  if (String(topic) == sub_buzz) {
    if (msg == "ON") {
      digitalWrite(PIN_BUZZ, HIGH);
      client.publish(pub_buzz, "Buzzer ON");
    } else {
      digitalWrite(PIN_BUZZ, LOW);
      client.publish(pub_buzz, "Buzzer OFF");
    }
  }
}

// ================== RECONNECT ==================
void reconnect() {
  while (!client.connected()) {
    Serial.println("Attempting MQTT connection...");
    if (client.connect("ESP32Client", mqtt_user, mqtt_password)) {
      Serial.println("MQTT connected");

      // Subscribes
      client.subscribe(sub_led);
      client.subscribe(sub_servo);
      client.subscribe(sub_buzz);

    } else {
      Serial.print("Failed. State=");
      Serial.print(client.state());
      Serial.println(" Retrying in 5 seconds...");
      delay(5000);
    }
  }
}


void setup() {
Serial.begin(115200);

  pinMode(PIN_MQ2, INPUT);
  pinMode(PIN_FLAME, INPUT);
  pinMode(PIN_LED, OUTPUT);
  pinMode(PIN_BUZZ, OUTPUT);

  dht.begin();
  myServo.attach(PIN_SERVO);

  lcd.init();
  lcd.backlight();

  lcd.setCursor(0, 0);
  lcd.print("Smart Kitchen");
  delay(1500);
  lcd.clear();

  Serial.println("=== Sensor + Servo + LCD Test Started ===");

// --- WiFi ---
  WiFi.begin(ssid, password);
  Serial.print("Connecting to WiFi");
  while (WiFi.status() != WL_CONNECTED) {
    delay(500);
    Serial.print(".");
  }
  Serial.println("\nWiFi connected");

  // --- MQTT ---
  secureClient.setInsecure();  
  client.setServer(mqtt_server, mqtt_port);
  client.setCallback(callback);

}

void loop() {

  if (!client.connected()) {
    reconnect();
  }
  client.loop();

  // --- Read sensors ---
  int gasValue = analogRead(PIN_MQ2);
  int flameValue = analogRead(PIN_FLAME); // 0–4095
  float temp = dht.readTemperature();
  float hum = dht.readHumidity();

  // --- Print results to Serial ---
  Serial.print("Temp: "); Serial.print(temp); Serial.print(" °C | ");
  Serial.print("Humidity: "); Serial.print(hum); Serial.print(" % | ");
  Serial.print("Gas: "); Serial.print(gasValue); Serial.print(" | ");
  Serial.print("Flame Intensity: "); Serial.println(flameValue);

 // --- Danger detection ---
  bool flameDanger = (flameValue < 2500); // Threshold for flame
  bool gasDanger   = (gasValue > 2000);
  bool tempDanger  = (temp > 40);

  bool danger = gasDanger || flameDanger || tempDanger;

  if (danger) {
    digitalWrite(PIN_LED, HIGH);
    digitalWrite(PIN_BUZZ, HIGH);
    myServo.write(0);
    Serial.println("⚠️ DANGER detected!");

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("DANGER Reason:");

    // Build message dynamically
    String dangerMsg = "";
    if (gasDanger)   dangerMsg += "Gas ";
    if (flameDanger) dangerMsg += "Flame ";
    if (tempDanger)  dangerMsg += "Temp ";

    lcd.setCursor(0, 1);
    lcd.print(dangerMsg);
  } else {
    digitalWrite(PIN_LED, LOW);
    digitalWrite(PIN_BUZZ, LOW);
    myServo.write(180);
    Serial.println("✅ Safe");

    lcd.clear();
    lcd.setCursor(0, 0);
    lcd.print("T:"); lcd.print(temp, 1); lcd.print("C H:"); lcd.print(hum, 0);

    lcd.setCursor(0, 1);
    lcd.print("Gas:"); lcd.print(gasValue);
    lcd.print(" F:");
    if (flameDanger) lcd.print("YES");
    else lcd.print("NO ");
  }

// --- Send sensor data to Cloud ---
  String sensorData = "{";
  sensorData += "\"temp\":" + String(temp) + ",";
  sensorData += "\"hum\":" + String(hum) + ",";
  sensorData += "\"gas\":" + String(gasValue) + ",";
  sensorData += "\"flame\":" + String(flameValue) + ",";
  sensorData += "\"led\":" + String(digitalRead(PIN_LED)) + ",";
  sensorData += "\"buzzer\":" + String(digitalRead(PIN_BUZZ)) + ",";
  sensorData += "\"servo\":" + String(servoPos) + ",";
  if (danger) {
    sensorData += "\"status\":\"Danger\"";
  } else {
    sensorData += "\"status\":\"Normal\"";
  }
  sensorData += "}";
  client.publish(pub_sensors, sensorData.c_str());


  delay(10000); // wait 2 seconds before next reading
}