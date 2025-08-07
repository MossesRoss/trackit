import 'package:flutter/material.dart';
import 'dart:convert';
import 'dart:async';
import 'package:http/http.dart' as http;
import 'package:intl/intl.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:timezone/data/latest.dart' as tz;
import 'package:timezone/timezone.dart' as tz;


// --- Notification Service ---
final FlutterLocalNotificationsPlugin flutterLocalNotificationsPlugin =
    FlutterLocalNotificationsPlugin();

Future<void> initNotifications() async {
  const AndroidInitializationSettings initializationSettingsAndroid =
      AndroidInitializationSettings('@mipmap/ic_launcher');

  const InitializationSettings initializationSettings = InitializationSettings(
    android: initializationSettingsAndroid,
  );

  await flutterLocalNotificationsPlugin.initialize(initializationSettings);
}

// CORRECTED notification scheduling function
Future<void> scheduleNotification(int id, String title, String body, int hour, int minute) async {
  // Helper function to calculate the next instance of the scheduled time
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

  await flutterLocalNotificationsPlugin.zonedSchedule(
    id,
    title,
    body,
    _nextInstanceOfTime(hour, minute),
    platformChannelSpecifics,
    uiLocalNotificationDateInterpretation: UILocalNotificationDateInterpretation.absoluteTime,
    matchDateTimeComponents: DateTimeComponents.time,
  );
}


// --- Main Entry Point ---
Future<void> main() async {
  // These two lines are essential for notifications and timezone support
  WidgetsFlutterBinding.ensureInitialized();
  tz.initializeTimeZones(); // Initialize timezone database
  await initNotifications();
  runApp(const MilestoneApp());
}

// --- App Theme & Configuration ---
class MilestoneApp extends StatefulWidget {
  const MilestoneApp({super.key});

  @override
  State<MilestoneApp> createState() => _MilestoneAppState();
}

class _MilestoneAppState extends State<MilestoneApp> {
  bool _isDarkMode = false;

  void _toggleDarkMode() {
    setState(() {
      _isDarkMode = !_isDarkMode;
    });
  }

  @override
  Widget build(BuildContext context) {
    // A more subtle color scheme
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
      title: 'Milestone AI',
      theme: lightTheme,
      darkTheme: darkTheme,
      themeMode: _isDarkMode ? ThemeMode.dark : ThemeMode.light,
      home: MainPage(toggleDarkMode: _toggleDarkMode, isDarkMode: _isDarkMode),
      debugShowCheckedModeBanner: false,
    );
  }
}

// --- Data Models ---
enum GoalStatus { active, achieved, givenUp }

class Goal {
  String id;
  String title;
  List<Milestone> milestones;
  GoalStatus status;
  DateTime createdAt;

  Goal({required this.title, this.milestones = const [], this.status = GoalStatus.active})
    : id = UniqueKey().toString(),
      createdAt = DateTime.now();

  int get completedMilestones => milestones.where((m) => m.isCompleted).length;
  bool get isCompleted => milestones.isNotEmpty && milestones.every((m) => m.isCompleted);
}


class Milestone {
  String id;
  String title;
  DateTime deadline;
  List<String> checkpoints;
  List<String> completedCheckpoints;
  bool isUnlocked;
  Duration timeSpent;

  Milestone({
    required this.title,
    required this.deadline,
    required this.checkpoints,
    this.completedCheckpoints = const [],
    this.isUnlocked = false,
    this.timeSpent = Duration.zero,
  }) : id = UniqueKey().toString();

  double get progress => checkpoints.isEmpty ? 0.0 : completedCheckpoints.length / checkpoints.length;
  bool get isCompleted => progress == 1.0;
}

// --- Main Page (Handles Navigation & State) ---
class MainPage extends StatefulWidget {
  final VoidCallback toggleDarkMode;
  final bool isDarkMode;

  const MainPage({super.key, required this.toggleDarkMode, required this.isDarkMode});

  @override
  State<MainPage> createState() => _MainPageState();
}

