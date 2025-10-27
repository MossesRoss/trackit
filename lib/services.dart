/*
 * @author Mosses
 * @version 1.4.0
 * --- CHANGELOG ---
 * v1.4.0:
 * - [FIX] Updated `_processPeriodData` background task to iterate
 * through the new `milestone.timeLog` list. It now correctly
 * sums *only* the session durations that fall within the
 * report's date range, fixing the inaccurate time bug.
 * - [FIX] Removed the old logic that checked `lastWorkedOn` and
 * added the total `milestone.timeSpent`.
 * - [FIX] Truncated `startOfWeek` in `getWeeklyReport` to 00:00:00
 * to fix the bug where the weekly report showed "0" on Mondays.
 * - [FIX] Adjusted `endOfWeek` to add 7 full days, making the
 * `isBefore(end)` check correct for the whole week.
 * v1.3.0:
 * - [FIX] Namespaced SharedPreferences cache key with user UID to prevent
 * data leaking between accounts on login/logout.
 * - [FEAT] Added logic to AuthService.signOut() to clear the current user's
 * namespaced cache and timer recovery keys upon logout.
 * v1.2.0:
 * - [PERF] Refactored all report getters (getWeeklyReport, etc.) to use Streams
 * instead of Futures. This enables real-time data updates on the reports page.
 * - [PERF] Added `compute` function and a top-level `_processPeriodData` helper
 * to move all heavy report calculations to a background isolate.
 * This fixes the UI lag/freeze on the reports page.
 * - [FIX] Report logic now correctly counts tasks completed *within* a period
 * by summing 'Done' check-ins, instead of just total completed tasks.
 * - [FEAT] Added `getGoalsStream` to provide a real-time stream of all user goals.
 */

import 'dart:convert';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
// import 'package:flutter/material.dart';
// --- FIX: Import for 'compute' function ---
import 'package:flutter/foundation.dart'
    show ChangeNotifier, debugPrint, compute;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http; // Kept for Apps Script calls
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import './models.dart';
import './notification_service.dart'; // Import the new service

