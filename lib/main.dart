import 'package:flutter/material.dart';
import 'package:flutter/foundation.dart' show kIsWeb;
import 'dart:io' show Platform;
import 'package:flutter_dotenv/flutter_dotenv.dart';
import 'package:flutter/services.dart';
import 'package:provider/provider.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;
import 'package:firebase_core/firebase_core.dart';
import 'firebase_options.dart';

import './models.dart';
import './services.dart';
import './ui.dart';
import './auth_screen.dart';

class ThemeProvider with ChangeNotifier {
  ThemeMode _themeMode = ThemeMode.light;
  ThemeMode get themeMode => _themeMode;

  bool get isDarkMode => _themeMode == ThemeMode.dark;

  void toggleTheme() {
    _themeMode = _themeMode == ThemeMode.light ? ThemeMode.dark : ThemeMode.light;
    notifyListeners();
  }
}

Future<void> main() async {
  WidgetsFlutterBinding.ensureInitialized();

  await dotenv.load(fileName: ".env");

  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );

  const MethodChannel timezoneChannel = MethodChannel('com.example.trackit/timezone');
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
    }
  }

  // Note: initNotifications is now called within the app's lifecycle
  // where a BuildContext is available.

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
      title: 'Milestone',
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
          return const Scaffold(body: Center(child: CircularProgressIndicator()));
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
    // FIX: Call initNotifications here, where context is available
    WidgetsBinding.instance.addPostFrameCallback((_) {
      initNotifications(context);
    });
    _loadGoals();
  }

  Future<void> _loadGoals() async {
    setState(() => _isLoading = true);
    final persistenceService =
        Provider.of<FirestoreService>(context, listen: false);
    final goals = await persistenceService.loadGoals();
    if (mounted) {
      setState(() {
        _allGoals = goals;
        _isLoading = false;
        _updateMilestoneLockStatus();
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
          content:
              const Text("Your new goal is active. Let's add the first milestone."),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(context).pop();
                _milestonesPageKey.currentState?.showAddMilestoneDialog(context);
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

  void _checkForGoalCompletion() {
    if (_activeGoal != null && _activeGoal!.isCompleted) {
      setState(() {
        _activeGoal!.status = GoalStatus.achieved;
        _editMode = true;
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
    setState(() {
      final milestone =
          _activeGoal?.milestones.firstWhere((m) => m.id == milestoneId);
      if (milestone != null) {
        milestone.timeSpent += timeToAdd;
        milestone.lastWorkedOn = DateTime.now();
      }
    });
    _saveGoals();
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

