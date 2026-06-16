#include <WiFi.h>
#include <Firebase_ESP_Client.h>
#include <Wire.h>
#include <Adafruit_INA219.h>
#include "firebase_config.h"

FirebaseData fbdo;
FirebaseAuth auth;
FirebaseConfig config;

const int PWM_PIN = 18;
const float BATT_MAX_VOLTAGE = 4.20;
#define LED_BUILTIN 2

// Dual I2C Buses
TwoWire I2C_S = Wire;
TwoWire I2C_B = TwoWire(1);

Adafruit_INA219 s_Solar(0x40);
Adafruit_INA219 s_Batt(0x40);

// MPPT Variables
int duty = 0;
float oldPower = 0;
int stepSize = 5;

// Timing Variables
unsigned long sendDataPrevMillis = 0;
unsigned long lastHistoryMillis = 0;
unsigned long lastSampleMillis = 0;
const unsigned long FIREBASE_INTERVAL = 2000;  // Live data every 2 seconds
const unsigned long HISTORY_INTERVAL = 150000; // History every 2.5 minutes
const unsigned long SAMPLE_INTERVAL = 10000;   // Sample every 10 seconds

// Variables for Averaging
float solarVoltageSum = 0;
float solarCurrentSum = 0;
float solarPowerSum = 0;
float batteryVoltageSum = 0;
float batteryCurrentSum = 0;
float batteryPowerSum = 0;
int sampleCount = 0;

// Sensor Status
bool solarSensorOK = false;
bool batterySensorOK = false;

void initSensors()
{
    // Initialize Solar Sensor
    solarSensorOK = s_Solar.begin(&I2C_S);
    if (!solarSensorOK)
    {
        Serial.println("SOLAR INA219 NOT FOUND on address 0x40");
    }
    else
    {
        s_Solar.setCalibration_32V_2A();
        Serial.println("Solar sensor initialized");
    }

    // Initialize Battery Sensor
    batterySensorOK = s_Batt.begin(&I2C_B);
    if (!batterySensorOK)
    {
        Serial.println("BATTERY INA219 NOT FOUND on address 0x41");
        // Scan for devices
        Serial.println("Scanning I2C bus B...");
        for (uint8_t addr = 1; addr < 127; addr++)
        {
            I2C_B.beginTransmission(addr);
            if (I2C_B.endTransmission() == 0)
            {
                Serial.print("Found device at 0x");
                Serial.println(addr, HEX);
            }
        }
    }
    else
    {
        s_Batt.setCalibration_32V_2A();
        Serial.println("Battery sensor initialized");
    }
}

void setup()
{
    Serial.begin(115200);

    // Initialize I2C Buses
    I2C_S.begin(21, 22);
    I2C_B.begin(17, 16);

    // Initialize Sensors
    initSensors();

    // PWM Setup
    ledcAttach(PWM_PIN, 1000, 10);
    ledcWrite(PWM_PIN, 0);

    // WiFi
    Serial.print("Connecting to WiFi");
    WiFi.begin(WIFI_SSID, WIFI_PASSWORD);
    while (WiFi.status() != WL_CONNECTED)
    {
        delay(500);
        Serial.print(".");
    }
    Serial.println("\nWiFi Connected!");

    // Firebase
    config.api_key = API_KEY;
    config.database_url = DATABASE_URL;
    auth.user.email = EMAIL;
    auth.user.password = PASS;

    Firebase.begin(&config, &auth);
    Firebase.reconnectNetwork(true);
    Firebase.setDoubleDigits(5);
    config.timeout.serverResponse = 10 * 1000;
    Serial.println("Firebase Initialized");

    lastSampleMillis = millis();
    lastHistoryMillis = millis();
}

float readSolarVoltage()
{
    if (!solarSensorOK)
        return 0;
    float v = s_Solar.getBusVoltage_V();
    return (v < 0.1) ? 0 : v;
}

float readSolarCurrent()
{
    if (!solarSensorOK)
        return 0;
    float c = s_Solar.getCurrent_mA();
    return (c < 0) ? 0 : c;
}

float readSolarPower()
{
    float v = readSolarVoltage();
    float c = readSolarCurrent();
    return v * c;
}

float readBatteryVoltage()
{
    if (!batterySensorOK)
        return 0;
    float v = s_Batt.getBusVoltage_V();
    return (v < 0.1) ? 0 : v;
}

float readBatteryCurrent()
{
    if (!batterySensorOK)
        return 0;
    float c = s_Batt.getCurrent_mA();
    return (c < 0) ? 0 : c;
}

float readBatteryPower()
{
    float v = readBatteryVoltage();
    float c = readBatteryCurrent();
    return v * c;
}

float readBatteryPercentage()
{
    float v = readBatteryVoltage();
    float pct = ((v - 3.0) / (4.2 - 3.0)) * 100.0;
    return constrain(pct, 0, 100);
}

// MPPT Control
void runMPPT()
{
    float v_panel = readSolarVoltage();
    float i_panel = readSolarCurrent();
    float p_panel = v_panel * i_panel;
    float v_batt = readBatteryVoltage();

    if (v_batt >= BATT_MAX_VOLTAGE)
    {
        duty = 0;
        oldPower = 0;
    }
    else if (v_panel > (v_batt + 0.1))
    {
        if (p_panel < oldPower)
        {
            stepSize = -stepSize;
        }
        duty = constrain(duty + stepSize, 0, 950);
        oldPower = p_panel;
    }
    else
    {
        duty = 0;
        oldPower = 0;
        stepSize = abs(stepSize);
    }

    ledcWrite(PWM_PIN, duty);
}

