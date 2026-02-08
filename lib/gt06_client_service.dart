import 'dart:async';
import 'dart:io';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'gt06_protocol.dart';
import 'command_log_service.dart';

/// ============================================================================
/// GT06 CLIENT SERVICE - Cliente TCP completo para protocolo GT06
/// ============================================================================
/// 
/// Este serviço implementa um cliente GT06 que se conecta ao servidor Traccar
/// e se comporta EXATAMENTE como um rastreador GT06 físico real.
///
/// FUNCIONALIDADES:
/// - Conexão TCP persistente com o servidor Traccar
/// - Login Packet (0x01) com IMEI
/// - Heartbeat periódico (0x13) para manter online
/// - Location Packet (0x12) com dados GPS
/// - Resposta a comandos do servidor (0x80)
/// - ACKs obrigatórios para todos os pacotes
/// - Reconexão automática em caso de queda
/// - Parsing completo de comandos recebidos
///
/// FLUXO DO PROTOCOLO GT06:
/// 1. Cliente → LOGIN (0x01) → Servidor
/// 2. Servidor → LOGIN ACK → Cliente
/// 3. Cliente → HEARTBEAT (0x13) → Servidor (a cada 30s)
/// 4. Servidor → HEARTBEAT ACK → Cliente
/// 5. Cliente → LOCATION (0x12) → Servidor (a cada X segundos)
/// 6. Servidor → LOCATION ACK → Cliente
/// 7. Servidor → COMMAND (0x80) → Cliente
/// 8. Cliente → COMMAND ACK → Servidor
/// ============================================================================

class GT06ClientService {
  static final GT06ClientService _instance = GT06ClientService._internal();
  factory GT06ClientService() => _instance;
  GT06ClientService._internal();

  // ==========================================================================
  // CONFIGURAÇÕES
  // ==========================================================================
  
  /// Servidor Traccar
  String _serverAddress = '127.0.0.1';
  int _serverPort = 5023;
  
  /// IMEI do dispositivo (15 dígitos)
  String _imei = '000000000000000';
  
  /// Intervalo de heartbeat em segundos (padrão: 30s)
  int _heartbeatInterval = 30;
  
  /// Intervalo de envio de posição GPS em segundos (padrão: 60s)
  int _locationInterval = 60;
  
  /// Timeout de reconexão em segundos
  int _reconnectDelay = 10;
  
  /// Número de tentativas de reconexão (-1 = infinito)
  int _maxReconnectAttempts = -1;

  // ==========================================================================
  // ESTADO INTERNO
  // ==========================================================================
  
  /// Socket TCP conectado ao servidor
  Socket? _socket;
  
  /// Estado da conexão
  bool _isConnected = false;
  bool _isConnecting = false;
  bool _shouldBeConnected = false;
  
  /// Login bem-sucedido
  bool _isLoggedIn = false;
  
  /// Contador de reconexões
  int _reconnectAttempts = 0;
  
  /// Número de série incremental para pacotes
  int _serialNumber = 1;
  
  /// Buffer de dados recebidos (para pacotes fragmentados)
  final List<int> _receiveBuffer = [];
  
  /// Timers
  Timer? _heartbeatTimer;
  Timer? _locationTimer;
  Timer? _reconnectTimer;
  
  /// Última posição GPS conhecida
  GT06Position? _lastPosition;
  
  /// Timestamp da última comunicação
  DateTime? _lastCommunication;

  // ==========================================================================
  // STREAM CONTROLLERS
  // ==========================================================================
  
  final StreamController<GT06ClientEvent> _eventController = 
      StreamController<GT06ClientEvent>.broadcast();
  final StreamController<GT06Command> _commandController = 
      StreamController<GT06Command>.broadcast();
  final StreamController<String> _logController = 
      StreamController<String>.broadcast();

  // ==========================================================================
  // GETTERS
  // ==========================================================================
  
  bool get isConnected => _isConnected;
  bool get isLoggedIn => _isLoggedIn;
  bool get isRunning => _shouldBeConnected;
  String get serverAddress => _serverAddress;
  int get serverPort => _serverPort;
  String get imei => _imei;
  DateTime? get lastCommunication => _lastCommunication;
  
  Stream<GT06ClientEvent> get eventStream => _eventController.stream;
  Stream<GT06Command> get commandStream => _commandController.stream;
  Stream<String> get logStream => _logController.stream;

  // ==========================================================================
  // INICIALIZAÇÃO E CONEXÃO
  // ==========================================================================
  
