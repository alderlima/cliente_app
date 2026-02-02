import 'dart:developer' as developer;
import 'package:traccar_client/protocols/gt06_protocol.dart';
import 'package:traccar_client/arduino/arduino_communication_manager.dart';

/// TCPUART Interface
/// 
/// Bridges TCP communication with Traccar server and UART communication with Arduino.
/// Acts as a central hub for command routing and status management.

typedef StatusCallback = void Function(String status);

class TCPUART {
  final String deviceId;
  final String serverHost;
  final int serverPort;
  final String? arduinoPort;
  final int arduinoBaudRate;
  final StatusCallback? statusCallback;

  GT06Protocol? _gt06Protocol;
  ArduinoCommunicationManager? _arduinoManager;
  bool _initialized = false;

  TCPUART({
    required this.deviceId,
    required this.serverHost,
    required this.serverPort,
    this.arduinoPort,
    this.arduinoBaudRate = 9600,
    this.statusCallback,
  });

  bool get isConnected => _gt06Protocol?.isConnected ?? false;
  bool get isArduinoConnected => _arduinoManager?.isConnected ?? false;

  /// Initialize TCPUART
  void initialize() {
    if (_initialized) return;

    developer.log('[TCPUART] Initializing for device: $deviceId');
    _initialized = true;
  }

  /// Start TCPUART
  Future<bool> start() async {
    try {
      if (!_initialized) {
        initialize();
      }

      developer.log('[TCPUART] Starting...');

      // Initialize Arduino if port specified
      if (arduinoPort != null && arduinoPort!.isNotEmpty) {
        _arduinoManager = ArduinoCommunicationManager(
          portName: arduinoPort!,
          baudRate: arduinoBaudRate,
          onConnected: _onArduinoConnected,
          onDisconnected: _onArduinoDisconnected,
          onDataReceived: _onArduinoDataReceived,
          onError: _onArduinoError,
        );

        final arduinoConnected = await _arduinoManager?.connect() ?? false;
        if (!arduinoConnected) {
          developer.log('[TCPUART] Arduino connection failed, continuing...');
          statusCallback?.call('Arduino connection failed');
        }
      }

      // Initialize GT06 Protocol
      _gt06Protocol = GT06Protocol(
        deviceId: deviceId,
        serverHost: serverHost,
        serverPort: serverPort,
        commandHandler: _onServerCommandReceived,
        connectionStatusHandler: _onServerConnectionStatusChanged,
        errorHandler: _onServerError,
      );

      // Connect to server
      final serverConnected = await _gt06Protocol?.connect() ?? false;
      if (!serverConnected) {
        developer.log('[TCPUART] Server connection failed');
        statusCallback?.call('Server connection failed');
        await stop();
        return false;
      }

      developer.log('[TCPUART] Started successfully');
      statusCallback?.call('TCPUART started');
      return true;
    } catch (e) {
      developer.log('[TCPUART] Start error: $e');
      statusCallback?.call('Start error: $e');
      return false;
    }
  }

  /// Stop TCPUART
  Future<void> stop() async {
    try {
      developer.log('[TCPUART] Stopping...');
      await _gt06Protocol?.disconnect();
      await _arduinoManager?.disconnect();
      developer.log('[TCPUART] Stopped');
      statusCallback?.call('TCPUART stopped');
    } catch (e) {
      developer.log('[TCPUART] Stop error: $e');
    }
  }

  /// Send position to server
  Future<void> sendPosition({
    required double latitude,
    required double longitude,
    required double speed,
    required double course,
    required double altitude,
    required double battery,
    required bool charging,
  }) async {
    try {
      await _gt06Protocol?.sendPosition(
        latitude: latitude,
        longitude: longitude,
        speed: speed,
        course: course,
        altitude: altitude,
        battery: battery,
        charging: charging,
      );
      developer.log('[TCPUART] Position sent: lat=$latitude, lon=$longitude');
    } catch (e) {
      developer.log('[TCPUART] Position send error: $e');
      statusCallback?.call('Position send error: $e');
    }
  }

  /// Send heartbeat
  Future<void> sendHeartbeat() async {
    try {
      await _gt06Protocol?.sendHeartbeat();
      developer.log('[TCPUART] Heartbeat sent');
    } catch (e) {
      developer.log('[TCPUART] Heartbeat error: $e');
    }
  }

  /// Convert Traccar command to Arduino command
  String? _convertTraccarCommandToArduino(GT06Command command) {
    switch (command.commandType) {
      case 'OUTPUT':
        final output = command.parameters['output'] ?? '0';
        final state = command.parameters['state'] ?? '0';
        if (output == '1' && state == '1') {
          return 'ENGINE_STOP';
        } else if (output == '1' && state == '0') {
          return 'ENGINE_RESUME';
        } else {
          return 'CUSTOM,OUTPUT=$output,STATE=$state';
        }
      case 'CUSTOM':
        return command.parameters['data'] ?? 'UNKNOWN';
      case 'REBOOT':
        return 'REBOOT';
      case 'FACTORY_RESET':
        return 'FACTORY_RESET';
      default:
        return null;
    }
  }

  /// Parse Arduino response
  void _parseArduinoResponse(String response) {
    developer.log('[TCPUART] Arduino response: $response');

    if (response.startsWith('ACK')) {
      developer.log('[TCPUART] Arduino ACK: $response');
      statusCallback?.call('Arduino ACK: $response');
    } else if (response.startsWith('ERROR')) {
      developer.log('[TCPUART] Arduino error: $response');
      statusCallback?.call('Arduino error: $response');
    } else if (response.startsWith('STATUS')) {
      developer.log('[TCPUART] Arduino status: $response');
      statusCallback?.call('Arduino status: $response');
    } else if (response.startsWith('LOG')) {
      developer.log('[TCPUART] Arduino log: $response');
    } else {
      developer.log('[TCPUART] Unknown response: $response');
    }
  }

  // ===== GT06Protocol Callbacks =====

  void _onServerCommandReceived(GT06Command command) {
    developer.log('[TCPUART] Command from server: $command');

    final arduinoCommand = _convertTraccarCommandToArduino(command);
    if (arduinoCommand != null) {
      developer.log('[TCPUART] Forwarding to Arduino: $arduinoCommand');
      _arduinoManager?.sendCommand(arduinoCommand);
      statusCallback?.call('Command forwarded: $arduinoCommand');
    }
  }

  void _onServerConnectionStatusChanged(bool connected) {
    if (connected) {
      developer.log('[TCPUART] Server connected');
      statusCallback?.call('Server connected');
    } else {
      developer.log('[TCPUART] Server disconnected');
      statusCallback?.call('Server disconnected');
    }
  }

  void _onServerError(String error) {
    developer.log('[TCPUART] Server error: $error');
    statusCallback?.call('Server error: $error');
  }

  // ===== Arduino Callbacks =====

  void _onArduinoConnected() {
    developer.log('[TCPUART] Arduino connected');
    statusCallback?.call('Arduino connected');
  }

  void _onArduinoDisconnected() {
    developer.log('[TCPUART] Arduino disconnected');
    statusCallback?.call('Arduino disconnected');
  }

  void _onArduinoDataReceived(String data) {
    developer.log('[TCPUART] Arduino data: $data');
    _parseArduinoResponse(data);
  }

  void _onArduinoError(String error) {
    developer.log('[TCPUART] Arduino error: $error');
    statusCallback?.call('Arduino error: $error');
  }
}