class _MainPageState extends State<MainPage> {
  int _selectedIndex = 0;
  List<Goal> _allGoals = [];
  bool _editMode = true;

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
    // Example Data
    _allGoals = [
      Goal(title: "Launch My App", status: GoalStatus.active, milestones: [
        Milestone(title: "Project Alpha Kick-off", deadline: DateTime.now().add(const Duration(days: 10)), checkpoints: ["Define Scope", "Assemble Team", "Initial Budget"], completedCheckpoints: ["Define Scope", "Assemble Team", "Initial Budget"], timeSpent: const Duration(hours: 5, minutes: 30)),
        Milestone(title: "Design Phase", deadline: DateTime.now().add(const Duration(days: 25)), checkpoints: ["Wireframes", "Mockups", "Prototype"], completedCheckpoints: ["Wireframes"], timeSpent: const Duration(minutes: 45)),
        Milestone(title: "Development Sprint 1", deadline: DateTime.now().add(const Duration(days: 40)), checkpoints: ["Setup Backend", "User Auth", "API Endpoints"]),
      ]),
      Goal(title: "Learn Flutter", status: GoalStatus.achieved, milestones: [Milestone(title: "Complete a course", deadline: DateTime.now(), checkpoints: ["Task 1"], completedCheckpoints: ["Task 1"])]),
      Goal(title: "World Domination", status: GoalStatus.givenUp),
    ];
    _updateMilestoneLockStatus();
  }

  void _onTabTapped(int index) {
    setState(() {
      _selectedIndex = index;
    });
  }

  void _setMainGoal(String goalTitle) {
    setState(() {
      if (_activeGoal != null) {
        _activeGoal!.status = GoalStatus.givenUp;
      }
      _allGoals.add(Goal(title: goalTitle));
    });
  }

  void _addMilestone(Milestone milestone) {
    setState(() {
      _activeGoal?.milestones.add(milestone);
      _updateMilestoneLockStatus();
    });
  }

  void _toggleCheckpoint(Milestone milestone, String checkpoint) {
    setState(() {
      if (milestone.completedCheckpoints.contains(checkpoint)) {
        milestone.completedCheckpoints.remove(checkpoint);
      } else {
        milestone.completedCheckpoints.add(checkpoint);
      }
      _updateMilestoneLockStatus();
      _checkForGoalCompletion();
    });
  }

  void _checkForGoalCompletion() {
      if (_activeGoal != null && _activeGoal!.isCompleted) {
          setState(() {
              _activeGoal!.status = GoalStatus.achieved;
              _editMode = true;
          });
          // Show congratulations dialog
          WidgetsBinding.instance.addPostFrameCallback((_) {
              showDialog(
                  context: context,
                  builder: (context) => AlertDialog(
                      title: const Text("Congratulations! 🎉"),
                      content: Text("You have successfully achieved your goal: '${_activeGoal!.title}'!"),
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
  }

  void _addTimeToMilestone(String milestoneId, Duration timeToAdd) {
      setState(() {
          final milestone = _activeGoal?.milestones.firstWhere((m) => m.id == milestoneId);
          milestone?.timeSpent += timeToAdd;
      });
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

  Future<bool> _onWillPop() async {
    return (await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Are you sure?'),
        content: const Text('Do you want to exit the app?'),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('No'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Yes'),
          ),
        ],
      ),
    )) ?? false;
  }

  @override
  Widget build(BuildContext context) {
    final List<Widget> pages = [
      HomePage(
        key: ValueKey(_activeGoal?.id), // Rebuilds homepage when goal changes
        activeGoal: _activeGoal,
        onSetGoal: _setMainGoal,
        onTimeAdd: _addTimeToMilestone,
      ),
      MilestonesPage(
        activeGoal: _activeGoal,
        onAddMilestone: _addMilestone,
        onToggleCheckpoint: _toggleCheckpoint,
        onDeleteMilestone: _deleteMilestone,
        editMode: _editMode,
      ),
      SettingsPage(
        isDarkMode: widget.isDarkMode,
        toggleDarkMode: widget.toggleDarkMode,
        editMode: _editMode,
        onEditModeChanged: (val) => setState(() => _editMode = val),
        allGoals: _allGoals,
      ),
    ];

    return WillPopScope(
      onWillPop: _onWillPop,
      child: Scaffold(
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
            BottomNavigationBarItem(icon: Icon(Icons.home_rounded), label: 'Home'),
            BottomNavigationBarItem(icon: Icon(Icons.flag_rounded), label: 'Milestones'),
            BottomNavigationBarItem(icon: Icon(Icons.settings_rounded), label: 'Settings'),
          ],
        ),
      ),
    );
  }
}


