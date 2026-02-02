import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

/// GT06 Protocol Implementation for Traccar Server Communication
/// 
/// This module implements the GT06 binary protocol used by Traccar for GPS tracking.
/// GT06 is a binary protocol that includes:
/// - Device authentication
/// - Position reporting
/// - Heartbeat/status messages
/// - Command reception from server
/// 
/// Protocol Structure:
/// [Header(2)] [Length(2)] [Protocol(1)] [Data(n)] [CRC(2)] [Tail(1)]

class GT06Command {
  final int commandId;
  final String commandType;
  final Map<String, String> parameters;

  GT06Command({
    required this.commandId,
    required this.commandType,
    this.parameters = const {},
  });

  @override
  String toString() => 'GT06Command(id: $commandId, type: $commandType, params: $parameters)';
}

typedef CommandHandler = void Function(GT06Command command);
typedef ConnectionStatusHandler = void Function(bool connected);
typedef ErrorHandler = void Function(String error);

class GT06Protocol {
  static const int messageTypeLogin = 0x01;
  static const int messageTypeGps = 0x12;
  static const int messageTypeHeartbeat = 0x13;
  static const int messageTypeServerCommand = 0x80;
  static const int messageTypeServerAck = 0x21;

  static const int headerMarker = 0x7878;
  static const int tailMarker = 0x0D;

  final String deviceId;
  final String serverHost;
  final int serverPort;
  final CommandHandler? commandHandler;
  final ConnectionStatusHandler? connectionStatusHandler;
  final ErrorHandler? errorHandler;

  Socket? _socket;
  bool _isConnected = false;
  int _sequenceNumber = 0;
  StreamSubscription? _streamSubscription;

  GT06Protocol({
    required this.deviceId,
    required this.serverHost,
    required this.serverPort,
    this.commandHandler,
    this.connectionStatusHandler,
    this.errorHandler,
  });

  bool get isConnected => _isConnected;

  /// Connect to Traccar server
  Future<bool> connect() async {
    try {
      _socket = await Socket.connect(serverHost, serverPort);
      _isConnected = true;
      connectionStatusHandler?.call(true);
      developer.log('Connected to Traccar server: $serverHost:$serverPort');

      // Send login message
      await _sendLoginMessage();

      // Start listening for commands
      _listenForCommands();

      return true;
    } catch (e) {
      developer.log('Connection failed: $e');
      errorHandler?.call('Connection failed: $e');
      _isConnected = false;
      connectionStatusHandler?.call(false);
      return false;
    }
  }

  /// Disconnect from server
  Future<void> disconnect() async {
    try {
      _isConnected = false;
      await _streamSubscription?.cancel();
      await _socket?.close();
      connectionStatusHandler?.call(false);
      developer.log('Disconnected from server');
    } catch (e) {
      developer.log('Error disconnecting: $e');
    }
  }

  /// Send login message to authenticate device
  Future<void> _sendLoginMessage() async {
    final data = BytesBuilder();

    // Device ID (8 bytes, IMEI)
    final imeiBytes = deviceId.padRight(8, '0').substring(0, 8).codeUnits;
    data.addByte(imeiBytes.length);
    for (var byte in imeiBytes) {
      data.addByte(byte);
    }

    // Type (1 byte) - 0x01 = GPS tracker
    data.addByte(0x01);

    // Language (1 byte) - 0x00 = English
    data.addByte(0x00);

    // Timezone (4 bytes) - UTC offset in seconds
    final timezone = DateTime.now().timeZoneOffset.inSeconds;
    data.add(_int32ToBytes(timezone));

    // Reserved (1 byte)
    data.addByte(0x00);

    await _sendMessage(messageTypeLogin, data.toBytes());
  }

  /// Send position data to server
  Future<void> sendPosition({
    required double latitude,
    required double longitude,
    required double speed,
    required double course,
    required double altitude,
    required double battery,
    required bool charging,
  }) async {
    final data = BytesBuilder();

    // GPS data length (1 byte)
    data.addByte(0x19); // 25 bytes

    // Latitude (4 bytes, signed)
    final lat = (latitude * 1e6).toInt();
    data.add(_int32ToBytes(lat));

    // Longitude (4 bytes, signed)
    final lon = (longitude * 1e6).toInt();
    data.add(_int32ToBytes(lon));

    // Speed (2 bytes)
    data.add(_int16ToBytes(speed.toInt()));

    // Course (2 bytes)
    data.add(_int16ToBytes(course.toInt()));

    // Altitude (2 bytes)
    data.add(_int16ToBytes(altitude.toInt()));

    // Timestamp (4 bytes)
    final timestamp = (DateTime.now().millisecondsSinceEpoch ~/ 1000).toInt();
    data.add(_int32ToBytes(timestamp));

    // Additional info (1 byte) - battery, GPS status, etc.
    int info = 0x00;
    if (charging) info |= 0x01;
    if (battery > 20) info |= 0x02;
    data.addByte(info);

    await _sendMessage(messageTypeGps, data.toBytes());
  }