// =======================================================================
// TOP-LEVEL FUNCTION FOR BACKGROUND REPORT PROCESSING
// (This function is unchanged)
// =======================================================================
Map<String, dynamic> _processPeriodData(Map<String, dynamic> params) {
  // Deserialize goals from JSON
  final List<Goal> allGoals = (params['goals'] as List<dynamic>)
      .map((g) => Goal.fromJson(g as Map<String, dynamic>))
      .toList();
  final DateTime start = params['start'] as DateTime;
  final DateTime end = params['end'] as DateTime;

  Duration totalTime = Duration.zero;
  int tasksCompleted = 0;
  Map<TaskCheckinStatus, int> checkinCounts = {
    for (var status in TaskCheckinStatus.values) status: 0
  };

  for (final goal in allGoals) {
    for (final milestone in goal.milestones) {
      // --- FIX: This is the new, correct logic ---
      // Iterate over every individual time session
      for (final session in milestone.timeLog) {
        // Check if the session *timestamp* is within the period
        if (session.timestamp.isAfter(start) &&
            session.timestamp.isBefore(end)) {
          // Add only *that session's* duration
          totalTime += session.duration;
        }
      }
      // --- End of new logic ---

      // --- DEPRECATED: Remove old, buggy logic ---
      // if (milestone.lastWorkedOn != null &&
      //     milestone.lastWorkedOn!.isAfter(start) &&
      //     milestone.lastWorkedOn!.isBefore(end)) {
      //   totalTime += milestone.timeSpent;
      // }
      // --- End of deprecated logic ---

      // --- FIX: Logic is now correct ---
      for (final checkin in milestone.checkins) {
        if (checkin.timestamp.isAfter(start) &&
            checkin.timestamp.isBefore(end)) {
          // Increment the count for the specific check-in status
          checkinCounts[checkin.status] =
              (checkinCounts[checkin.status] ?? 0) + 1;

          // If the status was 'Done', count it as a completed task for the period
          if (checkin.status == TaskCheckinStatus.done) {
            tasksCompleted++;
          }
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

// --- Auth Service (Updated) ---
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
    // --- FIX: Clear cache for the current user *before* signing out ---
    try {
      final currentUserUid = _auth.currentUser?.uid;
      if (currentUserUid != null) {
        final prefs = await SharedPreferences.getInstance();
        final userCacheKey = 'all_goals_cache_$currentUserUid';
        await prefs.remove(userCacheKey);
        debugPrint("Cleared cache for user $currentUserUid");

        // --- FIX: Also clear timer recovery keys ---
        // (Keys are from main.dart)
        await prefs.remove('recovery_time_seconds');
        await prefs.remove('recovery_milestone_id');
        debugPrint("Cleared timer recovery keys.");
      }
    } catch (e) {
      debugPrint("Error clearing user cache on sign-out: $e");
    }
    // --- End of fix ---

    await _googleSignIn.signOut();
    await _auth.signOut();
  }
}

// --- FIX: Add the missing FirestoreService class back in ---
class FirestoreService {
  final String? uid;
  FirestoreService(this.uid);

  final FirebaseFirestore _db = FirebaseFirestore.instance;
  // --- FIX: Remove static cache key ---
  // static const _localCacheKey = 'all_goals_cache';

  // --- FIX: Create a user-specific getter for the cache key ---
  String get _userCacheKey {
    // If uid is null, return a key that will never be found/set.
    if (uid == null) return 'all_goals_cache_anonymous';
    return 'all_goals_cache_$uid';
  }

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
    // Write all goals in a batch for efficiency
    final batch = _db.batch();
    for (var goal in allGoals) {
      goal.userId = uid;
      final docRef = goalsCollection.doc(goal.id);
      batch.set(docRef, goal.toJson());
    }
    await batch.commit();

    // Update the local cache
    await _cacheGoals(allGoals);
  }

  /// Helper to update the SharedPreferences cache
  Future<void> _cacheGoals(List<Goal> goals) async {
    // --- FIX: Don't cache if UID is null (e.g., logged out) ---
    if (uid == null) return;
    final prefs = await SharedPreferences.getInstance();
    final String goalsJson =
        json.encode(goals.map((g) => g.toJson()).toList());
    // --- FIX: Use user-specific cache key ---
    await prefs.setString(_userCacheKey, goalsJson);
  }

  Future<List<Goal>> loadGoals() async {
    // --- FIX: If no user, return empty list immediately ---
    if (uid == null) return [];

    final prefs = await SharedPreferences.getInstance();
    // --- FIX: Use user-specific cache key ---
    final String? localGoalsJson = prefs.getString(_userCacheKey);

    if (localGoalsJson != null) {
      final List<dynamic> decodedJson = json.decode(localGoalsJson);
      return decodedJson.map((g) => Goal.fromJson(g)).toList();
    }

    // No local cache found for this user, fetch from Firestore
    // (uid is guaranteed to be non-null here)
    final goalsCollection = _db.collection('users').doc(uid).collection('goals');
    final snapshot = await goalsCollection.get();
    final goals =
        snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();

    // Save to cache
    await _cacheGoals(goals);
    return goals;
  }

  /// Helper to convert goal list to JSON-encodable format for `compute`
  List<Map<String, dynamic>> _goalsToJson(List<Goal> goals) {
    return goals.map((g) => g.toJson()).toList();
  }

  /// --- NEW: Provides a real-time stream of all goals ---
  Stream<List<Goal>> getGoalsStream() {
    if (uid == null) {
      debugPrint("getGoalsStream: No UID, returning empty stream.");
      return Stream.value([]);
    }
    final goalsCollection = _db.collection('users').doc(uid).collection('goals');
    return goalsCollection.snapshots().map((snapshot) {
      debugPrint("getGoalsStream: Received new goals snapshot.");
      final goals =
          snapshot.docs.map((doc) => Goal.fromJson(doc.data())).toList();
      // Update cache in the background (will now use user-specific key)
      _cacheGoals(goals);
      return goals;
    });
  }

  /// --- REMOVED: `_getPeriodData` is now a top-level function ---

  /// --- FIX: Changed to return a Stream and use `compute` ---
  Stream<Map<String, dynamic>> getWeeklyReport() {
    // Get the real-time stream of goals
    return getGoalsStream().asyncMap((goals) async {
      debugPrint("getWeeklyReport: Processing ${goals.length} goals...");
      final now = DateTime.now();
      // --- FIX: Truncate `now` to 00:00:00 to get true start of week ---
      final startOfWeek = DateTime(now.year, now.month, now.day)
          .subtract(Duration(days: now.weekday - 1));
      // --- FIX: Add 7 full days so `isBefore` works correctly ---
      final endOfWeek = startOfWeek.add(const Duration(days: 7));
      final startOfLastWeek = startOfWeek.subtract(const Duration(days: 7));

      // Prepare data for background processing
      final goalsJson = _goalsToJson(goals);
      final currentParams = {
        'goals': goalsJson,
        'start': startOfWeek,
        'end': endOfWeek
      };
      final previousParams = {
        'goals': goalsJson,
        'start': startOfLastWeek,
        'end': startOfWeek
      };

      // --- PERF: Run both calculations in parallel on background threads ---
      final results = await Future.wait([
        compute(_processPeriodData, currentParams),
        compute(_processPeriodData, previousParams)
      ]);

      debugPrint("getWeeklyReport: Processing complete.");
      return {'currentPeriod': results[0], 'previousPeriod': results[1]};
    });
  }

  /// --- FIX: Changed to return a Stream and use `compute` ---
  Stream<Map<String, dynamic>> getMonthlyReport() {
    return getGoalsStream().asyncMap((goals) async {
      debugPrint("getMonthlyReport: Processing ${goals.length} goals...");
      final now = DateTime.now();
      final startOfMonth = DateTime(now.year, now.month, 1);
      final endOfMonth = DateTime(now.year, now.month + 1, 0);
      final startOfLastMonth = DateTime(now.year, now.month - 1, 1);

      final goalsJson = _goalsToJson(goals);
      final currentParams = {
        'goals': goalsJson,
        'start': startOfMonth,
        'end': endOfMonth
      };
      final previousParams = {
        'goals': goalsJson,
        'start': startOfLastMonth,
        'end': startOfMonth
      };

      final results = await Future.wait([
        compute(_processPeriodData, currentParams),
        compute(_processPeriodData, previousParams)
      ]);

      final summary = await SuggestionService.getMonthlyReportSummary(
          results[0], results[1]);

      debugPrint("getMonthlyReport: Processing complete.");
      return {
        'currentPeriod': results[0],
        'previousPeriod': results[1],
        'summary': summary
      };
    });
  }

  /// --- FIX: Changed to return a Stream and use `compute` ---
  Stream<Map<String, dynamic>> getYearlyReport() {
    return getGoalsStream().asyncMap((goals) async {
      debugPrint("getYearlyReport: Processing ${goals.length} goals...");
      final now = DateTime.now();
      final startOfYear = DateTime(now.year, 1, 1);
      final endOfYear = DateTime(now.year, 12, 31);
      final startOfLastYear = DateTime(now.year - 1, 1, 1);

      final goalsJson = _goalsToJson(goals);
      final currentParams = {
        'goals': goalsJson,
        'start': startOfYear,
        'end': endOfYear
      };
      final previousParams = {
        'goals': goalsJson,
        'start': startOfLastYear,
        'end': startOfYear
      };

      // Get archived goals (still a Future, that's fine)
      final querySnapshot = _db
          .collection('archived_goals')
          .where('userId', isEqualTo: uid)
          .where('createdAt',
              isGreaterThanOrEqualTo: startOfYear.toIso8601String())
          .where('createdAt', isLessThanOrEqualTo: endOfYear.toIso8601String())
          .get();

      // Run compute tasks and DB query in parallel
      final results = await Future.wait([
        compute(_processPeriodData, currentParams),
        compute(_processPeriodData, previousParams),
        querySnapshot,
      ]);

      final archivedGoals =
          (results[2] as QuerySnapshot<Map<String, dynamic>>)
              .docs
              .map((doc) => Goal.fromJson(doc.data()))
              .toList();

      debugPrint("getYearlyReport: Processing complete.");
      return {
        'currentPeriod': results[0] as Map<String, dynamic>,
        'previousPeriod': results[1] as Map<String, dynamic>,
        'archivedGoals': archivedGoals
      };
    });
  }
}
// --- End of fix ---

// --- FIX: Add this missing class ---
class SuggestionResult {
  final String? suggestion;
  final String? error; // e.g., "NO_API_KEY", "API_ERROR", "NETWORK_ERROR"

  SuggestionResult({this.suggestion, this.error});
}
// --- End of fix ---

// --- Suggestion Service (Unchanged) ---
class SuggestionService {
  // =======================================================================
  // CRITICAL ACTION: Paste your Google Apps Script Web App URL here.
  // =======================================================================
  static const String _appsScriptUrl =
      "httpsGive_Me_A_Link";
  // =======================================================================

  /// Calls the Google Apps Script backend proxy.
  /// This is the new single point of contact for all AI features.
  static Future<SuggestionResult> _callAppsScript(
      String action, Map<String, dynamic> body) async {
    // Check if the developer has set the URL.
    if (_appsScriptUrl.contains("PASTE_YOUR_DEPLOYED_WEB_APP_URL_HERE")) {
      debugPrint("CRITICAL: _appsScriptUrl is not set in services.dart.");
      // Return the "NO_API_KEY" error so the UI can display a helpful message.
      return SuggestionResult(error: "NO_API_KEY");
    }

    // Add the specific action to the request body
    body['action'] = action;

    // Get the current user's Firebase Auth ID Token.
    // This securely proves to your backend *who* is making the call.
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

    try {
      final response = await http.post(
        Uri.parse(_appsScriptUrl),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer $idToken', // Send the token for verification
        },
        body: json.encode(body),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        if (data['error'] != null) {
          debugPrint("Google Apps Script Error: ${data['error']}");
          return SuggestionResult(error: data['error']);
        }
        return SuggestionResult(suggestion: data['suggestion']);
      } else {
        // Handle non-200 HTTP responses
        debugPrint(
            "Apps Script HTTP Error ${response.statusCode}: ${response.body}");
        return SuggestionResult(error: "HTTP_ERROR_${response.statusCode}");
      }
    } catch (e) {
      // Handle network or connection errors
      debugPrint("Apps Script connection error: $e");
      return SuggestionResult(error: "NETWORK_ERROR");
    }
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

    // Call the new Apps Script backend
    debugPrint("Requesting suggestion from backend...");
    return _callAppsScript('getSuggestion', {'prompt': prompt});
  }

  static Future<SuggestionResult> getTaskSuggestions(
      String goalTitle, String milestoneTitle) async {
    debugPrint("Requesting task suggestions from backend...");
    // Call the new Apps Script backend
    return _callAppsScript('getTaskSuggestions', {
      'goalTitle': goalTitle,
      'milestoneTitle': milestoneTitle,
    });
  }

  static Future<String> getMonthlyReportSummary(
      Map<String, dynamic> currentData,
      Map<String, dynamic> previousData) async {
    debugPrint("Requesting monthly summary from backend...");
    // Call the new Apps Script backend
    final result = await _callAppsScript('getMonthlyReportSummary', {
      'currentData': currentData,
      'previousData': previousData,
    });

    return result.suggestion ?? "Could not generate summary at this time.";
  }
}

// --- Quote Service for Fallback Content (unchanged) ---
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