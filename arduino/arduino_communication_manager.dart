import 'dart:async';
import 'dart:developer' as developer;
import 'dart:io';

/// Arduino Communication Manager
/// 
/// Handles serial communication with Arduino devices.

typedef ArduinoConnectedHandler = void Function();
typedef ArduinoDisconnectedHandler = void Function();
typedef ArduinoDataReceivedHandler = void Function(String data);
typedef ArduinoErrorHandler = void Function(String error);

class ArduinoCommunicationManager {
  final String portName;
  final int baudRate;
  final ArduinoConnectedHandler? onConnected;
  final ArduinoDisconnectedHandler? onDisconnected;
  final ArduinoDataReceivedHandler? onDataReceived;
  final ArduinoErrorHandler? onError;

  Process? _process;
  bool _isConnected = false;
  StreamSubscription? _subscription;
  final StringBuffer _buffer = StringBuffer();

  ArduinoCommunicationManager({
    required this.portName,
    this.baudRate = 9600,
    this.onConnected,
    this.onDisconnected,
    this.onDataReceived,
    this.onError,
  });

  bool get isConnected => _isConnected;

  /// Connect to Arduino via serial port
  Future<bool> connect() async {
    try {
      developer.log('[Arduino] Connecting to $portName at $baudRate baud');

      // Use stty to configure serial port (Linux/Mac)
      if (Platform.isLinux || Platform.isMacOS) {
        await Process.run('stty', ['-f', portName, '$baudRate', 'cs8', '-cstopb', '-parenb']);
      }

      _process = await Process.start('cat', [portName]);
      _isConnected = true;
      developer.log('[Arduino] Connected');
      onConnected?.call();

      _startReadThread();
      return true;
    } catch (e) {
      developer.log('[Arduino] Connection error: $e');
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
      _process?.kill();
      developer.log('[Arduino] Disconnected');
      onDisconnected?.call();
    } catch (e) {
      developer.log('[Arduino] Disconnect error: $e');
    }
  }

  /// Send command to Arduino
  Future<void> sendCommand(String command) async {
    try {
      if (!_isConnected) {
        developer.log('[Arduino] Not connected');
        onError?.call('Not connected');
        return;
      }

      final commandWithNewline = command.endsWith('\n') ? command : '$command\n';
      
      // Write to serial port using echo and tee
      final process = await Process.run('bash', [
        '-c',
        'echo "$command" > $portName'
      ]);

      if (process.exitCode == 0) {
        developer.log('[Arduino] Command sent: $command');
      } else {
        developer.log('[Arduino] Send error: ${process.stderr}');
        onError?.call('Send error: ${process.stderr}');
      }
    } catch (e) {
      developer.log('[Arduino] Send error: $e');
      onError?.call('Send error: $e');
    }
  }

  /// Send ENGINE_STOP command
  Future<void> sendEngineStop() => sendCommand('ENGINE_STOP');

  /// Send ENGINE_RESUME command
  Future<void> sendEngineResume() => sendCommand('ENGINE_RESUME');

  /// Send custom command
  Future<void> sendCustomCommand(String command) => sendCommand(command);

  /// Start read thread
  void _startReadThread() {
    _subscription = _process?.stdout.transform(const Utf8Decoder()).listen(
      (String data) {
        _buffer.write(data);

        // Process complete lines
        final lines = _buffer.toString().split('\n');
        _buffer.clear();

        if (!data.endsWith('\n')) {
          _buffer.write(lines.last);
        }

        for (int i = 0; i < lines.length - 1; i++) {
          final line = lines[i].trim();
          if (line.isNotEmpty) {
            developer.log('[Arduino] Received: $line');
            onDataReceived?.call(line);
          }
        }
      },
      onError: (error) {
        developer.log('[Arduino] Read error: $error');
        if (_isConnected) {
          onError?.call('Read error: $error');
        }
      },
      onDone: () {
        developer.log('[Arduino] Port closed');
        disconnect();
      },
    );
  }
}
