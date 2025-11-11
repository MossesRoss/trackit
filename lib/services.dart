/*
 * @author Mosses
 * @version 1.4.3
 * --- CHANGELOG ---
 * v1.4.3:
 * - [FEAT] Changed all AI-related error handling in `_callAppsScript` to
 * return a user-friendly "Upgrade to Pro..." message instead of
 * a technical error.
 * - [FEAT] Updated `getMonthlyReportSummary` fallback to also show the
 * "Upgrade to Pro" message.
 * v1.4.2:
 * - [FIX] Added `_RedirectingClient` class to handle HTTP 302 redirects from
 * Google Apps Script.
 * - [FIX] Updated `SuggestionService._callAppsScript` to use the new
 * `_RedirectingClient`, which should resolve network errors.
 */

import 'package:flutter_secure_storage/flutter_secure_storage.dart';
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
import './models.dart';
import './notification_service.dart'; // Import the new service
import 'dart:async'; // --- ADDED for redirect client ---

// --- NEW: This is the fix for the HTTP 302 Redirect Error ---
// This class wraps the default HTTP client and tells it to follow
// redirects even for POST requests.
class _RedirectingClient extends http.BaseClient {
  final http.Client _inner;
  _RedirectingClient(this._inner);

  @override
  Future<http.StreamedResponse> send(http.BaseRequest request) {
    // For POST requests, manually set followRedirects to true.
    if (request.method == 'POST') {
      request.followRedirects = true;
      request.maxRedirects = 5; // Set a reasonable limit
    }
    return _inner.send(request);
  }
}
// --- End of new class ---

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
  final _storage = const FlutterSecureStorage();
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
        final userCacheKey = 'all_goals_cache_$currentUserUid';
        await _storage.delete(key: userCacheKey);
        debugPrint("Cleared cache for user $currentUserUid");

        // --- FIX: Also clear timer recovery keys ---
        // (Keys are from main.dart)
        await _storage.delete(key: 'recovery_time_seconds');
        await _storage.delete(key: 'recovery_milestone_id');
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
  final _storage = const FlutterSecureStorage();
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
    // --- FIX: Save to user-specific subcollection ---
    final archiveDoc = _db
        .collection('users')
        .doc(uid)
        .collection('archived_goals')
        .doc(goal.id);
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
    final String goalsJson = json.encode(goals.map((g) => g.toJson()).toList());
    // --- FIX: Use user-specific cache key ---
    await _storage.write(key: _userCacheKey, value: goalsJson);
  }

  Future<List<Goal>> loadGoals() async {
    // --- FIX: If no user, return empty list immediately ---
    if (uid == null) return [];

    // --- FIX: Use user-specific cache key ---
    final String? localGoalsJson = await _storage.read(key: _userCacheKey);

    if (localGoalsJson != null) {
      final List<dynamic> decodedJson = json.decode(localGoalsJson);
      return decodedJson.map((g) => Goal.fromJson(g)).toList();
    }

    // No local cache found for this user, fetch from Firestore
    // (uid is guaranteed to be non-null here)
    final goalsCollection =
        _db.collection('users').doc(uid).collection('goals');
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
    final goalsCollection =
        _db.collection('users').doc(uid).collection('goals');
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

      // --- FIX: Query the user-specific subcollection ---
      final querySnapshot = _db
          .collection('users')
          .doc(uid)
          .collection('archived_goals')
          // --- FIX: Removed redundant where clause ---
          // .where('userId', isEqualTo: uid)
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

      final archivedGoals = (results[2] as QuerySnapshot<Map<String, dynamic>>)
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

class SuggestionResult {
  final String? suggestion;
  final String? error;

  SuggestionResult({this.suggestion, this.error});
}

class SuggestionService {
  // --- NEW: Create an instance of the redirecting client ---
  static final http.Client _client = _RedirectingClient(http.Client());

  static const String _appsScriptUrl = String.fromEnvironment(
    'APPS_SCRIPT_URL',
    defaultValue: 'https://placeholder.com/error', // A fallback
  );

  // --- NEW: Define the user-facing error message ---
  static const String _proMessage =
      "Upgrade to Pro to enjoy AI features and more";

  /// Calls the Google Apps Script backend proxy.
  /// This is the new single point of contact for all AI features.
  static Future<SuggestionResult> _callAppsScript(
      String action, Map<String, dynamic> body) async {
    // Add the specific action to the request body
    body['action'] = action;

    // Get the current user's Firebase Auth ID Token.
    // This securely proves to your backend *who* is making the call.
    final idToken = await FirebaseAuth.instance.currentUser?.getIdToken();

    try {
      // --- FIX: Use `_client.post` instead of `http.post` ---
      final response = await _client.post(
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
          // --- UPDATED: Return pro message ---
          return SuggestionResult(error: _proMessage);
        }
        return SuggestionResult(suggestion: data['suggestion']);
      } else {
        // Handle non-200 HTTP responses
        debugPrint(
            "Apps Script HTTP Error ${response.statusCode}: ${response.body}");
        // --- UPDATED: Return pro message ---
        return SuggestionResult(error: _proMessage);
      }
    } catch (e) {
      // Handle network or connection errors
      debugPrint("Apps Script connection error: $e");
      // --- UPDATED: Return pro message ---
      return SuggestionResult(error: _proMessage);
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

    // Convert Duration objects to seconds
    final currentDataInSeconds = Map<String, dynamic>.from(currentData);
    currentDataInSeconds['timeSpent'] =
        (currentData['timeSpent'] as Duration).inSeconds;

    final previousDataInSeconds = Map<String, dynamic>.from(previousData);
    previousDataInSeconds['timeSpent'] =
        (previousData['timeSpent'] as Duration).inSeconds;

    // Call the new Apps Script backend
    final result = await _callAppsScript('getMonthlyReportSummary', {
      'currentData': currentDataInSeconds,
      'previousData': previousDataInSeconds,
    });

    // --- UPDATED: Check for error and return it, or return fallback ---
    if (result.error != null) {
      return result.error!;
    }
    return result.suggestion ?? _proMessage;
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
    final _storage = const FlutterSecureStorage();
    final lastIndexString = await _storage.read(key: _quoteIndexKey);
    int lastIndex = -1;
    if (lastIndexString != null) {
      lastIndex = int.parse(lastIndexString);
    }

    // Increment index and loop back to 0 if at the end
    int nextIndex = (lastIndex + 1) % _quotes.length;

    await _storage.write(key: _quoteIndexKey, value: nextIndex.toString());
    return _quotes[nextIndex];
  }
}