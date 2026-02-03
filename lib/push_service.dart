import 'dart:developer' as developer;
import 'dart:io';

import 'package:firebase_crashlytics/firebase_crashlytics.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_background_geolocation/flutter_background_geolocation.dart' as bg;
import 'package:traccar_client/password_service.dart';
import 'package:traccar_client/command_log_service.dart';

import 'preferences.dart';

class PushService {
  static Future<void> init() async {
    await FirebaseMessaging.instance.requestPermission();
    FirebaseMessaging.onBackgroundMessage(pushServiceBackgroundHandler);
    FirebaseMessaging.onMessage.listen(_onMessage);
    FirebaseMessaging.instance.onTokenRefresh.listen(_uploadToken);
    
    // Upload token if already enabled
    final state = await bg.BackgroundGeolocation.state;
    if (state.enabled) {
      try {
        _uploadToken(await FirebaseMessaging.instance.getToken());
      } catch (error) {
        developer.log('Failed to get notification token', error: error);
      }
    }

    bg.BackgroundGeolocation.onEnabledChange((enabled) async {
      if (enabled) {
        try {
          _uploadToken(await FirebaseMessaging.instance.getToken());
        } catch (error) {
          developer.log('Failed to get notification token', error: error);
        }
      }
    });
  }

  static Future<void> _onMessage(RemoteMessage message) async {
    // Traccar sends commands in 'command' or 'type' field
    // Protocol commands might come in 'data' or 'payload'
    final String? commandType = message.data['command'] ?? message.data['type'];
    final String? payload = message.data['data'] ?? message.data['payload'];
    
    FirebaseCrashlytics.instance.log('push_command: $commandType');
    
    if (commandType != null) {
      // Log with more detail if it's a protocol command
      String displayCommand = commandType;
      if (payload != null && payload.isNotEmpty) {
        displayCommand = '$commandType ($payload)';
      }
      
      await CommandLogService.addLog(displayCommand, data: message.data);
      await _handleCommand(commandType, message.data);
    } else if (message.notification != null) {
      await CommandLogService.addLog('Notification: ${message.notification?.title}', data: {'body': message.notification?.body});
    }
  }

  static Future<void> _handleCommand(String command, Map<String, dynamic> data) async {
    developer.log('Handling command: $command with data: $data');

    // Handle standard Traccar commands and common protocol aliases
    switch (command) {
      // Position Commands
      case 'positionSingle':
      case 'locate':
      case 'WHERE#': // GT06 locate
        try {
          await bg.BackgroundGeolocation.getCurrentPosition(
            samples: 1, 
            persist: true, 
            extras: {'remote': true, 'command': command}
          );
        } catch (error) {
          developer.log('Failed to get position', error: error);
        }
        break;

      case 'positionPeriodic':
      case 'resume':
      case 'MOVING#':
        await bg.BackgroundGeolocation.start();
        break;

      case 'positionStop':
      case 'stop':
      case 'PAUSE#':
        await bg.BackgroundGeolocation.stop();
        break;

      // Engine / Motor Control Commands
      case 'engineStop':
      case 'motorStop':
      case 'RELAY,1#': // GT06 Cut off fuel
      case 'DYD,000000#': // GT06 Stop engine
        await CommandLogService.addLog('AÇÃO: MOTOR BLOQUEADO', data: {'status': 'blocked'});
        // Here you could trigger a local notification or UI change to show "Motor Bloqueado"
        break;

      case 'engineResume':
      case 'motorResume':
      case 'RELAY,0#': // GT06 Restore fuel
      case 'HFYD,000000#': // GT06 Resume engine
        await CommandLogService.addLog('AÇÃO: MOTOR LIBERADO', data: {'status': 'released'});
        break;

      // Configuration Commands
      case 'setFrequency':
      case 'frequency':
      case 'TIMER,': // GT06 Timer config
        final frequency = data['frequency'] ?? data['interval'];
        if (frequency != null) {
          final int? interval = int.tryParse(frequency.toString());
          if (interval != null) {
            await Preferences.instance.setInt(Preferences.interval, interval);
            await bg.BackgroundGeolocation.setConfig(bg.Config(
              geolocation: bg.GeoConfig(locationUpdateInterval: interval * 1000)
            ));
          }
        }
        break;

      case 'factoryReset':
      case 'FACTORY#':
        await PasswordService.setPassword('');
        break;
        
      default:
        // Check if it's a raw GT06-like command in the payload
        final String? payload = data['data'] ?? data['payload'];
        if (payload != null) {
           if (payload.contains('RELAY,1') || payload.contains('DYD')) {
             await CommandLogService.addLog('AÇÃO: MOTOR BLOQUEADO (via payload)', data: {'payload': payload});
           } else if (payload.contains('RELAY,0') || payload.contains('HFYD')) {
             await CommandLogService.addLog('AÇÃO: MOTOR LIBERADO (via payload)', data: {'payload': payload});
           }
        }
        developer.log('Unknown command received: $command');
    }
  }

  static Future<void> _uploadToken(String? token) async {
    if (token == null) return;
    final id = Preferences.instance.getString(Preferences.id);
    final url = Preferences.instance.getString(Preferences.url);
    if (id == null || url == null) return;
    
    try {
      final uri = Uri.parse(url);
      final client = HttpClient();
      final request = await client.postUrl(uri);
      
      request.headers.contentType = ContentType.parse('application/x-www-form-urlencoded');
      
      final body = 'id=${Uri.encodeComponent(id)}&notificationToken=${Uri.encodeComponent(token)}';
      request.write(body);
      
      final response = await request.close();
      developer.log('Token upload status: ${response.statusCode}');
    } catch (error) {
      developer.log('Failed to upload token', error: error);
    }
  }
}

@pragma('vm:entry-point')
Future<void> pushServiceBackgroundHandler(RemoteMessage message) async {
  await Preferences.init();
  await bg.BackgroundGeolocation.ready(Preferences.geolocationConfig());
  FirebaseCrashlytics.instance.log('push_background_handler');
  await PushService._onMessage(message);
}
