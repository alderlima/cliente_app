import 'dart:async';
import 'dart:convert';
import 'package:shared_preferences/shared_preferences.dart';

class CommandLog {
  final String command;
  final DateTime timestamp;
  final Map<String, dynamic>? data;

  CommandLog({
    required this.command,
    required this.timestamp,
    this.data,
  });

  Map<String, dynamic> toJson() => {
    'command': command,
    'timestamp': timestamp.toIso8601String(),
    'data': data,
  };

  factory CommandLog.fromJson(Map<String, dynamic> json) => CommandLog(
    command: json['command'],
    timestamp: DateTime.parse(json['timestamp']),
    data: json['data'],
  );
}

class CommandLogService {
  static const String _storageKey = 'command_logs';
  static final StreamController<List<CommandLog>> _logsController = StreamController<List<CommandLog>>.broadcast();
  static List<CommandLog> _logs = [];

  static Stream<List<CommandLog>> get logsStream => _logsController.stream;

  static Future<void> init() async {
    final prefs = await SharedPreferences.getInstance();
    final String? logsJson = prefs.getString(_storageKey);
    if (logsJson != null) {
      try {
        final List<dynamic> decoded = jsonDecode(logsJson);
        _logs = decoded.map((item) => CommandLog.fromJson(item)).toList();
      } catch (e) {
        _logs = [];
      }
    }
    _logsController.add(List.from(_logs));
  }

  static Future<void> addLog(String command, {Map<String, dynamic>? data}) async {
    final newLog = CommandLog(
      command: command,
      timestamp: DateTime.now(),
      data: data,
    );
    
    _logs.insert(0, newLog);
    if (_logs.length > 100) {
      _logs = _logs.sublist(0, 100);
    }
    
    // Notify listeners immediately
    _logsController.add(List.from(_logs));
    
    // Persist to storage
    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setString(_storageKey, jsonEncode(_logs.map((e) => e.toJson()).toList()));
    } catch (e) {
      // Handle potential storage errors
    }
  }

  static List<CommandLog> get currentLogs => List.from(_logs);

  static Future<void> clearLogs() async {
    _logs = [];
    _logsController.add([]);
    final prefs = await SharedPreferences.getInstance();
    await prefs.remove(_storageKey);
  }
}
