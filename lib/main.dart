/*
 * @author Mosses
 * @version 1.3.2
 * --- CHANGELOG ---
 * v1.3.2:
 * - [FIX] Changed Provider.of<ThemeProvider> in MainPage.build to listen (removed listen: false) 
 * to ensure the settings page UI updates instantly when the theme is toggled.
 * v1.3.0:
 * - [FIX] Added one-time migration logic to main() to clear the old,
 * non-user-specific 'all_goals_cache' from SharedPreferences.
 * v1.2.2:
 * - [FIX] Registered a check for app launch via notification in initState.
 * - [FIX] Updated notification listener to use the new top-level stream
 * from NotificationService to correctly handle background/terminated taps.
 */
import 'package:firebase_auth/firebase_auth.dart';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb, debugPrint;
import 'dart:io' show Platform;
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
// import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:shared_preferences/shared_preferences.dart'; // Import for recovery & theme
import 'firebase_options.dart';

import './models.dart';
import './services.dart';
import './ui.dart';
import './auth_screen.dart';
import './notification_service.dart';

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';
// --- Key for Firestore Local Cache (Old key, now only used for migration) ---
const String _oldLocalCacheKey = 'all_goals_cache';
// --- Key for Theme Persistence ---
const String _kThemePersistenceKey = 'theme_mode';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// --- ThemeProvider (Unchanged) ---
class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  ThemeProvider() {
    _loadTheme();
  }

  /// Loads the saved theme mode from SharedPreferences.
  void _loadTheme() async {
    try {
      final prefs = await SharedPreferences.getInstance();
      // Load the theme index (0 = light, 1 = system, 2 = dark)
      final themeIndex = prefs.getInt(_kThemePersistenceKey) ?? 0;
      _themeMode = ThemeMode.values[themeIndex];
      notifyListeners();
    } catch (e) {
      debugPrint("Error loading theme: $e");
    }
  }

  /// Toggles the theme and saves the preference to SharedPreferences.
  void toggleTheme() async {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();

    try {
      final prefs = await SharedPreferences.getInstance();
      await prefs.setInt(_kThemePersistenceKey, _themeMode.index);
    } catch (e) {
      debugPrint("Error saving theme: $e");
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- FIX: Add one-time migration to clear the old, non-user-specific cache ---
  try {
    final prefs = await SharedPreferences.getInstance();
    if (prefs.containsKey(_oldLocalCacheKey)) {
      await prefs.remove(_oldLocalCacheKey);
      debugPrint("MIGRATION: Removed old, non-user-specific goals cache.");
    }
  } catch (e) {
    debugPrint("Error during one-time cache migration: $e");
  }
  // --- End of fix ---

  await NotificationService().init();

  if (!kIsWeb && Platform.isAndroid) {
    var status = await Permission.notification.status;
    if (status.isDenied) {
      await Permission.notification.request();
    }
  }

  const MethodChannel timezoneChannel =
      MethodChannel('com.example.trackit/timezone');
  String timeZoneName;
  try {
    timeZoneName = await timezoneChannel.invokeMethod('getLocalTimezone');
  } on PlatformException {
    timeZoneName = 'America/Detroit'; // Default fallback
    debugPrint("Failed to get native timezone, using default: $timeZoneName");
  } catch (e) {
    timeZoneName = 'America/Detroit'; // Catch any other error
    debugPrint(
        "Error getting native timezone: $e, using default: $timeZoneName");
  }

  try {
    tz.initializeTimeZones();
    if (!kIsWeb) {
      if (Platform.isAndroid || Platform.isIOS) {
        tz.setLocalLocation(tz.getLocation(timeZoneName));
        debugPrint("Timezone set to: ${tz.local.name}");
      }
    }
  } catch (e) {
    debugPrint("Error initializing/setting timezone: $e");
    // Continue execution even if timezone setup fails
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()), // Updated
        ChangeNotifierProvider(create: (_) => AuthService()),
        // --- DEBUG: Add logging to ProxyProvider update ---
        ProxyProvider<AuthService, FirestoreService>(update: (_, auth,
            previous) {
          debugPrint(
              "ProxyProvider update: auth.currentUser?.uid = ${auth.currentUser?.uid}");
          // Only create a new instance if uid changes OR if previous is null
          if (previous == null || previous.uid != auth.currentUser?.uid) {
            return FirestoreService(auth.currentUser?.uid);
          }
          return previous; // Reuse previous instance if uid hasn't changed
        }),
      ],
      child: const MilestoneApp(),
    ),
  );
}

