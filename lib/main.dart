/*
 * @author Mosses
 * @version 1.7.1
 * --- CHANGELOG ---
 * v1.7.1:
 * - [FIX] `onPressed` in check-in dialog is now `async` to properly `await`
 * the `toggleCheckpointByIds` call.
 * - [FIX] Changed `Color` type to `MaterialColor` to access `.shade700`
 * (This was a comment from your original code, kept for history)
 * - [FIX] Removed extra closing brace `}` at end of file.
 * - [STYLE] Changed dialog `TextButton` to `FilledButton` for a solid look.
 * v1.7.0:
 * - [FEAT] Redesigned check-in dialog per user feedback.
 * - [STYLE] Title is now the task name.
 * - [STYLE] Content is a 2x2 "Kahoot style" grid of buttons.
 * - [STYLE] Changed buttons to `ElevatedButton` for a solid color look.
 * - [FIX] Removed "Cancel" button and extra text for a simpler UI.
 * v1.6.0:
 * - [FEAT] Implemented new notification flow.
 * - [FEAT] Notifications no longer have actions. Tapping a notification
 * now opens the app and triggers an in-app dialog.
 * - [FIX] Removed all complex "background-safe" logic, as all state
 * changes now happen reliably in the foreground via the new dialog.
 * - [ADD] Added `_showCheckinDialog` to handle this new flow.
 * v1.5.8:
 * - [FIX] Corrected a missing brace '}' syntax error
 */
import 'package:flutter_secure_storage/flutter_secure_storage.dart';
import 'package:flutter_dotenv/flutter_dotenv.dart';
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
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:permission_handler/permission_handler.dart';
import 'firebase_options.dart';

import './models.dart';
import './services.dart';
import './ui.dart';
import './auth_screen.dart';
import './notification_service.dart';

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';
// is this safe to remove?
const String _oldLocalCacheKey = 'all_goals_cache';
// --- Key for Theme Persistence ---
const String _kThemePersistenceKey = 'theme_mode';
const String _kEditModePersistenceKey = 'edit_mode';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

// --- ThemeProvider (Unchanged) ---
class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  final _storage = const FlutterSecureStorage();

  ThemeProvider() {
    _loadTheme();
  }

  /// Loads the saved theme mode from SharedPreferences.
  void _loadTheme() async {
    try {
      final themeIndexString = await _storage.read(key: _kThemePersistenceKey);
      if (themeIndexString != null) {
        final themeIndex = int.parse(themeIndexString);
        _themeMode = ThemeMode.values[themeIndex];
        notifyListeners();
      }
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
      await _storage.write(
          key: _kThemePersistenceKey, value: _themeMode.index.toString());
    } catch (e) {
      debugPrint("Error saving theme: $e");
    }
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  // --- FIX: Add one-time migration to clear the old, non-user-specific cache ---
  try {
    const _storage = FlutterSecureStorage();
    await _storage.delete(key: _oldLocalCacheKey);
    debugPrint("MIGRATION: Removed old, non-user-specific goals cache.");
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
        ProxyProvider<AuthService, FirestoreService>(
            update: (_, auth, previous) {
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

class AuthWrapper extends StatelessWidget {
  const AuthWrapper({super.key});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context);
    debugPrint("AuthWrapper build: Listening to auth state.");

    return StreamBuilder<User?>(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
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
          return const MainPage();
        }
        debugPrint("AuthWrapper: User is logged out. Showing AuthScreen.");
        return const AuthScreen();
      },
    );
  }
} // <--- Fixed missing brace for AuthWrapper

class MainPage extends StatefulWidget {
  const MainPage({super.key});

