# Traccar Flutter Client - Arduino Integration Guide

## 📋 Overview

This guide explains how to integrate the new GT06 protocol, TCPUART interface, and Arduino communication into the existing Traccar Flutter Client application.

---

## 🏗️ Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                  Traccar Flutter Client                      │
├─────────────────────────────────────────────────────────────┤
│                                                               │
│  ┌──────────────────────────────────────────────────────┐   │
│  │      GeolocationService (existing)                   │   │
│  │  - Manages GPS position updates                      │   │
│  │  - Calls TCPUART.sendPosition()                      │   │
│  └──────────────────────────────────────────────────────┘   │
│                           │                                   │
│                           ▼                                   │
│  ┌──────────────────────────────────────────────────────┐   │
│  │              TCPUART (NEW)                           │   │
│  │  - Bridges TCP (server) and UART (Arduino)           │   │
│  │  - Manages both connections                          │   │
│  │  - Routes commands and responses                     │   │
│  └──────────────────────────────────────────────────────┘   │
│           │                                  │                │
│           ▼                                  ▼                │
│  ┌─────────────────────┐        ┌──────────────────────┐   │
│  │  GT06Protocol (NEW) │        │ ArduinoComm Mgr (NEW)│   │
│  │  - TCP to server    │        │ - USB Serial to      │   │
│  │  - Send position    │        │   Arduino            │   │
│  │  - Receive commands │        │ - Send/Recv commands │   │
│  └─────────────────────┘        └──────────────────────┘   │
│           │                                  │                │
└───────────┼──────────────────────────────────┼────────────────┘
            │                                  │
            ▼                                  ▼
    ┌──────────────────┐            ┌──────────────────┐
    │ Traccar Server   │            │    Arduino       │
    │  (TCP Port 5055) │            │  (USB Serial)    │
    └──────────────────┘            └──────────────────┘
```

---

## 📦 New Components

### 1. gt06_protocol.dart
**Purpose:** Implements the GT06 binary protocol for Traccar communication.

**Key Features:**
- Device authentication/login
- Position data transmission
- Heartbeat messages
- Command reception from server
- CRC16 checksum validation

**Usage:**
```dart
final protocol = GT06Protocol(
  deviceId: '123456789',
  serverHost: 'traccar.example.com',
  serverPort: 5055,
  commandHandler: (command) { /* handle command */ },
);
await protocol.connect();
await protocol.sendPosition(
  latitude: 23.55,
  longitude: -46.63,
  speed: 50,
  course: 180,
  altitude: 100,
  battery: 85,
  charging: false,
);
await protocol.sendHeartbeat();
await protocol.disconnect();
```

### 2. arduino_communication_manager.dart
**Purpose:** Manages USB-to-Serial communication with Arduino devices.

**Key Features:**
- Auto-detection of USB serial devices
- Configurable baud rate (default 9600)
- Command sending
- Asynchronous data reception
- Connection state management

**Usage:**
```dart
final arduinoMgr = ArduinoCommunicationManager(
  onConnected: () { /* handle connected */ },
  onDisconnected: () { /* handle disconnected */ },
  onDataReceived: (data) { /* handle data */ },
  onError: (error) { /* handle error */ },
);
await arduinoMgr.connect(baudRate: 9600);
await arduinoMgr.sendCommand('ENGINE_STOP');
await arduinoMgr.disconnect();
```

### 3. tcpuart.dart
**Purpose:** Acts as a bridge between Traccar server and Arduino device.

**Key Features:**
- Manages both GT06Protocol and ArduinoCommunicationManager
- Converts Traccar commands to Arduino commands
- Parses Arduino responses
- Handles connection states for both sides
- Provides unified status callbacks

**Usage:**
```dart
final tcpuart = TCPUART(
  deviceId: '123456789',
  serverHost: 'traccar.example.com',
  serverPort: 5055,
  statusCallback: (status) { /* handle status */ },
);
tcpuart.initialize();
await tcpuart.start();
await tcpuart.sendPosition(
  latitude: 23.55,
  longitude: -46.63,
  speed: 50,
  course: 180,
  altitude: 100,
  battery: 85,
  charging: false,
);
await tcpuart.stop();
```

---

## 🔧 Integration Steps

### Step 1: Add Dependencies

Update `pubspec.yaml`:

```yaml
dependencies:
  flutter:
    sdk: flutter
  usb_serial: ^0.4.9
  # ... existing dependencies ...