// --- Home Page ---
class HomePage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(String) onSetGoal;
  final Function(String, Duration) onTimeAdd;

  const HomePage({super.key, this.activeGoal, required this.onSetGoal, required this.onTimeAdd});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _aiSuggestion = "";
  bool _isLoading = false;

  Milestone? get _nextMilestone {
    try {
      return widget.activeGoal?.milestones.firstWhere((m) => !m.isCompleted);
    } catch (e) {
      return null;
    }
  }

  @override
  void initState() {
    super.initState();
    if (_nextMilestone != null) {
      _getAiSuggestion();
    }
  }

  Future<void> _getAiSuggestion() async {
    if (_nextMilestone == null) return;
    setState(() => _isLoading = true);

    const apiKey = ""; // IMPORTANT: Paste your Gemini API Key here
    if (apiKey.isEmpty) {
        setState(() {
            _aiSuggestion = "Please add your Gemini API Key in the code to enable this feature.";
            _isLoading = false;
        });
        return;
    }
    const url = 'https://generativelanguage.googleapis.com/v1beta/models/gemini-pro:generateContent?key=$apiKey';

    final prompt = "My current milestone is '${_nextMilestone!.title}' due on ${DateFormat.yMMMd().format(_nextMilestone!.deadline)}. The remaining tasks are: ${_nextMilestone!.checkpoints.where((c) => !_nextMilestone!.completedCheckpoints.contains(c)).join(', ')}. What is a single, concise, and actionable task I should focus on right now to make progress? Keep it short, motivating, and start with an action verb.";

    try {
      final response = await http.post(
        Uri.parse(url),
        headers: {'Content-Type': 'application/json'},
        body: json.encode({
          'contents': [{'role': 'user', 'parts': [{'text': prompt}]}]
        }),
      );

      if (response.statusCode == 200) {
        final data = json.decode(response.body);
        setState(() {
          _aiSuggestion = data['candidates'][0]['content']['parts'][0]['text'].trim();
        });
      } else {
        setState(() => _aiSuggestion = "Error: Could not get suggestion.");
      }
    } catch (e) {
      setState(() => _aiSuggestion = "Focus on your first incomplete task.");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  void _startFocusMode(Milestone milestone) {
    Navigator.of(context).push(MaterialPageRoute(
      builder: (context) => TimerFocusPage(
        milestone: milestone,
        onSessionComplete: (duration) {
          widget.onTimeAdd(milestone.id, duration);
        },
      ),
      fullscreenDialog: true,
    ));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(widget.activeGoal?.title ?? 'Set Your Main Goal')),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: widget.activeGoal == null
              ? GoalSetterCard(onSetGoal: widget.onSetGoal)
              : _nextMilestone == null
                  ? GoalSetterCard(onSetGoal: widget.onSetGoal, isNewGoal: true)
                  : ListView(
                      children: [
                        // AI Suggestion Card
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                          child: Container(
                            padding: const EdgeInsets.all(24.0),
                            width: double.infinity,
                            child: Column(
                              children: [
                                Icon(Icons.lightbulb_outline_rounded, size: 32, color: Colors.amber.shade700),
                                const SizedBox(height: 12),
                                const Text("Today's Focus", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
                                const SizedBox(height: 16),
                                _isLoading
                                    ? const CircularProgressIndicator()
                                    : Text(
                                        _aiSuggestion,
                                        textAlign: TextAlign.center,
                                        style: TextStyle(fontSize: 16, color: Theme.of(context).textTheme.bodyMedium?.color?.withOpacity(0.8)),
                                      ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 40),
                        // Timer Card
                        Text("Focus on: ${_nextMilestone!.title}", style: TextStyle(fontWeight: FontWeight.w600, color: Theme.of(context).colorScheme.primary)),
                        const SizedBox(height: 16),
                        GestureDetector(
                          onLongPress: () => _startFocusMode(_nextMilestone!),
                          child: Container(
                            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
                            decoration: BoxDecoration(
                              color: Theme.of(context).cardColor,
                              borderRadius: BorderRadius.circular(12),
                              boxShadow: [BoxShadow(color: Colors.black.withOpacity(0.05), blurRadius: 10, offset: const Offset(0, 4))]
                            ),
                            child: const Text("00:00:00", style: TextStyle(fontSize: 48, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                          ),
                        ),
                         Padding(
                           padding: const EdgeInsets.only(top: 12.0),
                           child: Text("Long-press to start focus session", style: TextStyle(color: Colors.grey.shade500, fontSize: 12)),
                         ),
                         const SizedBox(height: 40),
                         // Progress Chart
                         SizedBox(
                           height: 200,
                           child: ProgressPieChart(
                             completed: widget.activeGoal?.completedMilestones ?? 0,
                             total: widget.activeGoal?.milestones.length ?? 0,
                           ),
                         )
                      ],
                    ),
        ),
      ),
    );
  }
}

// --- Progress Pie Chart ---
class ProgressPieChart extends StatelessWidget {
  final int completed;
  final int total;
  const ProgressPieChart({super.key, required this.completed, required this.total});

  @override
  Widget build(BuildContext context) {
    final double percentage = total == 0 ? 0 : completed / total;
    return PieChart(
      PieChartData(
        sections: [
          PieChartSectionData(
            color: Colors.green,
            value: percentage * 100,
            title: '${(percentage * 100).toStringAsFixed(0)}%',
            radius: 50,
            titleStyle: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold, color: Colors.white)
          ),
          PieChartSectionData(
            color: Colors.grey.shade300,
            value: (1 - percentage) * 100,
            title: '',
            radius: 50,
          ),
        ],
        centerSpaceRadius: 40,
        sectionsSpace: 2,
      ),
    );
  }
}

// --- Goal Setter Card ---
class GoalSetterCard extends StatefulWidget {
  final Function(String) onSetGoal;
  final bool isNewGoal;
  const GoalSetterCard({super.key, required this.onSetGoal, this.isNewGoal = false});

  @override
  State<GoalSetterCard> createState() => _GoalSetterCardState();
}

class _GoalSetterCardState extends State<GoalSetterCard> {
  final _controller = TextEditingController();

  void _submit() {
    if (_controller.text.trim().isNotEmpty) {
      widget.onSetGoal(_controller.text.trim());
    }
  }

  @override
  Widget build(BuildContext context) {
    return Card(
      elevation: 2,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(24.0),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            if (widget.isNewGoal)
              const Text("Previous Goal Achieved! 🎉", style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: Colors.green)),
            const SizedBox(height: 8),
            Text(widget.isNewGoal ? "What's your next big goal?" : "What is your main goal?", style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
            const SizedBox(height: 16),
            TextField(
              controller: _controller,
              decoration: const InputDecoration(
                labelText: "e.g., Launch My App",
                border: OutlineInputBorder(),
              ),
              onSubmitted: (_) => _submit(),
            ),
            const SizedBox(height: 16),
            ElevatedButton(
              onPressed: _submit,
              child: const Text("Set New Goal"),
            ),
          ],
        ),
      ),
    );
  }
}


