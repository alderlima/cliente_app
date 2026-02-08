import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'gt06_protocol.dart';

/// ============================================================================
/// CLIENTE GT06 - Conexão TCP com Servidor Traccar
/// ============================================================================
/// 
/// Implementa cliente TCP que se conecta ao servidor Traccar e se comporta
/// exatamente como um rastreador GT06 físico.
///
/// FLUXO:
/// 1. Conectar ao servidor
/// 2. Enviar LOGIN (0x01)
/// 3. Aguardar LOGIN_ACK
/// 4. Iniciar heartbeat periódico
/// 5. Enviar posições GPS
/// 6. Receber e responder comandos
/// ============================================================================

class GT06Client {
  final GT06Protocol _protocol = GT06Protocol();
  
  // Socket
  Socket? _socket;
  
  // Estado
  bool _isConnected = false;
  bool _isLoggedIn = false;
  String _serverAddress = '';
  int _serverPort = 5023;
  String _imei = '';
  int _heartbeatInterval = 30;
  
  // Timers
  Timer? _heartbeatTimer;
  Timer? _reconnectTimer;
  
  // Buffer de recepção
  final List<int> _receiveBuffer = [];
  
  // Stream controllers
  final StreamController<ClientEvent> _eventController = StreamController<ClientEvent>.broadcast();
  final StreamController<String> _commandController = StreamController<String>.broadcast();
  final StreamController<Uint8List> _rawDataController = StreamController<Uint8List>.broadcast();
  
  // Getters
  bool get isConnected => _isConnected;
  bool get isLoggedIn => _isLoggedIn;
  String get serverAddress => _serverAddress;
  int get serverPort => _serverPort;
  String get imei => _imei;
  
  // Streams
  Stream<ClientEvent> get eventStream => _eventController.stream;
  Stream<String> get commandStream => _commandController.stream;
  Stream<Uint8List> get rawDataStream => _rawDataController.stream;

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  /// Conecta ao servidor Traccar
  Future<void> connect({
    required String serverAddress,
    required int serverPort,
    required String imei,
    int heartbeatInterval = 30,
  }) async {
    if (_isConnected) {
      await disconnect();
    }
    
    _serverAddress = serverAddress;
    _serverPort = serverPort;
    _imei = imei;
    _heartbeatInterval = heartbeatInterval;
    _protocol.resetSerial();
    
    _notifyEvent(ClientEventType.connecting, 'Conectando a $serverAddress:$serverPort...');
    
    try {
      // Cria conexão TCP
      _socket = await Socket.connect(
        serverAddress,
        serverPort,
        timeout: const Duration(seconds: 30),
      );
      
      _isConnected = true;
      _notifyEvent(ClientEventType.connected, 'Conectado a $serverAddress:$serverPort');
      
      // Configura listeners
      _setupSocketListeners();
      
      // Envia login
      await _sendLogin();
      
    } catch (e) {
      _isConnected = false;
      _notifyEvent(ClientEventType.error, 'Erro ao conectar: $e');
      _scheduleReconnect(heartbeatInterval);
    }
  }

  /// Configura listeners do socket
  void _setupSocketListeners() {
    if (_socket == null) return;
    
    _socket!.listen(
      _onDataReceived,
      onError: _onSocketError,
      onDone: _onSocketClosed,
      cancelOnError: false,
    );
  }

  /// Desconecta do servidor
  Future<void> disconnect() async {
    _stopTimers();
    
    if (_socket != null) {
      try {
        await _socket!.close();
      } catch (e) {
        // Ignora erro ao fechar
      }
      _socket = null;
    }
    
    _isConnected = false;
    _isLoggedIn = false;
    _receiveBuffer.clear();
    
    _notifyEvent(ClientEventType.disconnected, 'Desconectado do servidor');
  }

  /// ==========================================================================
  /// ENVIO DE PACOTES
  /// ==========================================================================

  /// Envia pacote de LOGIN
  Future<void> _sendLogin() async {
    if (!_isConnected) return;
    
    final packet = _protocol.createLoginPacket(_imei);
    await _sendPacket(packet, 'LOGIN');
    
    _notifyEvent(ClientEventType.loggingIn, 'Enviando login com IMEI: $_imei');
  }