void loop()
{
    // Sample sensors every 10 seconds for averaging
    if (millis() - lastSampleMillis > SAMPLE_INTERVAL)
    {
        lastSampleMillis = millis();

        float sVoltage = readSolarVoltage();
        float sCurrent = readSolarCurrent();
        float sPower = readSolarPower();
        float bVoltage = readBatteryVoltage();
        float bCurrent = readBatteryCurrent();
        float bPower = readBatteryPower();

        solarVoltageSum += sVoltage;
        solarCurrentSum += sCurrent;
        solarPowerSum += sPower;
        batteryVoltageSum += bVoltage;
        batteryCurrentSum += bCurrent;
        batteryPowerSum += bPower;
        sampleCount++;

        Serial.println("Sample " + String(sampleCount) + ": Solar " + String(sVoltage, 1) + "V " + String(sPower, 0) + "mW | Batt " + String(bVoltage, 2) + "V " + String(readBatteryPercentage(), 0) + "%");
    }

    // MPPT update every 100ms
    static unsigned long lastMPPT = 0;
    if (millis() - lastMPPT > 100)
    {
        lastMPPT = millis();
        runMPPT();
    }

    // Send live data to Firebase every 2 seconds
    if (Firebase.ready() && (millis() - sendDataPrevMillis > FIREBASE_INTERVAL || sendDataPrevMillis == 0))
    {
        sendDataPrevMillis = millis();

        float sVoltage = readSolarVoltage();
        float sCurrent = readSolarCurrent();
        float sPower = readSolarPower();
        float bVoltage = readBatteryVoltage();
        float bCurrent = readBatteryCurrent();
        float bPower = readBatteryPower();
        float bPercentage = readBatteryPercentage();

        // Solar Data
        Firebase.RTDB.setFloat(&fbdo, "/Solar/Voltage", sVoltage);
        Firebase.RTDB.setFloat(&fbdo, "/Solar/Current", sCurrent);
        Firebase.RTDB.setFloat(&fbdo, "/Solar/Power", sPower);
        Firebase.RTDB.setInt(&fbdo, "/Solar/DutyCycle", duty / 10);

        // Battery Data
        Firebase.RTDB.setFloat(&fbdo, "/Battery/Voltage", bVoltage);
        Firebase.RTDB.setFloat(&fbdo, "/Battery/Current", bCurrent);
        Firebase.RTDB.setFloat(&fbdo, "/Battery/Power", bPower);
        Firebase.RTDB.setFloat(&fbdo, "/Battery/Percentage", bPercentage);
        Firebase.RTDB.setInt(&fbdo, "/Battery/Status", bVoltage >= BATT_MAX_VOLTAGE ? 1 : 0);

        // System Status
        Firebase.RTDB.setInt(&fbdo, "/System/MPPT_Active", duty > 0 ? 1 : 0);
    }

    // Store averaged history every 2.5 minutes
    if (Firebase.ready() && millis() - lastHistoryMillis > HISTORY_INTERVAL && sampleCount > 0)
    {
        lastHistoryMillis = millis();

        // Calculate averages
        float avgSolarV = solarVoltageSum / sampleCount;
        float avgSolarC = solarCurrentSum / sampleCount;
        float avgSolarP = solarPowerSum / sampleCount;
        float avgBattV = batteryVoltageSum / sampleCount;
        float avgBattC = batteryCurrentSum / sampleCount;
        float avgBattP = batteryPowerSum / sampleCount;

        // Store Solar History
        FirebaseJson solarJson;
        solarJson.add("Voltage", avgSolarV);
        solarJson.add("Current", avgSolarC);
        solarJson.add("Power", avgSolarP);
        solarJson.add("DutyCycle", duty / 10);
        solarJson.add("SampleCount", sampleCount);
        Firebase.RTDB.pushJSON(&fbdo, "/History/Solar", &solarJson);

        // Store Battery History
        FirebaseJson battJson;
        battJson.add("Voltage", avgBattV);
        battJson.add("Current", avgBattC);
        battJson.add("Power", avgBattP);
        battJson.add("Percentage", readBatteryPercentage());
        battJson.add("SampleCount", sampleCount);
        Firebase.RTDB.pushJSON(&fbdo, "/History/Battery", &battJson);

        // Store System History
        FirebaseJson sysJson;
        sysJson.add("MPPT_Active", duty > 0 ? 1 : 0);
        sysJson.add("DutyCycle", duty / 10);
        Firebase.RTDB.pushJSON(&fbdo, "/History/System", &sysJson);

        Serial.println("\n=== History Saved (2.5min avg) ===");
        Serial.println("Solar: " + String(avgSolarV, 2) + "V, " + String(avgSolarC, 1) + "mA, " + String(avgSolarP, 1) + "mW");
        Serial.println("Battery: " + String(avgBattV, 2) + "V, " + String(avgBattC, 1) + "mA, " + String(avgBattP, 1) + "mW");
        Serial.println("Samples: " + String(sampleCount));
        Serial.println("===============================\n");

        // Reset averages
        solarVoltageSum = 0;
        solarCurrentSum = 0;
        solarPowerSum = 0;
        batteryVoltageSum = 0;
        batteryCurrentSum = 0;
        batteryPowerSum = 0;
        sampleCount = 0;
    }

    delay(10);
}