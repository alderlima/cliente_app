import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'command_log_service.dart';

/// Serviço TCP para comunicação com Arduino
/// Similar ao aplicativo Android TCPUART
/// Permite conectar, enviar comandos e receber dados do Arduino

class ArduinoTCPService {
  static final ArduinoTCPService _instance = ArduinoTCPService._internal();
  factory ArduinoTCPService() => _instance;
  ArduinoTCPService._internal();

  Socket? _socket;
  bool _isConnected = false;
  String _host = '';
  int _port = 80;

  // Stream controllers
  final StreamController<ArduinoConnectionState> _connectionController = 
      StreamController<ArduinoConnectionState>.broadcast();
  final StreamController<ArduinoDataEvent> _dataController = 
      StreamController<ArduinoDataEvent>.broadcast();
  final StreamController<String> _logController = 
      StreamController<String>.broadcast();

  // Buffer para dados recebidos
  final List<String> _receivedDataBuffer = [];
  static const int maxBufferSize = 1000;

  // Getters
  bool get isConnected => _isConnected;
  String get host => _host;
  int get port => _port;
  String get connectionInfo => _isConnected ? '$_host:$_port' : 'Desconectado';
  List<String> get receivedData => List.unmodifiable(_receivedDataBuffer);

  // Streams
  Stream<ArduinoConnectionState> get connectionStream => _connectionController.stream;
  Stream<ArduinoDataEvent> get dataStream => _dataController.stream;
  Stream<String> get logStream => _logController.stream;

