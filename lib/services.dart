import 'dart:convert';
import 'dart:math'; // For random quote index
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
// import 'package:flutter_dotenv/flutter_dotenv.dart'; // MOSSES FIX: No longer needed
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
      await _auth.createUserWithEmailAndPassword(
          email: email, password: password);
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
      final GoogleSignInAuthentication googleAuth =
          await googleUser.authentication;
      final AuthCredential credential = GoogleAuthProvider.credential(
        accessToken: googleAuth.accessToken,
        idToken: googleAuth.idToken,
      );
      await _auth.signInWithCredential(credential);
    } on FirebaseAuthException catch (e) {
      throw e.message ??
          'An unknown error occurred while signing in with Google.';
    }
  }

  Future<void> signOut() async {
    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

// --- Firestore Service (unchanged) ---
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
    final goals =
        snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    final String goalsJson = json.encode(goals.map((g) => g.toJson()).toList());
    await prefs.setString(_localCacheKey, goalsJson);
    return goals;
  }

  Future<Map<String, dynamic>> _getPeriodData(DateTime start, DateTime end,
      {bool isYearly = false}) async {
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
          if (checkin.timestamp.isAfter(start) &&
              checkin.timestamp.isBefore(end)) {
            checkinCounts[checkin.status] =
                (checkinCounts[checkin.status] ?? 0) + 1;
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

    final summary = await SuggestionService.getMonthlyReportSummary(
        currentData, previousData);

    return {
      'currentPeriod': currentData,
      'previousPeriod': previousData,
      'summary': summary
    };
  }

  Future<Map<String, dynamic>> getYearlyReport() async {
    final now = DateTime.now();
    final startOfYear = DateTime(now.year, 1, 1);
    final endOfYear = DateTime(now.year, 12, 31);
    final startOfLastYear = DateTime(now.year - 1, 1, 1);

    final currentData =
        await _getPeriodData(startOfYear, endOfYear, isYearly: true);
    final previousData = await _getPeriodData(startOfLastYear, startOfYear);

    final querySnapshot = await _db
        .collection('archived_goals')
        .where('userId', isEqualTo: uid)
        .where('createdAt',
            isGreaterThanOrEqualTo: startOfYear.toIso8601String())
        .where('createdAt', isLessThanOrEqualTo: endOfYear.toIso8601String())
        .get();

    final archivedGoals =
        querySnapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    return {
      'currentPeriod': currentData,
      'previousPeriod': previousData,
      'archivedGoals': archivedGoals
    };
  }
}

// --- NEW: Helper class for Suggestion Service results ---
class SuggestionResult {
  final String? suggestion;
  final String? error; // e.g., "NO_API_KEY", "API_ERROR", "NETWORK_ERROR"

  SuggestionResult({this.suggestion, this.error});
}

// MOSSES FIX: This entire service has been updated
class SuggestionService {
  // MOSSES FIX: Updated to modern Gemini 2.5 Flash model
  static const String _model = 'gemini-2.5-flash-preview-09-2025';
  static const String _apiUrl =
      '[https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=](https://generativelanguage.googleapis.com/v1beta/models/$_model:generateContent?key=)';

  // MOSSES FIX: Rewritten _callGemini for robustness
  static Future<SuggestionResult> _callGemini(String prompt,
      {bool isJson = false, int retries = 3}) async {
    final prefs = await SharedPreferences.getInstance();
    final String? apiKey = prefs.getString('gemini_api_key');

    if (apiKey == null || apiKey.isEmpty) {
      debugPrint("Gemini API Error: Key is missing.");
      return SuggestionResult(error: "NO_API_KEY");
    }

    final url = Uri.parse('$_apiUrl$apiKey');
    int retryCount = 0;
    int delay = 1000;

    final generationConfig = isJson
        ? {
            "responseMimeType": "application/json",
            "responseSchema": {
              "type": "OBJECT",
              "properties": {
                "tasks": {
                  "type": "ARRAY",
                  "items": {"type": "STRING"}
                }
              },
            }
          }
        : null;

    final payload = {
      'contents': [
        {
          'role': 'user',
          'parts': [
            {'text': prompt}
          ]
        }
      ],
      if (generationConfig != null)
        'generationConfig': generationConfig
    };

    while (retryCount < retries) {
      try {
        final response = await http.post(
          url,
          headers: {'Content-Type': 'application/json'},
          body: json.encode(payload),
        );

        if (response.statusCode == 200) {
          final data = json.decode(response.body);
          
          if (data['candidates'] == null || data['candidates'].isEmpty) {
             debugPrint("Gemini API Error: No candidates in response.");
             return SuggestionResult(error: "API_ERROR: No content generated.");
          }

          final text =
              data['candidates'][0]['content']['parts'][0]['text'].trim();
          return SuggestionResult(suggestion: text);

        } else if (response.statusCode == 400) {
          final errorBody = json.decode(response.body);
          final errorMessage = errorBody['error']?['message'] ?? 'Invalid request.';
          debugPrint("Gemini API Error 400: $errorMessage");
          return SuggestionResult(error: "API_ERROR: $errorMessage");

        } else if (response.statusCode == 429 || response.statusCode >= 500) {
          // Quota exhausted or server error, wait and retry
          debugPrint("Gemini API Error ${response.statusCode}, retrying in ${delay}ms...");
          await Future.delayed(Duration(milliseconds: delay));
          retryCount++;
          delay *= 2; // Exponential backoff
        } else {
          // Other client error (401, 403, 404)
          final errorBody = json.decode(response.body);
          final errorMessage = errorBody['error']?['message'] ?? 'Unknown API error.';
          debugPrint("Gemini API Error ${response.statusCode}: $errorMessage");
          return SuggestionResult(error: "API_ERROR: $errorMessage");
        }
      } catch (e) {
        debugPrint("Gemini connection Error: $e");
        return SuggestionResult(error: "NETWORK_ERROR");
      }
    }
    
    // If we've exhausted retries
    return SuggestionResult(error: "API_ERROR: Request failed after $retries retries.");
  }

