import 'dart:convert';
import 'dart:io' show Platform;
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, ChangeNotifier;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:timezone/timezone.dart' as tz;
import './models.dart';

// --- Auth Service ---
class AuthService with ChangeNotifier {
  final FirebaseAuth _auth = FirebaseAuth.instance;
  final GoogleSignIn _googleSignIn = GoogleSignIn();
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
  
  Future<void> signInWithGoogle() async {
    try {
      final GoogleSignInAccount? googleUser = await _googleSignIn.signIn();
      if (googleUser == null) {
        return; // User cancelled the sign-in
      }
      final GoogleSignInAuthentication googleAuth = await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    // FIX: Only catch FirebaseAuthExceptions as actual login failures.
    // Other exceptions from the GMS services can be ignored if login succeeds.
    } on FirebaseAuthException catch (e) {
      throw e.message ?? 'An unknown error occurred while signing in with Google.';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

// --- Firestore Service ---
class FirestoreService {
  final String? uid;
  FirestoreService(this.uid);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  static const _localCacheKey = 'all_goals_cache';

  Future<void> saveGoals(List<Goal> allGoals) async {
    if (uid == null) return;
    final userDoc = _db.collection('users').doc(uid);
    
    final user = FirebaseAuth.instance.currentUser;
    if (user?.email != null) {
        await userDoc.set({'email': user!.email}, SetOptions(merge: true));
    }

    final goalsCollection = userDoc.collection('goals');
    for (var goal in allGoals) {
      goal.userId = uid;
      await goalsCollection.doc(goal.id).set(goal.toJson());
    }

    final prefs = await SharedPreferences.getInstance();
    final String goalsJson =
        json.encode(allGoals.map((g) => g.toJson()).toList());
    await prefs.setString(_localCacheKey, goalsJson);
  }

  Future<List<Goal>> loadGoals() async {
    final prefs = await SharedPreferences.getInstance();
    final String? localGoalsJson = prefs.getString(_localCacheKey);
    if (localGoalsJson != null) {
      final List<dynamic> decodedJson = json.decode(localGoalsJson);
      return decodedJson.map((g) => Goal.fromJson(g)).toList();
    }

    if (uid == null) return [];
    final goalsCollection = _db.collection('users').doc(uid).collection('goals');
    final snapshot = await goalsCollection.get();
    final goals = snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    final String goalsJson = json.encode(goals.map((g) => g.toJson()).toList());
    await prefs.setString(_localCacheKey, goalsJson);
    return goals;
  }

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

    final summary = await SuggestionService.getMonthlyReportSummary(currentData, previousData);

    return {'currentPeriod': currentData, 'previousPeriod': previousData, 'summary': summary};
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

class SuggestionService {
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

  static Future<String> getTaskClarityAdvice(String goalTitle, String milestoneTitle, String taskList) async {
    final prompt = """
    A user is setting up a new milestone for their main goal. Critique the clarity and actionability of their milestone and tasks, and provide constructive feedback with 2-3 better, more specific examples. The user's input might be vague or gibberish.

    Main Goal: "$goalTitle"
    User's Milestone Title: "$milestoneTitle"
    User's Task List (one per line):
    $taskList

    Your response should be a single, helpful paragraph. Start by gently pointing out that the tasks could be more specific. Then provide the examples.

    Example response for a vague input:
    "Breaking down a big goal is a great step! To make your milestones even more effective, try making the tasks more specific and actionable. For example, instead of 'marketing', you could have tasks like 'Draft 3 social media posts' or 'Research 5 potential marketing channels'."
    """;
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

final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

// FIX: Updated notification logic for clarity and robustness
Future<void> initNotifications(BuildContext context) async {
  if (kIsWeb || !(Platform.isAndroid || Platform.isIOS)) {
    return;
  }

  // 1. Initialize the plugin first
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');
  final DarwinInitializationSettings initializationSettingsIOS =
      DarwinInitializationSettings();
  final InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
    iOS: initializationSettingsIOS,
  );
  await flutterLocalNotificationsPlugin.initialize(initializationSettings);

  // 2. Request basic notification permission
  await Permission.notification.request();

  // 3. Check and request the special "exact alarm" permission
  final alarmStatus = await Permission.scheduleExactAlarm.status;
  if (alarmStatus.isDenied) {
    // If denied, we need to guide the user to settings.
    await showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Permission Required'),
        content: const Text(
            'To send reminders at a specific time, this app needs permission to schedule alarms. Please enable this in the app settings.'),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(ctx).pop(),
              child: const Text('Later')),
          TextButton(
              onPressed: () {
                openAppSettings();
                Navigator.of(ctx).pop();
              },
              child: const Text('Open Settings')),
        ],
      ),
    );
  }
}


Future<void> scheduleNotification(
    int id, String title, String body, int hour, int minute) async {
  if (await Permission.notification.isDenied || await Permission.scheduleExactAlarm.isDenied) {
      print("Permissions are denied. Cannot schedule notification.");
      return;
  }
    
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

  try {
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
    print("Notification scheduled successfully for $hour:$minute");
  } catch(e) {
    print("Error scheduling notification: $e");
  }
}

