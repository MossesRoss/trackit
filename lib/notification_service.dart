import 'dart:convert';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:rxdart/rxdart.dart';
import 'package:timezone/timezone.dart' as tz;
import './models.dart';

// --- Action IDs for notifications ---
const String doneActionId = 'DONE_ACTION';
const String doingActionId = 'DOING_ACTION';
const String willDoActionId = 'WILL_DO_ACTION';
const String wontDoActionId = 'WONT_DO_ACTION';

// --- ReceivedNotification class for stream ---
class ReceivedNotification {
  ReceivedNotification({
    required this.id,
    required this.title,
    required this.body,
    required this.payload,
  });

  final int id;
  final String? title;
  final String? body;
  final String? payload;
}

// --- TOP-LEVEL FUNCTION FOR BACKGROUND HANDLING ---
// This annotation is critical for background execution on Android.
@pragma('vm:entry-point')
void notificationTapBackground(NotificationResponse notificationResponse) {
  // Handle your tap events here.
  debugPrint('Notification tapped in background: ${notificationResponse.payload}');
}


class NotificationService {
  // --- Singleton Pattern ---
  static final NotificationService _instance = NotificationService._internal();
  factory NotificationService() => _instance;
  NotificationService._internal();

  final FlutterLocalNotificationsPlugin _flutterLocalNotificationsPlugin =
      FlutterLocalNotificationsPlugin();

  // --- Stream to pass notification data to the UI ---
  final BehaviorSubject<ReceivedNotification> _didReceiveLocalNotificationSubject =
      BehaviorSubject<ReceivedNotification>();
  
  // Stream for the UI to listen to notification responses
  final BehaviorSubject<NotificationResponse> selectNotificationSubject =
      BehaviorSubject<NotificationResponse>();


  Future<void> init() async {
    // --- Android Initialization ---
    const AndroidInitializationSettings initializationSettingsAndroid =
        AndroidInitializationSettings('@mipmap/ic_launcher');

    // --- iOS Initialization ---
    final DarwinInitializationSettings initializationSettingsDarwin =
        DarwinInitializationSettings(
      onDidReceiveLocalNotification: (int id, String? title, String? body, String? payload) async {
        _didReceiveLocalNotificationSubject.add(
          ReceivedNotification(id: id, title: title, body: body, payload: payload),
        );
      },
    );

    // --- General Initialization ---
    final InitializationSettings initializationSettings = InitializationSettings(
      android: initializationSettingsAndroid,
      iOS: initializationSettingsDarwin,
    );

    await _flutterLocalNotificationsPlugin.initialize(
      initializationSettings,
      onDidReceiveNotificationResponse: (NotificationResponse notificationResponse) {
        selectNotificationSubject.add(notificationResponse);
      },
      onDidReceiveBackgroundNotificationResponse: notificationTapBackground,
    );
     debugPrint("Notification Service Initialized.");
  }

  // --- Method to schedule a recurring reminder ---
  Future<void> scheduleReminderNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
    required int hour,
    required int minute,
  }) async {
    final tz.TZDateTime scheduledDate = _nextInstanceOfTime(hour, minute);

    const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'reminder_channel_id',
      'Milestone Reminders',
      channelDescription: 'Channel for daily milestone reminders.',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(doneActionId, 'Done'),
        AndroidNotificationAction(doingActionId, 'Doing'),
        AndroidNotificationAction(willDoActionId, 'Will Do'),
        AndroidNotificationAction(wontDoActionId, 'Won\'t Do'),
      ],
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    try {
      await _flutterLocalNotificationsPlugin.zonedSchedule(
        id,
        title,
        body,
        scheduledDate,
        notificationDetails,
        payload: payload,
        androidScheduleMode: AndroidScheduleMode.exactAllowWhileIdle,
        uiLocalNotificationDateInterpretation:
            UILocalNotificationDateInterpretation.absoluteTime,
        matchDateTimeComponents: DateTimeComponents.time,
      );
      debugPrint("SUCCESS: Scheduled reminder #$id for $scheduledDate with payload: $payload");
    } catch (e) {
      debugPrint("ERROR scheduling reminder #$id: $e");
    }
  }
  
  // --- Method to show an immediate check-in notification ---
  Future<void> showTaskCheckinNotification({
    required int id,
    required String title,
    required String body,
    required String payload,
  }) async {
     const AndroidNotificationDetails androidNotificationDetails =
        AndroidNotificationDetails(
      'checkin_channel_id',
      'Task Check-ins',
      channelDescription: 'Channel for immediate task check-ins.',
      importance: Importance.max,
      priority: Priority.high,
      actions: <AndroidNotificationAction>[
        AndroidNotificationAction(doneActionId, 'Done'),
        AndroidNotificationAction(doingActionId, 'Doing'),
        AndroidNotificationAction(willDoActionId, 'Will Do'),
        AndroidNotificationAction(wontDoActionId, 'Won\'t Do'),
      ],
    );

    const NotificationDetails notificationDetails = NotificationDetails(
      android: androidNotificationDetails,
    );

    try {
      await _flutterLocalNotificationsPlugin.show(
        id,
        title,
        body,
        notificationDetails,
        payload: payload,
      );
       debugPrint("SUCCESS: Shown check-in notification #$id with payload: $payload");
    } catch (e) {
       debugPrint("ERROR showing check-in notification #$id: $e");
    }
  }

  // --- Method to show a persistent notification for the focus session ---
  Future<void> showFocusNotification(String milestoneTitle) async {
    const AndroidNotificationDetails androidPlatformChannelSpecifics = AndroidNotificationDetails(
        'focus_channel_id', 'Focus Mode',
        channelDescription: 'Notification shown while in a focus session.',
        importance: Importance.low,
        priority: Priority.low,
        ongoing: true,
        autoCancel: false,
    );
    const NotificationDetails platformChannelSpecifics =
        NotificationDetails(android: androidPlatformChannelSpecifics);
    
    await _flutterLocalNotificationsPlugin.show(
      99, // Unique ID for focus notification
      'Focusing on: $milestoneTitle',
      'Your session is in progress...',
      platformChannelSpecifics,
    );
  }

  // --- Method to cancel the persistent focus notification ---
  Future<void> cancelFocusNotification() async {
    await _flutterLocalNotificationsPlugin.cancel(99);
  }


  // --- Helper to calculate next notification time ---
  tz.TZDateTime _nextInstanceOfTime(int hour, int minute) {
    final tz.TZDateTime now = tz.TZDateTime.now(tz.local);
    tz.TZDateTime scheduledDate =
        tz.TZDateTime(tz.local, now.year, now.month, now.day, hour, minute);
    if (scheduledDate.isBefore(now)) {
      scheduledDate = scheduledDate.add(const Duration(days: 1));
    }
    return scheduledDate;
  }

  // --- Method to cancel a specific notification ---
  Future<void> cancelNotification(int id) async {
    await _flutterLocalNotificationsPlugin.cancel(id);
    debugPrint("Cancelled notification #$id");
  }

  // --- Dispose streams ---
  void dispose() {
    _didReceiveLocalNotificationSubject.close();
    selectNotificationSubject.close();
  }
}