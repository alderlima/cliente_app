import 'dart:async';
import 'dart:convert';
import 'dart:developer' as developer;
import 'dart:io';
import 'dart:typed_data';

/// GT06 Protocol Implementation
/// 
/// Binary protocol for Traccar server communication.
/// Message format: [Header] [Length] [Type] [Data] [Sequence] [CRC16] [Tail]

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
  String toString() => 'GT06Command(id: $commandId, type: $commandType)';
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
  final BytesBuilder _receiveBuffer = BytesBuilder();

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
      _socket = await Socket.connect(serverHost, serverPort, timeout: Duration(seconds: 10));
      _isConnected = true;
      connectionStatusHandler?.call(true);
      developer.log('[GT06] Connected to $serverHost:$serverPort');

      // Send login message
      await _sendLoginMessage();

      // Start listening for commands
      _listenForCommands();

      return true;
    } catch (e) {
      developer.log('[GT06] Connection failed: $e');
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
      developer.log('[GT06] Disconnected');
    } catch (e) {
      developer.log('[GT06] Disconnect error: $e');
    }
  }

  /// Send login message
  Future<void> _sendLoginMessage() async {
    final data = BytesBuilder();

    // Device ID (8 bytes, IMEI)
    final imeiBytes = deviceId.padRight(8, '0').substring(0, 8).codeUnits;
    data.addByte(imeiBytes.length);
    for (var byte in imeiBytes) {
      data.addByte(byte);
    }

    // Type (1 byte)
    data.addByte(0x01);

    // Language (1 byte)
    data.addByte(0x00);

    // Timezone (4 bytes)
    final timezone = DateTime.now().timeZoneOffset.inSeconds;
    data.add(_int32ToBytes(timezone));

    // Reserved (1 byte)
    data.addByte(0x00);

    await _sendMessage(messageTypeLogin, data.toBytes());
  }

  /// Send position data
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

    // GPS data length
    data.addByte(0x19);

    // Latitude (4 bytes)
    final lat = (latitude * 1e6).toInt();
    data.add(_int32ToBytes(lat));

    // Longitude (4 bytes)
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

    // Additional info
    int info = 0x00;
    if (charging) info |= 0x01;
    if (battery > 20) info |= 0x02;
    data.addByte(info);

    await _sendMessage(messageTypeGps, data.toBytes());
  }

  /// Send heartbeat
  Future<void> sendHeartbeat() async {
    final data = BytesBuilder();
    data.addByte(0x00);
    await _sendMessage(messageTypeHeartbeat, data.toBytes());
  }

  /// Send message to server
  Future<void> _sendMessage(int messageType, Uint8List data) async {
    try {
      if (!_isConnected || _socket == null) {
        developer.log('[GT06] Not connected');
        return;
      }

      final buffer = BytesBuilder();

      // Header
      buffer.add(_int16ToBytes(headerMarker));

      // Length
      buffer.add(_int16ToBytes(data.length + 1));

      // Type
      buffer.addByte(messageType);

      // Data
      buffer.add(data);

      // Sequence
      buffer.add(_int16ToBytes(_sequenceNumber++));

      // CRC16
      final payload = buffer.toBytes();
      final crc = _calculateCRC16(payload, 2, payload.length - 2);
      buffer.add(_int16ToBytes(crc));

      // Tail
      buffer.addByte(tailMarker);

      _socket?.add(buffer.toBytes());
      developer.log('[GT06] Message sent: type=0x${messageType.toRadixString(16)}');
    } catch (e) {
      developer.log('[GT06] Send error: $e');
      errorHandler?.call('Send failed: $e');
    }
  }

  /// Listen for commands
  void _listenForCommands() {
    _streamSubscription = _socket?.listen(
      (data) {
        _receiveBuffer.add(data);
        _processBuffer();
      },
      onError: (error) {
        developer.log('[GT06] Socket error: $error');
        disconnect();
      },
      onDone: () {
        developer.log('[GT06] Socket closed');
        disconnect();
      },
    );
  }

  /// Process receive buffer
  void _processBuffer() {
    final buffer = _receiveBuffer.toBytes();
    int offset = 0;

    while (offset < buffer.length - 7) {
      // Check header
      if (buffer[offset] != 0x78 || buffer[offset + 1] != 0x78) {
        offset++;
        continue;
      }

      // Read length
      final messageLength = (buffer[offset + 2] << 8) | buffer[offset + 3];
      final totalLength = messageLength + 7;

      if (offset + totalLength > buffer.length) {
        break;
      }

      // Extract message
      final message = buffer.sublist(offset, offset + totalLength);
      _parseMessage(message);

      offset += totalLength;
    }

    // Remove processed data
    if (offset > 0) {
      final remaining = buffer.sublist(offset);
      _receiveBuffer.clear();
      _receiveBuffer.add(remaining);
    }
  }

  /// Parse message
  void _parseMessage(Uint8List data) {
    try {
      if (data.length < 8) return;

      int offset = 0;

      // Skip header
      offset += 2;

      // Read length
      final messageLength = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Read type
      final messageType = data[offset];
      offset++;

      // Read data
      final messageData = data.sublist(offset, offset + messageLength - 1);
      offset += messageLength - 1;

      // Read sequence
      final seqNum = (data[offset] << 8) | data[offset + 1];
      offset += 2;

      // Read CRC
      final crc = (data[offset] << 8) | data[offset + 1];

      // Verify CRC
      final calculatedCrc = _calculateCRC16(data, 2, offset - 2);
      if (crc != calculatedCrc) {
        developer.log('[GT06] CRC mismatch');
        return;
      }

      // Process message
      if (messageType == messageTypeServerCommand) {
        _parseServerCommand(messageData);
      } else if (messageType == messageTypeServerAck) {
        developer.log('[GT06] Server ACK');
      }
    } catch (e) {
      developer.log('[GT06] Parse error: $e');
    }
  }

  /// Parse server command
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

      final parameters = <String, String>{};
      if (data.length > 1) {
        switch (commandId) {
          case 0x80:
            final outputNumber = data[1];
            final outputState = data.length > 2 ? data[2] : 0;
            parameters['output'] = outputNumber.toString();
            parameters['state'] = outputState.toString();
            break;
          case 0x83:
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

      developer.log('[GT06] Command: $command');
      commandHandler?.call(command);
    } catch (e) {
      developer.log('[GT06] Command parse error: $e');
    }
  }

  /// Calculate CRC16
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

  /// Convert 16-bit to bytes
  Uint8List _int16ToBytes(int value) {
    final bytes = ByteData(2);
    bytes.setInt16(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }

  /// Convert 32-bit to bytes
  Uint8List _int32ToBytes(int value) {
    final bytes = ByteData(4);
    bytes.setInt32(0, value, Endian.big);
    return bytes.buffer.asUint8List();
  }
}