// --- MilestoneApp (Unchanged) ---
class MilestoneApp extends StatelessWidget {
  const MilestoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final lightTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.light,
      colorSchemeSeed: Colors.indigo,
      appBarTheme: const AppBarTheme(
        elevation: 0,
        backgroundColor: Colors.transparent,
        foregroundColor: Colors.black87,
      ),
      cardTheme: CardThemeData(
        // FIX: Was CardTheme
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade300),
        ),
      ),
    );
    final darkTheme = ThemeData(
      useMaterial3: true,
      brightness: Brightness.dark,
      colorSchemeSeed: Colors.indigo,
      cardTheme: CardThemeData(
        // FIX: Was CardTheme
        elevation: 0,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12),
          side: BorderSide(color: Colors.grey.shade800),
        ),
      ),
    );

    return MaterialApp(
      navigatorKey: navigatorKey,
      title: 'Track It',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: themeProvider.themeMode,
      home: const AuthWrapper(),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- AuthWrapper (Unchanged) ---
class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    // --- DEBUG: Listen to AuthService here ---
    // Use watch to rebuild when auth state changes
    final authService = Provider.of<AuthService>(context);
    debugPrint("AuthWrapper build: Listening to auth state.");

    // Using StreamBuilder is still fine, but Provider.of ensures
    // we rebuild when notifyListeners is called.
    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        // --- DEBUG ---
        debugPrint(
            "AuthWrapper StreamBuilder: connectionState=${snapshot.connectionState}, hasData=${snapshot.hasData}");

        if (snapshot.connectionState == ConnectionState.waiting) {
          debugPrint("AuthWrapper: Waiting for auth state...");
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          debugPrint(
              "AuthWrapper: User is logged in (uid: ${snapshot.data?.uid}). Showing MainPage.");
          // IMPORTANT: Pass the UID here IF NEEDED, though MainPage uses Provider
          return const MainPage();
        }
        debugPrint("AuthWrapper: User is logged out. Showing AuthScreen.");
        return const AuthScreen();
      },
    );
  }
}

