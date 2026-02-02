import 'dart:async';
import 'dart:developer' as developer;
import 'package:usb_serial/usb_serial.dart';

/// Arduino Communication Manager
/// 
/// Handles USB-to-Serial communication with Arduino devices.
/// Provides interface for sending commands and receiving responses.

typedef ArduinoConnectedHandler = void Function();
typedef ArduinoDisconnectedHandler = void Function();
typedef ArduinoDataReceivedHandler = void Function(String data);
typedef ArduinoErrorHandler = void Function(String error);

class ArduinoCommunicationManager {
  final ArduinoConnectedHandler? onConnected;
  final ArduinoDisconnectedHandler? onDisconnected;
  final ArduinoDataReceivedHandler? onDataReceived;
  final ArduinoErrorHandler? onError;

  UsbPort? _port;
  bool _isConnected = false;
  StreamSubscription? _subscription;
  final StringBuffer _buffer = StringBuffer();

  ArduinoCommunicationManager({
    this.onConnected,
    this.onDisconnected,
    this.onDataReceived,
    this.onError,
  });

  bool get isConnected => _isConnected;

  /// Initialize USB manager and get available devices
  static Future<List<UsbDevice>> getAvailableDevices() async {
    return await UsbSerial.listDevices();
  }

  /// Connect to Arduino via USB Serial
  Future<bool> connect({int baudRate = 9600}) async {
    try {
      final devices = await getAvailableDevices();
      if (devices.isEmpty) {
        developer.log('No USB serial devices found');
        onError?.call('No USB serial devices found');
        return false;
      }

      final device = devices.first;
      _port = await device.create();

      if (!await _port!.open()) {
        developer.log('Cannot open USB device');
        onError?.call('Cannot open USB device');
        return false;
      }

      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _isConnected = true;
      developer.log('Connected to Arduino at $baudRate baud');
      onConnected?.call();

      // Start read thread
      _startReadThread();

      return true;
    } catch (e) {
      developer.log('Connection error: $e');
      onError?.call('Connection error: $e');
      _isConnected = false;
      return false;
    }
  }

  /// Disconnect from Arduino
  Future<void> disconnect() async {
    try {
      _isConnected = false;
      await _subscription?.cancel();
      await _port?.close();
      developer.log('Disconnected from Arduino');
      onDisconnected?.call();
    } catch (e) {
      developer.log('Error disconnecting: $e');
    }
  }

  /// Send command to Arduino
  Future<void> sendCommand(String command) async {
    try {
      if (!_isConnected || _port == null) {
        developer.log('Not connected to Arduino');
        onError?.call('Not connected to Arduino');
        return;
      }

      final commandWithNewline = command.endsWith('\n') ? command : '$command\n';
      await _port!.write(commandWithNewline.codeUnits);
      developer.log('Command sent: $command');
    } catch (e) {
      developer.log('Error sending command: $e');
      onError?.call('Send error: $e');
    }
  }

  /// Send ENGINE_STOP command
  Future<void> sendEngineStop() => sendCommand('ENGINE_STOP');

  /// Send ENGINE_RESUME command
  Future<void> sendEngineResume() => sendCommand('ENGINE_RESUME');

  /// Send custom command
  Future<void> sendCustomCommand(String command) => sendCommand(command);

  /// Start thread for reading data from Arduino
  void _startReadThread() {
    _subscription = _port?.inputStream?.listen(
      (Uint8List data) {
        final String dataStr = String.fromCharCodes(data);
        _buffer.write(dataStr);

        // Check for complete lines (ending with \n)
        final lines = _buffer.toString().split('\n');
        
        // Keep the last incomplete line in the buffer
        _buffer.clear();
        if (!_buffer.toString().endsWith('\n')) {
          _buffer.write(lines.last);
        }

        // Process complete lines
        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            developer.log('Data received: $line');
            onDataReceived?.call(line);
          }
        }
      },
      onError: (error) {
        developer.log('Read error: $error');
        if (_isConnected) {
          onError?.call('Read error: $error');
        }
      },
      onDone: () {
        developer.log('Port closed');
        disconnect();
      },
    );
  }
}
