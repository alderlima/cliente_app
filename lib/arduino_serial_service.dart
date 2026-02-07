import 'dart:async';
import 'dart:typed_data';
import 'package:flutter/foundation.dart';
import 'package:usb_serial/usb_serial.dart';
import 'package:usb_serial/transaction.dart';
import 'command_log_service.dart';

/// Serviço de comunicação SERIAL com Arduino via USB/OTG
/// Permite conectar ao Arduino e enviar/receber dados via porta serial

class ArduinoSerialService {
  static final ArduinoSerialService _instance = ArduinoSerialService._internal();
  factory ArduinoSerialService() => _instance;
  ArduinoSerialService._internal();

  UsbPort? _port;
  UsbDevice? _device;
  bool _isConnected = false;
  int _baudRate = 9600;
  
  // Stream subscriptions
  StreamSubscription<String>? _transactionSubscription;
  Transaction<String>? _transaction;

  // Stream controllers
  final StreamController<SerialConnectionState> _connectionController = 
      StreamController<SerialConnectionState>.broadcast();
  final StreamController<SerialDataEvent> _dataController = 
      StreamController<SerialDataEvent>.broadcast();
  final StreamController<String> _logController = 
      StreamController<String>.broadcast();

  // Buffer de dados recebidos
  final List<String> _receivedDataBuffer = [];
  static const int maxBufferSize = 500;

  // Getters
  bool get isConnected => _isConnected;
  int get baudRate => _baudRate;
  UsbDevice? get connectedDevice => _device;
  String get connectionInfo => _isConnected 
      ? '${_device?.productName ?? 'Arduino'} @ ${_baudRate}bps' 
      : 'Desconectado';
  List<String> get receivedData => List.unmodifiable(_receivedDataBuffer);

  // Streams
  Stream<SerialConnectionState> get connectionStream => _connectionController.stream;
  Stream<SerialDataEvent> get dataStream => _dataController.stream;
  Stream<String> get logStream => _logController.stream;

  /// Lista dispositivos USB disponíveis
  Future<List<UsbDevice>> listDevices() async {
    try {
      List<UsbDevice> devices = await UsbSerial.listDevices();
      _log('Dispositivos encontrados: ${devices.length}');
      for (var device in devices) {
        _log('  - ${device.productName} (${device.manufacturerName}) - VID: ${device.vid}, PID: ${device.pid}');
      }
      return devices;
    } catch (e) {
      _log('✗ Erro ao listar dispositivos: $e');
      return [];
    }
  }