  /// Envia heartbeat
  Future<void> sendHeartbeat() async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createHeartbeatPacket();
    await _sendPacket(packet, 'HEARTBEAT');
  }

  /// Envia posição GPS
  Future<void> sendLocation({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
  }) async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createLocationPacket(
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
      dateTime: dateTime,
    );
    
    await _sendPacket(packet, 'LOCATION');
  }

  /// Envia alarme
  Future<void> sendAlarm({
    required int alarmType,
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
  }) async {
    if (!_isConnected || !_isLoggedIn) return;
    
    final packet = _protocol.createAlarmPacket(
      alarmType: alarmType,
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
    );
    
    await _sendPacket(packet, 'ALARM');
  }

  /// Envia resposta de comando
  Future<void> sendCommandResponse(String response) async {
    if (!_isConnected) return;
    
    final packet = _protocol.createCommandResponse(response);
    await _sendPacket(packet, 'CMD_RESPONSE');
  }

  /// Envia pacote genérico
  Future<void> _sendPacket(Uint8List packet, String type) async {
    if (_socket == null || !_isConnected) {
      throw Exception('Socket não conectado');
    }
    
    try {
      _socket!.add(packet);
      await _socket!.flush();
      
      _notifyEvent(
        ClientEventType.packetSent, 
        'Enviado: $type',
        data: {'hex': GT06Protocol.bytesToHex(packet)},
      );
      
      _rawDataController.add(packet);
      
    } catch (e) {
      _notifyEvent(ClientEventType.error, 'Erro ao enviar $type: $e');
      _handleDisconnection();
    }
  }

  /// ==========================================================================
  /// RECEBIMENTO DE DADOS
  /// ==========================================================================

  /// Manipula dados recebidos
  void _onDataReceived(Uint8List data) {
    _receiveBuffer.addAll(data);
    _rawDataController.add(data);
    
    _notifyEvent(
      ClientEventType.dataReceived,
      'Recebidos ${data.length} bytes',
      data: {'hex': GT06Protocol.bytesToHex(data)},
    );
    
    _processReceiveBuffer();
  }

  /// Processa buffer de recepção
  void _processReceiveBuffer() {
    while (_receiveBuffer.length >= 7) {
      // Procura start bytes
      int startIndex = -1;
      for (int i = 0; i < _receiveBuffer.length - 1; i++) {
        if (_receiveBuffer[i] == GT06Protocol.START_BYTES[0] && 
            _receiveBuffer[i + 1] == GT06Protocol.START_BYTES[1]) {
          startIndex = i;
          break;
        }
      }
      
      if (startIndex == -1) {
        _receiveBuffer.clear();
        return;
      }
      
      // Remove lixo antes do start
      if (startIndex > 0) {
        _receiveBuffer.removeRange(0, startIndex);
      }
      
      if (_receiveBuffer.length < 3) return;
      
      int contentLength = _receiveBuffer[2];
      int packetLength = 2 + 1 + contentLength + 1 + 2;
      
      if (_receiveBuffer.length < packetLength) return;
      
      // Extrai pacote
      final packet = Uint8List.fromList(_receiveBuffer.sublist(0, packetLength));
      _receiveBuffer.removeRange(0, packetLength);
      
      // Processa pacote
      _processPacket(packet);
    }
  }

  /// Processa pacote recebido
  void _processPacket(Uint8List packet) {
    final parsed = _protocol.parseServerPacket(packet);
    
    if (parsed == null) {
      _notifyEvent(ClientEventType.warning, 'Pacote inválido recebido');
      return;
    }
    
    _notifyEvent(
      ClientEventType.packetReceived,
      'Recebido: ${parsed.protocolName}',
      data: {
        'protocol': parsed.protocolNumber,
        'serial': parsed.serialNumber,
        'hex': GT06Protocol.bytesToHex(packet),
      },
    );
    
    switch (parsed.protocolNumber) {
      case GT06Protocol.PROTOCOL_LOGIN:
        _handleLoginAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_STATUS:
        _handleHeartbeatAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_LOCATION:
        _handleLocationAck(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_COMMAND:
        _handleCommand(parsed);
        break;
        
      case GT06Protocol.PROTOCOL_COMMAND_RESPONSE:
        _handleCommandAck(parsed);
        break;
    }
  }

  /// Manipula ACK de login
  void _handleLoginAck(GT06ServerPacket packet) {
    _isLoggedIn = true;
    _notifyEvent(ClientEventType.loggedIn, 'Login aceito pelo servidor!');
    
    // Inicia heartbeat automático após login bem-sucedido
    startHeartbeat(_heartbeatInterval);
  }

  /// Manipula ACK de heartbeat
  void _handleHeartbeatAck(GT06ServerPacket packet) {
    _notifyEvent(ClientEventType.heartbeatAck, 'Heartbeat confirmado');
  }

  /// Manipula ACK de location
  void _handleLocationAck(GT06ServerPacket packet) {
    _notifyEvent(ClientEventType.locationAck, 'Posição confirmada');
  }

  /// Manipula comando do servidor
  void _handleCommand(GT06ServerPacket packet) {
    final command = _protocol.parseCommand(packet);
    
    if (command != null && command.isNotEmpty) {
      _notifyEvent(
        ClientEventType.commandReceived,
        'Comando recebido: $command',
        data: {'command': command},
      );
      
      _commandController.add(command);
      
      // Envia ACK
      sendCommandResponse('CMD OK');
    }
  }

  /// Manipula ACK de comando
  void _handleCommandAck(GT06ServerPacket packet) {
    _notifyEvent(ClientEventType.commandAck, 'Resposta de comando confirmada');
  }

  /// ==========================================================================
  /// HANDLERS DE SOCKET
  /// ==========================================================================

  void _onSocketError(error) {
    _notifyEvent(ClientEventType.error, 'Erro de socket: $error');
    _handleDisconnection();
  }

  void _onSocketClosed() {
    _notifyEvent(ClientEventType.disconnected, 'Conexão fechada pelo servidor');
    _handleDisconnection();
  }

  void _handleDisconnection() {
    if (!_isConnected) return;
    
    _isConnected = false;
    _isLoggedIn = false;
    _stopTimers();
    
    _notifyEvent(ClientEventType.disconnected, 'Desconectado');
  }

  /// ==========================================================================
  /// TIMERS E RECONEXÃO
  /// ==========================================================================

  /// Inicia heartbeat periódico
  void startHeartbeat(int intervalSeconds) {
    _heartbeatTimer?.cancel();
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: intervalSeconds),
      (_) => sendHeartbeat(),
    );
    
    // Envia heartbeat imediatamente também
    sendHeartbeat();
  }

  /// Para timers
  void _stopTimers() {
    _heartbeatTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _reconnectTimer = null;
  }

  /// Agenda reconexão
  void _scheduleReconnect(int delaySeconds) {
    _reconnectTimer?.cancel();
    _reconnectTimer = Timer(Duration(seconds: delaySeconds), () {
      if (!_isConnected) {
        connect(
          serverAddress: _serverAddress,
          serverPort: _serverPort,
          imei: _imei,
          heartbeatInterval: delaySeconds,
        );
      }
    });
  }

  /// ==========================================================================
  /// NOTIFICAÇÕES
  /// ==========================================================================

  void _notifyEvent(ClientEventType type, String message, {Map<String, dynamic>? data}) {
    _eventController.add(ClientEvent(
      type: type,
      message: message,
      timestamp: DateTime.now(),
      data: data,
    ));
  }

  /// Libera recursos
  void dispose() {
    disconnect();
    _eventController.close();
    _commandController.close();
    _rawDataController.close();
  }
}

/// Evento do cliente
class ClientEvent {
  final ClientEventType type;
  final String message;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  ClientEvent({
    required this.type,
    required this.message,
    required this.timestamp,
    this.data,
  });
}

enum ClientEventType {
  connecting,
  connected,
  disconnected,
  error,
  loggingIn,
  loggedIn,
  packetSent,
  packetReceived,
  dataReceived,
  heartbeatAck,
  locationAck,
  commandReceived,
  commandAck,
  warning,
}