// --- MainPage (Unchanged) ---
// (No changes were required in MainPage itself, as the fixes are
// in main() and services.dart)
class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  List<Goal> _allGoals = [];
  bool _editMode = true;
  bool _isLoading = true;

  final GlobalKey<MilestonesPageState> _milestonesPageKey =
      GlobalKey<MilestonesPageState>();

  Goal? get _activeGoal {
    try {
      return _allGoals.firstWhere((g) => g.status == GoalStatus.active);
    } catch (e) {
      // Return null if no active goal is found, don't crash
      return null;
    }
  }

  // ==========================================================
  // --- DEBUG FLAG: Set to true for ONE run to clear cache ---
  final bool _clearCacheOnStartup = false; // <-- SET TO true FOR TESTING
  // ==========================================================

  @override
  void initState() {
    super.initState();
    // --- DEBUG ---
    final initialUid =
        Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    debugPrint(
        "MainPage initState: Called. Initial UID from Provider: $initialUid");

    _loadGoalsAndRecover(); // Load goals AND check for lost time
    _configureSelectNotificationSubject();
    _checkNotificationLaunchApp(); // --- FIX: Add this call ---
  }

  // --- FIX: Add this new method ---
  /// Checks if the app was launched from a notification tap.
  void _checkNotificationLaunchApp() async {
    final notificationAppLaunchDetails =
        await NotificationService().getNotificationAppLaunchDetails();

    if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
      final notificationResponse =
          notificationAppLaunchDetails!.notificationResponse;
      if (notificationResponse != null && notificationResponse.payload != null) {
        debugPrint(
            "App LAUNCHED from notification tap: ${notificationResponse.payload}");
        // Manually pass this to the listener stream
        // Use the new getter
        NotificationService().notificationSubject.add(notificationResponse);
      }
    }
  }

  // --- configureSelectNotificationSubject (Updated with new log) ---
  void _configureSelectNotificationSubject() {
    // --- FIX: Listen to the new getter from the service ---
    NotificationService()
        .notificationSubject
        .stream
        .listen((response) async {
      debugPrint(
          'NotificationResponse received in UI: payload=${response.payload}, actionId=${response.actionId}, id=${response.id}');
      // Dismiss the notification banner *if* it has an ID
      if (response.id != null) {
        NotificationService().cancelNotification(response.id!);
      } else {
        debugPrint("Warning: NotificationResponse has null ID, cannot cancel.");
      }

      if (response.payload != null && response.payload!.isNotEmpty) {
        try {
          final payloadData = json.decode(response.payload!);
          final goalId = payloadData['goalId'];
          final milestoneId = payloadData['milestoneId'];
          final checkpointId = payloadData['checkpointId'];

          // Basic validation
          if (goalId == null || milestoneId == null || checkpointId == null) {
            debugPrint("Error: Invalid notification payload structure.");
            return;
          }

          TaskCheckinStatus? status; // Make nullable
          bool shouldToggleCheckpoint = false;

          switch (response.actionId) {
            case doneActionId:
              status = TaskCheckinStatus.done;
              shouldToggleCheckpoint = true;
              break;
            case doingActionId:
              status = TaskCheckinStatus.doing;
              break;
            case willDoActionId:
              status = TaskCheckinStatus.willDo;
              break;
            case wontDoActionId:
              status = TaskCheckinStatus.wontDo;
              break;
            default:
              debugPrint(
                  "Notification action tapped, but no specific action ID matched ('${response.actionId}'). Opening app.");
              // Handle tap without action (just opens app) - do nothing extra
              return;
          }

          // --- FIX: Removed unnecessary null check ---
          // The analyzer knows `status` is non-null here because
          // the `default` case above returns.

          // --- NEW DEBUG LOG ---
          debugPrint(
              "Matched action '${response.actionId}' to status '$status'. Proceeding to record.");
          if (shouldToggleCheckpoint) {
            toggleCheckpointByIds(goalId, milestoneId, checkpointId);
          }
          recordTaskCheckin(goalId, milestoneId, checkpointId, status);
        } catch (e) {
          debugPrint("Error processing notification payload: $e");
          debugPrint("Payload content: ${response.payload}");
        }
      } else {
        debugPrint("Notification tapped, but payload is null or empty.");
      }
    });
  }

  /// Loads all goals and checks for recovered timer data.
  Future<void> _loadGoalsAndRecover() async {
    debugPrint("_loadGoalsAndRecover: Starting...");
    setState(() => _isLoading = true);

    // --- DEBUG: Access FirestoreService via Provider ---
    // Use read here as we don't need to listen for changes within this method
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    debugPrint(
        "_loadGoalsAndRecover: Got FirestoreService instance for uid: ${persistenceService.uid}");

    // --- DEBUG: Handle Cache Clearing ---
    if (_clearCacheOnStartup) {
      try {
        final prefs = await SharedPreferences.getInstance();
        // --- FIX: Must use the *user-specific* key to clear it ---
        if (persistenceService.uid != null) {
          final userCacheKey = 'all_goals_cache_${persistenceService.uid}';
          await prefs.remove(userCacheKey);
          debugPrint(
              "DEBUG: Force cleared local goals cache ('$userCacheKey').");
        }
      } catch (e) {
        debugPrint("DEBUG: Error clearing cache: $e");
      }
    }

    // 1. Load goals from persistence (will now use user-specific key)
    final goals = await persistenceService.loadGoals();
    if (!mounted) {
      debugPrint(
          "_loadGoalsAndRecover: Widget unmounted during load. Aborting.");
      return; // Check if widget is still mounted
    }
    debugPrint("_loadGoalsAndRecover: Loaded ${goals.length} goals.");

    _allGoals = goals;
    _updateMilestoneLockStatus(); // Update lock status *before* recovery logic

    // 2. Check for recovered timer data
    SharedPreferences? prefs;
    try {
      prefs = await SharedPreferences.getInstance();
      final int? recoveredSeconds = prefs.getInt(kRecoveryTimeKey);
      final String? recoveredMilestoneId =
          prefs.getString(kRecoveryMilestoneKey);

      // Check if we have valid recovery data
      if (recoveredSeconds != null &&
          recoveredSeconds > 0 &&
          recoveredMilestoneId != null) {
        debugPrint(
            "RECOVERY: Found $recoveredSeconds seconds for milestone $recoveredMilestoneId");

        // Add the recovered time to the milestone
        // This now happens *before* setting isLoading to false
        _addTimeToMilestone(
            recoveredMilestoneId, Duration(seconds: recoveredSeconds));

        // Clear the keys so this doesn't run again on next launch
        await prefs.remove(kRecoveryTimeKey);
        await prefs.remove(kRecoveryMilestoneKey);
        debugPrint("RECOVERY: Cleared recovery keys.");

        // Notify the user after the UI has built
        WidgetsBinding.instance.addPostFrameCallback((_) {
          if (mounted) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(
                    "Recovered ${recoveredSeconds}s from your last session."),
                backgroundColor: Colors.green,
              ),
            );
          }
        });
      } else {
        debugPrint(
            "RECOVERY: No recovery data found (keys: $kRecoveryTimeKey, $kRecoveryMilestoneKey).");
      }
    } catch (e) {
      debugPrint("RECOVERY ERROR: Failed to process recovery data: $e");
      // Attempt to clear recovery keys if error occurs
      try {
        if (prefs != null) {
          await prefs.remove(kRecoveryTimeKey);
          await prefs.remove(kRecoveryMilestoneKey);
          debugPrint("RECOVERY: Cleared recovery keys due to error.");
        }
      } catch (clearError) {
        debugPrint(
            "RECOVERY ERROR: Failed to clear recovery keys during error handling: $clearError");
      }
    }

    // 3. Set loading to false
    if (mounted) {
      debugPrint("_loadGoalsAndRecover: Setting isLoading to false.");
      setState(() {
        _isLoading = false;
      });
    }
    debugPrint("_loadGoalsAndRecover: Finished.");
  }

  // --- saveGoals (Unchanged) ---
  Future<void> _saveGoals() async {
    // --- DEBUG ---
    debugPrint("saveGoals: Triggered. Saving ${_allGoals.length} goals.");
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    await persistenceService.saveGoals(_allGoals);
    debugPrint("saveGoals: Completed.");
  }

  // --- onTabTapped (Unchanged) ---
  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  // --- setMainGoal (Unchanged) ---
  void _setMainGoal(String goalTitle) {
    setState(() {
      final currentActiveGoal = _activeGoal;
      if (currentActiveGoal != null) {
        debugPrint(
            "Setting new main goal. Archiving old goal: ${currentActiveGoal.id}");
        currentActiveGoal.status = GoalStatus.givenUp;
        // Use read here as it's an action
        Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(currentActiveGoal);
      }
      final newGoal = Goal(title: goalTitle);
      _allGoals.add(newGoal);
      debugPrint("Added new goal: ${newGoal.id}");
      _selectedIndex = 1; // Go to milestones page
    });
    _saveGoals(); // Save immediately

    // Show dialog (unchanged)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      showDialog(
        context: context,
        builder: (ctx) => AlertDialog(
          title: const Text('Goal Set!'),
          content: const Text(
              'Your new goal is active. Head to the Milestones page to add your first task!'),
          actions: [
            TextButton(
              child: const Text('Okay'),
              onPressed: () => Navigator.of(ctx).pop(),
            ),
          ],
        ),
      );
    });
  }

  // --- giveUpGoal (Unchanged) ---
  void _giveUpGoal() {
    if (_activeGoal == null) return;
    debugPrint("Attempting to give up goal: ${_activeGoal!.id}");

    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text(
            'Are you sure you want to give up on this goal? This action cannot be undone.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Give Up', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        debugPrint("Goal give up confirmed for: ${_activeGoal!.id}");
        if (!mounted) return; // Check mount status after async gap
        setState(() {
          _activeGoal!.status = GoalStatus.givenUp;
          // Use read here
          Provider.of<FirestoreService>(context, listen: false)
              .archiveGoal(_activeGoal!);
          debugPrint("Goal status set to givenUp for: ${_activeGoal!.id}");
        });
        _saveGoals(); // Save immediately
      } else {
        debugPrint("Goal give up cancelled for: ${_activeGoal!.id}");
      }
    });
  }

  // --- addMilestone (Unchanged) ---
  void _addMilestone(Milestone milestone) {
    if (_activeGoal == null) {
      debugPrint(
          "AddMilestone Error: Cannot add milestone, active goal is null.");
      return;
    }
    debugPrint("Adding milestone: ${milestone.id} to goal: ${_activeGoal!.id}");
    setState(() {
      // Add safely
      _activeGoal?.milestones.add(milestone);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  // --- toggleCheckpoint (Unchanged) ---
  void _toggleCheckpoint(Milestone milestone, String checkpointId) {
    debugPrint(
        "Toggling checkpoint: $checkpointId in milestone: ${milestone.id}");
    setState(() {
      if (milestone.completedCheckpointIds.contains(checkpointId)) {
        milestone.completedCheckpointIds.remove(checkpointId);
        debugPrint("Checkpoint $checkpointId marked incomplete.");
      } else {
        milestone.completedCheckpointIds.add(checkpointId);
        debugPrint("Checkpoint $checkpointId marked complete.");
      }
      _updateMilestoneLockStatus();
      _checkForGoalCompletion(); // Check if goal is now complete
    });
    _saveGoals();
  }

  // --- toggleCheckpointByIds (Unchanged) ---
  void toggleCheckpointByIds(
      String goalId, String milestoneId, String checkpointId) {
    debugPrint(
        "toggleCheckpointByIds called: goal=$goalId, milestone=$milestoneId, checkpoint=$checkpointId");
    Goal? goal;
    try {
      goal = _allGoals.firstWhere((g) => g.id == goalId);
    } catch (e) {
      debugPrint("Error finding goal $goalId in toggleCheckpointByIds.");
      return;
    }

    Milestone? milestone;
    try {
      milestone = goal.milestones.firstWhere((m) => m.id == milestoneId);
    } catch (e) {
      debugPrint("Error finding milestone $milestoneId in goal $goalId.");
      return;
    }

    // Check if checkpoint exists before toggling
    if (milestone.checkpoints.any((c) => c.id == checkpointId)) {
      _toggleCheckpoint(milestone, checkpointId);
    } else {
      debugPrint(
          "Error: Checkpoint $checkpointId not found in milestone $milestoneId.");
    }
  }

  // --- checkForGoalCompletion (Unchanged) ---
  void _checkForGoalCompletion() {
    if (_activeGoal != null && _activeGoal!.isCompleted) {
      debugPrint("Goal ${_activeGoal!.id} is now complete!");
      if (!mounted) return;
      setState(() {
        _activeGoal!.status = GoalStatus.achieved;
        _editMode =
            true; // Allow editing again? Or should stay false? Revisit logic if needed.
        // Use read
        Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(_activeGoal!);
      });
      _saveGoals();
      // Show dialog (unchanged)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Goal Achieved!'),
            content: Text(
                'Congratulations! You have completed all milestones for "${_activeGoal!.title}".'),
            actions: [
              TextButton(
                child: const Text('Awesome!'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      });
    } else {
      // debugPrint("Goal ${_activeGoal?.id} is not yet complete."); // Optional verbose logging
    }
  }

  // --- deleteMilestone (Unchanged) ---
  void _deleteMilestone(String id) {
    if (_activeGoal == null) {
      debugPrint("DeleteMilestone Error: Cannot delete, active goal is null.");
      return;
    }
    debugPrint("Deleting milestone: $id from goal: ${_activeGoal!.id}");
    setState(() {
      _activeGoal?.milestones.removeWhere((m) => m.id == id);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  // --- addTimeToMilestone (Minor Update from Recovery Logic) ---
  void _addTimeToMilestone(String milestoneId, Duration timeToAdd) {
    if (_activeGoal == null) {
      debugPrint("AddTimeToMilestone: Active goal is null. Cannot add time.");
      return;
    }
    // Check if timeToAdd is valid
    if (timeToAdd.inSeconds <= 0) {
      debugPrint("AddTimeToMilestone: timeToAdd is zero or negative. Skipping.");
      return;
    }

    debugPrint("Adding ${timeToAdd.inSeconds}s to milestone: $milestoneId");
    setState(() {
      Milestone? milestone;
      try {
        milestone =
            _activeGoal!.milestones.firstWhere((m) => m.id == milestoneId);
      } catch (e) {
        debugPrint(
            "AddTimeToMilestone ERROR: Milestone $milestoneId not found in active goal ${_activeGoal!.id}.");
        return; // Exit if milestone not found
      }

      milestone.timeSpent += timeToAdd;
      milestone.lastWorkedOn = DateTime.now(); // Update last worked on time
      debugPrint(
          "Milestone ${milestone.id} updated: timeSpent=${milestone.timeSpent}, lastWorkedOn=${milestone.lastWorkedOn}");
    });
    // Save goals immediately after state change involving time
    _saveGoals();
  }

  // --- recordTaskCheckin (Unchanged) ---
  void recordTaskCheckin(String goalId, String milestoneId, String checkpointId,
      TaskCheckinStatus status) {
    debugPrint(
        "Recording check-in: goal=$goalId, milestone=$milestoneId, checkpoint=$checkpointId, status=$status");
    setState(() {
      Goal? goal;
      try {
        goal = _allGoals.firstWhere((g) => g.id == goalId);
      } catch (e) {
        debugPrint("RecordCheckin ERROR: Goal $goalId not found.");
        return;
      }

      Milestone? milestone;
      try {
        milestone = goal.milestones.firstWhere((m) => m.id == milestoneId);
      } catch (e) {
        debugPrint(
            "RecordCheckin ERROR: Milestone $milestoneId not found in goal $goalId.");
        return;
      }

      // Ensure checkpoint exists before adding checkin? Optional, depends on desired strictness.
      milestone.checkins
          .add(TaskCheckin(checkpointId: checkpointId, status: status));
    });
    _saveGoals();
    debugPrint("Check-in recorded successfully.");
  }

  // --- updateMilestoneLockStatus (Unchanged) ---
  void _updateMilestoneLockStatus() {
    if (_activeGoal == null) {
      // debugPrint("UpdateMilestoneLock: Active goal is null."); // Optional
      return;
    }
    bool currentlyLocked = false; // Start assuming unlocked
    bool changed = false;
    for (var m in _activeGoal!.milestones) {
      bool shouldBeUnlocked = !currentlyLocked;
      if (m.isUnlocked != shouldBeUnlocked) {
        m.isUnlocked = shouldBeUnlocked;
        changed = true;
        // debugPrint("Milestone ${m.id} lock status changed to: ${m.isUnlocked}"); // Optional
      }
      // If this milestone is NOT complete, lock all subsequent milestones
      if (!m.isCompleted) {
        currentlyLocked = true;
      }
    }
    if (changed) {
      debugPrint("Milestone lock statuses updated.");
    }
  }

  // --- build (CHANGED) ---
  @override
  Widget build(BuildContext context) {
    // --- DEBUG ---
    final buildUid =
        Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    debugPrint(
        "MainPage build: Called. UID from Provider: $buildUid. IsLoading: $_isLoading");

    if (_isLoading) {
      debugPrint("MainPage build: Showing loading indicator.");
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    // --- FIX: Set listen: true (default) to update SettingsPage switch ---
    final themeProvider = Provider.of<ThemeProvider>(context);

    // --- DEBUG ---
    debugPrint(
        "MainPage build: Building pages. Active goal ID: ${_activeGoal?.id}, Total goals: ${_allGoals.length}");

    final List<Widget> pages = [
      HomePage(
        activeGoal: _activeGoal,
        onSetGoal: _setMainGoal,
        onTimeAdd: _addTimeToMilestone,
        onGiveUp: _giveUpGoal,
      ),
      MilestonesPage(
        key: _milestonesPageKey, // Assign key
        activeGoal: _activeGoal,
        onAddMilestone: _addMilestone,
        onToggleCheckpoint: _toggleCheckpoint,
        onDeleteMilestone: _deleteMilestone,
        editMode: _editMode,
      ),
      SettingsPage(
        isDarkMode: themeProvider.isDarkMode,
        toggleDarkMode: themeProvider.toggleTheme,
        editMode: _editMode,
        onEditModeChanged: (val) => setState(() => _editMode = val),
        allGoals: _allGoals, // Pass all goals
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: NavigationBar(
        onDestinationSelected: _onTabTapped,
        selectedIndex: _selectedIndex,
        destinations: const <Widget>[
          NavigationDestination(
            icon: Icon(Icons.home_outlined),
            selectedIcon: Icon(Icons.home_rounded),
            label: 'Home',
          ),
          NavigationDestination(
            icon: Icon(Icons.account_tree_outlined),
            selectedIcon: Icon(Icons.account_tree_rounded),
            label: 'Milestones',
          ),
          NavigationDestination(
            icon: Icon(Icons.settings_outlined),
            selectedIcon: Icon(Icons.settings_rounded),
            label: 'Settings',
          ),
        ],
      ),
    );
  }
}