```

Run:
```bash
flutter pub get
```

### Step 2: Copy New Files

Copy the following files to `lib/`:

1. `gt06_protocol.dart`
2. `arduino_communication_manager.dart`
3. `tcpuart.dart`

### Step 3: Update AndroidManifest.xml

Add USB permissions to `android/app/src/main/AndroidManifest.xml`:

```xml
<uses-permission android:name="android.permission.USB_PERMISSION" />

<application>
    <!-- ... existing application config ... -->
    
    <!-- USB device filter for Arduino -->
    <activity android:name=".MainActivity">
        <intent-filter>
            <action android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED" />
        </intent-filter>
        <meta-data
            android:name="android.hardware.usb.action.USB_DEVICE_ATTACHED"
            android:resource="@xml/device_filter" />
    </activity>
</application>
```

### Step 4: Create USB Device Filter

Create `android/app/src/main/res/xml/device_filter.xml`:

```xml
<?xml version="1.0" encoding="utf-8"?>
<resources>
    <usb-device vendor-id="0x2341" product-id="0x0043" /> <!-- Arduino Uno -->
    <usb-device vendor-id="0x2341" product-id="0x0001" /> <!-- Arduino Mega -->
    <usb-device vendor-id="0x1a86" product-id="0x7523" /> <!-- CH340 -->
    <usb-device vendor-id="0x0403" product-id="0x6001" /> <!-- FT232 -->
</usb-device>
```

### Step 5: Modify GeolocationService

Update `lib/geolocation_service.dart` to use TCPUART:

```dart
import 'package:traccar_client/tcpuart.dart';

class GeolocationService {
  static TCPUART? _tcpuart;

  static Future<void> init() async {
    // ... existing initialization ...
    
    // Initialize TCPUART
    _tcpuart = TCPUART(
      deviceId: Preferences.instance.getString(Preferences.id) ?? '',
      serverHost: _getServerHost(),
      serverPort: _getServerPort(),
      statusCallback: (status) {
        developer.log('TCPUART: $status');
      },
    );
    _tcpuart?.initialize();
    await _tcpuart?.start();
  }

  static Future<void> onLocation(bg.Location location) async {
    // ... existing code ...
    
    // Send position via TCPUART
    await _tcpuart?.sendPosition(
      latitude: location.coords.latitude,
      longitude: location.coords.longitude,
      speed: location.coords.speed ?? 0,
      course: location.coords.heading ?? 0,
      altitude: location.coords.altitude ?? 0,
      battery: location.battery?.level ?? 0,
      charging: location.battery?.isCharging ?? false,
    );
  }

  static Future<void> onHeartbeat(bg.HeartbeatEvent event) async {
    // ... existing code ...
    
    // Send heartbeat via TCPUART
    await _tcpuart?.sendHeartbeat();
  }

  static String _getServerHost() {
    final url = Preferences.instance.getString(Preferences.url) ?? '';
    // Parse host from URL
    try {
      final uri = Uri.parse(url);
      return uri.host;
    } catch (e) {
      return 'localhost';
    }
  }

  static int _getServerPort() {
    final url = Preferences.instance.getString(Preferences.url) ?? '';
    // Parse port from URL
    try {
      final uri = Uri.parse(url);
      return uri.port > 0 ? uri.port : 5055;
    } catch (e) {
      return 5055;
    }
  }
}
```

### Step 6: Add Preferences for Arduino

Update `lib/preferences.dart` to add Arduino settings:

```dart
class Preferences {
  // ... existing constants ...
  
  static const String arduinoEnabled = 'arduino_enabled';
  static const String arduinoBaudRate = 'arduino_baud_rate';
  
  static Future<void> migrate() async {
    // ... existing migration code ...
    
    await instance.setBool(arduinoEnabled, instance.getBool(arduinoEnabled) ?? false);
    await instance.setInt(arduinoBaudRate, instance.getInt(arduinoBaudRate) ?? 9600);
  }
}
```

### Step 7: Add Settings Screen Option

Update `lib/settings_screen.dart` to add Arduino settings:

```dart
// Add to settings list
ListTile(
  title: const Text('Arduino Integration'),
  subtitle: const Text('Enable Arduino communication'),
  trailing: Switch(
    value: Preferences.instance.getBool(Preferences.arduinoEnabled) ?? false,
    onChanged: (value) async {
      await Preferences.instance.setBool(Preferences.arduinoEnabled, value);
      setState(() {});
    },
  ),
),
```

---

## 🔄 Command Flow

### Server → Arduino Flow

```
1. Traccar Server sends command (e.g., ENGINE_STOP)
   ↓