// --- Timer Focus Page ---
class TimerFocusPage extends StatefulWidget {
  final Milestone milestone;
  final Function(Duration) onSessionComplete;
  const TimerFocusPage({super.key, required this.milestone, required this.onSessionComplete});

  @override
  State<TimerFocusPage> createState() => _TimerFocusPageState();
}

class _TimerFocusPageState extends State<TimerFocusPage> {
  Timer? _timer;
  int _seconds = 0;

  @override
  void initState() {
    super.initState();
    _startTimer();
  }

  void _startTimer() {
    _timer = Timer.periodic(const Duration(seconds: 1), (timer) {
      setState(() {
        _seconds++;
      });
    });
  }

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  String _formatTime(int totalSeconds) {
    final duration = Duration(seconds: totalSeconds);
    String twoDigits(int n) => n.toString().padLeft(2, '0');
    final hours = twoDigits(duration.inHours);
    final minutes = twoDigits(duration.inMinutes.remainder(60));
    final seconds = twoDigits(duration.inSeconds.remainder(60));
    return "$hours:$minutes:$seconds";
  }

  Future<void> _showExitConfirmation() async {
    _timer?.cancel();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Focus Session?"),
        content: Text("You've focused for ${_formatTime(_seconds)}. Do you want to add this time to your milestone?"),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text("Discard"),
          ),
          ElevatedButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text("Save & Exit"),
          ),
        ],
      ),
    );

    if (result != null) {
      if (result) { // Save
        widget.onSessionComplete(Duration(seconds: _seconds));
      }
      if (mounted) {
        Navigator.of(context).pop();
      }
    } else {
      // Dialog was dismissed, resume timer
      _startTimer();
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Theme.of(context).scaffoldBackgroundColor,
      body: GestureDetector(
        onLongPress: _showExitConfirmation,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text("Focusing on:", style: TextStyle(fontSize: 20, color: Colors.grey.shade500)),
                  const SizedBox(height: 8),
                  Text(widget.milestone.title, style: TextStyle(fontSize: 28, fontWeight: FontWeight.bold, color: Theme.of(context).colorScheme.primary), textAlign: TextAlign.center,),
                  const SizedBox(height: 40),
                  Text(_formatTime(_seconds), style: const TextStyle(fontSize: 72, fontWeight: FontWeight.bold, fontFamily: 'monospace')),
                ],
              ),
            ),
            Positioned(
              bottom: 40,
              left: 20,
              right: 20,
              child: Text("Long-press anywhere to end session", textAlign: TextAlign.center, style: TextStyle(color: Colors.grey.shade500)),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Milestones Page ---
class MilestonesPage extends StatelessWidget {
  final Goal? activeGoal;
  final Function(Milestone) onAddMilestone;
  final Function(Milestone, String) onToggleCheckpoint;
  final Function(String) onDeleteMilestone;
  final bool editMode;

  const MilestonesPage({super.key, this.activeGoal, required this.onAddMilestone, required this.onToggleCheckpoint, required this.onDeleteMilestone, required this.editMode});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        actions: [
          if (editMode && activeGoal != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => _showAddMilestoneDialog(context),
              tooltip: 'Add Milestone',
            ),
        ],
      ),
      body: activeGoal == null
          ? const Center(child: Text("Set a main goal on the Home page first."))
          : activeGoal!.milestones.isEmpty
              ? const Center(child: Text("No milestones yet. Add one to start!"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: activeGoal!.milestones.length,
                  itemBuilder: (context, index) {
                    return MilestoneNode(
                      milestone: activeGoal!.milestones[index],
                      isFirst: index == 0,
                      isLast: index == activeGoal!.milestones.length - 1,
                      onToggleCheckpoint: onToggleCheckpoint,
                      onDelete: () => onDeleteMilestone(activeGoal!.milestones[index].id),
                      editMode: editMode,
                    );
                  },
                ),
    );
  }

  void _showAddMilestoneDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding: EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddMilestoneForm(onAdd: onAddMilestone),
      ),
    );
  }
}

