/*
 * @author Mosses
 * @version 1.1.0
 * --- CHANGELOG ---
 * v1.1.0: Implemented timer recovery logic on app startup.
 * App now checks SharedPreferences for 'kRecoveryTimeKey'.
 * If found, adds the lost time to the correct milestone
 * and notifies the user via a SnackBar.
 */

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
import 'package:shared_preferences/shared_preferences.dart'; // Import for recovery
import 'firebase_options.dart';

import './models.dart';
import './services.dart';
import './ui.dart';
import './auth_screen.dart';
import './notification_service.dart';

// --- Keys for SharedPreferences Timer Recovery ---
const String kRecoveryTimeKey = 'recovery_time_seconds';
const String kRecoveryMilestoneKey = 'recovery_milestone_id';

final GlobalKey<NavigatorState> navigatorKey = GlobalKey<NavigatorState>();

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode =
        _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

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
    timeZoneName = 'America/Detroit';
  }

  tz.initializeTimeZones();
  if (!kIsWeb) {
    if (Platform.isAndroid || Platform.isIOS) {
      tz.setLocalLocation(tz.getLocation(timeZoneName));
      debugPrint("Timezone set to: ${tz.local.name}");
    }
  }

  runApp(
    MultiProvider(
      providers: [
        ChangeNotifierProvider(create: (_) => ThemeProvider()),
        ChangeNotifierProvider(create: (_) => AuthService()),
        ProxyProvider<AuthService, FirestoreService>(
          update: (_, auth, __) => FirestoreService(auth.currentUser?.uid),
        ),
      ],
      child: const MilestoneApp(),
    ),
  );
}

class MilestoneApp extends StatelessWidget {
  const MilestoneApp({super.key});