2. GT06Protocol receives command via TCP
   ↓
3. GT06Protocol.commandHandler is called
   ↓
4. TCPUART converts Traccar command to Arduino format
   ↓
5. ArduinoCommunicationManager sends via USB Serial
   ↓
6. Arduino receives and executes command
   ↓
7. Arduino sends response (e.g., "ACK,ENGINE_STOP")
   ↓
8. ArduinoCommunicationManager receives response
   ↓
9. TCPUART parses and logs response
```

### Arduino → Server Flow

```
1. Arduino sends position data or status
   ↓
2. ArduinoCommunicationManager receives via USB Serial
   ↓
3. ArduinoCommunicationManager.onDataReceived is called
   ↓
4. TCPUART parses Arduino response
   ↓
5. TCPUART updates internal state/logs
```

---

## 📡 Protocol Details

### GT06 Message Format

```
[Header: 0x7878] [Length: 2 bytes] [Type: 1 byte] [Data: n bytes] [Sequence: 2 bytes] [CRC16: 2 bytes] [Tail: 0x0D]
```

### Message Types

| Type | Name | Direction |
|------|------|-----------|
| 0x01 | LOGIN | Client → Server |
| 0x12 | GPS | Client → Server |
| 0x13 | HEARTBEAT | Client → Server |
| 0x80 | SERVER_COMMAND | Server → Client |
| 0x21 | SERVER_ACK | Server → Client |

### Arduino Command Format

```
COMMAND_NAME,PARAM1=VALUE1,PARAM2=VALUE2\n
```

**Examples:**
```
ENGINE_STOP
ENGINE_RESUME
GET_STATUS
GET_GPS
GET_LOGS
CLEAR_LOGS
```

---

## 🧪 Testing

### Test 1: Server Connection
```dart
final tcpuart = TCPUART(
  deviceId: '123456789',
  serverHost: 'traccar.example.com',
  serverPort: 5055,
);
await tcpuart.start();
// Check logs for "Connected to Traccar server"
```

### Test 2: Arduino Connection
```dart
// Connect Arduino via USB
final tcpuart = TCPUART(
  deviceId: '123456789',
  serverHost: 'traccar.example.com',
  serverPort: 5055,
);
await tcpuart.start();
// Check logs for "Connected to Arduino"
```

### Test 3: Send Position
```dart
await tcpuart.sendPosition(
  latitude: 23.550520,
  longitude: -46.633309,
  speed: 50.0,
  course: 180.0,
  altitude: 100.0,
  battery: 85.0,
  charging: false,
);
// Check server for position update
```

### Test 4: Receive Command
```dart
// Send ENGINE_STOP from Traccar web interface
// Check logs for "Command received from server"
// Check Arduino for relay activation
```

---

## 🔒 Security Considerations

1. **Device Authentication:** GT06 protocol includes device ID verification
2. **CRC Validation:** All messages include CRC16 checksum
3. **USB Permissions:** Request explicit user permission for USB access
4. **Data Encryption:** Consider adding TLS/SSL for TCP connection (future enhancement)

---

## 🚀 Future Enhancements

1. **TLS/SSL Support:** Encrypt TCP communication with server
2. **Bluetooth Support:** Add Bluetooth as alternative to USB Serial
3. **Multiple Arduino Support:** Handle multiple Arduino devices
4. **Command Queuing:** Implement persistent command queue
5. **Offline Mode:** Cache commands when offline
6. **OTA Updates:** Support firmware updates for Arduino
7. **Advanced Logging:** Implement detailed event logging

---

## 📚 References

- [Traccar Protocol Documentation](https://www.traccar.org/protocol/)
- [GT06 Protocol Specification](https://www.traccar.org/gt06/)
- [Flutter USB Serial Package](https://pub.dev/packages/usb_serial)
- [Arduino USB Communication](https://www.arduino.cc/en/Guide/ArduinoUno)

---

## 📞 Support

For issues or questions:
1. Check the logs in Flutter DevTools
2. Verify USB device connections
3. Test Arduino communication separately
4. Verify Traccar server connectivity

---

**Version:** 1.0
**Date:** 2025-02-02
**Author:** Traccar Flutter Arduino Integration Team
