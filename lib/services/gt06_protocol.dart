import 'dart:typed_data';
import 'dart:convert';

/// ============================================================================
/// PROTOCOLO GT06 COMPLETO - Implementação Cliente
/// ============================================================================
/// 
/// Protocolo Concox GT06 para rastreadores GPS
/// Documentação baseada nas especificações oficiais
///
/// ESTRUTURA DO PACOTE:
/// [Start Bytes: 0x78 0x78] [Length: 1 byte] [Protocol: 1 byte] 
/// [Content: n bytes] [Serial: 2 bytes] [Checksum: 1 byte] [Stop: 0x0D 0x0A]
/// ============================================================================

class GT06Protocol {
  // Start e Stop bytes
  static const List<int> START_BYTES = [0x78, 0x78];
  static const List<int> STOP_BYTES = [0x0D, 0x0A];

  // Protocol Numbers
  static const int PROTOCOL_LOGIN = 0x01;
  static const int PROTOCOL_LOCATION = 0x12;
  static const int PROTOCOL_STATUS = 0x13;  // Heartbeat
  static const int PROTOCOL_STRING = 0x15;
  static const int PROTOCOL_ALARM = 0x16;
  static const int PROTOCOL_COMMAND = 0x80;  // Server -> Client
  static const int PROTOCOL_COMMAND_RESPONSE = 0x21;  // Client -> Server
  static const int PROTOCOL_TIME_REQUEST = 0x32;
  static const int PROTOCOL_INFO = 0x98;

  // Tipos de alarme
  static const int ALARM_NORMAL = 0x00;
  static const int ALARM_SOS = 0x01;
  static const int ALARM_POWER_CUT = 0x02;
  static const int ALARM_VIBRATION = 0x03;
  static const int ALARM_GEO_FENCE_IN = 0x04;
  static const int ALARM_GEO_FENCE_OUT = 0x05;
  static const int ALARM_OVERSPEED = 0x06;
  static const int ALARM_ACC_ON = 0x09;
  static const int ALARM_ACC_OFF = 0x0A;
  static const int ALARM_LOW_BATTERY = 0x0E;

  /// Serial number incremental
  int _serialNumber = 1;

  int get nextSerialNumber {
    final serial = _serialNumber;
    _serialNumber = (_serialNumber + 1) & 0xFFFF;
    if (_serialNumber == 0) _serialNumber = 1;
    return serial;
  }

  void resetSerial() => _serialNumber = 1;

  /// ==========================================================================
  /// CRIAÇÃO DE PACOTES - CLIENTE -> SERVIDOR
  /// ==========================================================================

