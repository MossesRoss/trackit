import 'dart:convert';
import 'dart:io' show Platform;
import 'package:flutter/foundation.dart' show kIsWeb;
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import './models.dart'; // <-- FIX: Corrected the import path

// --- Notification Service ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  if (!kIsWeb) {
    if (Platform.isAndroid || Platform.isIOS) {
      await Permission.notification.isDenied.then((value) {
        if (value) {
          Permission.notification.request();
        }
      });
    }
  }

  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  const LinuxInitializationSettings initializationSettingsLinux =
      LinuxInitializationSettings(defaultActionName: 'Open notification');
  final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings(
          requestAlertPermission: true,
          requestBadgePermission: true,
          requestSoundPermission: true);

  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    linux: initializationSettingsLinux,
    iOS: initializationSettingsIOS,
    macOS: initializationSettingsIOS,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

Future<void> scheduleNotification(
    int id, String title, String body, int hour, int minute) async {
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  var androidPlatformChannelSpecifics = const AndroidNotificationDetails(
      'milestone_channel_id', 'Milestone Reminders',
      channelDescription: 'Channel for Milestone app reminders',
      importance: Importance.max,
      priority: Priority.high,
      showWhen: false);
  var platformChannelSpecifics =
      NotificationDetails(android: androidPlatformChannelSpecifics);

  await flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    title,
    body,
    _nextInstanceOfTime(hour, minute),
    platformChannelSpecifics,
    uiLocalNotificationDateInterpretation:
        UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}

// --- Persistence Service ---
class PersistenceService {
  static const _key = 'all_goals';

  static Future<List<Goal>> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final String? goalsJson = prefs.getString(_key);
    if (goalsJson != null) {
      final List<dynamic> decodedJson = json.decode(goalsJson);
      return decodedJson.map((g) => Goal.fromJson(g)).toList();
    }
    return [];
  }

  static Future<void> saveGoals(List<Goal> allGoals) async {
    final prefs = await SharedPreferences.getInstance();
    final String goalsJson =
        json.encode(allGoals.map((g) => g.toJson()).toList());
    await prefs.setString(_key, goalsJson);
  }
}

// --- AI Service ---
class AIService {
  static Future<String> getSuggestion(Milestone nextMilestone) async {
    const apiKey = "YOUR_API_KEY"; // IMPORTANT: Add your API key here
    if (apiKey.isEmpty || apiKey == "YOUR_API_KEY") {
      return "Please add your Gemini API Key in `lib/services.dart` to enable this feature.";
    }

    const model = 'gemini-1.5-flash-latest';
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$apiKey');

    final remainingTasks = nextMilestone.checkpoints
        .where((c) => !nextMilestone.completedCheckpointIds.contains(c.id))
        .map((c) => c.title)
        .join(', ');

    final prompt =
        "My current milestone is '${nextMilestone.title}' due on ${DateFormat.yMMMd().format(nextMilestone.deadline)}. The remaining tasks are: $remainingTasks. What is a single, concise, and actionable task I should focus on right now to make progress? Keep it short, motivating, and start with an action verb.";

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [
            {
              'role': 'user',
              'parts': [
                {'text': prompt}
              ]
            }
          ]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      } else {
        final errorBody = json.decode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? 'Unknown API error.';
        return "Error ${response.statusCode}: $errorMessage";
      }
    } catch (e) {
      return "Error: Failed to connect. Check network or API key.";
    }
  }
}