  @override
  Widget build(BuildContext context) {
    final themeProvider = Provider.of<ThemeProvider>(context);

    final lightTheme = ThemeData(
      brightness: Brightness.light,
      primarySwatch: Colors.deepPurple,
      scaffoldBackgroundColor: const Color(0xFFF7F7FA),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFFF7F7FA),
        foregroundColor: Colors.black87,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.black87,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.light,
        primary: Colors.deepPurple.shade500,
        secondary: Colors.deepPurple.shade300,
      ),
      cardColor: Colors.white,
      dividerColor: Colors.grey[200],
    );

    final darkTheme = ThemeData(
      brightness: Brightness.dark,
      primarySwatch: Colors.deepPurple,
      scaffoldBackgroundColor: const Color(0xFF121212),
      appBarTheme: const AppBarTheme(
        backgroundColor: Color(0xFF1E1E1E),
        foregroundColor: Colors.white70,
        elevation: 0,
        titleTextStyle: TextStyle(
          color: Colors.white70,
          fontSize: 20,
          fontWeight: FontWeight.w600,
        ),
      ),
      colorScheme: ColorScheme.fromSeed(
        seedColor: Colors.deepPurple,
        brightness: Brightness.dark,
        primary: Colors.deepPurple.shade400,
        secondary: Colors.deepPurple.shade600,
      ),
      cardColor: const Color(0xFF1E1E1E),
      dividerColor: Colors.grey[800],
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

    return StreamBuilder(
      stream: authService.authStateChanges,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const Scaffold(
              body: Center(child: CircularProgressIndicator()));
        }
        if (snapshot.hasData) {
          return const MainPage();
        }
        return const AuthScreen();
      },
    );
  }
}

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
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    _loadGoalsAndRecover(); // Load goals AND check for lost time
    _configureSelectNotificationSubject();
  }

  void _configureSelectNotificationSubject() {
    NotificationService()
        .selectNotificationSubject
        .stream
        .listen((response) async {
      debugPrint('UI received notification response: ${response.payload}');
      // Dismiss the notification banner
      NotificationService().cancelNotification(response.id ?? 0);

      if (response.payload != null && response.payload!.isNotEmpty) {
        final payloadData = json.decode(response.payload!);
        final goalId = payloadData['goalId'];
        final milestoneId = payloadData['milestoneId'];
        final checkpointId = payloadData['checkpointId'];

        TaskCheckinStatus status;
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
            return;
        }

        if (shouldToggleCheckpoint) {
          toggleCheckpointByIds(goalId, milestoneId, checkpointId);
        }
        recordTaskCheckin(goalId, milestoneId, checkpointId, status);
      }
    });
  }

  /// Loads all goals from Firestore and checks for any recovered timer data.
  Future<void> _loadGoalsAndRecover() async {
    setState(() => _isLoading = true);
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);

    // 1. Load goals from persistence
    final goals = await persistenceService.loadGoals();
    if (!mounted) return;

    _allGoals = goals;
    _updateMilestoneLockStatus(); // Update lock status *before* recovery logic

    // 2. Check for recovered timer data
    final prefs = await SharedPreferences.getInstance();
    final int? recoveredSeconds = prefs.getInt(kRecoveryTimeKey);
    final String? recoveredMilestoneId = prefs.getString(kRecoveryMilestoneKey);

    // Check if we have valid recovery data
    if (recoveredSeconds != null &&
        recoveredSeconds > 0 &&
        recoveredMilestoneId != null) {
      debugPrint(
          "RECOVERY: Found $recoveredSeconds seconds for milestone $recoveredMilestoneId");

      // Add the recovered time to the milestone
      // We call this *before* setting isLoading to false
      _addTimeToMilestone(
          recoveredMilestoneId, Duration(seconds: recoveredSeconds));

      // Clear the keys so this doesn't run again on next launch
      await prefs.remove(kRecoveryTimeKey);
      await prefs.remove(kRecoveryMilestoneKey);

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
      debugPrint("RECOVERY: No recovery data found.");
    }

    // 3. Set loading to false
    if (mounted) {
      setState(() {
        _isLoading = false;
      });
    }
  }

  Future<void> _saveGoals() async {
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    await persistenceService.saveGoals(_allGoals);
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _setMainGoal(String goalTitle) {
    setState(() {
      final currentActiveGoal = _activeGoal;
      if (currentActiveGoal != null) {
        currentActiveGoal.status = GoalStatus.givenUp;
        Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(currentActiveGoal);
      }
      _allGoals.add(Goal(title: goalTitle));
      _selectedIndex = 1;
    });
    _saveGoals();

    WidgetsBinding.instance.addPostFrameCallback((_) {
      showDialog(
        context: context,
        builder: (context) => AlertDialog(
          title: const Text("Goal Set! 🚀"),
          content: const Text(
              "Your new goal is active. Let's add the first milestone."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _milestonesPageKey.currentState
                    ?.showAddMilestoneDialog(context);
              },
              child: const Text("Let's Go!"),
            ),
          ],
        ),
      );
    });
  }

  void _giveUpGoal() {
    if (_activeGoal == null) return;

    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Give Up Goal?'),
        content: Text(
            "Are you sure you want to give up on '${_activeGoal!.title}'? This cannot be undone."),
        actions: <Widget>[
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
        setState(() {
          _activeGoal!.status = GoalStatus.givenUp;
          Provider.of<FirestoreService>(context, listen: false)
              .archiveGoal(_activeGoal!);
        });
        _saveGoals();
      }
    });
  }

  void _addMilestone(Milestone milestone) {
    setState(() {
      _activeGoal?.milestones.add(milestone);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  void _toggleCheckpoint(Milestone milestone, String checkpointId) {
    setState(() {
      if (milestone.completedCheckpointIds.contains(checkpointId)) {
        milestone.completedCheckpointIds.remove(checkpointId);
      } else {
        milestone.completedCheckpointIds.add(checkpointId);
      }
      _updateMilestoneLockStatus();
      _checkForGoalCompletion();
    });
    _saveGoals();
  }

  void toggleCheckpointByIds(
      String goalId, String milestoneId, String checkpointId) {
    final goal = _allGoals.firstWhere((g) => g.id == goalId,
        orElse: () => Goal(title: ''));
    if (goal.title.isEmpty) return;

    final milestone = goal.milestones.firstWhere((m) => m.id == milestoneId,
        orElse: () =>
            Milestone(title: '', deadline: DateTime.now(), checkpoints: []));
    if (milestone.title.isEmpty) return;

    _toggleCheckpoint(milestone, checkpointId);
  }

  void _checkForGoalCompletion() {
    if (_activeGoal != null && _activeGoal!.isCompleted) {
      setState(() {
        _activeGoal!.status = GoalStatus.achieved;
        _editMode = true;
        Provider.of<FirestoreService>(context, listen: false)
            .archiveGoal(_activeGoal!);
      });
      _saveGoals();
      WidgetsBinding.instance.addPostFrameCallback((_) {
        showDialog(
          context: context,
          builder: (context) => AlertDialog(
            title: const Text("Congratulations! 🎉"),
            content: Text(
                "You have successfully achieved your goal: '${_activeGoal!.title}'!"),
            actions: [
              TextButton(
                onPressed: () => Navigator.of(context).pop(),
                child: const Text("Awesome!"),
              ),
            ],
          ),
        );
      });
    }
  }

  void _deleteMilestone(String id) {
    setState(() {
      _activeGoal?.milestones.removeWhere((m) => m.id == id);
      _updateMilestoneLockStatus();
    });
    _saveGoals();
  }

  void _addTimeToMilestone(String milestoneId, Duration timeToAdd) {
    // Guard against adding time to a non-existent goal
    if (_activeGoal == null) {
      debugPrint("RECOVERY: Could not add time. Active goal is null.");
      return;
    }

    setState(() {
      // Find the milestone safely.
      final milestone =
          _activeGoal?.milestones.firstWhere((m) => m.id == milestoneId);

      if (milestone != null) {
        milestone.timeSpent += timeToAdd;
        milestone.lastWorkedOn = DateTime.now();
        debugPrint(
            "RECOVERY: Successfully added ${timeToAdd.inSeconds}s to ${milestone.title}");
      } else {
        debugPrint(
            "RECOVERY: Could not find milestone $milestoneId to add time to.");
      }
    });
    _saveGoals();
  }

  void recordTaskCheckin(String goalId, String milestoneId, String checkpointId,
      TaskCheckinStatus status) {
    setState(() {
      final goal = _allGoals.firstWhere((g) => g.id == goalId,
          orElse: () => Goal(title: ''));
      if (goal.title.isEmpty) return;

      final milestone = goal.milestones.firstWhere((m) => m.id == milestoneId,
          orElse: () =>
              Milestone(title: '', deadline: DateTime.now(), checkpoints: []));
      if (milestone.title.isEmpty) return;

      milestone.checkins
          .add(TaskCheckin(checkpointId: checkpointId, status: status));
    });
    _saveGoals();
    debugPrint("Check-in recorded for $checkpointId with status $status");
  }

  void _updateMilestoneLockStatus() {
    if (_activeGoal == null) return;
    bool isLocked = false;
    for (var m in _activeGoal!.milestones) {
      m.isUnlocked = !isLocked;
      if (!m.isCompleted) {
        isLocked = true;
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
        body: Center(child: CircularProgressIndicator()),
      );
    }

    final themeProvider = Provider.of<ThemeProvider>(context, listen: false);

    final List<Widget> pages = [
      HomePage(
        key: ValueKey('${_activeGoal?.id}-${_activeGoal?.completedTasks}'),
        activeGoal: _activeGoal,
        onSetGoal: _setMainGoal,
        onTimeAdd: _addTimeToMilestone,
        onGiveUp: _giveUpGoal,
      ),
      MilestonesPage(
        key: _milestonesPageKey,
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
        allGoals: _allGoals,
      ),
    ];

    return Scaffold(
      body: IndexedStack(
        index: _selectedIndex,
        children: pages,
      ),
      bottomNavigationBar: BottomNavigationBar(
        currentIndex: _selectedIndex,
        onTap: _onTabTapped,
        selectedItemColor: Theme.of(context).colorScheme.primary,
        unselectedItemColor: Colors.grey,
        backgroundColor: Theme.of(context).cardColor,
        elevation: 4,
        items: const [
          BottomNavigationBarItem(
              icon: Icon(Icons.home_rounded), label: 'Home'),
          BottomNavigationBarItem(
              icon: Icon(Icons.flag_rounded), label: 'Milestones'),
          BottomNavigationBarItem(
              icon: Icon(Icons.settings_rounded), label: 'Settings'),
        ],
      ),
    );
  }
}
