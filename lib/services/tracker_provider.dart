import 'dart:async';
import 'dart:convert';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'gt06_client.dart';
import 'gt06_protocol.dart';
import 'gps_service.dart';
import 'arduino_service.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// TRACKER PROVIDER - Gerenciamento de Estado do Rastreador
/// ============================================================================
/// 
/// Provider principal que coordena todos os serviços:
/// - Cliente GT06 (conexão TCP com Traccar)
/// - Serviço GPS (localização do celular)
/// - Serviço Arduino (comunicação USB)
/// ============================================================================

class TrackerProvider extends ChangeNotifier {
  // Serviços
  final GT06Client _gt06Client = GT06Client();
  final GpsService _gpsService = GpsService();
  final ArduinoService _arduinoService = ArduinoService();
  
  // Estado
  TrackerStatus _status = TrackerStatus.disconnected;
  TrackerConfig _config = TrackerConfig();
  TrackerStats _stats = TrackerStats();
  ArduinoState _arduinoState = ArduinoState();
  GpsPosition? _currentPosition;
  
  // Logs
  final List<LogEntry> _logs = [];
  static const int maxLogs = 500;
  
  // Timers
  Timer? _locationTimer;
  
  // Subscriptions
  StreamSubscription? _clientEventSub;
  StreamSubscription? _clientCommandSub;
  StreamSubscription? _gpsPositionSub;
  StreamSubscription? _arduinoMessageSub;
  StreamSubscription? _arduinoStateSub;

  // Getters
  TrackerStatus get status => _status;
  TrackerConfig get config => _config;
  TrackerStats get stats => _stats;
  ArduinoState get arduinoState => _arduinoState;
  GpsPosition? get currentPosition => _currentPosition;
  List<LogEntry> get logs => List.unmodifiable(_logs);
  ArduinoService get arduinoService => _arduinoService;
  
  bool get isOnline => _status == TrackerStatus.online;
  bool get isConnected => _status == TrackerStatus.connected || _status == TrackerStatus.online;
  bool get isArduinoConnected => _arduinoState.status == ArduinoStatus.connected;
  String get statusText {
    switch (_status) {
      case TrackerStatus.disconnected: return 'Desconectado';
      case TrackerStatus.connecting: return 'Conectando...';
      case TrackerStatus.connected: return 'Conectado';
      case TrackerStatus.loggingIn: return 'Autenticando...';
      case TrackerStatus.online: return 'ONLINE';
      case TrackerStatus.error: return 'Erro';
    }
  }

  /// ==========================================================================
  /// INICIALIZAÇÃO
  /// ==========================================================================

  TrackerProvider() {
    _init();
  }

  Future<void> _init() async {
    await _loadConfig();
    _setupListeners();
    
    // Gera IMEI se não tiver
    if (_config.imei.isEmpty) {
      generateNewIMEI();
    }
    
    notifyListeners();
  }

  void _setupListeners() {
    // Eventos do cliente GT06
    _clientEventSub = _gt06Client.eventStream.listen(_onClientEvent);
    
    // Comandos do servidor
    _clientCommandSub = _gt06Client.commandStream.listen(_onServerCommand);
    
    // Posições GPS
    _gpsPositionSub = _gpsService.positionStream.listen(_onGpsPosition);
    
    // Mensagens do Arduino
    _arduinoMessageSub = _arduinoService.messageStream.listen(_onArduinoMessage);
    
    // Estado do Arduino
    _arduinoStateSub = _arduinoService.stateStream.listen(_onArduinoState);
  }

  /// ==========================================================================
  /// CONFIGURAÇÃO
  /// ==========================================================================

  Future<void> _loadConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final json = prefs.getString('tracker_config');
      
