#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include <DFRobot_DHT11.h>
#include "firebase_config.h"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

TwoWire I2C_Two = TwoWire(1);

Adafruit_INA219 ina219(0x40);
Adafruit_INA219 ina219_2(0x40);
#define FAN_RELAY_DOWNSTAIRS_ROOM_1 25
#define FAN_RELAY_DOWNSTAIRS_ROOM_2 26
DFRobot_DHT11 DHT;
#define DHT11_PIN 4

unsigned long sendDataPrevMillis = 0;
unsigned long lastHistoryMillis = 0;
// Set to 150000 for 2.5 minutes
unsigned long historyInterval = 150000;

// Variables for Averaging
float tempSum = 0;
float humiditySum = 0;
int sampleCount = 0;
unsigned long lastSampleMillis = 0;
const unsigned long sampleInterval = 10000; // Sample every 10 seconds
float room1PowerSum = 0;
float room2PowerSum = 0;
float room1CurrentSum = 0;
float room2CurrentSum = 0;
float room1VoltageSum = 0;
float room2VoltageSum = 0;

void setup()
{
    Serial.begin(115200);
    Wire.begin(21, 22);
    I2C_Two.begin(33, 32);

    pinMode(FAN_RELAY_DOWNSTAIRS_ROOM_1, OUTPUT);
    pinMode(FAN_RELAY_DOWNSTAIRS_ROOM_2, OUTPUT);

    // Initialize relays to OFF state
    digitalWrite(FAN_RELAY_DOWNSTAIRS_ROOM_1, LOW);
    digitalWrite(FAN_RELAY_DOWNSTAIRS_ROOM_2, LOW);

    // Start sensors on their specific buses
    if (!ina219.begin(&Wire))
    {
        Serial.println("Room 1 INA (Bus 1) not found");
    }
    if (!ina219_2.begin(&I2C_Two))
    {
        Serial.println("Room 2 INA (Bus 2) not found");
    }

    Serial.print("Connecting to WiFi");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    while (WiFi.status() != WL_CONNECTED)
    {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi Connected!");

    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    auth.user.email = EMAIL;
    auth.user.password = PASS;

    Firebase.reconnectNetwork(true);
    fbdo.setBSSLBufferSize(4096, 1024);
    fbdo.setResponseSize(2048);

    Firebase.begin(&config, &auth);
    Firebase.setDoubleDigits(5);
    config.timeout.serverResponse = 10 * 1000;
    Serial.println("Firebase Initialized");

    // Initialize sample timing
    lastSampleMillis = millis();
    lastHistoryMillis = millis();
}

void loop()
{
    static unsigned long lastDebugPrint = 0;
    if (millis() - lastDebugPrint > 5000)
    {
        lastDebugPrint = millis();
        Serial.println("=== STATUS ===");
        Serial.println("WiFi: " + String(WiFi.status() == WL_CONNECTED));
        Serial.println("Firebase.ready(): " + String(Firebase.ready()));
        Serial.println("Time to history: " + String(millis() - lastHistoryMillis));
        Serial.println("historyInterval: " + String(historyInterval));
        Serial.println("sampleCount: " + String(sampleCount));
    }

    // Sample sensors every 10 seconds for averaging
    if (millis() - lastSampleMillis > sampleInterval)
    {
        lastSampleMillis = millis();

        // Read DHT11
        DHT.read(DHT11_PIN);
        float humidity = DHT.humidity;
        float temperature = DHT.temperature;

        // Read Room 1 INA219
        float busVoltage1 = ina219.getBusVoltage_V();
        if (busVoltage1 < 1.0)
            busVoltage1 = 0;
        float current_mA1 = ina219.getCurrent_mA();
        if (current_mA1 < 0.0)
            current_mA1 = 0;
        float power_mW1 = ina219.getPower_mW();
        if (power_mW1 < 0.0)
            power_mW1 = 0;

        // Read Room 2 INA219
        float busVoltage2 = ina219_2.getBusVoltage_V();
        if (busVoltage2 < 1.0)
            busVoltage2 = 0;
        float current_mA2 = ina219_2.getCurrent_mA();
        if (current_mA2 < 0.0)
            current_mA2 = 0;
        float power_mW2 = ina219_2.getPower_mW();
        if (power_mW2 < 0.0)
            power_mW2 = 0;

        // Accumulate values for averaging
        tempSum += temperature;
        humiditySum += humidity;
        room1PowerSum += power_mW1;
        room1CurrentSum += current_mA1;
        room1VoltageSum += busVoltage1;
        room2PowerSum += power_mW2;
        room2CurrentSum += current_mA2;
        room2VoltageSum += busVoltage2;
        sampleCount++;

        Serial.println("Sample " + String(sampleCount) + " collected");
        Serial.println("Temp: " + String(temperature) + "°C, Humidity: " + String(humidity) + "%");
        Serial.println("Room1 - V: " + String(busVoltage1) + "V, I: " + String(current_mA1) + "mA, P: " + String(power_mW1) + "mW");
        Serial.println("Room2 - V: " + String(busVoltage2) + "V, I: " + String(current_mA2) + "mA, P: " + String(power_mW2) + "mW");
    }

    // Send real-time data to Firebase every 2 seconds
    if (Firebase.ready() && (millis() - sendDataPrevMillis > 2000 || sendDataPrevMillis == 0))
    {
        sendDataPrevMillis = millis();

        // Read current sensor values for real-time display
        DHT.read(DHT11_PIN);
        float humidity = DHT.humidity;
        float temperature = DHT.temperature;

        float busVoltage1 = ina219.getBusVoltage_V();
        if (busVoltage1 < 1.0)
            busVoltage1 = 0;
        float current_mA1 = ina219.getCurrent_mA();
        if (current_mA1 < 0.0)
            current_mA1 = 0;
        float power_mW1 = ina219.getPower_mW();
        if (power_mW1 < 0.0)
            power_mW1 = 0;

        float busVoltage2 = ina219_2.getBusVoltage_V();
        if (busVoltage2 < 1.0)
            busVoltage2 = 0;
        float current_mA2 = ina219_2.getCurrent_mA();
        if (current_mA2 < 0.0)
            current_mA2 = 0;
        float power_mW2 = ina219_2.getPower_mW();
        if (power_mW2 < 0.0)
            power_mW2 = 0;

        // Upload Environment data
        Firebase.RTDB.setFloat(&fbdo, "/Environment/Humidity", humidity);
        Firebase.RTDB.setFloat(&fbdo, "/Environment/Temperature", temperature);

        // Relay Control from Firebase
        String Relay1_cmd = "OFF";
        String Relay2_cmd = "OFF";
        Firebase.RTDB.getString(&fbdo, "/Downstairs/Room1/Relay", &Relay1_cmd);
        Firebase.RTDB.getString(&fbdo, "/Downstairs/Room2/Relay", &Relay2_cmd);

        digitalWrite(FAN_RELAY_DOWNSTAIRS_ROOM_1, (Relay1_cmd == "ON") ? HIGH : LOW);
        digitalWrite(FAN_RELAY_DOWNSTAIRS_ROOM_2, (Relay2_cmd == "ON") ? HIGH : LOW);

        // Upload ACTUAL state back to Firebase
        Firebase.RTDB.setString(&fbdo, "/Downstairs/Room1/Appliances", (digitalRead(FAN_RELAY_DOWNSTAIRS_ROOM_1) == HIGH) ? "ON" : "OFF");
        Firebase.RTDB.setString(&fbdo, "/Downstairs/Room2/Appliances", (digitalRead(FAN_RELAY_DOWNSTAIRS_ROOM_2) == HIGH) ? "ON" : "OFF");

        // Room 1 Power Data
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room1/Voltage", busVoltage1);
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room1/Current", current_mA1);
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room1/Power", power_mW1);

        // Room 2 Power Data
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room2/Voltage", busVoltage2);
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room2/Current", current_mA2);
        Firebase.RTDB.setFloat(&fbdo, "/Downstairs/Room2/Power", power_mW2);

        Serial.println("Real-time data synced to Firebase");
    }

    // Store averaged history data every 2.5 minutes
    if (Firebase.ready() && millis() - lastHistoryMillis > historyInterval && sampleCount > 0)
    {
        lastHistoryMillis = millis();

        // Calculate averages
        float avgTemp = tempSum / sampleCount;
        float avgHumidity = humiditySum / sampleCount;
        float avgRoom1Power = room1PowerSum / sampleCount;
        float avgRoom1Current = room1CurrentSum / sampleCount;
        float avgRoom1Voltage = room1VoltageSum / sampleCount;
        float avgRoom2Power = room2PowerSum / sampleCount;
        float avgRoom2Current = room2CurrentSum / sampleCount;
        float avgRoom2Voltage = room2VoltageSum / sampleCount;

        // Reset averaging variables
        tempSum = 0;
        humiditySum = 0;
        room1PowerSum = 0;
        room1CurrentSum = 0;
        room1VoltageSum = 0;
        room2PowerSum = 0;
        room2CurrentSum = 0;
        room2VoltageSum = 0;

        // Store Environment History with averages
        FirebaseJson envJson;
        envJson.add("Temperature", avgTemp);
        envJson.add("Humidity", avgHumidity);
        envJson.add("SampleCount", sampleCount);

        if (Firebase.RTDB.pushJSON(&fbdo, "/History/Environment", &envJson))
        {
            Serial.println("Environment History Saved (Avg over " + String(sampleCount) + " samples)");
        }
        else
        {
            Serial.println("Environment History Error: " + fbdo.errorReason());
        }

        // Store Room 1 History with averages
        FirebaseJson room1Json;
        room1Json.add("Power", avgRoom1Power);
        room1Json.add("Current", avgRoom1Current);
        room1Json.add("Voltage", avgRoom1Voltage);
        room1Json.add("SampleCount", sampleCount);

        if (Firebase.RTDB.pushJSON(&fbdo, "/History/Room1", &room1Json))
        {
            Serial.println("Room1 History Saved");
        }
        else
        {
            Serial.println("Room1 History Error: " + fbdo.errorReason());
        }

        // Store Room 2 History with averages
        FirebaseJson room2Json;
        room2Json.add("Power", avgRoom2Power);
        room2Json.add("Current", avgRoom2Current);
        room2Json.add("Voltage", avgRoom2Voltage);
        room2Json.add("SampleCount", sampleCount);

        if (Firebase.RTDB.pushJSON(&fbdo, "/History/Room2", &room2Json))
        {
            Serial.println("Room2 History Saved");
        }
        else
        {
            Serial.println("Room2 History Error: " + fbdo.errorReason());
        }
        sampleCount = 0;
    }
}