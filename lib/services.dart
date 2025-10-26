/*
 * @author Mosses
 * @version 1.1.0
 * --- CHANGELOG ---
 * v1.1.0: Removed direct Gemini API calls.
 * Pivoted to using a Google Apps Script proxy for all AI features.
 * Removed _callGemini, added _callAppsScript.
 * Ensures API key is 100% server-side and free.
 */

import 'dart:convert';
// import 'dart:math'; // For random quote index
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show ChangeNotifier, debugPrint;
import 'package:google_sign_in/google_sign_in.dart';
import 'package:http/http.dart' as http; // Kept for Apps Script calls
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

// --- Helper class for Suggestion Service results ---
class SuggestionResult {
  final String? suggestion;
  final String? error; // e.g., "NO_API_KEY", "API_ERROR", "NETWORK_ERROR"

  SuggestionResult({this.suggestion, this.error});
}

// --- Suggestion Service (Completely Updated) ---
class SuggestionService {
  
  // =======================================================================
  // CRITICAL ACTION: Paste your Google Apps Script Web App URL here.
  // =======================================================================
  static const String _appsScriptUrl = "https://script.google.com/macros/s/AKfycbyNDtjg-zyL4OZJlLacYhDuh0vpWFQsuqyMFWuMiLXyA15qMBtz0Fq3ZelpNkZiJMDN/exec";
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