      if (json != null) {
        _config = TrackerConfig.fromJson(
          Map<String, dynamic>.from(
            jsonDecode(json) as Map,
          ),
        );
      }
    } catch (e) {
      _addLog(LogType.error, 'Erro ao carregar configuração', e.toString());
    }
  }

  Future<void> _saveConfig() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString('tracker_config', jsonEncode(_config.toJson()));
    } catch (e) {
      _addLog(LogType.error, 'Erro ao salvar configuração', e.toString());
    }
  }

  void updateConfig({
    String? serverAddress,
    int? serverPort,
    String? imei,
    int? heartbeatInterval,
    int? locationInterval,
    bool? autoConnect,
  }) {
    _config = TrackerConfig(
      serverAddress: serverAddress ?? _config.serverAddress,
      serverPort: serverPort ?? _config.serverPort,
      imei: imei ?? _config.imei,
      heartbeatInterval: heartbeatInterval ?? _config.heartbeatInterval,
      locationInterval: locationInterval ?? _config.locationInterval,
      autoConnect: autoConnect ?? _config.autoConnect,
    );
    
    _saveConfig();
    notifyListeners();
  }

  void generateNewIMEI() {
    final newImei = GT06Protocol.generateRandomIMEI();
    updateConfig(imei: newImei);
    _addLog(LogType.info, 'Novo IMEI gerado: $newImei');
  }

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  Future<void> connect() async {
    if (_status == TrackerStatus.connecting || _status == TrackerStatus.online) {
      return;
    }
    
    if (_config.serverAddress.isEmpty) {
      _addLog(LogType.error, 'Configure o servidor antes de conectar');
      return;
    }
    
    if (_config.imei.isEmpty || _config.imei.length != 15) {
      _addLog(LogType.error, 'IMEI inválido. Deve ter 15 dígitos.');
      return;
    }
    
    _updateStatus(TrackerStatus.connecting);
    
    // Inicia GPS
    await _gpsService.startTracking(
      intervalSeconds: _config.locationInterval,
    );
    
    // Conecta ao servidor
    await _gt06Client.connect(
      serverAddress: _config.serverAddress,
      serverPort: _config.serverPort,
      imei: _config.imei,
      heartbeatInterval: _config.heartbeatInterval,
    );
  }

  Future<void> disconnect() async {
    _stopLocationTimer();
    await _gpsService.stopTracking();
    await _gt06Client.disconnect();
    _updateStatus(TrackerStatus.disconnected);
    _stats.reset();
    notifyListeners();
  }

  /// ==========================================================================
  /// EVENTOS DO CLIENTE GT06
  /// ==========================================================================

  void _onClientEvent(ClientEvent event) {
    switch (event.type) {
      case ClientEventType.connecting:
        _updateStatus(TrackerStatus.connecting);
        break;
        
      case ClientEventType.connected:
        _updateStatus(TrackerStatus.connected);
        _stats.connectedSince = DateTime.now();
        break;
        
      case ClientEventType.loggingIn:
        _updateStatus(TrackerStatus.loggingIn);
        break;
        
      case ClientEventType.loggedIn:
        _updateStatus(TrackerStatus.online);
        _gt06Client.startHeartbeat(_config.heartbeatInterval);
        _startLocationTimer();
        break;
        
      case ClientEventType.disconnected:
        _updateStatus(TrackerStatus.disconnected);
        _stopLocationTimer();
        break;
        
      case ClientEventType.error:
        _updateStatus(TrackerStatus.error);
        _addLog(LogType.error, event.message);
        break;
        
      case ClientEventType.packetSent:
        _stats.packetsSent++;
        _addLog(LogType.sent, event.message, event.data?['hex']);
        break;
        
      case ClientEventType.packetReceived:
        _stats.packetsReceived++;
        _addLog(LogType.received, event.message, event.data?['hex']);
        break;
        
      case ClientEventType.heartbeatAck:
        _stats.heartbeatsSent++;
        _addLog(LogType.info, event.message);
        break;
        
      case ClientEventType.locationAck:
        _stats.locationsSent++;
        _addLog(LogType.info, event.message);
        break;
        
      case ClientEventType.commandReceived:
        _stats.commandsReceived++;
        _addLog(LogType.command, event.message, event.data?['command']);
        break;
        
      default:
        _addLog(LogType.info, event.message);
    }
    
    _stats.lastActivity = DateTime.now();
    notifyListeners();
  }

  /// ==========================================================================
  /// COMANDOS DO SERVIDOR
  /// ==========================================================================

  void _onServerCommand(String command) {
    // Envia para Arduino
    if (_arduinoService.isConnected) {
      final arduinoCmd = _arduinoService.convertTraccarCommand(command);
      _arduinoService.sendCommand(arduinoCmd);
    }
    
    // Notifica na UI
    _addLog(LogType.command, 'Comando Traccar: $command');
  }

  /// ==========================================================================
  /// GPS
  /// ==========================================================================

  void _onGpsPosition(GpsPosition position) {
    _currentPosition = position;
    
    if (position.isValid) {
      _addLog(
        LogType.gps,
        'GPS: ${position.latitude.toStringAsFixed(6)}, ${position.longitude.toStringAsFixed(6)}',
        'Velocidade: ${position.speed.toStringAsFixed(1)} km/h',
      );
    }
    
    notifyListeners();
  }

  void _startLocationTimer() {
    _stopLocationTimer();
    
    // Envia posição imediatamente
    _sendCurrentLocation();
    
    // Configura timer periódico
    _locationTimer = Timer.periodic(
      Duration(seconds: _config.locationInterval),
      (_) => _sendCurrentLocation(),
    );
  }

  void _stopLocationTimer() {
    _locationTimer?.cancel();
    _locationTimer = null;
  }

  Future<void> _sendCurrentLocation() async {
    if (_currentPosition == null || !_currentPosition!.isValid) {
      // Tenta obter posição atual
      final position = await _gpsService.getCurrentPosition();
      if (position == null || !position.isValid) return;
      _currentPosition = position;
    }
    
    await _gt06Client.sendLocation(
      latitude: _currentPosition!.latitude,
      longitude: _currentPosition!.longitude,
      speed: _currentPosition!.speed,
      course: _currentPosition!.heading,
    );
  }

  /// ==========================================================================
  /// ARDUINO
  /// ==========================================================================

  Future<void> connectArduino() async {
    final connected = await _arduinoService.autoConnect();
    
    if (connected) {
      _addLog(LogType.arduino, 'Arduino conectado');
    } else {
      _addLog(LogType.warning, 'Falha ao conectar Arduino');
    }
  }

  Future<void> disconnectArduino() async {
    await _arduinoService.disconnect();
    _addLog(LogType.arduino, 'Arduino desconectado');
  }

  Future<void> sendToArduino(String command) async {
    await _arduinoService.sendCommand(command);
  }

  void _onArduinoMessage(ArduinoMessage message) {
    LogType logType;
    switch (message.type) {
      case ArduinoMessageType.sent:
        logType = LogType.arduino;
        break;
      case ArduinoMessageType.received:
        logType = LogType.arduino;
        break;
      case ArduinoMessageType.error:
        logType = LogType.error;
        break;
      case ArduinoMessageType.warning:
        logType = LogType.warning;
        break;
      default:
        logType = LogType.info;
    }
    
    _addLog(logType, '[Arduino] ${message.message}');
  }

  void _onArduinoState(ArduinoState state) {
    _arduinoState = state;
    notifyListeners();
  }

  /// ==========================================================================
  /// LOGS
  /// ==========================================================================

  void _addLog(LogType type, String message, [String? details]) {
    final entry = LogEntry(
      timestamp: DateTime.now(),
      type: type,
      message: message,
      details: details,
    );
    
    _logs.add(entry);
    
    // Limita tamanho
    if (_logs.length > maxLogs) {
      _logs.removeAt(0);
    }
    
    notifyListeners();
  }

  void clearLogs() {
    _logs.clear();
    notifyListeners();
  }

  /// ==========================================================================
  /// UTILIDADES
  /// ==========================================================================

  void _updateStatus(TrackerStatus status) {
    _status = status;
    notifyListeners();
  }

  /// Envia alarme SOS
  Future<void> sendSosAlarm() async {
    if (_currentPosition != null) {
      await _gt06Client.sendAlarm(
        alarmType: GT06Protocol.ALARM_SOS,
        latitude: _currentPosition!.latitude,
        longitude: _currentPosition!.longitude,
        speed: _currentPosition!.speed,
      );
      _addLog(LogType.warning, 'Alarme SOS enviado!');
    }
  }

  /// Libera recursos
  @override
  void dispose() {
    _clientEventSub?.cancel();
    _clientCommandSub?.cancel();
    _gpsPositionSub?.cancel();
    _arduinoMessageSub?.cancel();
    _arduinoStateSub?.cancel();
    
    _locationTimer?.cancel();
    
    _gt06Client.dispose();
    _gpsService.dispose();
    _arduinoService.dispose();
    
    super.dispose();
  }
}
