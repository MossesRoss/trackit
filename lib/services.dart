import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import './models.dart';

// --- Auth Service ---
class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  User? _user;

  AuthService() {
    _auth.authStateChanges().listen((user) {
      _user = user;
      notifyListeners();
    });
  }

  User? get currentUser => _user;
  Stream<User?> get authStateChanges => _auth.authStateChanges();

  Future<void> signInWithEmail(String email, String password) async {
    try {
      await _auth.signInWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An unknown error occurred.';
    }
  }

  Future<void> signUpWithEmail(String email, String password) async {
    try {
      await _auth.createUserWithEmailAndPassword(email: email, password: password);
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An unknown error occurred.';
    }
  }

  Future<void> signOut() async {
    await _auth.signOut();
  }
}

// --- Firestore Service (Cloud & Local Cache Hybrid) ---
class FirestoreService {
  final String? uid;
  FirestoreService(this.uid);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _localCacheKey = 'all_goals_cache';

  // Save goals to both Firestore and local cache
  Future<void> saveGoals(List<Goal> allGoals) async {
    if (uid == null) return;
    final goalsCollection = _db.collection('users').doc(uid).collection('goals');

    // Write to Firestore
    for (var goal in allGoals) {
      goal.userId = uid;
      await goalsCollection.doc(goal.id).set(goal.toJson());
    }

    // Write to local cache
    final prefs = await SharedPreferences.getInstance();
    final String goalsJson =
        json.encode(allGoals.map((g) => g.toJson()).toList());
    await prefs.setString(_localCacheKey, goalsJson);
  }

  // Load goals from local cache first, then sync with Firestore
  Future<List<Goal>> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    
    // Try loading from local cache first for speed
    final String? localGoalsJson = prefs.getString(_localCacheKey);
    if (localGoalsJson != null) {
      final List<dynamic> decodedJson = json.decode(localGoalsJson);
      final localGoals = decodedJson.map((g) => Goal.fromJson(g)).toList();
      // Return local goals immediately for a fast UI response
      // In a real app, you might trigger a background sync with Firestore here
      return localGoals;
    }

    // If no local cache, fetch from Firestore
    if (uid == null) return [];
    final goalsCollection = _db.collection('users').doc(uid).collection('goals');
    final snapshot = await goalsCollection.get();
    final goals = snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    // Save the fetched goals to the local cache for next time
    final String goalsJson = json.encode(goals.map((g) => g.toJson()).toList());
    await prefs.setString(_localCacheKey, goalsJson);

    return goals;
  }

  // --- REPORTING LOGIC ---
  Future<Map<String, dynamic>> _getPeriodData(DateTime start, DateTime end) async {
    final allGoals = await loadGoals();
    Duration totalTime = Duration.zero;
    int tasksCompleted = 0;

    for (final goal in allGoals) {
      for (final milestone in goal.milestones) {
        if (milestone.lastWorkedOn != null &&
            milestone.lastWorkedOn!.isAfter(start) &&
            milestone.lastWorkedOn!.isBefore(end)) {
          totalTime += milestone.timeSpent;
          tasksCompleted += milestone.completedCheckpointIds.length;
        }
      }
    }
    return {'timeSpent': totalTime, 'tasksCompleted': tasksCompleted};
  }

  Future<Map<String, dynamic>> getWeeklyReport() async {
    final now = DateTime.now();
    final startOfWeek = now.subtract(Duration(days: now.weekday - 1));
    final endOfWeek = startOfWeek.add(const Duration(days: 6));
    final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));
    
    final currentData = await _getPeriodData(startOfWeek, endOfWeek);
    final previousData = await _getPeriodData(startOfLastWeek, startOfWeek);

    return {'currentPeriod': currentData, 'previousPeriod': previousData};
  }

  Future<Map<String, dynamic>> getMonthlyReport() async {
    final now = DateTime.now();
    final startOfMonth = DateTime(now.year, now.month, 1);
    final endOfMonth = DateTime(now.year, now.month + 1, 0);
    final startOfLastMonth = DateTime(now.year, now.month - 1, 1);
    
    final currentData = await _getPeriodData(startOfMonth, endOfMonth);
    final previousData = await _getPeriodData(startOfLastMonth, startOfMonth);

    // Generate AI Summary for Monthly Report
    final aiSummary = await AIService.getMonthlyReportSummary(currentData, previousData);

    return {'currentPeriod': currentData, 'previousPeriod': previousData, 'aiSummary': aiSummary};
  }

  Future<Map<String, dynamic>> getYearlyReport() async {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31);
    final startOfLastYear = DateTime(now.year - 1, 1, 1);

    final currentData = await _getPeriodData(startOfYear, endOfYear);
    final previousData = await _getPeriodData(startOfLastYear, startOfYear);

    return {'currentPeriod': currentData, 'previousPeriod': previousData};
  }
}


// --- AI Service ---
class AIService {
  static final String? _apiKey = dotenv.env['GEMINI_API_KEY'];

  static Future<String> _callGemini(String prompt) async {
    if (_apiKey == null || _apiKey!.isEmpty) {
      return "API Key is missing. Please add it to your .env file.";
    }

    const model = 'gemini-1.5-flash-latest';
    final url = Uri.parse(
        'https://generativelanguage.googleapis.com/v1beta/models/$model:generateContent?key=$_apiKey');

    try {
      final response = await http.post(
        url,
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [{'role': 'user', 'parts': [{'text': prompt}]}]
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

  static Future<String> getSuggestion(Milestone nextMilestone) async {
    final remainingTasks = nextMilestone.checkpoints
        .where((c) => !nextMilestone.completedCheckpointIds.contains(c.id))
        .map((c) => c.title)
        .join(', ');

    final prompt =
        "My current milestone is '${nextMilestone.title}' due on ${DateFormat.yMMMd().format(nextMilestone.deadline)}. The remaining tasks are: $remainingTasks. What is a single, concise, and actionable task I should focus on right now to make progress? Keep it short, motivating, and start with an action verb.";
    
    return _callGemini(prompt);
  }

  static Future<String> getMonthlyReportSummary(Map<String, dynamic> currentData, Map<String, dynamic> previousData) async {
      final prompt = """
      Generate a concise, encouraging monthly performance report for a user of a goal-setting app.
      Focus on positive reinforcement, even for small improvements.
      Do not use markdown. Keep it to a single paragraph.

      Data:
      - This month's time spent: ${currentData['timeSpent']}
      - This month's tasks completed: ${currentData['tasksCompleted']}
      - Last month's time spent: ${previousData['timeSpent']}
      - Last month's tasks completed: ${previousData['tasksCompleted']}

      Example Output:
      "Great work this month! You dedicated a solid amount of time to your goals and made tangible progress. You've shown fantastic consistency. Keep that momentum going into next month!"
      """;
      return _callGemini(prompt);
  }
}

// --- Notification Service (Largely unchanged) ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  // ... (rest of the notification code is unchanged)
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

