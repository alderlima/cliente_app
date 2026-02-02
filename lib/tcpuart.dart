import 'dart:developer' as developer;
import 'package:traccar_client/gt06_protocol.dart';
import 'package:traccar_client/arduino_communication_manager.dart';

/// TCPUART Interface
/// 
/// Bridges TCP communication with Traccar server and UART communication with Arduino.
/// Acts as a central hub for:
/// - Receiving commands from Traccar server
/// - Forwarding commands to Arduino
/// - Receiving responses from Arduino
/// - Sending position data to server

typedef StatusCallback = void Function(String status);

class TCPUART {
  final String deviceId;
  final String serverHost;
  final int serverPort;
  final StatusCallback? statusCallback;

  GT06Protocol? _gt06Protocol;
  ArduinoCommunicationManager? _arduinoManager;

  TCPUART({
    required this.deviceId,
    required this.serverHost,
    required this.serverPort,
    this.statusCallback,
  });

  bool get isConnected => _gt06Protocol?.isConnected ?? false;
  bool get isArduinoConnected => _arduinoManager?.isConnected ?? false;

  /// Initialize TCPUART
  void initialize() {
    developer.log('TCPUART initialized for device: $deviceId');
  }

  /// Start TCPUART - Connect to both server and Arduino
  Future<bool> start() async {
    try {
      developer.log('Starting TCPUART...');

      // Initialize Arduino communication
      _arduinoManager = ArduinoCommunicationManager(
        onConnected: _onArduinoConnected,
        onDisconnected: _onArduinoDisconnected,
        onDataReceived: _onArduinoDataReceived,
        onError: _onArduinoError,
      );

      // Initialize GT06 protocol
      _gt06Protocol = GT06Protocol(
        deviceId: deviceId,
        serverHost: serverHost,
        serverPort: serverPort,
        commandHandler: _onServerCommandReceived,
        connectionStatusHandler: _onServerConnectionStatusChanged,
        errorHandler: _onServerError,
      );

      // Connect to Arduino first
      final arduinoConnected = await _arduinoManager?.connect(baudRate: 9600) ?? false;
      if (!arduinoConnected) {
        developer.log('Failed to connect to Arduino, continuing anyway...');
        statusCallback?.call('Arduino connection failed, continuing...');
      }

      // Connect to Traccar server
      final serverConnected = await _gt06Protocol?.connect() ?? false;
      if (!serverConnected) {
        developer.log('Failed to connect to Traccar server');
        statusCallback?.call('Server connection failed');
        await stop();
        return false;
      }

      developer.log('TCPUART started successfully');
      statusCallback?.call('TCPUART started');
      return true;
    } catch (e) {
      developer.log('Error starting TCPUART: $e');
      statusCallback?.call('Start error: $e');
      return false;
    }
  }

  /// Stop TCPUART - Disconnect from both server and Arduino
  Future<void> stop() async {
    try {
      developer.log('Stopping TCPUART...');
      await _gt06Protocol?.disconnect();
      await _arduinoManager?.disconnect();
      developer.log('TCPUART stopped');
      statusCallback?.call('TCPUART stopped');
    } catch (e) {
      developer.log('Error stopping TCPUART: $e');
    }
  }

  /// Send position data to Traccar server
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
      developer.log('Position sent to server: lat=$latitude, lon=$longitude');
    } catch (e) {
      developer.log('Error sending position: $e');
      statusCallback?.call('Position send error: $e');
    }
  }

  /// Send heartbeat to server
  Future<void> sendHeartbeat() async {
    try {
      await _gt06Protocol?.sendHeartbeat();
      developer.log('Heartbeat sent');
    } catch (e) {
      developer.log('Error sending heartbeat: $e');
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

  /// Parse Arduino response and determine action
  void _parseArduinoResponse(String response) {
    developer.log('Arduino response: $response');

    if (response.startsWith('ACK')) {
      developer.log('Arduino acknowledged: $response');
      statusCallback?.call('Arduino ACK: $response');
    } else if (response.startsWith('ERROR')) {
      developer.log('Arduino error: $response');
      statusCallback?.call('Arduino error: $response');
    } else if (response.startsWith('STATUS')) {
      developer.log('Arduino status: $response');
      statusCallback?.call('Arduino status: $response');
    } else if (response.startsWith('LOG')) {
      developer.log('Arduino log: $response');
      statusCallback?.call('Arduino log: $response');
    } else {
      developer.log('Unknown Arduino response: $response');
    }
  }

  // ===== GT06Protocol Callbacks =====

  void _onServerCommandReceived(GT06Command command) {
    developer.log('Command received from server: $command');

    // Convert Traccar command to Arduino command
    final arduinoCommand = _convertTraccarCommandToArduino(command);
    if (arduinoCommand != null) {
      developer.log('Forwarding to Arduino: $arduinoCommand');
      _arduinoManager?.sendCommand(arduinoCommand);
      statusCallback?.call('Command forwarded: $arduinoCommand');
    } else {
      developer.log('Unknown command type: ${command.commandType}');
    }
  }

  void _onServerConnectionStatusChanged(bool connected) {
    if (connected) {
      developer.log('Connected to Traccar server');
      statusCallback?.call('Server connected');
    } else {
      developer.log('Disconnected from Traccar server');
      statusCallback?.call('Server disconnected');
    }
  }

  void _onServerError(String error) {
    developer.log('GT06 Protocol error: $error');
    statusCallback?.call('Server error: $error');
  }

  // ===== ArduinoCommunicationManager Callbacks =====

  void _onArduinoConnected() {
    developer.log('Connected to Arduino');
    statusCallback?.call('Arduino connected');
  }

  void _onArduinoDisconnected() {
    developer.log('Disconnected from Arduino');
    statusCallback?.call('Arduino disconnected');
  }

  void _onArduinoDataReceived(String data) {
    developer.log('Data received from Arduino: $data');
    _parseArduinoResponse(data);
  }

  void _onArduinoError(String error) {
    developer.log('Arduino error: $error');
    statusCallback?.call('Arduino error: $error');
  }
}
