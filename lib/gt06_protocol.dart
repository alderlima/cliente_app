import 'dart:typed_data';
import 'dart:convert';

/// GT06 Protocol Parser
/// Protocolo usado por rastreadores GPS GT06/TK100/TK110
/// Documentação baseada no protocolo Concox GT06

class GT06Packet {
  final int protocolNumber;
  final String type;
  final Uint8List rawData;
  final Map<String, dynamic> parsedData;
  final DateTime timestamp;

  GT06Packet({
    required this.protocolNumber,
    required this.type,
    required this.rawData,
    required this.parsedData,
    required this.timestamp,
  });

  @override
  String toString() {
    return 'GT06Packet{type: $type, protocol: 0x${protocolNumber.toRadixString(16).padLeft(2, '0')}, data: $parsedData}';
  }
}

class GT06Protocol {
  // Start bytes do protocolo GT06
  static const List<int> START_BYTES = [0x78, 0x78]; // xx
  static const List<int> STOP_BYTES = [0x0D, 0x0A]; // \r\n

  // Protocol Numbers
  static const int PROTOCOL_LOGIN = 0x01;
  static const int PROTOCOL_LOCATION = 0x12;
  static const int PROTOCOL_STATUS = 0x13;
  static const int PROTOCOL_STRING = 0x15;
  static const int PROTOCOL_ALARM = 0x16;
  static const int PROTOCOL_COMMAND = 0x80;
  static const int PROTOCOL_COMMAND_RESPONSE = 0x21;
  static const int PROTOCOL_TIME_REQUEST = 0x32;
  static const int PROTOCOL_INFO = 0x98;

  // Comandos do servidor para o rastreador
  static const Map<String, List<int>> COMMANDS = {
    'CORTE_COMBUSTIVEL': [0x52, 0x65, 0x6C, 0x61, 0x79], // "Relay"
    'RESTAURAR_COMBUSTIVEL': [0x52, 0x65, 0x6C, 0x61, 0x79], // "Relay"
    'BLOQUEIO': [0x53, 0x54, 0x4F, 0x50], // "STOP"
    'DESBLOQUEIO': [0x52, 0x45, 0x53, 0x55, 0x4D, 0x45], // "RESUME"
    'REINICIAR': [0x52, 0x45, 0x53, 0x45, 0x54], // "RESET"
    'LOCALIZAR': [0x57, 0x48, 0x45, 0x52, 0x45], // "WHERE"
    'STATUS': [0x53, 0x54, 0x41, 0x54, 0x55, 0x53], // "STATUS"
    'PARAMETROS': [0x50, 0x41, 0x52, 0x41, 0x4D], // "PARAM"
  };

  /// Calcula o checksum do pacote GT06 (XOR de todos os bytes)
  static int calculateChecksum(Uint8List data) {
    int checksum = 0;
    for (int byte in data) {
      checksum ^= byte;
    }
    return checksum;
  }

  /// Calcula CRC16-CCITT (X25) - usado em algumas variantes do protocolo
  static int calculateCRC16(Uint8List data) {
    int crc = 0xFFFF;
    for (int byte in data) {
      crc ^= byte;
      for (int i = 0; i < 8; i++) {
        if ((crc & 0x0001) != 0) {
          crc = (crc >> 1) ^ 0x8408;
        } else {
          crc >>= 1;
        }
      }
    }
    return crc ^ 0xFFFF;
  }

  /// Verifica se os dados são um pacote GT06 válido
  static bool isValidPacket(Uint8List data) {
    if (data.length < 5) return false;
    
    // Verifica start bytes
    if (data[0] != START_BYTES[0] || data[1] != START_BYTES[1]) {
      return false;
    }

    // Verifica tamanho mínimo
    int contentLength = data[2];
    if (data.length < contentLength + 5) return false;

    // Verifica checksum (opcional - pode ser desabilitado para debug)
    // int checksum = data[contentLength + 3];
    // Uint8List content = data.sublist(2, contentLength + 3);
    // return calculateChecksum(content) == checksum;

    return true;
  }

  /// Parse de um pacote GT06
  static GT06Packet? parsePacket(Uint8List data) {
    try {
      if (!isValidPacket(data)) {
        return null;
      }

      int contentLength = data[2];
      int protocolNumber = data[3];
      Uint8List content = data.sublist(4, 4 + contentLength - 1);
      // int checksum = data[contentLength + 3];
      // int endByte1 = data[contentLength + 4];
      // int endByte2 = data[contentLength + 5];

      String type = _getProtocolType(protocolNumber);
      Map<String, dynamic> parsedData = _parseContent(protocolNumber, content);

      return GT06Packet(
        protocolNumber: protocolNumber,
        type: type,
        rawData: data,
        parsedData: parsedData,
        timestamp: DateTime.now(),
      );
    } catch (e) {
      print('Erro ao fazer parse do pacote GT06: $e');
      return null;
    }
  }

