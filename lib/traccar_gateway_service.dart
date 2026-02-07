import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'gt06_server_service.dart';
import 'gt06_protocol.dart';
import 'arduino_serial_service.dart';
import 'command_log_service.dart';

/// Serviço Gateway Traccar-Arduino
/// Funciona como um bridge entre o servidor Traccar e o Arduino via USB Serial
/// 
/// Fluxo:
/// Servidor Traccar → Comando GT06 (Porta 5023) → Gateway → Arduino (USB Serial)
/// Arduino → Resposta Serial → Gateway → (Opcional: Resposta ao Traccar)

class TraccarGatewayService {
  static final TraccarGatewayService _instance = TraccarGatewayService._internal();
  factory TraccarGatewayService() => _instance;
  TraccarGatewayService._internal();

  // Serviços
  final GT06ServerService _serverService = GT06ServerService();
  final ArduinoSerialService _serialService = ArduinoSerialService();

  // Estado
  bool _isRunning = false;
  bool _autoConnectArduino = true;
  int _baudRate = 9600;
  
  // Subscriptions
  StreamSubscription? _commandSubscription;
  StreamSubscription? _serialDataSubscription;
  StreamSubscription? _serverConnectionSubscription;

  // Stream controllers
  final StreamController<GatewayEvent> _gatewayController = 
      StreamController<GatewayEvent>.broadcast();
  final StreamController<String> _logController = 
      StreamController<String>.broadcast();

  // Estatísticas
  int _commandsReceived = 0;
  int _commandsForwarded = 0;
  int _responsesReceived = 0;
  DateTime? _startTime;

  // Getters
  bool get isRunning => _isRunning;
  bool get isServerRunning => _serverService.isRunning;
  bool get isArduinoConnected => _serialService.isConnected;
  bool get autoConnectArduino => _autoConnectArduino;
  int get baudRate => _baudRate;
  
  int get commandsReceived => _commandsReceived;
  int get commandsForwarded => _commandsForwarded;
  int get responsesReceived => _responsesReceived;
  DateTime? get startTime => _startTime;
  
  String get serverInfo => _serverService.isRunning 
      ? 'Porta ${_serverService.port}' 
      : 'Offline';
  String get arduinoInfo => _serialService.connectionInfo;

  // Streams
  Stream<GatewayEvent> get gatewayStream => _gatewayController.stream;
  Stream<String> get logStream => _logController.stream;

