import 'dart:async';
import 'dart:typed_data';
import 'dart:convert';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';
import '../models/tracker_state.dart';

/// ============================================================================
/// SERVIÇO ARDUINO - Comunicação USB Serial
/// ============================================================================
/// 
/// Gerencia a comunicação com Arduino via cabo USB-OTG.
/// Envia comandos recebidos do Traccar para o Arduino.
/// ============================================================================

class ArduinoService {
  // Porta serial
  UsbPort? _port;
  
  // Stream subscriptions
  StreamSubscription<String>? _transactionSubscription;
  
  // Stream controllers
  final StreamController<ArduinoMessage> _messageController = StreamController<ArduinoMessage>.broadcast();
  final StreamController<ArduinoState> _stateController = StreamController<ArduinoState>.broadcast();
  
  // Estado
  ArduinoState _state = ArduinoState();
  
  // Baud rates disponíveis
  static const List<int> availableBaudRates = [
    9600,
    19200,
    38400,
    57600,
    115200,
  ];
  
  // Getters
  ArduinoState get state => _state;
  bool get isConnected => _state.status == ArduinoStatus.connected;
  Stream<ArduinoMessage> get messageStream => _messageController.stream;
  Stream<ArduinoState> get stateStream => _stateController.stream;

  /// ==========================================================================
  /// DISPOSITIVOS
  /// ==========================================================================

  /// Lista dispositivos USB disponíveis
  Future<List<UsbDevice>> listDevices() async {
    try {
      return await UsbSerial.listDevices();
    } catch (e) {
      _notifyMessage('Erro ao listar dispositivos: $e', ArduinoMessageType.error);
      return [];
    }
  }

  /// ==========================================================================
  /// CONEXÃO
  /// ==========================================================================