  /// Retorna o tipo de protocolo baseado no número
  static String _getProtocolType(int protocolNumber) {
    switch (protocolNumber) {
      case PROTOCOL_LOGIN:
        return 'LOGIN';
      case PROTOCOL_LOCATION:
        return 'LOCATION';
      case PROTOCOL_STATUS:
        return 'STATUS';
      case PROTOCOL_STRING:
        return 'STRING';
      case PROTOCOL_ALARM:
        return 'ALARM';
      case PROTOCOL_COMMAND:
        return 'COMMAND';
      case PROTOCOL_COMMAND_RESPONSE:
        return 'COMMAND_RESPONSE';
      case PROTOCOL_TIME_REQUEST:
        return 'TIME_REQUEST';
      case PROTOCOL_INFO:
        return 'INFO';
      default:
        return 'UNKNOWN(0x${protocolNumber.toRadixString(16).padLeft(2, '0')})';
    }
  }

  /// Parse do conteúdo baseado no tipo de protocolo
  static Map<String, dynamic> _parseContent(int protocolNumber, Uint8List content) {
    Map<String, dynamic> result = {};

    switch (protocolNumber) {
      case PROTOCOL_LOGIN:
        result['imei'] = _bytesToHex(content.sublist(0, 8));
        result['model'] = content.length > 8 ? String.fromCharCodes(content.sublist(8)) : 'Unknown';
        break;

      case PROTOCOL_LOCATION:
        if (content.length >= 20) {
          result['date'] = _parseDate(content.sublist(0, 6));
          result['gps_count'] = content[6];
          result['latitude'] = _parseCoordinate(content.sublist(7, 11));
          result['longitude'] = _parseCoordinate(content.sublist(11, 15));
          result['speed'] = content[15];
          result['course'] = _parseCourse(content.sublist(16, 18));
          result['status'] = _parseStatus(content.sublist(18, 20));
        }
        break;

      case PROTOCOL_STATUS:
        if (content.length >= 5) {
          result['status'] = _parseDeviceStatus(content);
        }
        break;

      case PROTOCOL_STRING:
      case PROTOCOL_COMMAND:
        try {
          result['message'] = utf8.decode(content);
        } catch (e) {
          result['raw'] = _bytesToHex(content);
        }
        break;

      case PROTOCOL_ALARM:
        if (content.length >= 20) {
          result['date'] = _parseDate(content.sublist(0, 6));
          result['alarm_type'] = _getAlarmType(content[6]);
          result['latitude'] = _parseCoordinate(content.sublist(7, 11));
          result['longitude'] = _parseCoordinate(content.sublist(11, 15));
          result['alarm_status'] = _bytesToHex(content.sublist(16, 20));
        }
        break;

      default:
        result['raw'] = _bytesToHex(content);
    }

    return result;
  }

  /// Cria uma resposta de comando para o rastreador
  static Uint8List createCommandResponse(String command, {int serialNumber = 0x0001}) {
    List<int> commandBytes = utf8.encode(command);
    int contentLength = 5 + commandBytes.length;

    List<int> packet = [
      ...START_BYTES,
      contentLength,
      PROTOCOL_COMMAND,
      0x00, // Flag do servidor
      0x01, // Comando tipo texto
      ...commandBytes.length.toRadixString(16).padLeft(4, '0').codeUnits,
      ...commandBytes,
      (serialNumber >> 8) & 0xFF,
      serialNumber & 0xFF,
    ];

    // Calcula e adiciona checksum
    int checksum = calculateChecksum(Uint8List.fromList(packet.sublist(2)));
    packet.add(checksum);
    packet.addAll(STOP_BYTES);

    return Uint8List.fromList(packet);
  }

  /// Cria resposta de login
  static Uint8List createLoginResponse({int serialNumber = 0x0001}) {
    List<int> packet = [
      ...START_BYTES,
      0x05, // Content length
      PROTOCOL_LOGIN,
      0x00, // Resposta OK
      (serialNumber >> 8) & 0xFF,
      serialNumber & 0xFF,
    ];

    int checksum = calculateChecksum(Uint8List.fromList(packet.sublist(2)));
    packet.add(checksum);
    packet.addAll(STOP_BYTES);

    return Uint8List.fromList(packet);
  }

  /// Cria resposta de heartbeat/status
  static Uint8List createStatusResponse({int serialNumber = 0x0001}) {
    List<int> packet = [
      ...START_BYTES,
      0x05, // Content length
      PROTOCOL_STATUS,
      0x00, // Resposta OK
      (serialNumber >> 8) & 0xFF,
      serialNumber & 0xFF,
    ];

    int checksum = calculateChecksum(Uint8List.fromList(packet.sublist(2)));
    packet.add(checksum);
    packet.addAll(STOP_BYTES);

    return Uint8List.fromList(packet);
  }