// --- Milestone Node (for vertical timeline) ---
class MilestoneNode extends StatelessWidget {
  final Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Function(Milestone, String) onToggleCheckpoint;
  final VoidCallback onDelete;
  final bool editMode;

  const MilestoneNode({super.key, required this.milestone, required this.isFirst, required this.isLast, required this.onToggleCheckpoint, required this.onDelete, required this.editMode});

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) return "${duration.inSeconds}s";
    if (duration.inHours == 0) return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
  }

  Future<void> _confirmToggle(BuildContext context, String task) async {
    if (editMode) {
      onToggleCheckpoint(milestone, task);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(milestone.completedCheckpoints.contains(task) ? "Mark as Incomplete?" : "Mark as Complete?"),
        content: Text("Are you sure you want to change the status of this task?"),
        actions: [
          TextButton(onPressed: () => Navigator.of(context).pop(false), child: const Text("Cancel")),
          TextButton(onPressed: () => Navigator.of(context).pop(true), child: const Text("Confirm")),
        ],
      ),
    );
    if (confirm == true) {
      onToggleCheckpoint(milestone, task);
    }
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = milestone.isCompleted ? Colors.green : milestone.isUnlocked ? Theme.of(context).colorScheme.primary : Colors.grey;
    final Color lightColor = milestone.isCompleted ? Colors.green.shade100 : milestone.isUnlocked ? Theme.of(context).colorScheme.primary.withOpacity(0.1) : Colors.grey.shade200;

    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // The timeline connector
          SizedBox(
            width: 40,
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                if (!isFirst) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
                Container(
                  width: 20,
                  height: 20,
                  decoration: BoxDecoration(
                    shape: BoxShape.circle,
                    color: primaryColor,
                  ),
                  child: Icon(
                    milestone.isCompleted ? Icons.check_rounded : milestone.isUnlocked ? Icons.flag_rounded : Icons.lock_rounded,
                    color: Colors.white,
                    size: 12,
                  ),
                ),
                if (!isLast) Expanded(child: Container(width: 2, color: Colors.grey.shade300)),
              ],
            ),
          ),
          // The content card
          Expanded(
            child: Container(
              margin: const EdgeInsets.symmetric(vertical: 8.0),
              child: Card(
                elevation: 1,
                color: lightColor,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                  side: BorderSide(color: primaryColor.withOpacity(0.5)),
                ),
                child: ExpansionTile(
                  enabled: milestone.isUnlocked,
                  title: Text(milestone.title, style: TextStyle(fontWeight: FontWeight.bold, color: milestone.isUnlocked ? null : Colors.grey)),
                  subtitle: Row(
                    children: [
                      Text('Due: ${DateFormat.yMMMd().format(milestone.deadline)}'),
                      const Spacer(),
                      if (milestone.timeSpent > Duration.zero) ...[
                        Icon(Icons.timer_outlined, size: 14, color: Colors.grey.shade600),
                        const SizedBox(width: 4),
                        Text(_formatDuration(milestone.timeSpent), style: TextStyle(color: Colors.grey.shade600)),
                      ]
                    ],
                  ),
                  trailing: milestone.isUnlocked ? null : const SizedBox.shrink(),
                  children: [
                    Padding(
                      padding: const EdgeInsets.all(16.0).copyWith(top: 0),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          LinearProgressIndicator(
                            value: milestone.progress,
                            backgroundColor: Colors.grey.shade300,
                            valueColor: AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                          const SizedBox(height: 16),
                          ...milestone.checkpoints.map((task) => CheckboxListTile(
                                value: milestone.completedCheckpoints.contains(task),
                                title: Text(task, style: TextStyle(decoration: milestone.completedCheckpoints.contains(task) ? TextDecoration.lineThrough : null)),
                                onChanged: (val) => _confirmToggle(context, task),
                                dense: true,
                                contentPadding: EdgeInsets.zero,
                              )),
                          if (editMode)
                            Align(
                              alignment: Alignment.centerRight,
                              child: TextButton(
                                onPressed: onDelete,
                                child: const Text("Delete", style: TextStyle(color: Colors.red)),
                              ),
                            )
                        ],
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }
}

// --- Add Milestone Form ---
class AddMilestoneForm extends StatefulWidget {
  final Function(Milestone) onAdd;
  const AddMilestoneForm({super.key, required this.onAdd});

  @override
  State<AddMilestoneForm> createState() => _AddMilestoneFormState();
}

class _AddMilestoneFormState extends State<AddMilestoneForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  DateTime? _selectedDate;

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  void _submit() {
    if (_formKey.currentState!.validate()) {
      if (_selectedDate == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Please choose a deadline date.')),
        );
        return;
      }
      final newMilestone = Milestone(
        title: _titleController.text,
        deadline: _selectedDate!,
        checkpoints: _tasksController.text.split('\n').where((s) => s.trim().isNotEmpty).toList(),
        completedCheckpoints: [],
      );
      widget.onAdd(newMilestone);
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(20.0),
      child: Form(
        key: _formKey,
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text("New Milestone", style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(labelText: 'Title', border: OutlineInputBorder()),
              validator: (value) => value == null || value.isEmpty ? 'Please enter a title' : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tasksController,
              decoration: const InputDecoration(labelText: 'Tasks (one per line)', border: OutlineInputBorder()),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: Text(_selectedDate == null ? 'No date chosen' : 'Due: ${DateFormat.yMMMd().format(_selectedDate!)}'),
                ),
                TextButton(onPressed: _pickDate, child: const Text('Choose Date')),
              ],
            ),
            const SizedBox(height: 20),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                onPressed: _submit,
                child: const Text('Add Milestone'),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// --- Settings Pages ---
class SettingsPage extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback toggleDarkMode;
  final bool editMode;
  final Function(bool) onEditModeChanged;
  final List<Goal> allGoals;

  const SettingsPage({super.key, required this.isDarkMode, required this.toggleDarkMode, required this.editMode, required this.onEditModeChanged, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ListView(
        children: [
          SwitchListTile(
            title: const Text('Dark Mode'),
            value: isDarkMode,
            onChanged: (val) => toggleDarkMode(),
            secondary: const Icon(Icons.dark_mode_rounded),
          ),
          SwitchListTile(
            title: const Text('Edit Mode'),
            subtitle: const Text("Allows adding/modifying goals"),
            value: editMode,
            onChanged: onEditModeChanged,
            secondary: const Icon(Icons.edit_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text("My Journey"),
            subtitle: const Text("View all your past and present goals"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => MyJourneyPage(allGoals: allGoals))),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_rounded),
            title: const Text("Notifications"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => NotificationsSettingsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text("Help"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const HelpPage())),
          ),
          ListTile(
            leading: const Icon(Icons.connect_without_contact_rounded),
            title: const Text("Get in Touch"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(builder: (_) => const GetInTouchPage())),
          ),
        ],
      ),
    );
  }
}

class MyJourneyPage extends StatelessWidget {
  final List<Goal> allGoals;
  const MyJourneyPage({super.key, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Journey")),
      body: ListView.builder(
        itemCount: allGoals.length,
        itemBuilder: (context, index) {
          final goal = allGoals[index];
          final Color color;
          final IconData icon;
          switch (goal.status) {
            case GoalStatus.active:
              color = Colors.amber.shade700;
              icon = Icons.flag_rounded;
              break;
            case GoalStatus.achieved:
              color = Colors.green;
              icon = Icons.check_circle_rounded;
              break;
            case GoalStatus.givenUp:
              color = Colors.red;
              icon = Icons.cancel_rounded;
              break;
          }
          return Card(
            margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: ListTile(
              leading: Icon(icon, color: color),
              title: Text(goal.title, style: const TextStyle(fontWeight: FontWeight.bold)),
              subtitle: Text("Set on: ${DateFormat.yMMMd().format(goal.createdAt)}"),
              trailing: Text(goal.status.name.toUpperCase(), style: TextStyle(color: color, fontWeight: FontWeight.bold)),
            ),
          );
        },
      ),
    );
  }
}

class NotificationsSettingsPage extends StatefulWidget {
  const NotificationsSettingsPage({super.key});

  @override
  _NotificationsSettingsPageState createState() => _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  int _notificationCount = 1;
  List<TimeOfDay> _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];

  void _updateNotifications() {
    // First, cancel all previous notifications to avoid duplicates
    flutterLocalNotificationsPlugin.cancelAll();
    // Then, schedule new ones based on the current settings
    for (int i = 0; i < _notificationCount; i++) {
      // CORRECTED: Pass hour and minute as integers
      scheduleNotification(
        i, 
        'Milestone Reminder',
        'Don\'t forget to work on your goals today!',
        _notificationTimes[i].hour,
        _notificationTimes[i].minute,
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: [
          Text("Number of daily reminders: $_notificationCount"),
          Slider(
            value: _notificationCount.toDouble(),
            min: 0,
            max: 5,
            divisions: 5,
            label: _notificationCount.toString(),
            onChanged: (value) {
              setState(() {
                _notificationCount = value.toInt();
                // Adjust the times list to match the count
                while (_notificationTimes.length < _notificationCount) {
                  _notificationTimes.add(const TimeOfDay(hour: 9, minute: 0));
                }
                while (_notificationTimes.length > _notificationCount) {
                  _notificationTimes.removeLast();
                }
              });
            },
          ),
          const Divider(),
          for (int i = 0; i < _notificationCount; i++)
            ListTile(
              title: Text("Reminder ${i + 1}"),
              trailing: Text(_notificationTimes[i].format(context)),
              onTap: () async {
                final time = await showTimePicker(
                  context: context,
                  initialTime: _notificationTimes[i],
                );
                if (time != null) {
                  setState(() {
                    _notificationTimes[i] = time;
                  });
                }
              },
            ),
          const SizedBox(height: 20),
          ElevatedButton(
            onPressed: () {
              _updateNotifications();
              ScaffoldMessenger.of(context).showSnackBar(
                const SnackBar(content: Text("Notification settings saved!"))
              );
            },
            child: const Text("Save Settings"),
          )
        ],
      ),
    );
  }
}

