import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './models.dart';
import './notification_service.dart'; // Import the new service

// --- Auth Service (unchanged) ---
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

  Future<void> archiveGoal(Goal goal) async {
    if (uid == null) return;
    final archiveDoc = _db.collection('archived_goals').doc(goal.id);
    goal.isArchived = true;
    await archiveDoc.set(goal.toJson());
  }

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

  Future<Map<String, dynamic>> _getPeriodData(DateTime start, DateTime end, {bool isYearly = false}) async {
    final allGoals = await loadGoals();
    
    Duration totalTime = Duration.zero;
    int tasksCompleted = 0;
    Map<TaskCheckinStatus, int> checkinCounts = {
      for (var status in TaskCheckinStatus.values) status: 0
    };

    for (final goal in allGoals) {
      for (final milestone in goal.milestones) {
        if (milestone.lastWorkedOn != null &&
            milestone.lastWorkedOn!.isAfter(start) &&
            milestone.lastWorkedOn!.isBefore(end)) {
          totalTime += milestone.timeSpent;
        }
        tasksCompleted += milestone.completedCheckpointIds.length;

        for (final checkin in milestone.checkins) {
          if (checkin.timestamp.isAfter(start) && checkin.timestamp.isBefore(end)) {
            checkinCounts[checkin.status] = (checkinCounts[checkin.status] ?? 0) + 1;
          }
        }
      }
    }
    return {
      'timeSpent': totalTime, 
      'tasksCompleted': tasksCompleted,
      'checkinCounts': checkinCounts
    };
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

    final currentData = await _getPeriodData(startOfYear, endOfYear, isYearly: true);
    final previousData = await _getPeriodData(startOfLastYear, startOfYear);

    final querySnapshot = await _db.collection('archived_goals')
      .where('userId', isEqualTo: uid)
      .where('createdAt', isGreaterThanOrEqualTo: startOfYear.toIso8601String())
      .where('createdAt', isLessThanOrEqualTo: endOfYear.toIso8601String())
      .get();
    
    final archivedGoals = querySnapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();
    
    return {
      'currentPeriod': currentData, 
      'previousPeriod': previousData,
      'archivedGoals': archivedGoals
    };
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

      if (response.statusCode == 503) {
        return "The AI service is temporarily unavailable. Please try again later.";
      }

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        return data['candidates'][0]['content']['parts'][0]['text'].trim();
      } else {
        final errorBody = json.decode(response.body);
        final errorMessage = errorBody['error']?['message'] ?? 'Unknown API error.';
        debugPrint("Gemini API Error: ${response.body}");
        return "Error ${response.statusCode}: $errorMessage";
      }
    } catch (e) {
      debugPrint("Gemini connection Error: $e");
      return "Error: Failed to connect. Check network or API key.";
    }
  }

  static Future<String> getSuggestion(Goal? activeGoal, Milestone? nextMilestone) async {
    if (activeGoal == null || nextMilestone == null) {
      return "All tasks complete! Great job on finishing your milestones.";
    }
    
    final nextCheckpoint = nextMilestone.checkpoints.firstWhere(
      (c) => !nextMilestone.completedCheckpointIds.contains(c.id),
      orElse: () => Checkpoint(title: "No more tasks in this milestone"),
    );

    if (nextCheckpoint.title == "No more tasks in this milestone") {
      return "Milestone '${nextMilestone.title}' is complete! Well done!";
    }

    final payload = {
      'goalId': activeGoal.id,
      'milestoneId': nextMilestone.id,
      'checkpointId': nextCheckpoint.id,
    };
    NotificationService().showTaskCheckinNotification(
        id: 101, // Unique ID for this type of notification
        title: "How's it going?",
        body: "Progress on: ${nextCheckpoint.title}",
        payload: json.encode(payload));

    final prompt =
        "My current milestone is '${nextMilestone.title}' due on ${DateFormat.yMMMd().format(nextMilestone.deadline)}. My next task is: ${nextCheckpoint.title}. What is a single, concise, and actionable tip to help me with this specific task? Keep it short and motivating.";
    
    return _callGemini(prompt);
  }

  static Future<List<String>> getTaskSuggestions(String goalTitle, String milestoneTitle) async {
    final prompt = """
    A user is planning their goal.
    Main Goal: "$goalTitle"
    Current Milestone: "$milestoneTitle"
    
    Suggest 3 to 4 actionable, specific sub-tasks for this milestone. Respond with only a JSON object containing a single key 'tasks' which is an array of strings. Do not include markdown formatting like ```json.
    
    Example:
    {
      "tasks": [
        "Draft initial chapter outline",
        "Write 500 words for the first section",
        "Research key historical events for context"
      ]
    }
    """;
    try {
      final response = await _callGemini(prompt);
      final cleanedResponse = response.replaceAll('```json', '').replaceAll('```', '').trim();
      final decoded = json.decode(cleanedResponse);
      return List<String>.from(decoded['tasks']);
    } catch (e) {
      debugPrint("Error decoding task suggestions: $e");
      return [];
    }
  }

  static Future<String> getMonthlyReportSummary(Map<String, dynamic> currentData, Map<String, dynamic> previousData) async {
      final prompt = """
      Generate a concise, encouraging monthly performance report for a user of a goal-setting app.
      Focus on positive reinforcement, even for small improvements. If the user didn't make any progress
      Tell him the conciquences if he continues to do this.
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