# Smart Kitchen Safety System 

An IoT-based **kitchen monitoring and safety system** using **ESP32, Node-RED, Supabase, and Flutter**.  
The system detects **gas leaks, fire, and high temperature**, takes automated safety actions, and alerts users in real-time.

---

##  Features

### ESP32 + Sensors
- MQ2 Gas Sensor → detects gas leaks
- Flame Sensor → detects fire
- DHT11 → monitors temperature
- PIR Sensor → detects human presence (safety delay)
- Servo Motor → controls kitchen door
- Buzzer + LED → alarm notifications

### Node-RED + MQTT + Supabase
- ESP32 publishes sensor data to MQTT broker
- Node-RED subscribes, processes, and forwards data to Supabase
- Supabase stores logs and provides real-time sync with app

### Flutter App
- Login/Sign up (Supabase Auth)
- Real-time dashboard (gas, fire, temperature status)
- Alerts page (critical incidents)
- History logs (past records)

---

##  System Architecture
ESP32 → MQTT (HiveMQ) → Node-RED → Supabase → Flutter App
## Setup Instructions

### 1. ESP32
1. Open `esp32-code/main.ino` in Arduino IDE
2. Install libraries:
   - WiFi
   - PubSubClient
   - DHT sensor library
3. Update WiFi SSID, password, and MQTT broker
4. Upload to ESP32

### 2. Node-RED
1. Run Node-RED
2. Import `nodered-flow.json`
3. Connect to HiveMQ broker
4. Ensure data is forwarded to Supabase REST API

### 3. Flutter App
1. `cd flutter-app/`
2. Run `flutter pub get`
3. Update `lib/config.dart` with Supabase credentials
4. Run `flutter run`

---

## Example Data Flow
Gas detected → ESP32 publishes → MQTT broker → Node-RED → Supabase → Flutter app alert
