import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'gt06_protocol.dart';
import 'command_log_service.dart';

/// Servidor TCP para protocolo GT06
/// Escuta na porta 5023 e recebe comandos como se fosse um rastreador real

class GT06ServerService {
  static final GT06ServerService _instance = GT06ServerService._internal();
  factory GT06ServerService() => _instance;
  GT06ServerService._internal();

  ServerSocket? _serverSocket;
  final List<Socket> _connectedClients = [];
  bool _isRunning = false;
  int _port = 5023;

  // Stream controllers para notificar listeners
  final StreamController<GT06ConnectionEvent> _connectionController = 
      StreamController<GT06ConnectionEvent>.broadcast();
  final StreamController<GT06CommandEvent> _commandController = 
      StreamController<GT06CommandEvent>.broadcast();

  // Getters
  bool get isRunning => _isRunning;
  int get port => _port;
  int get connectedClientsCount => _connectedClients.length;
  List<Socket> get connectedClients => List.unmodifiable(_connectedClients);
  
  Stream<GT06ConnectionEvent> get connectionStream => _connectionController.stream;
  Stream<GT06CommandEvent> get commandStream => _commandController.stream;

  /// Inicia o servidor GT06 na porta especificada
  Future<void> start({int port = 5023}) async {
    if (_isRunning) {
      await stop();
    }

    _port = port;

    try {
      _serverSocket = await ServerSocket.bind(
        InternetAddress.anyIPv4,
        port,
        shared: true,
      );

      _isRunning = true;

      // Log de inicialização
      await CommandLogService.addLog(
        'SERVIDOR GT06 INICIADO',
        data: {
          'porta': port,
          'endereco': _serverSocket!.address.address,
          'status': 'ONLINE',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(GT06ConnectionEvent(
        type: GT06ConnectionType.serverStarted,
        message: 'Servidor GT06 iniciado na porta $port',
        timestamp: DateTime.now(),
      ));

      // Escuta conexões de clientes
      _serverSocket!.listen(
        _handleClientConnection,
        onError: _handleServerError,
        onDone: _handleServerDone,
      );

    } catch (e) {
      _isRunning = false;
      await CommandLogService.addLog(
        'ERRO AO INICIAR SERVIDOR',
        data: {
          'erro': e.toString(),
          'porta': port,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      throw Exception('Falha ao iniciar servidor GT06: $e');
    }
  }

  /// Para o servidor
  Future<void> stop() async {
    if (!_isRunning) return;

    // Desconecta todos os clientes
    for (var client in List<Socket>.from(_connectedClients)) {
      await _disconnectClient(client, reason: 'Servidor sendo encerrado');
    }
    _connectedClients.clear();

    // Fecha o servidor
    await _serverSocket?.close();
    _serverSocket = null;
    _isRunning = false;

    await CommandLogService.addLog(
      'SERVIDOR GT06 PARADO',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(GT06ConnectionEvent(
      type: GT06ConnectionType.serverStopped,
      message: 'Servidor GT06 parado',
      timestamp: DateTime.now(),
    ));
  }

  /// Reinicia o servidor
  Future<void> restart({int? port}) async {
    await stop();
    await start(port: port ?? _port);
  }

  /// Manipula nova conexão de cliente
  void _handleClientConnection(Socket client) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    _connectedClients.add(client);
    
    CommandLogService.addLog(
      'NOVA CONEXÃO',
      data: {
        'cliente': clientInfo,
        'total_conexoes': _connectedClients.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(GT06ConnectionEvent(
      type: GT06ConnectionType.clientConnected,
      message: 'Cliente conectado: $clientInfo',
      clientAddress: clientInfo,
      timestamp: DateTime.now(),
    ));

    // Escuta dados do cliente
    client.listen(
      (data) => _handleClientData(client, data),
      onError: (error) => _handleClientError(client, error),
      onDone: () => _handleClientDisconnect(client),
      cancelOnError: false,
    );
  }

  /// Manipula dados recebidos do cliente
  void _handleClientData(Socket client, Uint8List data) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    try {
      // Tenta fazer parse como pacote GT06
      GT06Packet? packet = GT06Protocol.parsePacket(data);
      
      if (packet != null) {
        // Pacote GT06 válido
        _handleGT06Packet(client, packet);
      } else {
        // Pode ser um comando do servidor em formato texto
        _handleRawCommand(client, data);
      }
    } catch (e) {
      // Trata como dados raw
      _handleRawCommand(client, data);
    }
  }

  /// Manipula pacote GT06 válido
  void _handleGT06Packet(Socket client, GT06Packet packet) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    // Log do pacote recebido
    CommandLogService.addLog(
      'PACOTE GT06: ${packet.type}',
      data: {
        'cliente': clientInfo,
        'protocolo': '0x${packet.protocolNumber.toRadixString(16).padLeft(2, '0')}',
        'tipo': packet.type,
        'dados': packet.parsedData,
        'raw_hex': GT06Protocol.parsePacket(packet.rawData) != null 
            ? packet.rawData.map((b) => b.toRadixString(16).padLeft(2, '0')).join(' ').toUpperCase()
            : null,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Envia resposta apropriada
    _sendResponse(client, packet);

    // Notifica listeners
    _commandController.add(GT06CommandEvent(
      type: GT06CommandType.protocolPacket,
      command: packet.type,
      data: packet.parsedData,
      rawData: packet.rawData,
      clientAddress: clientInfo,
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula comando raw (possivelmente do servidor)
  void _handleRawCommand(Socket client, Uint8List data) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    // Decodifica o comando
    final decoded = GT06Protocol.decodeServerCommand(data);
    
    // Log do comando recebido
    CommandLogService.addLog(
      'AÇÃO: ${decoded['command_type']}',
      data: {
        'cliente': clientInfo,
        'comando': decoded['command_type'],
        'acao': decoded['action'],
        'raw_hex': decoded['raw_hex'],
        'raw_ascii': decoded['raw_ascii'],
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    // Notifica listeners
    _commandController.add(GT06CommandEvent(
      type: GT06CommandType.serverCommand,
      command: decoded['command_type'],
      data: decoded,
      rawData: data,
      clientAddress: clientInfo,
      timestamp: DateTime.now(),
    ));

    // Envia resposta de confirmação
    _sendCommandAcknowledgment(client, decoded['command_type']);
  }

  /// Envia resposta apropriada baseada no tipo de pacote
  void _sendResponse(Socket client, GT06Packet packet) {
    Uint8List? response;

    switch (packet.protocolNumber) {
      case GT06Protocol.PROTOCOL_LOGIN:
        response = GT06Protocol.createLoginResponse();
        break;
      case GT06Protocol.PROTOCOL_STATUS:
        response = GT06Protocol.createStatusResponse();
        break;
      case GT06Protocol.PROTOCOL_COMMAND:
        // Responde com confirmação de comando
        final message = packet.parsedData['message']?.toString() ?? 'OK';
        response = GT06Protocol.createCommandResponse('CMD:$message:OK');
        break;
      default:
        // Para outros pacotes, apenas confirma recebimento
        response = GT06Protocol.createStatusResponse();
    }

    if (response != null) {
      client.add(response);
    }
  }

  /// Envia confirmação de comando
  void _sendCommandAcknowledgment(Socket client, String commandType) {
    final ackMessage = 'CMD:${commandType}:RECEIVED';
    final response = GT06Protocol.createCommandResponse(ackMessage);
    client.add(response);
  }

  /// Envia comando para um cliente específico
  Future<bool> sendCommandToClient(Socket client, String command) async {
    try {
      final response = GT06Protocol.createCommandResponse(command);
      client.add(response);
      
      final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
      await CommandLogService.addLog(
        'COMANDO ENVIADO',
        data: {
          'cliente': clientInfo,
          'comando': command,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      return true;
    } catch (e) {
      debugPrint('Erro ao enviar comando: $e');
      return false;
    }
  }

  /// Envia comando para todos os clientes conectados
  Future<int> broadcastCommand(String command) async {
    int successCount = 0;
    
    for (var client in List<Socket>.from(_connectedClients)) {
      if (await sendCommandToClient(client, command)) {
        successCount++;
      }
    }
    
    return successCount;
  }

  /// Desconecta um cliente específico
  Future<void> _disconnectClient(Socket client, {String? reason}) async {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    try {
      await CommandLogService.addLog(
        'CLIENTE DESCONECTADO',
        data: {
          'cliente': clientInfo,
          'motivo': reason ?? 'Desconhecido',
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
      await client.close();
    } catch (e) {
      debugPrint('Erro ao desconectar cliente: $e');
    }
    
    _connectedClients.remove(client);
  }

  /// Manipula erro do servidor
  void _handleServerError(error) async {
    await CommandLogService.addLog(
      'ERRO DO SERVIDOR',
      data: {
        'erro': error.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    _connectionController.add(GT06ConnectionEvent(
      type: GT06ConnectionType.serverError,
      message: 'Erro do servidor: $error',
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula encerramento do servidor
  void _handleServerDone() async {
    _isRunning = false;
    await CommandLogService.addLog(
      'SERVIDOR ENCERRADO',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Manipula erro de cliente
  void _handleClientError(Socket client, error) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    CommandLogService.addLog(
      'ERRO DO CLIENTE',
      data: {
        'cliente': clientInfo,
        'erro': error.toString(),
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Manipula desconexão de cliente
  void _handleClientDisconnect(Socket client) {
    final clientInfo = '${client.remoteAddress.address}:${client.remotePort}';
    
    _connectedClients.remove(client);
    
    CommandLogService.addLog(
      'CLIENTE DESCONECTADO',
      data: {
        'cliente': clientInfo,
        'motivo': 'Conexão fechada pelo cliente',
        'conexoes_restantes': _connectedClients.length,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(GT06ConnectionEvent(
      type: GT06ConnectionType.clientDisconnected,
      message: 'Cliente desconectado: $clientInfo',
      clientAddress: clientInfo,
      timestamp: DateTime.now(),
    ));
  }

  /// Libera recursos
  void dispose() {
    stop();
    _connectionController.close();
    _commandController.close();
  }
}

/// Eventos de conexão
enum GT06ConnectionType {
  serverStarted,
  serverStopped,
  serverError,
  clientConnected,
  clientDisconnected,
}

class GT06ConnectionEvent {
  final GT06ConnectionType type;
  final String message;
  final String? clientAddress;
  final DateTime timestamp;

  GT06ConnectionEvent({
    required this.type,
    required this.message,
    this.clientAddress,
    required this.timestamp,
  });
}

/// Eventos de comando
enum GT06CommandType {
  protocolPacket,
  serverCommand,
  unknown,
}

class GT06CommandEvent {
  final GT06CommandType type;
  final String command;
  final Map<String, dynamic> data;
  final Uint8List rawData;
  final String clientAddress;
  final DateTime timestamp;

  GT06CommandEvent({
    required this.type,
    required this.command,
    required this.data,
    required this.rawData,
    required this.clientAddress,
    required this.timestamp,
  });
}