  /// Inicializa o cliente com configurações
  void initialize({
    required String serverAddress,
    required int serverPort,
    required String imei,
    int heartbeatInterval = 30,
    int locationInterval = 60,
    int reconnectDelay = 10,
    int maxReconnectAttempts = -1,
  }) {
    _serverAddress = serverAddress;
    _serverPort = serverPort;
    _imei = _validateImei(imei);
    _heartbeatInterval = heartbeatInterval;
    _locationInterval = locationInterval;
    _reconnectDelay = reconnectDelay;
    _maxReconnectAttempts = maxReconnectAttempts;
    
    _log('GT06 Client inicializado:');
    _log('  Servidor: $_serverAddress:$_serverPort');
    _log('  IMEI: $_imei');
    _log('  Heartbeat: ${_heartbeatInterval}s');
    _log('  Location: ${_locationInterval}s');
  }

  /// Conecta ao servidor Traccar
  Future<void> connect() async {
    if (_isConnected || _isConnecting) {
      _log('Já conectado ou conectando...');
      return;
    }

    _isConnecting = true;
    _shouldBeConnected = true;
    _reconnectAttempts = 0;

    await _performConnection();
  }

  /// Realiza a conexão TCP
  Future<void> _performConnection() async {
    try {
      _log('=== CONECTANDO AO SERVIDOR TRACCAR ===');
      _log('Servidor: $_serverAddress:$_serverPort');

      // Limpa socket anterior se existir
      await _cleanupSocket();

      // Cria conexão TCP
      _socket = await Socket.connect(
        _serverAddress,
        _serverPort,
        timeout: const Duration(seconds: 30),
      );

      _isConnected = true;
      _isConnecting = false;
      _reconnectAttempts = 0;
      _lastCommunication = DateTime.now();

      _log('✓ Conexão TCP estabelecida');

      // Configura listeners do socket
      _setupSocketListeners();

      // Notifica conexão
      _eventController.add(GT06ClientEvent(
        type: GT06ClientEventType.connected,
        message: 'Conectado a $_serverAddress:$_serverPort',
        timestamp: DateTime.now(),
      ));

      await CommandLogService.addLog(
        'GT06 CLIENT: CONECTADO',
        data: {
          'servidor': '$_serverAddress:$_serverPort',
          'imei': _imei,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      // Envia pacote de login
      await _sendLoginPacket();

    } catch (e) {
      _isConnecting = false;
      _isConnected = false;
      _log('✗ Erro na conexão: $e');
      
      _eventController.add(GT06ClientEvent(
        type: GT06ClientEventType.connectionError,
        message: 'Erro de conexão: $e',
        timestamp: DateTime.now(),
      ));

      // Agenda reconexão
      _scheduleReconnect();
    }
  }

  /// Configura listeners do socket
  void _setupSocketListeners() {
    if (_socket == null) return;

    // Listener de dados
    _socket!.listen(
      _handleReceivedData,
      onError: _handleSocketError,
      onDone: _handleSocketClosed,
      cancelOnError: false,
    );
  }

  /// Limpa o socket anterior
  Future<void> _cleanupSocket() async {
    try {
      await _socket?.close();
    } catch (e) {
      // Ignora erros ao fechar
    }
    _socket = null;
    _isConnected = false;
    _isLoggedIn = false;
  }

  // ==========================================================================
  // ENVIO DE PACOTES
  // ==========================================================================
  
  /// Envia pacote de LOGIN (0x01)
  Future<void> _sendLoginPacket() async {
    _log('Enviando pacote de LOGIN...');

    // Converte IMEI para BCD (8 bytes para 15 dígitos)
    final imeiBytes = _imeiToBCD(_imei);
    
    // Conteúdo do pacote: IMEI (8 bytes) + Serial (2 bytes)
    final content = BytesBuilder();
    content.add(imeiBytes);
    content.add(_getSerialNumberBytes());

    final packet = _buildPacket(GT06Protocol.PROTOCOL_LOGIN, content.toBytes());
    
    await _sendPacket(packet);
    
    _log('✓ Login enviado - IMEI: $_imei');
  }

  /// Envia pacote de HEARTBEAT (0x13)
  Future<void> _sendHeartbeatPacket() async {
    if (!_isConnected || !_isLoggedIn) {
      _log('Não pode enviar heartbeat: não conectado ou não logado');
      return;
    }

    // Conteúdo do heartbeat: Terminal Info + Voltage + GSM Signal + Alarm/Language + Serial
    final content = BytesBuilder();
    
    // Terminal Info (1 byte)
    // Bit 0: ACC ON/OFF
    // Bit 1: GPS posicionado
    // Bit 2-3: Status
    // Bit 4: GPS real-time
    // Bit 5: Estado do relé
    int terminalInfo = 0x00;
    terminalInfo |= 0x01; // ACC ON
    terminalInfo |= 0x02; // GPS posicionado
    terminalInfo |= 0x40; // GPS real-time
    content.addByte(terminalInfo);
    
    // Voltage Level (1 byte) - 0x04 = normal
    content.addByte(0x04);
    
    // GSM Signal (1 byte) - 0x04 = bom sinal
    content.addByte(0x04);
    
    // Alarm/Language (2 bytes) - 0x0000 = normal
    content.add([0x00, 0x00]);
    
    // Serial Number (2 bytes)
    content.add(_getSerialNumberBytes());

    final packet = _buildPacket(GT06Protocol.PROTOCOL_STATUS, content.toBytes());
    
    await _sendPacket(packet);
    
    _log('♥ Heartbeat enviado');
  }

  /// Envia pacote de LOCATION/GPS (0x12)
  Future<void> sendLocationPacket({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    bool gpsValid = true,
    DateTime? dateTime,
  }) async {
    if (!_isConnected || !_isLoggedIn) {
      _log('Não pode enviar location: não conectado ou não logado');
      return;
    }

    dateTime ??= DateTime.now();

    // Salva posição
    _lastPosition = GT06Position(
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
      timestamp: dateTime,
      gpsValid: gpsValid,
    );

    final content = BytesBuilder();
    
    // Date/Time (6 bytes): YY MM DD HH MM SS
    content.addByte(dateTime.year - 2000);
    content.addByte(dateTime.month);
    content.addByte(dateTime.day);
    content.addByte(dateTime.hour);
    content.addByte(dateTime.minute);
    content.addByte(dateTime.second);
    
    // GPS Count (1 byte) - número de satélites
    content.addByte(gpsValid ? 8 : 0);
    
    // Latitude (4 bytes) - graus * 30000 * 60
    final latValue = (_coordinateToGT06(latitude)).toInt();
    content.add(_intToBytes(latValue, 4));
    
    // Longitude (4 bytes)
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    content.add(_intToBytes(lonValue, 4));
    
    // Speed (1 byte) - km/h
    content.addByte(speed.toInt());
    
    // Course/Status (2 bytes)
    int courseStatus = ((course ~/ 10) & 0x03FF);
    if (gpsValid) courseStatus |= 0x1000; // GPS valid
    if (latitude < 0) courseStatus |= 0x0400; // South
    if (longitude < 0) courseStatus |= 0x0800; // West
    content.add(_intToBytes(courseStatus, 2));
    
    // Serial Number (2 bytes)
    content.add(_getSerialNumberBytes());

    final packet = _buildPacket(GT06Protocol.PROTOCOL_LOCATION, content.toBytes());
    
    await _sendPacket(packet);
    
    _log('📍 Location enviado: $latitude, $longitude (speed: ${speed.toStringAsFixed(1)} km/h)');
  }

  /// Envia pacote de ALARM (0x16)
  Future<void> sendAlarmPacket({
    required int alarmType,
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
  }) async {
    if (!_isConnected || !_isLoggedIn) return;

    final dateTime = DateTime.now();
    
    final content = BytesBuilder();
    
    // Date/Time (6 bytes)
    content.addByte(dateTime.year - 2000);
    content.addByte(dateTime.month);
    content.addByte(dateTime.day);
    content.addByte(dateTime.hour);
    content.addByte(dateTime.minute);
    content.addByte(dateTime.second);
    
    // Alarm Type (1 byte)
    content.addByte(alarmType);
    
    // GPS Count
    content.addByte(8);
    
    // Latitude
    final latValue = (_coordinateToGT06(latitude)).toInt();
    content.add(_intToBytes(latValue, 4));
    
    // Longitude
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    content.add(_intToBytes(lonValue, 4));
    
    // Speed
    content.addByte(speed.toInt());
    
    // Course/Status
    int courseStatus = ((course ~/ 10) & 0x03FF);
    courseStatus |= 0x1000;
    content.add(_intToBytes(courseStatus, 2));
    
    // Alarm Status (4 bytes)
    content.add([0x00, 0x00, 0x00, 0x00]);
    
    // Serial Number
    content.add(_getSerialNumberBytes());

    final packet = _buildPacket(GT06Protocol.PROTOCOL_ALARM, content.toBytes());
    await _sendPacket(packet);
    
    _log('🚨 Alarm enviado: tipo=$alarmType');
  }

  /// Envia ACK para comando recebido
  Future<void> _sendCommandAck(String commandId) async {
    if (!_isConnected) return;

    final content = BytesBuilder();
    
    // Flag do servidor (1 byte)
    content.addByte(0x00);
    
    // Tipo de comando (1 byte) - 0x01 = texto
    content.addByte(0x01);
    
    // Comando de resposta
    final responseText = 'CMD OK:$commandId';
    final commandBytes = Uint8List.fromList(responseText.codeUnits);
    
    // Tamanho do comando (2 bytes, big-endian)
    content.add(_intToBytes(commandBytes.length, 2));
    
    // Comando
    content.add(commandBytes);
    
    // Serial Number
    content.add(_getSerialNumberBytes());

    final packet = _buildPacket(GT06Protocol.PROTOCOL_COMMAND_RESPONSE, content.toBytes());
    await _sendPacket(packet);
    
    _log('✓ ACK de comando enviado');
  }

  /// Envia ACK genérico
  Future<void> _sendAck(int protocolNumber, {int? serialNumber}) async {
    if (!_isConnected) return;

    final content = BytesBuilder();
    content.addByte(0x00); // Status OK
    
    if (serialNumber != null) {
      content.add(_intToBytes(serialNumber, 2));
    } else {
      content.add(_getSerialNumberBytes());
    }

    final packet = _buildPacket(protocolNumber, content.toBytes());
    await _sendPacket(packet);
  }

  /// Constrói pacote GT06 completo
  Uint8List _buildPacket(int protocolNumber, Uint8List content) {
    final builder = BytesBuilder();
    
    // Start Bytes (2 bytes)
    builder.add(GT06Protocol.START_BYTES);
    
    // Content Length (1 byte) - tamanho do protocolo + conteúdo + serial
    builder.addByte(content.length + 1);
    
    // Protocol Number (1 byte)
    builder.addByte(protocolNumber);
    
    // Content
    builder.add(content);
    
    // Calcula checksum (XOR de tudo após start bytes)
    final packetWithoutChecksum = builder.toBytes();
    final checksum = _calculateChecksum(packetWithoutChecksum.sublist(2));
    builder.addByte(checksum);
    
    // Stop Bytes (2 bytes)
    builder.add(GT06Protocol.STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Envia pacote pelo socket
  Future<void> _sendPacket(Uint8List packet) async {
    if (_socket == null || !_isConnected) {
      throw Exception('Socket não conectado');
    }

    try {
      _socket!.add(packet);
      await _socket!.flush();
      _lastCommunication = DateTime.now();
      
      // Incrementa serial number
      _serialNumber = (_serialNumber + 1) & 0xFFFF;
      if (_serialNumber == 0) _serialNumber = 1;
      
    } catch (e) {
      _log('✗ Erro ao enviar pacote: $e');
      _handleDisconnection('Erro ao enviar: $e');
      throw;
    }
  }

  // ==========================================================================
  // RECEBIMENTO DE DADOS
  // ==========================================================================
  
  /// Manipula dados recebidos do servidor
  void _handleReceivedData(Uint8List data) {
    _lastCommunication = DateTime.now();
    
    // Adiciona ao buffer
    _receiveBuffer.addAll(data);
    
    // Processa pacotes completos no buffer
    _processReceiveBuffer();
  }

  /// Processa o buffer de recepção extraindo pacotes completos
  void _processReceiveBuffer() {
    while (_receiveBuffer.length >= 5) {
      // Procura por start bytes
      int startIndex = -1;
      for (int i = 0; i < _receiveBuffer.length - 1; i++) {
        if (_receiveBuffer[i] == GT06Protocol.START_BYTES[0] &&
            _receiveBuffer[i + 1] == GT06Protocol.START_BYTES[1]) {
          startIndex = i;
          break;
        }
      }
      
      // Se não encontrou start bytes, limpa buffer
      if (startIndex == -1) {
        _receiveBuffer.clear();
        return;
      }
      
      // Remove lixo antes do start byte
      if (startIndex > 0) {
        _receiveBuffer.removeRange(0, startIndex);
      }
      
      // Verifica se tem bytes suficientes para o header
      if (_receiveBuffer.length < 3) return;
      
      // Pega o tamanho do conteúdo
      int contentLength = _receiveBuffer[2];
      int packetLength = 2 + 1 + contentLength + 1 + 2; // start + length byte + content + checksum + stop
      
      // Verifica se tem o pacote completo
      if (_receiveBuffer.length < packetLength) return;
      
      // Extrai o pacote
      final packet = Uint8List.fromList(_receiveBuffer.sublist(0, packetLength));
      _receiveBuffer.removeRange(0, packetLength);
      
      // Processa o pacote
      _processReceivedPacket(packet);
    }
  }

  /// Processa um pacote GT06 recebido
  void _processReceivedPacket(Uint8List packet) {
    try {
      // Verifica start bytes
      if (packet[0] != GT06Protocol.START_BYTES[0] || 
          packet[1] != GT06Protocol.START_BYTES[1]) {
        _log('⚠ Pacote inválido: start bytes incorretos');
        return;
      }
      
      // Verifica stop bytes
      if (packet[packet.length - 2] != GT06Protocol.STOP_BYTES[0] || 
          packet[packet.length - 1] != GT06Protocol.STOP_BYTES[1]) {
        _log('⚠ Pacote inválido: stop bytes incorretos');
        return;
      }
      
      // Verifica checksum
      int contentLength = packet[2];
      int expectedChecksum = packet[2 + 1 + contentLength];
      Uint8List contentForChecksum = Uint8List.fromList(packet.sublist(2, 2 + 1 + contentLength));
      int calculatedChecksum = _calculateChecksum(contentForChecksum);
      
      if (expectedChecksum != calculatedChecksum) {
        _log('⚠ Checksum inválido: esperado=$expectedChecksum, calculado=$calculatedChecksum');
        // Continua processando mesmo com checksum inválido (alguns servidores podem ter variações)
      }
      
      // Extrai protocol number
      int protocolNumber = packet[3];
      
      // Extrai serial number (últimos 2 bytes antes do checksum)
      int serialNumber = (packet[packet.length - 4] << 8) | packet[packet.length - 3];
      
      _log('📥 Pacote recebido: 0x${protocolNumber.toRadixString(16).padLeft(2, '0')} (serial: $serialNumber)');
      
      // Processa baseado no tipo de pacote
      switch (protocolNumber) {
        case GT06Protocol.PROTOCOL_LOGIN:
          _handleLoginAck(packet);
          break;
          
        case GT06Protocol.PROTOCOL_STATUS:
          _handleHeartbeatAck(packet);
          break;
          
        case GT06Protocol.PROTOCOL_LOCATION:
          _handleLocationAck(packet);
          break;
          
        case GT06Protocol.PROTOCOL_COMMAND:
          _handleServerCommand(packet);
          break;
          
        case GT06Protocol.PROTOCOL_COMMAND_RESPONSE:
          _handleCommandResponseAck(packet);
          break;
          
        default:
          _log('ℹ Pacote não tratado: 0x${protocolNumber.toRadixString(16)}');
          // Envia ACK genérico
          _sendAck(protocolNumber, serialNumber: serialNumber);
      }
      
    } catch (e) {
      _log('✗ Erro ao processar pacote: $e');
    }
  }

  /// Manipula ACK de login
  void _handleLoginAck(Uint8List packet) {
    _log('✓ LOGIN ACK recebido - Dispositivo autenticado!');
    _isLoggedIn = true;
    
    // Inicia timers
    _startTimers();
    
    _eventController.add(GT06ClientEvent(
      type: GT06ClientEventType.loggedIn,
      message: 'Login aceito pelo servidor',
      timestamp: DateTime.now(),
    ));
    
    CommandLogService.addLog(
      'GT06 CLIENT: LOGIN ACEITO',
      data: {
        'imei': _imei,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Manipula ACK de heartbeat
  void _handleHeartbeatAck(Uint8List packet) {
    _log('✓ HEARTBEAT ACK recebido');
    
    _eventController.add(GT06ClientEvent(
      type: GT06ClientEventType.heartbeatAck,
      message: 'Heartbeat confirmado',
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula ACK de location
  void _handleLocationAck(Uint8List packet) {
    _log('✓ LOCATION ACK recebido');
    
    _eventController.add(GT06ClientEvent(
      type: GT06ClientEventType.locationAck,
      message: 'Location confirmado',
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula ACK de comando
  void _handleCommandResponseAck(Uint8List packet) {
    _log('✓ COMMAND ACK recebido');
  }

  /// Manipula comando do servidor
  void _handleServerCommand(Uint8List packet) {
    try {
      // Extrai o comando do pacote
      // Formato: [start][len][0x80][flag][type][len_hi][len_lo][command...][serial][checksum][stop]
      
      int contentLength = packet[2];
      int commandType = packet[5];
      int commandLength = (packet[6] << 8) | packet[7];
      
      String commandText = '';
      if (commandLength > 0 && packet.length >= 8 + commandLength) {
        commandText = String.fromCharCodes(packet.sublist(8, 8 + commandLength));
      }
      
      _log('📟 COMANDO DO SERVIDOR: $commandText');
      
      // Envia ACK
      _sendCommandAck(commandText);
      
      // Decodifica o comando
      final decodedCommand = _decodeCommand(commandText);
      
      // Notifica listeners
      _commandController.add(decodedCommand);
      
      _eventController.add(GT06ClientEvent(
        type: GT06ClientEventType.commandReceived,
        message: 'Comando recebido: $commandText',
        data: {'command': commandText, 'type': commandType},
        timestamp: DateTime.now(),
      ));
      
      CommandLogService.addLog(
        'GT06 CLIENT: COMANDO RECEBIDO',
        data: {
          'comando': commandText,
          'tipo': commandType,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );
      
    } catch (e) {
      _log('✗ Erro ao processar comando: $e');
    }
  }

  /// Decodifica comando recebido
  GT06Command _decodeCommand(String commandText) {
    String upperCommand = commandText.toUpperCase();
    GT06CommandType type = GT06CommandType.unknown;
    String action = '';
    
    if (upperCommand.contains('STOP') || upperCommand.contains('CUT') || upperCommand.contains('BLOQUEAR')) {
      type = GT06CommandType.block;
      action = 'Bloquear veículo';
    } else if (upperCommand.contains('RESUME') || upperCommand.contains('RESTORE') || upperCommand.contains('DESBLOQUEAR')) {
      type = GT06CommandType.unblock;
      action = 'Desbloquear veículo';
    } else if (upperCommand.contains('WHERE') || upperCommand.contains('LOCATE') || upperCommand.contains('POSITION')) {
      type = GT06CommandType.locate;
      action = 'Solicitar localização';
    } else if (upperCommand.contains('RESET') || upperCommand.contains('REBOOT')) {
      type = GT06CommandType.reboot;
      action = 'Reiniciar dispositivo';
    } else if (upperCommand.contains('STATUS')) {
      type = GT06CommandType.status;
      action = 'Solicitar status';
    } else if (upperCommand.contains('PARAM')) {
      type = GT06CommandType.parameters;
      action = 'Configurar parâmetros';
    }
    
    return GT06Command(
      type: type,
      rawCommand: commandText,
      action: action,
      timestamp: DateTime.now(),
    );
  }

  // ==========================================================================
  // TIMERS E RECONEXÃO
  // ==========================================================================
  
  /// Inicia timers de heartbeat e location
  void _startTimers() {
    _stopTimers();
    
    // Timer de heartbeat
    _heartbeatTimer = Timer.periodic(
      Duration(seconds: _heartbeatInterval),
      (_) => _sendHeartbeatPacket(),
    );
    
    // Timer de location
    _locationTimer = Timer.periodic(
      Duration(seconds: _locationInterval),
      (_) => _sendPeriodicLocation(),
    );
    
    _log('Timers iniciados (heartbeat: ${_heartbeatInterval}s, location: ${_locationInterval}s)');
  }

  /// Para todos os timers
  void _stopTimers() {
    _heartbeatTimer?.cancel();
    _locationTimer?.cancel();
    _reconnectTimer?.cancel();
    _heartbeatTimer = null;
    _locationTimer = null;
    _reconnectTimer = null;
  }

  /// Envia location periódico (usa última posição conhecida ou posição padrão)
  Future<void> _sendPeriodicLocation() async {
    if (_lastPosition != null) {
      await sendLocationPacket(
        latitude: _lastPosition!.latitude,
        longitude: _lastPosition!.longitude,
        speed: _lastPosition!.speed,
        course: _lastPosition!.course,
        gpsValid: _lastPosition!.gpsValid,
      );
    }
  }

  /// Agenda reconexão automática
  void _scheduleReconnect() {
    if (!_shouldBeConnected) return;
    
    if (_maxReconnectAttempts > 0 && _reconnectAttempts >= _maxReconnectAttempts) {
      _log('Máximo de tentativas de reconexão atingido');
      return;
    }
    
    _reconnectAttempts++;
    
    _log('Agendando reconexão em $_reconnectDelay segundos (tentativa $_reconnectAttempts)...');
    
    _reconnectTimer = Timer(Duration(seconds: _reconnectDelay), () {
      if (_shouldBeConnected && !_isConnected) {
        _performConnection();
      }
    });
  }

  // ==========================================================================
  // HANDLERS DE SOCKET
  // ==========================================================================
  
  /// Manipula erro do socket
  void _handleSocketError(error) {
    _log('✗ Erro do socket: $error');
    _handleDisconnection('Erro: $error');
  }

  /// Manipula fechamento do socket
  void _handleSocketClosed() {
    _log('Socket fechado pelo servidor');
    _handleDisconnection('Conexão fechada');
  }

  /// Manipula desconexão
  void _handleDisconnection(String reason) {
    if (!_isConnected) return;
    
    _isConnected = false;
    _isLoggedIn = false;
    _stopTimers();
    
    _log('=== DESCONECTADO: $reason ===');
    
    _eventController.add(GT06ClientEvent(
      type: GT06ClientEventType.disconnected,
      message: 'Desconectado: $reason',
      timestamp: DateTime.now(),
    ));
    
    CommandLogService.addLog(
      'GT06 CLIENT: DESCONECTADO',
      data: {
        'motivo': reason,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
    
    // Agenda reconexão
    if (_shouldBeConnected) {
      _scheduleReconnect();
    }
  }

  // ==========================================================================
  // MÉTODOS PÚBLICOS
  // ==========================================================================
  
  /// Desconecta do servidor
  Future<void> disconnect() async {
    _log('=== DESCONECTANDO ===');
    
    _shouldBeConnected = false;
    _stopTimers();
    
    await _cleanupSocket();
    
    _isConnected = false;
    _isLoggedIn = false;
    _isConnecting = false;
    
    _eventController.add(GT06ClientEvent(
      type: GT06ClientEventType.disconnected,
      message: 'Desconectado manualmente',
      timestamp: DateTime.now(),
    ));
    
    _log('✓ Desconectado');
  }

  /// Atualiza a posição GPS atual
  void updatePosition({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    bool gpsValid = true,
  }) {
    _lastPosition = GT06Position(
      latitude: latitude,
      longitude: longitude,
      speed: speed,
      course: course,
      timestamp: DateTime.now(),
      gpsValid: gpsValid,
    );
  }

  /// Envia posição atual imediatamente
  Future<void> sendCurrentPosition() async {
    if (_lastPosition != null) {
      await sendLocationPacket(
        latitude: _lastPosition!.latitude,
        longitude: _lastPosition!.longitude,
        speed: _lastPosition!.speed,
        course: _lastPosition!.course,
        gpsValid: _lastPosition!.gpsValid,
      );
    } else {
      _log('⚠ Nenhuma posição disponível para enviar');
    }
  }

  /// Envia alarme SOS
  Future<void> sendSosAlarm({
    required double latitude,
    required double longitude,
  }) async {
    await sendAlarmPacket(
      alarmType: 0x01, // SOS
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Envia alarme de excesso de velocidade
  Future<void> sendOverspeedAlarm({
    required double latitude,
    required double longitude,
    required double speed,
  }) async {
    await sendAlarmPacket(
      alarmType: 0x06, // Overspeed
      latitude: latitude,
      longitude: longitude,
      speed: speed,
    );
  }

  /// Envia alarme de corte de energia
  Future<void> sendPowerCutAlarm({
    required double latitude,
    required double longitude,
  }) async {
    await sendAlarmPacket(
      alarmType: 0x02, // Power cut
      latitude: latitude,
      longitude: longitude,
    );
  }

  /// Altera intervalo de heartbeat
  void setHeartbeatInterval(int seconds) {
    _heartbeatInterval = seconds;
    if (_isLoggedIn) {
      _stopTimers();
      _startTimers();
    }
    _log('Intervalo de heartbeat alterado para ${seconds}s');
  }

  /// Altera intervalo de location
  void setLocationInterval(int seconds) {
    _locationInterval = seconds;
    if (_isLoggedIn) {
      _stopTimers();
      _startTimers();
    }
    _log('Intervalo de location alterado para ${seconds}s');
  }

  /// Altera IMEI (requer reconexão)
  void setImei(String imei) {
    _imei = _validateImei(imei);
    _log('IMEI alterado para: $_imei');
  }

  /// Altera servidor (requer reconexão)
  void setServer(String address, int port) {
    _serverAddress = address;
    _serverPort = port;
    _log('Servidor alterado para: $_serverAddress:$_serverPort');
  }

  // ==========================================================================
  // HELPERS
  // ==========================================================================
  
  /// Valida e formata IMEI
  String _validateImei(String imei) {
    // Remove caracteres não numéricos
    String cleanImei = imei.replaceAll(RegExp(r'[^0-9]'), '');
    
    // Completa ou trunca para 15 dígitos
    if (cleanImei.length < 15) {
      cleanImei = cleanImei.padLeft(15, '0');
    } else if (cleanImei.length > 15) {
      cleanImei = cleanImei.substring(0, 15);
    }
    
    return cleanImei;
  }

  /// Converte IMEI para BCD (8 bytes para 15 dígitos)
  Uint8List _imeiToBCD(String imei) {
    final bytes = <int>[];
    
    for (int i = 0; i < imei.length; i += 2) {
      if (i + 1 < imei.length) {
        // Dois dígitos: segundo dígito nos 4 bits altos, primeiro nos baixos
        int high = imei[i + 1].codeUnitAt(0) - 0x30; // ASCII '0' = 0x30
        int low = imei[i].codeUnitAt(0) - 0x30;
        bytes.add((high << 4) | low);
      } else {
        // Último dígito sozinho nos 4 bits baixos
        bytes.add(imei[i].codeUnitAt(0) - 0x30);
      }
    }
    
    // Garante 8 bytes
    while (bytes.length < 8) {
      bytes.add(0);
    }
    
    return Uint8List.fromList(bytes);
  }

  /// Converte coordenada para formato GT06
  double _coordinateToGT06(double coordinate) {
    // GT06 usa: graus * 30000 * 60
    return coordinate.abs() * 30000.0 * 60.0;
  }

  /// Converte inteiro para bytes (big-endian)
  Uint8List _intToBytes(int value, int length) {
    final bytes = <int>[];
    for (int i = length - 1; i >= 0; i--) {
      bytes.add((value >> (i * 8)) & 0xFF);
    }
    return Uint8List.fromList(bytes);
  }

  /// Retorna bytes do número de série atual
  Uint8List _getSerialNumberBytes() {
    return _intToBytes(_serialNumber, 2);
  }

  /// Calcula checksum (XOR de todos os bytes)
  int _calculateChecksum(Uint8List data) {
    int checksum = 0;
    for (int byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  /// Log interno
  void _log(String message) {
    final logMessage = '[${DateTime.now().toString().substring(11, 19)}] $message';
    _logController.add(logMessage);
    debugPrint('GT06Client: $message');
  }

  /// Libera recursos
  void dispose() {
    disconnect();
    _eventController.close();
    _commandController.close();
    _logController.close();
  }
}

// =============================================================================
// CLASSES DE SUPORTE
// =============================================================================

/// Eventos do cliente GT06
enum GT06ClientEventType {
  connected,
  disconnected,
  connectionError,
  loggedIn,
  heartbeatAck,
  locationAck,
  commandReceived,
}

class GT06ClientEvent {
  final GT06ClientEventType type;
  final String message;
  final Map<String, dynamic>? data;
  final DateTime timestamp;

  GT06ClientEvent({
    required this.type,
    required this.message,
    this.data,
    required this.timestamp,
  });

  @override
  String toString() => 'GT06ClientEvent{type: $type, message: $message}';
}

/// Tipos de comando
enum GT06CommandType {
  block,
  unblock,
  locate,
  reboot,
  status,
  parameters,
  unknown,
}

/// Comando recebido do servidor
class GT06Command {
  final GT06CommandType type;
  final String rawCommand;
  final String action;
  final DateTime timestamp;

  GT06Command({
    required this.type,
    required this.rawCommand,
    required this.action,
    required this.timestamp,
  });

  @override
  String toString() => 'GT06Command{type: $type, action: $action, raw: $rawCommand}';
}

/// Posição GPS
class GT06Position {
  final double latitude;
  final double longitude;
  final double speed;
  final double course;
  final DateTime timestamp;
  final bool gpsValid;

  GT06Position({
    required this.latitude,
    required this.longitude,
    required this.speed,
    required this.course,
    required this.timestamp,
    required this.gpsValid,
  });

  @override
  String toString() => 'GT06Position{lat: $latitude, lon: $longitude, speed: $speed}';
}