  static Future<SuggestionResult> getSuggestion(
      Goal? activeGoal, Milestone? nextMilestone) async {
    if (activeGoal == null || nextMilestone == null) {
      return SuggestionResult(
          suggestion:
              "All tasks complete! Great job on finishing your milestones.");
    }

    final nextCheckpoint = nextMilestone.checkpoints.firstWhere(
      (c) => !nextMilestone.completedCheckpointIds.contains(c.id),
      orElse: () => Checkpoint(title: "No more tasks in this milestone"),
    );

    if (nextCheckpoint.title == "No more tasks in this milestone") {
      return SuggestionResult(
          suggestion:
              "Milestone '${nextMilestone.title}' is complete! Well done!");
    }

    // Schedule notification (this can happen in parallel)
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

  // MOSSES FIX: Updated prompt for reliability and set isJson = true
  static Future<SuggestionResult> getTaskSuggestions(
      String goalTitle, String milestoneTitle) async {
    final prompt = """
    A user is planning their goal.
    Main Goal: "$goalTitle"
    Current Milestone: "$milestoneTitle"
    
    Suggest 3 to 4 actionable, specific sub-tasks for this milestone.
    """;

    try {
      // MOSSES FIX: Call _callGemini with isJson = true
      final result = await _callGemini(prompt, isJson: true);
      
      if (result.suggestion != null) {
        // The API will now return a clean JSON string: '{"tasks": ["Task 1", "Task 2"]}'
        // We return this string directly for the UI to decode.
        return SuggestionResult(suggestion: result.suggestion);
      } else {
        return result; // Pass the error up
      }
    } catch (e) {
      debugPrint("Error in getTaskSuggestions: $e");
      return SuggestionResult(error: "DECODING_ERROR");
    }
  }

  // MOSSES FIX: Updated prompt to be more concise
  static Future<String> getMonthlyReportSummary(
      Map<String, dynamic> currentData,
      Map<String, dynamic> previousData) async {
    final prompt = """
      Generate a concise, encouraging, single-paragraph monthly performance report.
      Focus on positive reinforcement. If no progress was made, be gentle but note the consequences.
      Do not use markdown.

      Data:
      - This month's time: ${currentData['timeSpent']}
      - This month's tasks: ${currentData['tasksCompleted']}
      - Last month's time: ${previousData['timeSpent']}
      - Last month's tasks: ${previousData['tasksCompleted']}

      Example:
      "Great work this month! You dedicated a solid amount of time to your goals and made tangible progress. You've shown fantastic consistency. Keep that momentum going into next month!"
      """;
    final result = await _callGemini(prompt);
    return result.suggestion ??
        "Could not generate summary at this time."; // Return a simple fallback
  }
}

// --- NEW: Quote Service for Fallback Content ---
class QuoteService {
  static const String _quoteIndexKey = 'last_quote_index';
  static const List<String> _quotes = [
    "The secret of getting ahead is getting started. – Mark Twain",
    "It does not matter how slowly you go as long as you do not stop. – Confucius",
    "Your time is limited, so don't waste it living someone else's life. – Steve Jobs",
    "The only way to do great work is to love what you do. – Steve Jobs",
    "The future belongs to those who believe in the beauty of their dreams. – Eleanor Roosevelt",
    "Success is not final; failure is not fatal: It is the courage to continue that counts. – Winston Churchill",
    "Believe you can and you're halfway there. – Theodore Roosevelt",
    "The best way to predict the future is to create it. – Peter Drucker",
    "A year from now you may wish you had started today. – Karen Lamb",
    "The journey of a thousand miles begins with a single step. – Laozi"
  ];

  static Future<String> getQuote() async {
    final prefs = await SharedPreferences.getInstance();
    int lastIndex = prefs.getInt(_quoteIndexKey) ?? -1;

    // Increment index and loop back to 0 if at the end
    int nextIndex = (lastIndex + 1) % _quotes.length;

    await prefs.setInt(_quoteIndexKey, nextIndex);
    return _quotes[nextIndex];
  }
}