class HelpPage extends StatelessWidget {
  const HelpPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("How to Use")),
      body: ListView(
        padding: const EdgeInsets.all(16),
        children: const [
          HelpTile(
            icon: Icons.lightbulb_rounded,
            title: "AI Suggestions",
            content: "The Home page shows an AI-powered task to help you focus. This requires a Gemini API key from Google AI Studio to be added to the code.",
          ),
          HelpTile(
            icon: Icons.timer_rounded,
            title: "Focus Timer",
            content: "Long-press the timer on the Home page to enter a full-screen Focus Mode. Long-press again to end the session and save your time.",
          ),
          HelpTile(
            icon: Icons.edit_rounded,
            title: "Edit Mode",
            content: "Enable 'Edit Mode' in Settings to add, modify, or delete milestones. When turned off, you can only mark tasks as complete, preventing accidental changes.",
          ),
          HelpTile(
            icon: Icons.check_circle_rounded,
            title: "Completing Goals",
            content: "When all milestones for a goal are complete, the goal is marked as 'Achieved'. The app will automatically enter Edit Mode for you to set a new goal.",
          ),
        ],
      ),
    );
  }
}

class HelpTile extends StatelessWidget {
  final IconData icon;
  final String title;
  final String content;
  const HelpTile({super.key, required this.icon, required this.title, required this.content});

  @override
  Widget build(BuildContext context) {
    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                Icon(icon, color: Theme.of(context).colorScheme.primary),
                const SizedBox(width: 12),
                Text(title, style: const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
              ],
            ),
            const SizedBox(height: 8),
            Text(content),
          ],
        ),
      ),
    );
  }
}

class GetInTouchPage extends StatelessWidget {
  const GetInTouchPage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Get in Touch")),
      body: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          children: [
            Card(
              child: ListTile(
                leading: const Icon(Icons.email_rounded),
                title: const Text("Contact Us"),
                subtitle: const Text("For feedback or support"),
                onTap: () {"pachamangacorp@gmail.com"}, 
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_rounded, color: Colors.red),
                title: const Text("Donate"),
                subtitle: const Text("Support the development"),
                onTap: () {"https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing"},
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text("Contribute"),
                subtitle: const Text("Help improve the app on GitHub"),
                onTap: () {"https://github.com/MossesRoss/trackit/edit/main/main.dart"},
              ),
            ),
          ],
        ),
      ),
    );
  }
}