  /// Inicia o Gateway completo
  Future<void> start({
    int serverPort = 5023,
    int baudRate = 9600,
    bool autoConnectArduino = true,
  }) async {
    if (_isRunning) {
      await stop();
    }

    _baudRate = baudRate;
    _autoConnectArduino = autoConnectArduino;
    _commandsReceived = 0;
    _commandsForwarded = 0;
    _responsesReceived = 0;
    _startTime = DateTime.now();

    _log('=== INICIANDO GATEWAY TRACCAR-ARDUINO ===');
    _log('Porta do Servidor: $serverPort');
    _log('Baud Rate: $baudRate');
    _log('Auto-conectar Arduino: $autoConnectArduino');

    try {
      // 1. Inicia o servidor GT06
      await _serverService.start(port: serverPort);
      _log('✓ Servidor GT06 iniciado na porta $serverPort');

      // 2. Configura listeners
      _setupListeners();

      // 3. Tenta conectar ao Arduino automaticamente (se habilitado)
      if (_autoConnectArduino) {
        await _tryConnectArduino();
      }

      _isRunning = true;

      await CommandLogService.addLog(
        'GATEWAY INICIADO',
        data: {
          'porta_servidor': serverPort,
          'baud_rate': baudRate,
          'auto_conectar': autoConnectArduino,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _gatewayController.add(GatewayEvent(
        type: GatewayEventType.started,
        message: 'Gateway iniciado - Porta $serverPort @ ${baudRate}bps',
        timestamp: DateTime.now(),
      ));

    } catch (e) {
      _log('✗ Erro ao iniciar gateway: $e');
      await stop();
      throw Exception('Falha ao iniciar gateway: $e');
    }
  }

  /// Para o Gateway
  Future<void> stop() async {
    if (!_isRunning) return;

    _log('=== PARANDO GATEWAY ===');

    await _commandSubscription?.cancel();
    await _serialDataSubscription?.cancel();
    await _serverConnectionSubscription?.cancel();

    await _serverService.stop();
    await _serialService.disconnect();

    _isRunning = false;
    _startTime = null;

    _log('✓ Gateway parado');

    await CommandLogService.addLog(
      'GATEWAY PARADO',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _gatewayController.add(GatewayEvent(
      type: GatewayEventType.stopped,
      message: 'Gateway parado',
      timestamp: DateTime.now(),
    ));
  }

  /// Reinicia o Gateway
  Future<void> restart() async {
    await stop();
    await start(
      serverPort: _serverService.port,
      baudRate: _baudRate,
      autoConnectArduino: _autoConnectArduino,
    );
  }

  /// Configura listeners de eventos
  void _setupListeners() {
    // Listener de comandos do servidor Traccar
    _commandSubscription = _serverService.commandStream.listen((event) {
      _handleTraccarCommand(event);
    });

    // Listener de dados do Arduino
    _serialDataSubscription = _serialService.dataStream.listen((event) {
      _handleArduinoResponse(event);
    });

    // Listener de conexões do servidor
    _serverConnectionSubscription = _serverService.connectionStream.listen((event) {
      _log('Servidor: ${event.message}');
    });
  }

  /// Manipula comando recebido do Traccar
  Future<void> _handleTraccarCommand(GT06CommandEvent event) async {
    _commandsReceived++;

    _log('');
    _log('=== COMANDO TRACCAR RECEBIDO ===');
    _log('Tipo: ${event.type}');
    _log('Comando: ${event.command}');
    _log('Cliente: ${event.clientAddress}');

    // Log detalhado
    await CommandLogService.addLog(
      'GATEWAY: COMANDO TRACCAR',
      data: {
        'tipo': event.type.toString(),
        'comando': event.command,
        'cliente': event.clientAddress,
        'dados': event.data,
        'raw_hex': event.rawData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Notifica listeners
    _gatewayController.add(GatewayEvent(
      type: GatewayEventType.commandReceived,
      message: 'Comando recebido: ${event.command}',
      data: {
        'command': event.command,
        'type': event.type.toString(),
        'client': event.clientAddress,
      },
      timestamp: DateTime.now(),
    ));

    // Converte o comando para formato adequado ao Arduino
    String? arduinoCommand = _convertToArduinoCommand(event);
    
    if (arduinoCommand != null) {
      await _forwardToArduino(arduinoCommand, event);
    } else {
      _log('⚠ Comando não convertido para Arduino');
    }
  }

  /// Converte comando Traccar para comando Arduino
  String? _convertToArduinoCommand(GT06CommandEvent event) {
    String command = event.command.toUpperCase();
    String? originalMessage;

    // Tenta extrair mensagem original se for pacote GT06
    if (event.data.containsKey('message')) {
      originalMessage = event.data['message'].toString().toUpperCase();
    }

    // Mapeamento de comandos Traccar → Arduino
    final Map<String, String> commandMap = {
      'BLOQUEIO': 'CMD_BLOQUEAR',
      'DESBLOQUEIO': 'CMD_DESBLOQUEAR',
      'STOP': 'CMD_PARAR',
      'RESUME': 'CMD_CONTINUAR',
      'LOCALIZACAO': 'CMD_LOCALIZAR',
      'WHERE': 'CMD_LOCALIZAR',
      'REINICIAR': 'CMD_REINICIAR',
      'RESET': 'CMD_REINICIAR',
      'STATUS': 'CMD_STATUS',
      'PARAMETROS': 'CMD_PARAM',
      'CORTE_COMBUSTIVEL': 'CMD_CORTE_COMBUSTIVEL',
      'RESTAURAR_COMBUSTIVEL': 'CMD_RESTAURAR_COMBUSTIVEL',
    };

    // Tenta encontrar comando pelo tipo
    if (commandMap.containsKey(command)) {
      return commandMap[command];
    }

    // Tenta pela mensagem original
    if (originalMessage != null) {
      for (var key in commandMap.keys) {
        if (originalMessage.contains(key)) {
          return commandMap[key];
        }
      }
    }

    // Se não encontrou mapeamento, envia o comando raw
    if (originalMessage != null && originalMessage.isNotEmpty) {
      return 'CMD:$originalMessage';
    }

    // Retorna o comando como está
    return 'CMD:$command';
  }

  /// Encaminha comando para o Arduino
  Future<void> _forwardToArduino(String command, GT06CommandEvent originalEvent) async {
    _log('');
    _log('=== ENCAMINHANDO PARA ARDUINO ===');
    _log('Comando: $command');

    // Verifica se Arduino está conectado
    if (!_serialService.isConnected) {
      _log('⚠ Arduino não conectado. Tentando reconectar...');
      
      bool connected = await _tryConnectArduino();
      
      if (!connected) {
        _log('✗ Falha ao conectar Arduino. Comando não enviado.');
        
        await CommandLogService.addLog(
          'GATEWAY: ERRO - ARDUINO DESCONECTADO',
          data: {
            'comando': command,
            'erro': 'Arduino não conectado',
            'timestamp': DateTime.now().toIso8601String(),
          },
        );

        _gatewayController.add(GatewayEvent(
          type: GatewayEventType.forwardError,
          message: 'Arduino desconectado - comando não enviado',
          data: {'command': command},
          timestamp: DateTime.now(),
        ));
        return;
      }
    }

    // Envia comando para o Arduino
    bool sent = await _serialService.send(command, addNewline: true);

    if (sent) {
      _commandsForwarded++;
      _log('✓ Comando enviado ao Arduino');

      await CommandLogService.addLog(
        'GATEWAY: ENVIADO AO ARDUINO',
        data: {
          'comando_traccar': originalEvent.command,
          'comando_arduino': command,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _gatewayController.add(GatewayEvent(
        type: GatewayEventType.commandForwarded,
        message: 'Comando enviado ao Arduino: $command',
        data: {
          'traccarCommand': originalEvent.command,
          'arduinoCommand': command,
        },
        timestamp: DateTime.now(),
      ));
    } else {
      _log('✗ Falha ao enviar comando ao Arduino');

      await CommandLogService.addLog(
        'GATEWAY: ERRO AO ENVIAR',
        data: {
          'comando': command,
          'erro': 'Falha na comunicação serial',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _gatewayController.add(GatewayEvent(
        type: GatewayEventType.forwardError,
        message: 'Falha ao enviar comando ao Arduino',
        data: {'command': command},
        timestamp: DateTime.now(),
      ));
    }
  }

  /// Manipula resposta do Arduino
  Future<void> _handleArduinoResponse(SerialDataEvent event) async {
    _responsesReceived++;

    _log('');
    _log('=== RESPOSTA DO ARDUINO ===');
    _log('Dados: ${event.data}');

    await CommandLogService.addLog(
      'GATEWAY: RESPOSTA ARDUINO',
      data: {
        'resposta': event.data,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _gatewayController.add(GatewayEvent(
      type: GatewayEventType.arduinoResponse,
      message: 'Resposta do Arduino: ${event.data}',
      data: {'response': event.data},
      timestamp: DateTime.now(),
    ));

    // Aqui você pode adicionar lógica para enviar resposta de volta ao Traccar
    // Por exemplo, se o Arduino retornar coordenadas GPS, pode enviar de volta
    await _sendResponseToTraccar(event.data);
  }

  /// Envia resposta do Arduino de volta ao servidor Traccar
  Future<void> _sendResponseToTraccar(String response) async {
    // Implementação futura: enviar resposta de volta ao servidor Traccar
    // Isso pode ser útil para enviar dados de sensores, confirmações, etc.
    
    _log('Resposta processada (não enviada ao Traccar - modo unidirecional)');
  }

  /// Tenta conectar ao Arduino automaticamente
  Future<bool> _tryConnectArduino() async {
    _log('Tentando conectar ao Arduino...');
    
    bool connected = await _serialService.autoConnect(baudRate: _baudRate);
    
    if (connected) {
      _log('✓ Arduino conectado automaticamente');
    } else {
      _log('⚠ Arduino não encontrado. Conecte manualmente.');
    }
    
    return connected;
  }

  /// Conecta manualmente a um dispositivo específico
  Future<bool> connectArduino(UsbDevice device) async {
    return await _serialService.connect(device, baudRate: _baudRate);
  }

  /// Desconecta do Arduino
  Future<void> disconnectArduino() async {
    await _serialService.disconnect();
  }

  /// Lista dispositivos USB disponíveis
  Future<List<UsbDevice>> listArduinoDevices() async {
    return await _serialService.listDevices();
  }

  /// Altera baud rate
  Future<void> setBaudRate(int baudRate) async {
    _baudRate = baudRate;
    _log('Baud rate alterado para: $baudRate');
    
    // Se estiver conectado, reconecta com novo baud rate
    if (_serialService.isConnected) {
      _log('Reconectando com novo baud rate...');
      UsbDevice? device = _serialService.connectedDevice;
      if (device != null) {
        await _serialService.disconnect();
        await _serialService.connect(device, baudRate: baudRate);
      }
    }
  }

  /// Envia comando manual para o Arduino (para testes)
  Future<bool> sendManualCommand(String command) async {
    return await _serialService.send(command);
  }

  /// Adiciona log
  void _log(String message) {
    final logMessage = '[${DateTime.now().toString().substring(11, 19)}] $message';
    _logController.add(logMessage);
    debugPrint('Gateway: $message');
  }

  /// Limpa estatísticas
  void clearStats() {
    _commandsReceived = 0;
    _commandsForwarded = 0;
    _responsesReceived = 0;
    _startTime = DateTime.now();
    _log('Estatísticas zeradas');
  }

  /// Libera recursos
  void dispose() {
    stop();
    _gatewayController.close();
    _logController.close();
    _serialService.dispose();
  }
}

/// Eventos do Gateway
enum GatewayEventType {
  started,
  stopped,
  commandReceived,
  commandForwarded,
  forwardError,
  arduinoResponse,
  arduinoConnected,
  arduinoDisconnected,
}

class GatewayEvent {
  final GatewayEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  GatewayEvent({
    required this.type,
    required this.message,
    this.data,
    required this.timestamp,
  });
}