  @override
  State<MainPage> createState() => _MainPageState();
} // <--- Fixed missing brace for MainPage

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
      return null;
    }
  }

  final bool _clearCacheOnStartup = false;
  final _storage = const FlutterSecureStorage();

  @override
  void initState() {
    super.initState();
    // --- DEBUG ---
    final initialUid =
        Provider.of<AuthService>(context, listen: false).currentUser?.uid;
    debugPrint(
        "MainPage initState: Called. Initial UID from Provider: $initialUid");

    // --- REFACTORED: ---
    // 1. Attach listener immediately.
    _configureSelectNotificationSubject();
    // 2. Load goals, recover timer, AND process any launch notification.
    _loadGoalsAndProcessLaunch();
  }

  // --- MODIFIED: This listener now triggers the in-app dialog ---
  void _configureSelectNotificationSubject() {
    NotificationService().notificationSubject.stream.listen((response) async {
      debugPrint(
          'NotificationResponse received by listener (app-running): payload=${response.payload}, actionId=${response.actionId}');

      // --- FIX: Check if this is a launch notification ---
      // We check our *own* flag that we set after processing a launch event.
      if (_isLaunchNotification(response)) {
        debugPrint(
            "Ignoring notification because it was just processed on launch.");
        return;
      }

      // --- This is a "live" tap (app already running), not a launch tap ---
      // Show the dialog
      if (mounted) {
        _showCheckinDialog(response);
      }
    });
  }

  // --- NEW: Helper variable and function to track the launch notification ---
  NotificationResponse? _processedLaunchNotification;

  bool _isLaunchNotification(NotificationResponse response) {
    if (_processedLaunchNotification == null) {
      return false;
    }
    // Check if the payload matches the one we just processed on launch
    // We don't check actionId anymore since there are no actions
    return _processedLaunchNotification!.payload == response.payload;
  }

  Future<void> _setEditMode(bool newValue) async {
    // Update state immediately for UI responsiveness
    setState(() {
      _editMode = newValue;
    });

    // Save the new value
    try {
      await _storage.write(
          key: _kEditModePersistenceKey, value: newValue.toString());
      debugPrint("Saved editMode: $newValue");
    } catch (e) {
      debugPrint("Error saving edit mode preference: $e");
    }
  }

  /// --- MODIFIED: Combined loading and launch processing function ---
  Future<void> _loadGoalsAndProcessLaunch() async {
    debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Starting...");
    setState(() => _isLoading = true);

    // --- 1. Load Edit Mode (from old _loadGoalsAndRecover) ---
    try {
      debugPrint("[DEBUG] Loading edit mode...");
      final savedEditModeString =
          await _storage.read(key: _kEditModePersistenceKey);
      debugPrint("[DEBUG] Edit mode string from storage: $savedEditModeString");
      if (savedEditModeString != null) {
        final savedEditMode = savedEditModeString.toLowerCase() == 'true';
        if (mounted) {
          setState(() {
            _editMode = savedEditMode;
          });
          debugPrint("[DEBUG] Loaded editMode: $_editMode");
        }
      }
    } catch (e) {
      debugPrint("[DEBUG] Error loading edit mode preference: $e");
    }

    // --- 2. Load Goals (from old _loadGoalsAndRecover) ---
    try {
      debugPrint("[DEBUG] Loading goals...");
      final persistenceService =
          Provider.of<FirestoreService>(context, listen: false);
      debugPrint(
          "[DEBUG] _loadGoalsAndProcessLaunch: Got FirestoreService instance for uid: ${persistenceService.uid}");

      if (_clearCacheOnStartup) {
        try {
          debugPrint("[DEBUG] Clearing cache on startup...");
          // --- FIX: Must use the *user-specific* key to clear it ---
          if (persistenceService.uid != null) {
            final userCacheKey = 'all_goals_cache_${persistenceService.uid}';
            await _storage.delete(key: userCacheKey);
            debugPrint(
                "[DEBUG] Force cleared local goals cache ('$userCacheKey').");
          }
        } catch (e) {
          debugPrint("[DEBUG] Error clearing cache: $e");
        }
      }

      final goals = await persistenceService.loadGoals();
      if (!mounted) {
        debugPrint(
            "[DEBUG] _loadGoalsAndProcessLaunch: Widget unmounted during load. Aborting.");
        return; // Check if widget is still mounted
      }
      debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Loaded ${goals.length} goals.");

      _allGoals = goals;
      _updateMilestoneLockStatus(); // Update lock status *before* recovery logic
    } catch (e) {
      debugPrint("[DEBUG] Error loading goals: $e");
    }

    // --- 3. Process Launch Notification (from old _checkNotificationLaunchApp) ---
    try {
      debugPrint("[DEBUG] Processing launch notification...");
      final notificationAppLaunchDetails =
          await NotificationService().getNotificationAppLaunchDetails();

      if (notificationAppLaunchDetails?.didNotificationLaunchApp ?? false) {
        final notificationResponse =
            notificationAppLaunchDetails!.notificationResponse;
        if (notificationResponse != null) {
          debugPrint(
              "[DEBUG] App LAUNCHED from notification tap. Processing payload directly...");

          // --- FIX: Store this so the stream listener can ignore it ---
          _processedLaunchNotification = notificationResponse;

          // --- FIX: Process it directly by queueing the dialog ---
          // We must wait for the first frame to build before showing a dialog.
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (mounted) {
              _showCheckinDialog(notificationResponse);
            }
          });
        }
      }
    } catch (e) {
      debugPrint("[DEBUG] Error processing launch notification: $e");
    }

    // --- 4. Recover Timer (from old _loadGoalsAndRecover) ---
    try {
      debugPrint("[DEBUG] Recovering timer...");
      final recoveredSecondsString = await _storage.read(key: kRecoveryTimeKey);
      final recoveredMilestoneId =
          await _storage.read(key: kRecoveryMilestoneKey);
      debugPrint(
          "[DEBUG] Recovered seconds: $recoveredSecondsString, milestone ID: $recoveredMilestoneId");

      if (recoveredSecondsString != null && recoveredMilestoneId != null) {
        final recoveredSeconds = int.parse(recoveredSecondsString);
        if (recoveredSeconds > 0) {
          debugPrint(
              "[DEBUG] RECOVERY: Found $recoveredSeconds seconds for milestone $recoveredMilestoneId");

          _addTimeToMilestone(
              recoveredMilestoneId, Duration(seconds: recoveredSeconds));

          await _storage.delete(key: kRecoveryTimeKey);
          await _storage.delete(key: kRecoveryMilestoneKey);
          debugPrint("[DEBUG] RECOVERY: Cleared recovery keys.");

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
        }
      } else {
        debugPrint(
            "[DEBUG] RECOVERY: No recovery data found (keys: $kRecoveryTimeKey, $kRecoveryMilestoneKey).");
      }
    } catch (e) {
      debugPrint("[DEBUG] RECOVERY ERROR: Failed to process recovery data: $e");
      try {
        await _storage.delete(key: kRecoveryTimeKey);
        await _storage.delete(key: kRecoveryMilestoneKey);
        debugPrint("[DEBUG] RECOVERY: Cleared recovery keys due to error.");
      } catch (clearError) {
        debugPrint(
            "[DEBUG] RECOVERY ERROR: Failed to clear recovery keys during error handling: $clearError");
      }
    }

    // --- 5. Set loading to false
    if (mounted) {
      debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Setting isLoading to false.");
      setState(() {
        _isLoading = false;
      });
    }
    debugPrint("[DEBUG] _loadGoalsAndProcessLaunch: Finished.");
  }

  // --- saveGoals (CHANGED) ---
  // --- FIX: Made async so we can await it ---
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
    _saveGoals(); // Save immediately (fire-and-forget is fine here)

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
        _saveGoals(); // Save immediately (fire-and-forget is fine here)
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
    _saveGoals(); // (fire-and-forget is fine here)
  }

  // --- toggleCheckpoint (CHANGED) ---
  // --- FIX: Made async to await completion check and save ---
  // --- FIX (v1.5.2): Changed return type to Future<void> ---
  Future<void> _toggleCheckpoint(
      Milestone milestone, String checkpointId) async {
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

      // --- NEW (v1.5.0): Set completion timestamp ---
      // Uses the 'isCompleted' getter from the model
      if (milestone.isCompleted && milestone.completedAt == null) {
        // This milestone just became complete
        milestone.completedAt = DateTime.now();
        debugPrint(
            "Milestone ${milestone.id} marked as complete at ${milestone.completedAt}");
      } else if (!milestone.isCompleted && milestone.completedAt != null) {
        // This milestone was just made incomplete (e.g., user unchecked a task)
        milestone.completedAt = null;
        debugPrint("Milestone ${milestone.id} marked as incomplete.");
      }
      // --- End of new logic ---
    });

    _updateMilestoneLockStatus();

    // --- FIX: Await the completion check. It will save if goal is complete. ---
    final bool didGoalComplete = await _checkForGoalCompletion();

    // --- FIX: If the goal was *not* just completed, we still need to save. ---
    if (!didGoalComplete) {
      await _saveGoals();
    }
  }

  // --- toggleCheckpointByIds (CHANGED) ---
  // --- FIX: Made async to await _toggleCheckpoint ---
  // --- FIX (v1.5.2): Changed return type to Future<void> ---
  Future<void> toggleCheckpointByIds(
      String goalId, String milestoneId, String checkpointId) async {
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
      // --- FIX: Await the call ---
      await _toggleCheckpoint(milestone, checkpointId);
    } else {
      debugPrint(
          "Error: Checkpoint $checkpointId not found in milestone $milestoneId.");
    }
  }

  // --- checkForGoalCompletion (CHANGED) ---
  // --- FIX: Made async, returns bool, and awaits archive/save ---
  Future<bool> _checkForGoalCompletion() async {
    // --- FIX: Capture the active goal *before* the setState ---
    final Goal? goalToComplete = _activeGoal;

    if (goalToComplete != null && goalToComplete.isCompleted) {
      debugPrint("Goal ${goalToComplete.id} is now complete!");
      if (!mounted) return false;

      // Set state synchronously
      setState(() {
        goalToComplete.status = GoalStatus.achieved;
        _editMode = true;
      });

      try {
        // --- FIX: Archive goal and await it ---
        await Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(goalToComplete);
        debugPrint("Goal ${goalToComplete.id} archived in Firestore.");

        // --- FIX: Save all goals (to update cache/main collection) and await it ---
        await _saveGoals();
        debugPrint("Main goals list saved after archiving.");
      } catch (e) {
        debugPrint("Error during goal completion/archiving: $e");
        // Don't throw, just log.
      }

      // Show dialog (unchanged)
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (!mounted) return;
        showDialog(
          context: context,
          builder: (ctx) => AlertDialog(
            title: const Text('Goal Achieved!'),
            content: Text(
                'Congratulations! You have completed all milestones for "${goalToComplete.title}".'),
            actions: [
              TextButton(
                child: const Text('Awesome!'),
                onPressed: () => Navigator.of(ctx).pop(),
              ),
            ],
          ),
        );
      });
      return true; // --- FIX: Return true (goal was completed) ---
    }
    return false; // --- FIX: Return false (goal not completed) ---
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
    _saveGoals(); // (fire-and-forget is fine here)
  }

  // --- addTimeToMilestone (Unchanged) ---
  void _addTimeToMilestone(String milestoneId, Duration timeToAdd) {
    if (_activeGoal == null) {
      debugPrint("AddTimeToMilestone: Active goal is null. Cannot add time.");
      return;
    }
    // Check if timeToAdd is valid
    if (timeToAdd.inSeconds <= 0) {
      debugPrint(
          "AddTimeToMilestone: timeToAdd is zero or negative. Skipping.");
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

      // --- FIX: This is the new, correct logic ---
      // Add a new session to the time log
      milestone.timeLog.add(TimeSession(
        timestamp: DateTime.now(),
        duration: timeToAdd,
      ));
      // --- End of new logic ---

      // --- DEPRECATED: Remove old logic ---
      // milestone.timeSpent += timeToAdd;
      // milestone.lastWorkedOn = DateTime.now(); // Update last worked on time
      // --- End of deprecated logic ---

      debugPrint(
          "Milestone ${milestone.id} updated: New session added. Total time is now ${milestone.timeSpent}, lastWorkedOn=${milestone.lastWorkedOn}");
    });
    // Save goals immediately after state change involving time
    _saveGoals(); // (fire-and-forget is fine here)
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
    _saveGoals(); // (fire-and-forget is fine here)
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

  // --- build (Unchanged) ---
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
        onEditModeChanged: _setEditMode,
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

  // ---
  // --- NEW: In-App Dialog Logic ---
  // ---

  /// Shows the check-in dialog pop-up.
  Future<void> _showCheckinDialog(NotificationResponse response) async {
    // Ensure the widget is still mounted before attempting to show a dialog.
    if (!mounted) {
      debugPrint("Cannot show dialog, widget is not mounted.");
      return;
    }

    if (response.payload == null || response.payload!.isEmpty) {
      debugPrint("Cannot show dialog, notification payload is empty.");
      return;
    }

    // 1. Parse Payload
    Map<String, dynamic> payloadData;
    String goalId, milestoneId, checkpointId;
    try {
      payloadData = json.decode(response.payload!);
      goalId = payloadData['goalId'];
      milestoneId = payloadData['milestoneId'];
      checkpointId = payloadData['checkpointId'];
    } catch (e) {
      debugPrint("Error parsing payload for dialog: $e");
      return;
    }

    // 2. Find Titles (We need this for the dialog UI)
    String checkpointTitle = "your task"; // Default
    try {
      final goal = _allGoals.firstWhere((g) => g.id == goalId);
      final milestone = goal.milestones.firstWhere((m) => m.id == milestoneId);
      final checkpoint =
          milestone.checkpoints.firstWhere((c) => c.id == checkpointId);
      // --- FIX: Use plain title, removed single quotes ---
      checkpointTitle = checkpoint.title;
    } catch (e) {
      debugPrint("Error finding item titles for dialog: $e");
      // Don't return, just use the default title.
    }

    // 3. Show the Dialog
    // Use the global navigatorKey's context for robustness.
    final context = navigatorKey.currentContext;
    if (context == null || !Navigator.of(context).mounted) {
      debugPrint("Cannot show dialog, context is not available.");
      return;
    }

    await showDialog(
      context: context,
      builder: (BuildContext dialogContext) {
        return AlertDialog(
          // --- FIX: Title is now the task name ---
          title: Text("$checkpointTitle?"),
          // --- FIX: Content is the 2x2 grid ---
          content: Column(
            mainAxisSize: MainAxisSize.min, // Keeps the dialog compact
            children: [
              Row(
                children: [
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Done",
                        Colors.green,
                        TaskCheckinStatus.done,
                        goalId,
                        milestoneId,
                        checkpointId,
                        toggle: true),
                  ),
                  const SizedBox(width: 8), // Gutter
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Doing",
                        Colors.blue,
                        TaskCheckinStatus.doing,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                ],
              ),
              const SizedBox(height: 8), // Space between rows
              Row(
                children: [
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Will Do",
                        Colors.orange,
                        TaskCheckinStatus.willDo,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                  const SizedBox(width: 8), // Gutter
                  Expanded(
                    child: _buildCheckinButton(
                        dialogContext,
                        "Won't Do",
                        Colors.red,
                        TaskCheckinStatus.wontDo,
                        goalId,
                        milestoneId,
                        checkpointId),
                  ),
                ],
              ),
            ],
          ),
          // --- FIX: Removed actions array ---
        );
      },
    );
  }

  /// Helper widget to build the colored buttons inside the dialog.
  Widget _buildCheckinButton(
    BuildContext dialogContext,
    String text,
    MaterialColor color, // <-- FIX: Changed type from Color to MaterialColor
    TaskCheckinStatus status,
    String goalId,
    String milestoneId,
    String checkpointId, {
    bool toggle = false,
  }) {
    // --- MOSSES: CHANGED TextButton to FilledButton ---
    return FilledButton(
      style: FilledButton.styleFrom(
        backgroundColor: color.shade100, // Light background
        foregroundColor: color.shade900, // Dark text
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(12), // Softer corners
        ),
        // Make the buttons a bit taller to fill the 2x2 grid
        padding: const EdgeInsets.symmetric(vertical: 16.0),
      ).copyWith(
        // Use .copyWith to override overlay color for a nice press effect
        overlayColor: MaterialStateProperty.all(color.shade200),
      ),
      child: Text(text, style: const TextStyle(fontWeight: FontWeight.bold)),
      // --- MOSSES: FIX: Added async/await ---
      onPressed: () async {
        Navigator.of(dialogContext).pop(); // Close dialog

        // Run the original foreground logic
        debugPrint("In-app dialog: '${status.name}' tapped.");
        recordTaskCheckin(goalId, milestoneId, checkpointId, status);
        if (toggle) {
          // Use `await` to ensure it completes
          await toggleCheckpointByIds(goalId, milestoneId, checkpointId);
        }
      },
    );
  }
}