  /// Send heartbeat/status message
  Future<void> sendHeartbeat() async {
    final data = BytesBuilder();
    data.addByte(0x00); // Status: normal operation
    await _sendMessage(messageTypeHeartbeat, data.toBytes());
  }

  /// Send generic message to server
  Future<void> _sendMessage(int messageType, Uint8List data) async {
    try {
      if (!_isConnected || _socket == null) {
        developer.log('Not connected, cannot send message');
        return;
      }

      final buffer = BytesBuilder();

      // Header
      buffer.add(_int16ToBytes(headerMarker));

      // Length (includes protocol byte + data)
      buffer.add(_int16ToBytes(data.length + 1));

      // Protocol/Message type
      buffer.addByte(messageType);

      // Data
      buffer.add(data);

      // Sequence number
      buffer.add(_int16ToBytes(_sequenceNumber++));

      // CRC16
      final payload = buffer.toBytes();
      final crc = _calculateCRC16(payload, 2, payload.length - 2);
      final crcBytes = ByteData(2);
      crcBytes.setUint16(0, crc, Endian.big);
      buffer.add(crcBytes.buffer.asUint8List());

      // Tail
      buffer.addByte(tailMarker);

      // Send to server
      _socket?.add(buffer.toBytes());
      developer.log('Message sent: type=$messageType, length=${data.length}');
    } catch (e) {
      developer.log('Error sending message: $e');
      errorHandler?.call('Send failed: $e');
    }
  }

  /// Listen for commands from server
  void _listenForCommands() {
    _streamSubscription = _socket?.listen(
      (data) {
        _parseMessage(data);
      },
      onError: (error) {
        developer.log('Socket error: $error');
        errorHandler?.call('Socket error: $error');
        disconnect();
      },
      onDone: () {
        developer.log('Socket closed');
        disconnect();
      },
    );
  }

  /// Parse incoming message from server
  void _parseMessage(Uint8List data) {
    try {
      if (data.length < 8) return;

      int offset = 0;

      // Check header
      if (data[offset] != 0x78 || data[offset + 1] != 0x78) {
        developer.log('Invalid message header');
        return;
      }
      offset += 2;

      // Read length
      final messageLength = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Read message type
      final messageType = data[offset];
      offset++;

      // Read message data
      final messageData = data.sublist(offset, offset + messageLength - 1);
      offset += messageLength - 1;

      // Read sequence number
      final seqNum = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Read CRC
      final crc = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Verify CRC
      final calculatedCrc = _calculateCRC16(data, 2, offset - 4);
      if (crc != calculatedCrc) {
        developer.log('CRC mismatch: expected=$crc, calculated=$calculatedCrc');
        return;
      }

      // Process message
      switch (messageType) {
        case messageTypeServerCommand:
          _parseServerCommand(messageData);
          break;
        case messageTypeServerAck:
          developer.log('Server ACK received');
          break;
        default:
          developer.log('Unknown message type: $messageType');
      }
    } catch (e) {
      developer.log('Error parsing message: $e');
    }
  }

  /// Parse command from server
  void _parseServerCommand(Uint8List data) {
    try {
      if (data.isEmpty) return;

      final commandId = data[0];
      final commandType = switch (commandId) {
        0x80 => 'OUTPUT',
        0x81 => 'REBOOT',
        0x82 => 'FACTORY_RESET',
        0x83 => 'CUSTOM',
        _ => 'UNKNOWN',
      };

      // Parse command parameters
      final parameters = <String, String>{};
      if (data.length > 1) {
        switch (commandId) {
          case 0x80: // OUTPUT command
            final outputNumber = data[1];
            final outputState = data.length > 2 ? data[2] : 0;
            parameters['output'] = outputNumber.toString();
            parameters['state'] = outputState.toString();
            break;
          case 0x83: // CUSTOM command
            final customData = utf8.decode(data.sublist(1));
            parameters['data'] = customData;
            break;
        }
      }

      final command = GT06Command(
        commandId: commandId,
        commandType: commandType,
        parameters: parameters,
      );

      developer.log('Command received: $command');
      commandHandler?.call(command);
    } catch (e) {
      developer.log('Error parsing command: $e');
    }
  }

  /// Calculate CRC16 checksum (CRC-CCITT)
  int _calculateCRC16(Uint8List data, int start, int length) {
    int crc = 0;
    for (int i = start; i < start + length; i++) {
      crc = crc ^ (data[i] & 0xFF);
      for (int j = 0; j < 8; j++) {
        if ((crc & 0x0001) == 0x0001) {
          crc = (crc >> 1) ^ 0xA6BC;
        } else {
          crc = crc >> 1;
        }
      }
    }
    return crc;
  }

  /// Convert 16-bit integer to bytes (big-endian)
  Uint8List _int16ToBytes(int value) {
    final bytes = ByteData(2);
    bytes.setInt16(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  /// Convert 32-bit integer to bytes (big-endian)
  Uint8List _int32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setInt32(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }
}