  /// Cria pacote de LOGIN (0x01)
  /// 
  /// Estrutura: [Start][Len][0x01][IMEI BCD 8bytes][Serial][Checksum][Stop]
  Uint8List createLoginPacket(String imei) {
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length (protocol + imei + serial = 1 + 8 + 2 = 11)
    builder.addByte(0x0B);
    
    // Protocol number
    builder.addByte(PROTOCOL_LOGIN);
    
    // IMEI em BCD (8 bytes para 15 dígitos)
    builder.add(_imeiToBCD(imei));
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Calcula checksum (XOR de tudo após start bytes)
    final packetWithoutChecksum = builder.toBytes();
    final checksum = _calculateChecksum(packetWithoutChecksum.sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de HEARTBEAT (0x13)
  /// 
  /// Estrutura: [Start][Len][0x13][TerminalInfo][Voltage][GSM][AlarmLang][Serial][Checksum][Stop]
  Uint8List createHeartbeatPacket({
    bool accOn = true,
    bool gpsPositioned = true,
    int voltageLevel = 4,  // 0-6
    int gsmSignal = 4,     // 0-4
    int alarmType = 0,     // 0 = normal
  }) {
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length (protocol + terminal + voltage + gsm + alarm + serial = 1+1+1+1+2+2 = 8)
    builder.addByte(0x08);
    
    // Protocol number
    builder.addByte(PROTOCOL_STATUS);
    
    // Terminal Info (1 byte)
    int terminalInfo = 0x00;
    if (accOn) terminalInfo |= 0x01;
    if (gpsPositioned) terminalInfo |= 0x02;
    terminalInfo |= 0x40;  // GPS real-time
    builder.addByte(terminalInfo);
    
    // Voltage level (1 byte)
    builder.addByte(voltageLevel.clamp(0, 6));
    
    // GSM signal (1 byte)
    builder.addByte(gsmSignal.clamp(0, 4));
    
    // Alarm/Language (2 bytes)
    builder.add([alarmType & 0xFF, 0x00]);
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de LOCATION/GPS (0x12)
  /// 
  /// Estrutura completa com data, coordenadas, velocidade e curso
  Uint8List createLocationPacket({
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
    int satellites = 8,
    bool gpsValid = true,
  }) {
    dateTime ??= DateTime.now().toUtc();
    
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length (protocol + datetime + satellites + lat + lon + speed + course_status + serial)
    // = 1 + 6 + 1 + 4 + 4 + 1 + 2 + 2 = 21
    builder.addByte(0x15);
    
    // Protocol number
    builder.addByte(PROTOCOL_LOCATION);
    
    // Date/Time (6 bytes): YY MM DD HH MM SS
    builder.addByte(dateTime.year - 2000);
    builder.addByte(dateTime.month);
    builder.addByte(dateTime.day);
    builder.addByte(dateTime.hour);
    builder.addByte(dateTime.minute);
    builder.addByte(dateTime.second);
    
    // GPS Count (1 byte) - número de satélites
    builder.addByte(satellites);
    
    // Latitude (4 bytes) - graus * 30000 * 60
    final latValue = (_coordinateToGT06(latitude)).toInt();
    builder.add(_intToBytes(latValue, 4));
    
    // Longitude (4 bytes)
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    builder.add(_intToBytes(lonValue, 4));
    
    // Speed (1 byte) - km/h
    builder.addByte(speed.clamp(0, 255).toInt());
    
    // Course/Status (2 bytes)
    int courseStatus = ((course ~/ 10) & 0x03FF);
    if (gpsValid) courseStatus |= 0x1000;  // GPS valid bit
    if (latitude < 0) courseStatus |= 0x0400;  // South
    if (longitude < 0) courseStatus |= 0x0800;  // West
    builder.add(_intToBytes(courseStatus, 2));
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria pacote de ALARM (0x16)
  Uint8List createAlarmPacket({
    required int alarmType,
    required double latitude,
    required double longitude,
    double speed = 0,
    double course = 0,
    DateTime? dateTime,
  }) {
    dateTime ??= DateTime.now().toUtc();
    
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length
    builder.addByte(0x19);  // 25 bytes
    
    // Protocol number
    builder.addByte(PROTOCOL_ALARM);
    
    // Date/Time (6 bytes)
    builder.addByte(dateTime.year - 2000);
    builder.addByte(dateTime.month);
    builder.addByte(dateTime.day);
    builder.addByte(dateTime.hour);
    builder.addByte(dateTime.minute);
    builder.addByte(dateTime.second);
    
    // Alarm type (1 byte)
    builder.addByte(alarmType);
    
    // GPS Count
    builder.addByte(8);
    
    // Latitude
    final latValue = (_coordinateToGT06(latitude)).toInt();
    builder.add(_intToBytes(latValue, 4));
    
    // Longitude
    final lonValue = (_coordinateToGT06(longitude)).toInt();
    builder.add(_intToBytes(lonValue, 4));
    
    // Speed
    builder.addByte(speed.clamp(0, 255).toInt());
    
    // Course/Status
    int courseStatus = ((course ~/ 10) & 0x03FF) | 0x1000;
    builder.add(_intToBytes(courseStatus, 2));
    
    // Alarm Status (4 bytes)
    builder.add([0x00, 0x00, 0x00, 0x00]);
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// Cria resposta de comando (0x21)
  Uint8List createCommandResponse(String responseText) {
    final textBytes = utf8.encode(responseText);
    final builder = BytesBuilder();
    
    // Start bytes
    builder.add(START_BYTES);
    
    // Content length
    builder.addByte(5 + textBytes.length);
    
    // Protocol number
    builder.addByte(PROTOCOL_COMMAND_RESPONSE);
    
    // Server flag (1 byte)
    builder.addByte(0x00);
    
    // Command type (1 byte) - 0x01 = texto
    builder.addByte(0x01);
    
    // Command length (2 bytes, big-endian)
    builder.add(_intToBytes(textBytes.length, 2));
    
    // Command text
    builder.add(textBytes);
    
    // Serial number
    builder.add(_intToBytes(nextSerialNumber, 2));
    
    // Checksum
    final checksum = _calculateChecksum(builder.toBytes().sublist(2));
    builder.addByte(checksum);
    
    // Stop bytes
    builder.add(STOP_BYTES);
    
    return Uint8List.fromList(builder.toBytes());
  }

  /// ==========================================================================
  /// PARSING DE PACOTES - SERVIDOR -> CLIENTE
  /// ==========================================================================

  /// Parse de pacote recebido do servidor
  GT06ServerPacket? parseServerPacket(Uint8List data) {
    try {
      // Verifica tamanho mínimo
      if (data.length < 7) return null;
      
      // Procura start bytes
      int startIndex = -1;
      for (int i = 0; i < data.length - 1; i++) {
        if (data[i] == START_BYTES[0] && data[i + 1] == START_BYTES[1]) {
          startIndex = i;
          break;
        }
      }
      
      if (startIndex == -1 || startIndex + 2 >= data.length) return null;
      
      // Pega content length
      int contentLength = data[startIndex + 2];
      int packetLength = 2 + 1 + contentLength + 1 + 2; // start + len byte + content + checksum + stop
      
      if (startIndex + packetLength > data.length) return null;
      
      // Extrai o pacote
      final packet = data.sublist(startIndex, startIndex + packetLength);
      
      // Verifica stop bytes
      if (packet[packet.length - 2] != STOP_BYTES[0] || 
          packet[packet.length - 1] != STOP_BYTES[1]) {
        return null;
      }
      
      // Extrai campos
      int protocolNumber = packet[3];
      Uint8List content = packet.sublist(4, 4 + contentLength - 1);
      int serialNumber = (packet[packet.length - 4] << 8) | packet[packet.length - 3];
      
      // Verifica checksum
      int expectedChecksum = packet[packet.length - 3];
      Uint8List contentForChecksum = packet.sublist(2, packet.length - 3);
      int calculatedChecksum = _calculateChecksum(contentForChecksum);
      
      return GT06ServerPacket(
        protocolNumber: protocolNumber,
        content: content,
        serialNumber: serialNumber,
        checksumValid: expectedChecksum == calculatedChecksum,
        rawData: packet,
      );
      
    } catch (e) {
      return null;
    }
  }

  /// Parse de comando do servidor (0x80)
  String? parseCommand(GT06ServerPacket packet) {
    if (packet.protocolNumber != PROTOCOL_COMMAND) return null;
    
    try {
      // Estrutura: [Flag][Type][LenHi][LenLo][Command...]
      if (packet.content.length < 4) return null;
      
      int commandType = packet.content[1];
      int commandLength = (packet.content[2] << 8) | packet.content[3];
      
      if (packet.content.length < 4 + commandLength) return null;
      
      Uint8List commandBytes = packet.content.sublist(4, 4 + commandLength);
      return utf8.decode(commandBytes);
      
    } catch (e) {
      return null;
    }
  }

  /// ==========================================================================
  /// HELPERS
  /// ==========================================================================

  /// Converte IMEI para BCD (8 bytes para 15 dígitos)
  Uint8List _imeiToBCD(String imei) {
    final cleanImei = imei.replaceAll(RegExp(r'[^0-9]'), '').padLeft(15, '0');
    final bytes = <int>[];
    
    for (int i = 0; i < cleanImei.length; i += 2) {
      if (i + 1 < cleanImei.length) {
        int high = cleanImei[i + 1].codeUnitAt(0) - 0x30;
        int low = cleanImei[i].codeUnitAt(0) - 0x30;
        bytes.add((high << 4) | low);
      } else {
        bytes.add(cleanImei[i].codeUnitAt(0) - 0x30);
      }
    }
    
    while (bytes.length < 8) {
      bytes.add(0);
    }
    
    return Uint8List.fromList(bytes.sublist(0, 8));
  }

  /// Converte coordenada para formato GT06
  double _coordinateToGT06(double coordinate) {
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

  /// Calcula checksum (XOR de todos os bytes)
  int _calculateChecksum(Uint8List data) {
    int checksum = 0;
    for (int byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  /// Gera IMEI aleatório válido
  static String generateRandomIMEI() {
    final buffer = StringBuffer();
    
    // TAC (8 dígitos) - prefixo comum de rastreadores
    buffer.write('35963208');
    
    // Serial (6 dígitos aleatórios)
    for (int i = 0; i < 6; i++) {
      buffer.write((DateTime.now().millisecond + i) % 10);
    }
    
    // Calcula dígito verificador (Luhn)
    String imei14 = buffer.toString();
    int sum = 0;
    bool doubleDigit = false;
    
    for (int i = imei14.length - 1; i >= 0; i--) {
      int digit = imei14[i].codeUnitAt(0) - 0x30;
      if (doubleDigit) {
        digit *= 2;
        if (digit > 9) digit -= 9;
      }
      sum += digit;
      doubleDigit = !doubleDigit;
    }
    
    int checkDigit = (10 - (sum % 10)) % 10;
    buffer.write(checkDigit);
    
    return buffer.toString();
  }

  /// Formata bytes para hex string
  static String bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join(' ');
  }
}

/// Pacote recebido do servidor
class GT06ServerPacket {
  final int protocolNumber;
  final Uint8List content;
  final int serialNumber;
  final bool checksumValid;
  final Uint8List rawData;

  GT06ServerPacket({
    required this.protocolNumber,
    required this.content,
    required this.serialNumber,
    required this.checksumValid,
    required this.rawData,
  });

  String get protocolName {
    switch (protocolNumber) {
      case GT06Protocol.PROTOCOL_LOGIN: return 'LOGIN_ACK';
      case GT06Protocol.PROTOCOL_LOCATION: return 'LOCATION_ACK';
      case GT06Protocol.PROTOCOL_STATUS: return 'HEARTBEAT_ACK';
      case GT06Protocol.PROTOCOL_COMMAND: return 'COMMAND';
      case GT06Protocol.PROTOCOL_COMMAND_RESPONSE: return 'CMD_ACK';
      default: return 'UNKNOWN(0x${protocolNumber.toRadixString(16)})';
    }
  }
}