  /// Conecta a um dispositivo USB específico
  Future<bool> connect(UsbDevice device, {int baudRate = 9600}) async {
    if (_isConnected) {
      await disconnect();
    }

    _baudRate = baudRate;
    _device = device;

    try {
      _log('Tentando conectar a ${device.productName}...');
      _log('Baud Rate: $baudRate bps');

      // Cria a porta serial
      _port = await device.create();
      if (_port == null) {
        _log('✗ Falha ao criar porta serial');
        return false;
      }

      // Abre a porta
      bool openResult = await _port!.open();
      if (!openResult) {
        _log('✗ Falha ao abrir porta serial');
        _port = null;
        return false;
      }

      // Configura os parâmetros da porta
      await _port!.setDTR(true);
      await _port!.setRTS(true);
      await _port!.setPortParameters(
        baudRate,
        UsbPort.DATABITS_8,
        UsbPort.STOPBITS_1,
        UsbPort.PARITY_NONE,
      );

      _isConnected = true;

      _log('✓ Conectado com sucesso!');
      _log('Dispositivo: ${device.productName}');
      _log('Baud Rate: $baudRate bps');

      await CommandLogService.addLog(
        'ARDUINO SERIAL CONECTADO',
        data: {
          'dispositivo': device.productName,
          'fabricante': device.manufacturerName,
          'vid': device.vid,
          'pid': device.pid,
          'baud_rate': baudRate,
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(SerialConnectionState(
        status: SerialStatus.connected,
        device: device,
        baudRate: baudRate,
        message: 'Conectado a ${device.productName} @ ${baudRate}bps',
        timestamp: DateTime.now(),
      ));

      // Inicia listener de dados
      _startListening();

      return true;
    } catch (e) {
      _isConnected = false;
      _port = null;
      _log('✗ Erro de conexão: $e');

      await CommandLogService.addLog(
        'ARDUINO SERIAL ERRO',
        data: {
          'erro': e.toString(),
          'timestamp': DateTime.now().toIso8601String(),
        },
      );

      _connectionController.add(SerialConnectionState(
        status: SerialStatus.error,
        device: device,
        baudRate: baudRate,
        message: 'Erro: $e',
        timestamp: DateTime.now(),
      ));

      return false;
    }
  }

  /// Conecta automaticamente ao primeiro Arduino encontrado
  Future<bool> autoConnect({int baudRate = 9600}) async {
    List<UsbDevice> devices = await listDevices();
    
    // Procura por dispositivos Arduino (VID 0x2341 = Arduino, 0x1A86 = CH340, etc.)
    for (var device in devices) {
      // VID comuns de Arduino e conversores USB-Serial
      const List<int> arduinoVids = [
        0x2341, // Arduino
        0x1A86, // CH340/CH341
        0x0403, // FTDI
        0x10C4, // CP210x
        0x067B, // Prolific
        0x0483, // STM32
        0x2A03, // Arduino.org
        0x16C0, // Teensy
      ];

      if (arduinoVids.contains(device.vid)) {
        _log('Arduino encontrado: ${device.productName}');
        return await connect(device, baudRate: baudRate);
      }
    }

    _log('✗ Nenhum Arduino encontrado');
    return false;
  }

  /// Inicia escuta de dados da porta serial
  void _startListening() {
    if (_port == null) return;

    // Cria transação para ler linhas
    _transaction = Transaction.stringTerminated(
      _port!.inputStream!,
      Uint8List.fromList([0x0D, 0x0A]), // \r\n
    );

    _transactionSubscription = _transaction!.stream.listen(
      (String line) {
        _handleReceivedData(line);
      },
      onError: (error) {
        _log('✗ Erro na leitura: $error');
      },
      onDone: () {
        _log('Stream de dados encerrado');
        _handleDisconnect();
      },
    );
  }

  /// Manipula dados recebidos
  void _handleReceivedData(String data) {
    data = data.trim();
    if (data.isEmpty) return;

    _log('← RX: $data');

    // Adiciona ao buffer
    _receivedDataBuffer.add(data);
    if (_receivedDataBuffer.length > maxBufferSize) {
      _receivedDataBuffer.removeAt(0);
    }

    // Notifica listeners
    _dataController.add(SerialDataEvent(
      data: data,
      rawBytes: Uint8List.fromList(data.codeUnits),
      timestamp: DateTime.now(),
    ));

    // Log no serviço de comandos
    CommandLogService.addLog(
      'ARDUINO RX SERIAL',
      data: {
        'dados': data,
        'timestamp': DateTime.now().toIso8601String(),
      },
    );
  }

  /// Envia dados em formato texto (ASCII)
  Future<bool> send(String text, {bool addNewline = true}) async {
    if (!_isConnected || _port == null) {
      _log('✗ Não está conectado');
      return false;
    }

    try {
      String message = addNewline ? '$text\r\n' : text;
      Uint8List data = Uint8List.fromList(message.codeUnits);
      
      await _port!.write(data);

      _log('→ TX: $text');

      await CommandLogService.addLog(
        'ARDUINO TX SERIAL',
        data: {
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
    if (!_isConnected || _port == null) {
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

      await _port!.write(Uint8List.fromList(bytes));

      _log('→ TX HEX: $hexString');

      return true;
    } catch (e) {
      _log('✗ Erro ao enviar HEX: $e');
      return false;
    }
  }

  /// Envia bytes raw
  Future<bool> sendBytes(List<int> bytes) async {
    if (!_isConnected || _port == null) {
      _log('✗ Não está conectado');
      return false;
    }

    try {
      await _port!.write(Uint8List.fromList(bytes));

      String hexStr = bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
      _log('→ TX RAW: $hexStr');

      return true;
    } catch (e) {
      _log('✗ Erro ao enviar bytes: $e');
      return false;
    }
  }

  /// Desconecta do Arduino
  Future<void> disconnect() async {
    if (!_isConnected && _port == null) return;

    _log('Desconectando...');

    await _transactionSubscription?.cancel();
    _transactionSubscription = null;
    _transaction = null;

    try {
      await _port?.close();
    } catch (e) {
      debugPrint('Erro ao fechar porta: $e');
    }

    _port = null;
    _device = null;
    _isConnected = false;

    _log('✓ Desconectado');

    await CommandLogService.addLog(
      'ARDUINO SERIAL DESCONECTADO',
      data: {
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(SerialConnectionState(
      status: SerialStatus.disconnected,
      device: null,
      baudRate: _baudRate,
      message: 'Desconectado',
      timestamp: DateTime.now(),
    ));
  }

  /// Manipula desconexão
  void _handleDisconnect() async {
    if (!_isConnected) return;

    _isConnected = false;
    _port = null;

    _log('Conexão perdida');

    await CommandLogService.addLog(
      'ARDUINO SERIAL DESCONECTADO',
      data: {
        'motivo': 'Conexão perdida',
        'timestamp': DateTime.now().toIso8601String(),
      },
    );

    _connectionController.add(SerialConnectionState(
      status: SerialStatus.disconnected,
      device: null,
      baudRate: _baudRate,
      message: 'Conexão perdida',
      timestamp: DateTime.now(),
    ));
  }

  /// Adiciona log interno
  void _log(String message) {
    final logMessage = '[${DateTime.now().toString().substring(11, 19)}] $message';
    _logController.add(logMessage);
    debugPrint('ArduinoSerial: $message');
  }

  /// Limpa o buffer de dados recebidos
  void clearBuffer() {
    _receivedDataBuffer.clear();
    _log('Buffer limpo');
  }

  /// Libera recursos
  void dispose() {
    disconnect();
    _connectionController.close();
    _dataController.close();
    _logController.close();
  }

  /// Baud rates disponíveis
  static const List<int> availableBaudRates = [
    300,
    1200,
    2400,
    4800,
    9600,
    14400,
    19200,
    28800,
    38400,
    57600,
    115200,
    230400,
  ];
}

/// Estados de conexão serial
enum SerialStatus {
  disconnected,
  connecting,
  connected,
  error,
}

class SerialConnectionState {
  final SerialStatus status;
  final UsbDevice? device;
  final int baudRate;
  final String message;
  final DateTime timestamp;

  SerialConnectionState({
    required this.status,
    this.device,
    required this.baudRate,
    required this.message,
    required this.timestamp,
  });

  bool get isConnected => status == SerialStatus.connected;
}

/// Evento de dados recebidos
class SerialDataEvent {
  final String data;
  final Uint8List rawBytes;
  final DateTime timestamp;

  SerialDataEvent({
    required this.data,
    required this.rawBytes,
    required this.timestamp,
  });
}