  /// Conecta a um dispositivo específico
  Future<bool> connect(UsbDevice device, {int baudRate = 9600}) async {
    if (_state.status == ArduinoStatus.connected) {
      await disconnect();
    }
    
    _updateState(status: ArduinoStatus.connecting);
    
    try {
      // Abre porta
      _port = await device.create();
      if (_port == null) {
        _updateState(status: ArduinoStatus.error);
        _notifyMessage('Não foi possível criar porta USB', ArduinoMessageType.error);
        return false;
      }
      
      // Abre conexão
      bool openResult = await _port!.open();
      if (!openResult) {
        _updateState(status: ArduinoStatus.error);
        _notifyMessage('Não foi possível abrir porta USB', ArduinoMessageType.error);
        return false;
      }
      
      // Configura porta
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );
      
      // Configura listener de mensagens
      _setupMessageListener();
      
      _updateState(
        status: ArduinoStatus.connected,
        deviceName: device.productName ?? 'Arduino',
        baudRate: baudRate,
      );
      
      _notifyMessage(
        'Conectado a ${device.productName ?? "Arduino"} @ $baudRate bps',
        ArduinoMessageType.info,
      );
      
      return true;
      
    } catch (e) {
      _updateState(status: ArduinoStatus.error);
      _notifyMessage('Erro ao conectar: $e', ArduinoMessageType.error);
      return false;
    }
  }

  /// Conecta automaticamente ao primeiro Arduino disponível
  Future<bool> autoConnect({int baudRate = 9600}) async {
    final devices = await listDevices();
    
    if (devices.isEmpty) {
      _notifyMessage('Nenhum dispositivo USB encontrado', ArduinoMessageType.warning);
      return false;
    }
    
    // Tenta encontrar um dispositivo que pareça ser Arduino
    for (final device in devices) {
      final name = (device.productName ?? '').toLowerCase();
      final manufacturer = (device.manufacturerName ?? '').toLowerCase();
      
      if (name.contains('arduino') || 
          name.contains('ch340') || 
          name.contains('ftdi') ||
          name.contains('cp210') ||
          manufacturer.contains('arduino')) {
        return await connect(device, baudRate: baudRate);
      }
    }
    
    // Se não encontrou Arduino específico, tenta o primeiro
    return await connect(devices.first, baudRate: baudRate);
  }

  /// Desconecta do Arduino
  Future<void> disconnect() async {
    await _transactionSubscription?.cancel();
    _transactionSubscription = null;
    
    if (_port != null) {
      try {
        await _port!.close();
      } catch (e) {
        // Ignora erro ao fechar
      }
      _port = null;
    }
    
    _updateState(status: ArduinoStatus.disconnected);
    _notifyMessage('Desconectado do Arduino', ArduinoMessageType.info);
  }

  /// Configura listener de mensagens
  void _setupMessageListener() {
    if (_port == null) return;
    
    // Usa Transaction para ler linhas completas
    _transactionSubscription = Transaction.stringTerminated(
      _port!.inputStream!,
      Uint8List.fromList([0x0A]),  // LF
    ).listen(
      (String line) {
        _onMessageReceived(line);
      },
      onError: (error) {
        _notifyMessage('Erro na comunicação: $error', ArduinoMessageType.error);
      },
    );
  }

  /// ==========================================================================
  /// ENVIO DE MENSAGENS
  /// ==========================================================================

  /// Envia comando para o Arduino
  Future<bool> sendCommand(String command) async {
    if (_port == null || _state.status != ArduinoStatus.connected) {
      _notifyMessage('Arduino não conectado', ArduinoMessageType.warning);
      return false;
    }
    
    try {
      // Adiciona newline se não tiver
      String message = command;
      if (!message.endsWith('\n')) {
        message += '\n';
      }
      
      final data = Uint8List.fromList(utf8.encode(message));
      await _port!.write(data);
      
      _notifyMessage('Enviado: $command', ArduinoMessageType.sent);
      
      _updateState(lastMessage: command, lastMessageTime: DateTime.now());
      
      return true;
      
    } catch (e) {
      _notifyMessage('Erro ao enviar: $e', ArduinoMessageType.error);
      return false;
    }
  }

  /// Envia comando formatado para o Arduino
  Future<bool> sendFormattedCommand(String commandType, {String? data}) async {
    final buffer = StringBuffer();
    buffer.write('CMD:');
    buffer.write(commandType.toUpperCase());
    
    if (data != null && data.isNotEmpty) {
      buffer.write(':');
      buffer.write(data);
    }
    
    return await sendCommand(buffer.toString());
  }

  /// ==========================================================================
  /// RECEBIMENTO DE MENSAGENS
  /// ==========================================================================

  void _onMessageReceived(String message) {
    // Remove caracteres de controle
    final cleanMessage = message.replaceAll(RegExp(r'[\r\n]'), '').trim();
    
    if (cleanMessage.isEmpty) return;
    
    _notifyMessage('Recebido: $cleanMessage', ArduinoMessageType.received);
    
    _updateState(lastMessage: cleanMessage, lastMessageTime: DateTime.now());
  }

  /// ==========================================================================
  /// NOTIFICAÇÕES
  /// ==========================================================================

  void _notifyMessage(String message, ArduinoMessageType type) {
    _messageController.add(ArduinoMessage(
      message: message,
      type: type,
      timestamp: DateTime.now(),
    ));
  }

  void _updateState({
    ArduinoStatus? status,
    String? deviceName,
    int? baudRate,
    String? lastMessage,
    DateTime? lastMessageTime,
  }) {
    _state = _state.copyWith(
      status: status,
      deviceName: deviceName,
      baudRate: baudRate,
      lastMessage: lastMessage,
      lastMessageTime: lastMessageTime,
    );
    _stateController.add(_state);
  }

  /// ==========================================================================
  /// UTILIDADES
  /// ==========================================================================

  /// Converte comando Traccar para comando Arduino
  String convertTraccarCommand(String traccarCommand) {
    final upper = traccarCommand.toUpperCase();
    
    if (upper.contains('STOP') || upper.contains('CUT') || upper.contains('BLOQUEAR')) {
      return 'CMD:BLOQUEAR';
    } else if (upper.contains('RESUME') || upper.contains('RESTORE') || upper.contains('DESBLOQUEAR')) {
      return 'CMD:DESBLOQUEAR';
    } else if (upper.contains('WHERE') || upper.contains('LOCATE') || upper.contains('POSICAO')) {
      return 'CMD:POSICAO';
    } else if (upper.contains('RESET') || upper.contains('REINICIAR')) {
      return 'CMD:REINICIAR';
    } else if (upper.contains('STATUS')) {
      return 'CMD:STATUS';
    }
    
    return 'CMD:$traccarCommand';
  }

  /// Libera recursos
  void dispose() {
    disconnect();
    _messageController.close();
    _stateController.close();
  }
}

/// Mensagem do Arduino
class ArduinoMessage {
  final String message;
  final ArduinoMessageType type;
  final DateTime timestamp;

  ArduinoMessage({
    required this.message,
    required this.type,
    required this.timestamp,
  });
}

enum ArduinoMessageType {
  info,
  sent,
  received,
  error,
  warning,
}