  /// Conecta ao Arduino via TCP
  Future<bool> connect(String host, int port, {Duration timeout = const Duration(seconds: 10)}) async {
    if (_isConnected) {
      await disconnect();
    }

    _host = host;
    _port = port;

    try {
      _log('Tentando conectar a $host:$port...');

      _socket = await Socket.connect(host, port, timeout: timeout);
      _isConnected = true;

      _log('✓ Conectado com sucesso a $host:$port');
      
      await CommandLogService.addLog(
        'ARDUINO CONECTADO',
        data: {
          'host': host,
          'port': port,
          'status': 'CONECTADO',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(ArduinoConnectionState(
        status: ConnectionStatus.connected,
        host: host,
        port: port,
        message: 'Conectado a $host:$port',
        timestamp: DateTime.now(),
      ));

      // Inicia listener de dados
      _socket!.listen(
        _handleData,
        onError: _handleError,
        onDone: _handleDisconnect,
        cancelOnError: false,
      );

      return true;
    } on SocketException catch (e) {
      _isConnected = false;
      _log('✗ Erro de conexão: ${e.message}');
      
      await CommandLogService.addLog(
        'ARDUINO ERRO CONEXÃO',
        data: {
          'host': host,
          'port': port,
          'erro': e.message,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(ArduinoConnectionState(
        status: ConnectionStatus.error,
        host: host,
        port: port,
        message: 'Erro: ${e.message}',
        timestamp: DateTime.now(),
      ));

      return false;
    } on TimeoutException {
      _isConnected = false;
      _log('✗ Timeout ao conectar');
      
      await CommandLogService.addLog(
        'ARDUINO TIMEOUT',
        data: {
          'host': host,
          'port': port,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(ArduinoConnectionState(
        status: ConnectionStatus.timeout,
        host: host,
        port: port,
        message: 'Timeout na conexão',
        timestamp: DateTime.now(),
      ));

      return false;
    } catch (e) {
      _isConnected = false;
      _log('✗ Erro: $e');
      
      _connectionController.add(ArduinoConnectionState(
        status: ConnectionStatus.error,
        host: host,
        port: port,
        message: 'Erro: $e',
        timestamp: DateTime.now(),
      ));

      return false;
    }
  }

  /// Desconecta do Arduino
  Future<void> disconnect() async {
    if (!_isConnected && _socket == null) return;

    _log('Desconectando...');

    try {
      await _socket?.close();
    } catch (e) {
      debugPrint('Erro ao fechar socket: $e');
    }

    _socket = null;
    _isConnected = false;

    _log('✓ Desconectado');
    
    await CommandLogService.addLog(
      'ARDUINO DESCONECTADO',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(ArduinoConnectionState(
      status: ConnectionStatus.disconnected,
      host: _host,
      port: _port,
      message: 'Desconectado',
      timestamp: DateTime.now(),
    ));
  }

  /// Envia comando em formato texto (ASCII)
  Future<bool> sendText(String text, {bool addNewline = true}) async {
    if (!_isConnected || _socket == null) {
      _log('✗ Não está conectado');
      return false;
    }

    try {
      String message = addNewline ? '$text\r\n' : text;
      _socket!.write(message);
      await _socket!.flush();

      _log('→ Enviado (TXT): $text');
      
      await CommandLogService.addLog(
        'ARDUINO TX',
        data: {
          'tipo': 'TEXTO',
          'dados': text,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      return true;
    } catch (e) {
      _log('✗ Erro ao enviar: $e');
      return false;
    }
  }

  /// Envia dados em formato hexadecimal
  Future<bool> sendHex(String hexString) async {
    if (!_isConnected || _socket == null) {
      _log('✗ Não está conectado');
      return false;
    }

    try {
      // Remove espaços e converte para bytes
      hexString = hexString.replaceAll(' ', '').replaceAll('0x', '');
      
      if (hexString.length % 2 != 0) {
        _log('✗ String hex inválida (tamanho ímpar)');
        return false;
      }

      List<int> bytes = [];
      for (int i = 0; i < hexString.length; i += 2) {
        String byte = hexString.substring(i, i + 2);
        bytes.add(int.parse(byte, radix: 16));
      }

      _socket!.add(Uint8List.fromList(bytes));
      await _socket!.flush();

      _log('→ Enviado (HEX): $hexString');
      
      await CommandLogService.addLog(
        'ARDUINO TX',
        data: {
          'tipo': 'HEX',
          'dados': hexString,
          'bytes': bytes,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      return true;
    } catch (e) {
      _log('✗ Erro ao enviar HEX: $e');
      return false;
    }
  }

  /// Envia bytes raw
  Future<bool> sendBytes(List<int> bytes) async {
    if (!_isConnected || _socket == null) {
      _log('✗ Não está conectado');
      return false;
    }

    try {
      _socket!.add(Uint8List.fromList(bytes));
      await _socket!.flush();

      String hexStr = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      _log('→ Enviado (RAW): $hexStr');

      return true;
    } catch (e) {
      _log('✗ Erro ao enviar bytes: $e');
      return false;
    }
  }

  /// Manipula dados recebidos
  void _handleData(Uint8List data) {
    // Converte para string ASCII
    String text = utf8.decode(data, allowMalformed: true);
    
    // Converte para hex
    String hex = data.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
    
    // Converte para decimal
    List<int> decimal = data.toList();

    _log('← Recebido: $text');

    // Adiciona ao buffer
    _receivedDataBuffer.add(text);
    if (_receivedDataBuffer.length > maxBufferSize) {
      _receivedDataBuffer.removeAt(0);
    }

    // Notifica listeners
    _dataController.add(ArduinoDataEvent(
      text: text,
      hex: hex,
      decimal: decimal,
      rawBytes: data,
      timestamp: DateTime.now(),
    ));

    // Log no serviço de comandos
    CommandLogService.addLog(
      'ARDUINO RX',
      data: {
        'texto': text,
        'hex': hex,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Manipula erros
  void _handleError(error) async {
    _log('✗ Erro na conexão: $error');
    
    await CommandLogService.addLog(
      'ARDUINO ERRO',
      data: {
        'erro': error.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(ArduinoConnectionState(
      status: ConnectionStatus.error,
      host: _host,
      port: _port,
      message: 'Erro: $error',
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula desconexão
  void _handleDisconnect() async {
    _isConnected = false;
    _socket = null;
    
    _log('Conexão fechada pelo servidor');
    
    await CommandLogService.addLog(
      'ARDUINO DESCONECTADO',
      data: {
        'motivo': 'Conexão fechada pelo servidor',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(ArduinoConnectionState(
      status: ConnectionStatus.disconnected,
      host: _host,
      port: _port,
      message: 'Desconectado pelo servidor',
      timestamp: DateTime.now(),
    ));
  }

  /// Adiciona log interno
  void _log(String message) {
    final logMessage = '[${DateTime.now().toString().substring(11, 19)}] $message';
    _logController.add(logMessage);
    debugPrint('ArduinoTCP: $message');
  }

  /// Limpa o buffer de dados recebidos
  void clearBuffer() {
    _receivedDataBuffer.clear();
    _log('Buffer limpo');
  }

  /// Comandos pré-definidos para Arduino
  static final Map<String, String> predefinedCommands = {
    'LED ON': 'LED_ON',
    'LED OFF': 'LED_OFF',
    'LER SENSOR': 'READ_SENSOR',
    'STATUS': 'STATUS',
    'REINICIAR': 'RESET',
    'PING': 'PING',
    'INFO': 'INFO',
    'TEMPERATURA': 'GET_TEMP',
    'UMIDADE': 'GET_HUM',
    'ANALOG A0': 'READ_A0',
    'ANALOG A1': 'READ_A1',
    'DIGITAL 2': 'READ_D2',
    'DIGITAL 3': 'READ_D3',
    'PWM 5 128': 'PWM_5_128',
    'PWM 6 255': 'PWM_6_255',
  };

  /// Envia comando pré-definido
  Future<bool> sendPredefinedCommand(String commandKey) async {
    final command = predefinedCommands[commandKey];
    if (command != null) {
      return await sendText(command);
    }
    return false;
  }

  /// Libera recursos
  void dispose() {
    disconnect();
    _connectionController.close();
    _dataController.close();
    _logController.close();
  }
}

/// Estados de conexão
enum ConnectionStatus {
  disconnected,
  connecting,
  connected,
  error,
  timeout,
}

class ArduinoConnectionState {
  final ConnectionStatus status;
  final String host;
  final int port;
  final String message;
  final DateTime timestamp;

  ArduinoConnectionState({
    required this.status,
    required this.host,
    required this.port,
    required this.message,
    required this.timestamp,
  });

  bool get isConnected => status == ConnectionStatus.connected;
  bool get hasError => status == ConnectionStatus.error || status == ConnectionStatus.timeout;
}

/// Evento de dados recebidos
class ArduinoDataEvent {
  final String text;
  final String hex;
  final List<int> decimal;
  final Uint8List rawBytes;
  final DateTime timestamp;

  ArduinoDataEvent({
    required this.text,
    required this.hex,
    required this.decimal,
    required this.rawBytes,
    required this.timestamp,
  });
}