  // Helpers

  static String _bytesToHex(Uint8List bytes) {
    return bytes.map((b) => b.toRadixString(16).padLeft(2, '0').toUpperCase()).join('');
  }

  static String _parseDate(Uint8List bytes) {
    if (bytes.length < 6) return 'Invalid';
    int year = 2000 + bytes[0];
    int month = bytes[1];
    int day = bytes[2];
    int hour = bytes[3];
    int minute = bytes[4];
    int second = bytes[5];
    return '$year-${month.toString().padLeft(2, '0')}-${day.toString().padLeft(2, '0')} '
           '${hour.toString().padLeft(2, '0')}:${minute.toString().padLeft(2, '0')}:${second.toString().padLeft(2, '0')}';
  }

  static double _parseCoordinate(Uint8List bytes) {
    if (bytes.length < 4) return 0.0;
    int raw = (bytes[0] << 24) | (bytes[1] << 16) | (bytes[2] << 8) | bytes[3];
    return raw / 30000.0 / 60.0;
  }

  static double _parseCourse(Uint8List bytes) {
    if (bytes.length < 2) return 0.0;
    int raw = (bytes[0] << 8) | bytes[1];
    return (raw & 0x03FF) * 0.1;
  }

  static Map<String, dynamic> _parseStatus(Uint8List bytes) {
    if (bytes.length < 2) return {};
    int status = (bytes[0] << 8) | bytes[1];
    return {
      'acc_on': (status & 0x0001) != 0,
      'gps_positioned': (status & 0x0002) != 0,
      'south_latitude': (status & 0x0004) != 0,
      'west_longitude': (status & 0x0008) != 0,
      'status': (status >> 4) & 0x03,
      'gps_realtime': (status & 0x0040) != 0,
    };
  }

  static Map<String, dynamic> _parseDeviceStatus(Uint8List content) {
    if (content.length < 5) return {};
    return {
      'terminal_info': _bytesToHex(content.sublist(0, 1)),
      'voltage_level': content[1],
      'gsm_signal': content[2],
      'alarm_language': _bytesToHex(content.sublist(3, 5)),
    };
  }

  static String _getAlarmType(int type) {
    switch (type) {
      case 0x00: return 'NORMAL';
      case 0x01: return 'SOS';
      case 0x02: return 'POWER_CUT';
      case 0x03: return 'VIBRATION';
      case 0x04: return 'GEO_FENCE_IN';
      case 0x05: return 'GEO_FENCE_OUT';
      case 0x06: return 'OVERSPEED';
      case 0x09: return 'ACC_ON';
      case 0x0A: return 'ACC_OFF';
      case 0x0E: return 'LOW_BATTERY';
      default: return 'UNKNOWN(0x${type.toRadixString(16)})';
    }
  }

  /// Decodifica um comando recebido do servidor
  static Map<String, dynamic> decodeServerCommand(Uint8List data) {
    Map<String, dynamic> result = {
      'raw_hex': _bytesToHex(data),
      'raw_ascii': String.fromCharCodes(data.where((b) => b >= 32 && b < 127)),
      'timestamp': DateTime.now().toIso8601String(),
    };

    // Tenta identificar o comando
    String ascii = result['raw_ascii'].toString().toUpperCase();
    
    if (ascii.contains('STOP') || ascii.contains('BLOQUEAR') || ascii.contains('CUT')) {
      result['command_type'] = 'BLOQUEIO';
      result['action'] = 'Bloquear veículo';
    } else if (ascii.contains('RESUME') || ascii.contains('DESBLOQUEAR') || ascii.contains('RESTORE')) {
      result['command_type'] = 'DESBLOQUEIO';
      result['action'] = 'Desbloquear veículo';
    } else if (ascii.contains('WHERE') || ascii.contains('LOCATE') || ascii.contains('POSITION')) {
      result['command_type'] = 'LOCALIZACAO';
      result['action'] = 'Solicitar localização';
    } else if (ascii.contains('RESET') || ascii.contains('REINICIAR')) {
      result['command_type'] = 'REINICIAR';
      result['action'] = 'Reiniciar rastreador';
    } else if (ascii.contains('STATUS')) {
      result['command_type'] = 'STATUS';
      result['action'] = 'Solicitar status';
    } else if (ascii.contains('PARAM')) {
      result['command_type'] = 'PARAMETROS';
      result['action'] = 'Configurar parâmetros';
    } else {
      result['command_type'] = 'DESCONHECIDO';
      result['action'] = 'Comando não reconhecido';
    }

    return result;
  }
}
