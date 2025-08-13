import 'dart:async';
import 'dart:convert';
import 'package:flutter/material.dart';
import 'package:fl_chart/fl_chart.dart';
import 'package:intl/intl.dart';
import 'package:permission_handler/permission_handler.dart';
import 'package:provider/provider.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:url_launcher/url_launcher.dart';
// FIX: Added missing import for data models.
import './models.dart';
import './services.dart';
import './reports_page.dart';

// --- Home Page ---
class HomePage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(String) onSetGoal;
  final Function(String, Duration) onTimeAdd;
  final VoidCallback onGiveUp;

  const HomePage(
      {super.key,
      this.activeGoal,
      required this.onSetGoal,
      required this.onTimeAdd,
      required this.onGiveUp});

  @override
  State<HomePage> createState() => _HomePageState();
}

class _HomePageState extends State<HomePage> {
  String _suggestion = "";
  bool _isLoading = false;

  Milestone? get _nextMilestone {
    if (widget.activeGoal == null) return null;
    for (final milestone in widget.activeGoal!.milestones) {
      if (!milestone.isCompleted) {
        return milestone;
      }
    }
    return null;
  }

  @override
  void initState() {
    super.initState();
    _fetchSuggestion();
  }

  Future<void> _fetchSuggestion() async {
    setState(() => _isLoading = true);
    // FIX: Pass the active goal to the suggestion service
    final suggestion = await SuggestionService.getSuggestion(widget.activeGoal, _nextMilestone);
    if (mounted) {
      setState(() {
        _suggestion = suggestion;
        _isLoading = false;
      });
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
      appBar: AppBar(
        title: Text(widget.activeGoal?.title ?? 'Track It'),
        actions: [
          if (widget.activeGoal != null)
            IconButton(
              icon: const Icon(Icons.outlined_flag_rounded),
              tooltip: 'Give Up Goal',
              onPressed: widget.onGiveUp,
            ),
        ],
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(16.0),
          child: widget.activeGoal == null
              ? GoalSetterCard(onSetGoal: widget.onSetGoal)
              : (widget.activeGoal!.milestones.isEmpty)
                  ? const Center(
                      child: Text(
                          "No milestones yet. Add one on the Milestones page to see your progress!"))
                  : ListView(
                      children: [
                        Card(
                          elevation: 2,
                          shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(16)),
                          child: Padding(
                            padding: const EdgeInsets.all(16.0),
                            child: Row(
                              children: [
                                // Left Side: NEW Focus Button
                                Expanded(
                                  child: Column(
                                    children: [
                                      if (_nextMilestone != null)
                                        FocusButton(
                                          onFocusStarted: () =>
                                              _startFocusMode(_nextMilestone!),
                                        )
                                      else
                                        const Icon(Icons.check_circle_outline_rounded, size: 60, color: Colors.green),
                                      const SizedBox(height: 8),
                                      Text(
                                        _nextMilestone != null
                                            ? "Focus on '${_nextMilestone!.title}'"
                                            : "All milestones complete!",
                                        textAlign: TextAlign.center,
                                        style: TextStyle(
                                            color: Colors.grey.shade600,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                // Right Side: Suggestion
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.center,
                                    children: [
                                      Icon(Icons.lightbulb_outline_rounded,
                                          size: 24,
                                          color: Colors.amber.shade700),
                                      const SizedBox(height: 8),
                                      _isLoading
                                          ? const Center(
                                              child: SizedBox(
                                                  width: 20,
                                                  height: 20,
                                                  child:
                                                      CircularProgressIndicator(
                                                          strokeWidth: 2)))
                                          : Text(
                                              _suggestion,
                                              textAlign: TextAlign.center,
                                              style: TextStyle(
                                                  fontSize: 14,
                                                  color: Theme.of(context)
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.color
                                                      ?.withOpacity(0.8)),
                                            ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "Overall Progress",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: ProgressPieChart(
                            completed: widget.activeGoal?.completedTasks ?? 0,
                            total: widget.activeGoal?.totalTasks ?? 0,
                          ),
                        ),
                        const SizedBox(height: 24),
                        const Text(
                          "Milestone Breakdown",
                          style: TextStyle(
                              fontSize: 18, fontWeight: FontWeight.bold),
                        ),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 200,
                          child: Card(
                            elevation: 0,
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(12),
                                side: BorderSide(
                                    color: Theme.of(context).dividerColor)),
                            child: Padding(
                              padding: const EdgeInsets.all(16.0),
                              child: MilestoneProgressChart(
                                  milestones:
                                      widget.activeGoal?.milestones ?? []),
                            ),
                          ),
                        ),
                      ],
                    ),
        ),
      ),
    );
  }
}

// --- Focus Button with Long-Press Indicator (unchanged) ---
class FocusButton extends StatefulWidget {
  final VoidCallback onFocusStarted;
  const FocusButton({super.key, required this.onFocusStarted});

  @override
  State<FocusButton> createState() => _FocusButtonState();
}

class _FocusButtonState extends State<FocusButton> with SingleTickerProviderStateMixin {
  late AnimationController _controller;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 750),
    )..addListener(() {
        setState(() {});
      });

    _controller.addStatusListener((status) {
      if (status == AnimationStatus.completed) {
        widget.onFocusStarted();
        _controller.reset();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  void _onLongPressStart(LongPressStartDetails details) {
    _controller.forward();
  }

  void _onLongPressEnd(LongPressEndDetails details) {
    if (_controller.status != AnimationStatus.completed) {
      _controller.reverse();
    }
  }

  @override
  Widget build(BuildContext context) {
    return GestureDetector(
      onLongPressStart: _onLongPressStart,
      onLongPressEnd: _onLongPressEnd,
      onTap: () {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Hold the button to start a focus session."),
          duration: Duration(seconds: 2),
        ));
      },
      child: SizedBox(
        width: 80,
        height: 80,
        child: Stack(
          alignment: Alignment.center,
          children: [
            SizedBox(
              width: 70,
              height: 70,
              child: CircularProgressIndicator(
                value: _controller.value,
                strokeWidth: 6,
                backgroundColor: Colors.grey.shade300,
                valueColor: AlwaysStoppedAnimation<Color>(Theme.of(context).colorScheme.primary),
              ),
            ),
            Container(
              width: 60,
              height: 60,
              decoration: BoxDecoration(
                shape: BoxShape.circle,
                color: Theme.of(context).colorScheme.primary.withOpacity(0.1),
              ),
              child: Icon(
                Icons.center_focus_strong_rounded,
                size: 30,
                color: Theme.of(context).colorScheme.primary,
              ),
            )
          ],
        ),
      ),
    );
  }
}

// --- MilestoneProgressChart (unchanged) ---
class MilestoneProgressChart extends StatelessWidget {
  final List<Milestone> milestones;
  const MilestoneProgressChart({super.key, required this.milestones});

  @override
  Widget build(BuildContext context) {
    if (milestones.isEmpty) {
      return const Center(child: Text("No milestones to show."));
    }

    final barGroups = <BarChartGroupData>[];
    for (int i = 0; i < milestones.length; i++) {
      final milestone = milestones[i];
      barGroups.add(
        BarChartGroupData(
          x: i,
          barRods: [
            BarChartRodData(
              toY: milestone.checkpoints.isEmpty ? 0 : milestone.completedCheckpointIds.length.toDouble(),
              color: Colors.deepPurple.shade300,
              width: 16,
              borderRadius: const BorderRadius.only(
                topLeft: Radius.circular(4),
                topRight: Radius.circular(4),
              ),
            ),
          ],
        ),
      );
    }

    return BarChart(
      BarChartData(
        alignment: BarChartAlignment.spaceAround,
        barGroups: barGroups,
        titlesData: FlTitlesData(
          bottomTitles: AxisTitles(
            sideTitles: SideTitles(
              showTitles: true,
              getTitlesWidget: (double value, TitleMeta meta) {
                final index = value.toInt();
                if (index >= 0 && index < milestones.length) {
                  return Padding(
                    padding: const EdgeInsets.only(top: 6.0),
                    child: Text(
                      milestones[index].title.length > 3 ? milestones[index].title.substring(0, 3) : milestones[index].title,
                      style: const TextStyle(fontSize: 10),
                    ),
                  );
                }
                return const Text('');
              },
              reservedSize: 28,
            ),
          ),
          leftTitles: AxisTitles(
            sideTitles: SideTitles(showTitles: true, reservedSize: 28,
             getTitlesWidget: (value, meta) {
                if (value % 1 == 0) {
                  return Text(value.toInt().toString());
                }
                return const Text('');
              },
            ),
          ),
          topTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
          rightTitles: const AxisTitles(sideTitles: SideTitles(showTitles: false)),
        ),
        borderData: FlBorderData(show: false),
        gridData: FlGridData(
          show: true,
          drawVerticalLine: false,
          horizontalInterval: 1,
          getDrawingHorizontalLine: (value) {
            return FlLine(
              color: Theme.of(context).dividerColor,
              strokeWidth: 1,
            );
          },
        ),
      ),
    );
  }
}


// --- Milestones Page (unchanged) ---
class MilestonesPage extends StatefulWidget {
  final Goal? activeGoal;
  final Function(Milestone) onAddMilestone;
  final Function(Milestone, String) onToggleCheckpoint;
  final Function(String) onDeleteMilestone;
  final bool editMode;

  const MilestonesPage(
      {super.key,
      this.activeGoal,
      required this.onAddMilestone,
      required this.onToggleCheckpoint,
      required this.onDeleteMilestone,
      required this.editMode});

  @override
  State<MilestonesPage> createState() => MilestonesPageState();
}

class MilestonesPageState extends State<MilestonesPage> {
  void showAddMilestoneDialog(BuildContext context) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      builder: (context) => Padding(
        padding:
            EdgeInsets.only(bottom: MediaQuery.of(context).viewInsets.bottom),
        child: AddMilestoneForm(
          onAdd: widget.onAddMilestone,
          goalTitle: widget.activeGoal?.title ?? "your goal",
        ),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('Milestones'),
        actions: [
          if (widget.editMode && widget.activeGoal != null)
            IconButton(
              icon: const Icon(Icons.add_circle_outline_rounded),
              onPressed: () => showAddMilestoneDialog(context),
              tooltip: 'Add Milestone',
            ),
        ],
      ),
      body: widget.activeGoal == null
          ? const Center(child: Text("Set a main goal on the Home page first."))
          : widget.activeGoal!.milestones.isEmpty
              ? const Center(child: Text("No milestones yet. Add one to start!"))
              : ListView.builder(
                  padding: const EdgeInsets.all(16.0),
                  itemCount: widget.activeGoal!.milestones.length,
                  itemBuilder: (context, index) {
                    final milestone = widget.activeGoal!.milestones[index];
                    return MilestoneNode(
                      key: ValueKey('${milestone.id}-${milestone.progress}'),
                      milestone: milestone,
                      isFirst: index == 0,
                      isLast:
                          index == widget.activeGoal!.milestones.length - 1,
                      onToggleCheckpoint: widget.onToggleCheckpoint,
                      onDelete: () => widget.onDeleteMilestone(milestone.id),
                      editMode: widget.editMode,
                    );
                  },
                ),
    );
  }
}

// --- Settings Page (unchanged) ---
class SettingsPage extends StatelessWidget {
  final bool isDarkMode;
  final VoidCallback toggleDarkMode;
  final bool editMode;
  final Function(bool) onEditModeChanged;
  final List<Goal> allGoals;

  const SettingsPage(
      {super.key,
      required this.isDarkMode,
      required this.toggleDarkMode,
      required this.editMode,
      required this.onEditModeChanged,
      required this.allGoals});

  @override
  Widget build(BuildContext context) {
    final authService = Provider.of<AuthService>(context, listen: false);
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
            subtitle: const Text("Allows adding/deleting milestones"),
            value: editMode,
            onChanged: onEditModeChanged,
            secondary: const Icon(Icons.edit_rounded),
          ),
          ListTile(
            leading: const Icon(Icons.assessment_rounded),
            title: const Text("Reports"),
            subtitle: const Text("View your weekly and monthly progress"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const ReportsPage())),
          ),
          ListTile(
            leading: const Icon(Icons.history_rounded),
            title: const Text("My Journey"),
            subtitle: const Text("View all your past and present goals"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => MyJourneyPage(allGoals: allGoals))),
          ),
          ListTile(
            leading: const Icon(Icons.notifications_rounded),
            title: const Text("Notifications"),
            onTap: () => Navigator.of(context).push(MaterialPageRoute(
                builder: (_) => NotificationsSettingsPage(activeGoal: Provider.of<FirestoreService>(context, listen: false).uid == null ? null : allGoals.firstWhere((g) => g.status == GoalStatus.active)))),
          ),
          ListTile(
            leading: const Icon(Icons.help_outline_rounded),
            title: const Text("Help"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const HelpPage())),
          ),
          ListTile(
            leading: const Icon(Icons.connect_without_contact_rounded),
            title: const Text("Get in Touch"),
            onTap: () => Navigator.of(context)
                .push(MaterialPageRoute(builder: (_) => const GetInTouchPage())),
          ),
          const Divider(),
          ListTile(
            leading: Icon(Icons.logout_rounded, color: Colors.red.shade400),
            title: const Text("Sign Out"),
            onTap: () {
              authService.signOut();
            },
          ),
        ],
      ),
    );
  }
}

// --- Other Pages and Widgets ---
class MyJourneyPage extends StatelessWidget {
  final List<Goal> allGoals;
  const MyJourneyPage({super.key, required this.allGoals});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("My Journey")),
      body: allGoals.isEmpty
          ? const Center(child: Text("Your journey hasn't started yet!"))
          : ListView.builder(
              itemCount: allGoals.length,
              itemBuilder: (context, index) {
                final goal = allGoals[index];
                Color color;
                IconData icon;
                final String statusText =
                    goal.status.name[0].toUpperCase() + goal.status.name.substring(1);

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
                  margin:
                      const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
                  child: ListTile(
                    leading: Icon(icon, color: color),
                    title: Text(goal.title,
                        style: const TextStyle(fontWeight: FontWeight.bold)),
                    subtitle:
                        Text("Set on: ${DateFormat.yMMMd().format(goal.createdAt)}"),
                    trailing: Text(statusText.toUpperCase(),
                        style: TextStyle(
                            color: color, fontWeight: FontWeight.bold)),
                  ),
                );
              },
            ),
    );
  }
}

class NotificationsSettingsPage extends StatefulWidget {
  final Goal? activeGoal;
  const NotificationsSettingsPage({super.key, this.activeGoal});

  @override
  _NotificationsSettingsPageState createState() =>
      _NotificationsSettingsPageState();
}

class _NotificationsSettingsPageState extends State<NotificationsSettingsPage> {
  int _notificationCount = 1;
  List<TimeOfDay> _notificationTimes = [const TimeOfDay(hour: 9, minute: 0)];
  bool _isLoading = true;
  bool _hasExactAlarmPermission = false;

  @override
  void initState() {
    super.initState();
    _loadSettings();
    _checkPermissions();
  }

  Future<void> _checkPermissions() async {
    final status = await Permission.scheduleExactAlarm.status;
    if (mounted) {
      setState(() {
        _hasExactAlarmPermission = status.isGranted;
      });
    }
  }

  Future<void> _loadSettings() async {
    final prefs = await SharedPreferences.getInstance();
    setState(() {
      _notificationCount = prefs.getInt('notification_count') ?? 1;
      final timeStrings =
          prefs.getStringList('notification_times') ?? ['09:00'];
      _notificationTimes = timeStrings.map((t) {
        final parts = t.split(':');
        return TimeOfDay(
            hour: int.parse(parts[0]), minute: int.parse(parts[1]));
      }).toList();
      _isLoading = false;
    });
  }

  Future<void> _saveSettings() async {
    final prefs = await SharedPreferences.getInstance();
    await prefs.setInt('notification_count', _notificationCount);
    final timeStrings =
        _notificationTimes.map((t) => '${t.hour}:${t.minute}').toList();
    await prefs.setStringList('notification_times', timeStrings);
  }

  void _updateAndSaveChanges() async {
    if (!_hasExactAlarmPermission) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            backgroundColor: Colors.red,
            content: Text("Permission denied. Cannot schedule notifications.")));
        return;
    }

    final prefs = await SharedPreferences.getInstance();
    final int oldNotificationCount = prefs.getInt('notification_count') ?? 0;
    for (int i = 0; i < oldNotificationCount; i++) {
      flutterLocalNotificationsPlugin.cancel(i);
    }

    for (int i = 0; i < _notificationCount; i++) {
      String payload = '';
      if (widget.activeGoal != null) {
        final nextMilestone = widget.activeGoal!.milestones.firstWhere((m) => !m.isCompleted, orElse: () => Milestone(title: '', deadline: DateTime.now(), checkpoints: []));
        if (nextMilestone.title.isNotEmpty) {
          final nextCheckpoint = nextMilestone.checkpoints.firstWhere((c) => !nextMilestone.completedCheckpointIds.contains(c.id), orElse: () => Checkpoint(title: ''));
          if (nextCheckpoint.title.isNotEmpty) {
            payload = json.encode({
              'goalId': widget.activeGoal!.id,
              'milestoneId': nextMilestone.id,
              'checkpointId': nextCheckpoint.id,
            });
          }
        }
      }

      scheduleReminderNotification(
        i,
        'Milestone Reminder',
        'How are you doing with your goals today?',
        payload,
        _notificationTimes[i].hour,
        _notificationTimes[i].minute,
      );
    }
    _saveSettings();
    ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Notification settings saved!")));
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text("Notifications")),
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : ListView(
              padding: const EdgeInsets.all(16),
              children: [
                if (!_hasExactAlarmPermission)
                  Card(
                    color: Colors.red.shade100,
                    child: Padding(
                      padding: const EdgeInsets.all(12.0),
                      child: Column(
                        children: [
                          const Text("Permission Required", style: TextStyle(fontWeight: FontWeight.bold, color: Colors.red)),
                          const SizedBox(height: 8),
                          const Text(
                            "This app needs permission to schedule exact alarms for notifications to work correctly. Please grant this permission in your phone's settings.",
                             textAlign: TextAlign.center,
                          ),
                           const SizedBox(height: 8),
                          TextButton(onPressed: openAppSettings, child: const Text("Open Settings"))
                        ],
                      ),
                    ),
                  ),
                Text("Number of daily reminders: $_notificationCount"),
                Slider(
                  value: _notificationCount.toDouble(),
                  min: 0,
                  max: 5,
                  divisions: 5,
                  label: _notificationCount.toString(),
                  onChanged: (value) {
                    setState(() {
                      final newCount = value.toInt();
                      while (_notificationTimes.length < newCount) {
                        _notificationTimes
                            .add(const TimeOfDay(hour: 9, minute: 0));
                      }
                      while (_notificationTimes.length > newCount) {
                        _notificationTimes.removeLast();
                      }
                      _notificationCount = newCount;
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
                  onPressed: _updateAndSaveChanges,
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
            icon: Icons.track_changes_rounded,
            title: "The Power of a Clear Goal",
            content:
                "Goals give you direction and focus. They turn your dreams into a destination. When you know where you're going, you can start planning the journey. Think of it as the difference between wandering aimlessly and following a map to a hidden treasure. Every step you take is a step closer to success.",
          ),
          HelpTile(
            icon: Icons.rule_rounded,
            title: "Set Goals the SMART Way",
            content:
                'To make your goals more powerful, make them SMART:\n\nSpecific: Instead of "get fit," try "run a 5k race."\nMeasurable: Track your progress. "Run 3 times a week."\nAchievable: Start with a goal you can realistically meet.\nRelevant: Does this goal matter to you right now?\nTime-bound: Set a deadline. "Run a 5k in 3 months."',
          ),
          HelpTile(
            icon: Icons.splitscreen_rounded,
            title: "Break It Down, Build It Up",
            content:
                "Big goals can feel overwhelming. The secret is to break them into smaller, manageable tasks. Want to write a book? Start with one chapter, then one page, then one paragraph. Our app lets you create milestones and tasks for your main goal. Ticking off these small wins will keep you motivated and build momentum.",
          ),
          HelpTile(
            icon: Icons.show_chart_rounded,
            title: "Track Your Progress, Stay Motivated",
            content:
                "Seeing how far you've come is a powerful motivator. Use our app's reporting features to log your efforts and celebrate your milestones. Whether it's a chart showing your progress or a simple checklist, visual feedback makes your hard work feel real and rewarding. Don't forget to look back at your journey and see your success!",
          ),
          HelpTile(
            icon: Icons.alt_route_rounded,
            title: "Stay Flexible, Adjust as You Go",
            content:
                "Life happens! It's okay if you need to adjust your plan. A goal isn't set in stone. It's a guide, not a rule. If you miss a day or find a better approach, use our app to update your milestones or timeline. The key is to stay engaged with your goal and keep moving forward, no matter the pace.",
          ),
          HelpTile(
            icon: Icons.celebration_rounded,
            title: "Celebrate Every Victory!",
            content:
                "Don't wait until the very end to celebrate. Every step forward is a victory. Did you complete a task? Did you stick to your schedule for a week? Acknowledge your effort! Use our app's features to mark your achievements. Celebrating small wins makes the journey enjoyable and fuels your motivation for the long run.",
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
  const HelpTile(
      {super.key,
      required this.icon,
      required this.title,
      required this.content});

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
                Expanded(
                  child: Text(title,
                      style: const TextStyle(
                          fontSize: 18, fontWeight: FontWeight.bold)),
                ),
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

  Future<void> _launchURL(String urlString) async {
    final Uri url = Uri.parse(urlString);
    if (!await launchUrl(url)) {
      throw Exception('Could not launch $url');
    }
  }

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
                onTap: () => _launchURL(
                    "mailto:pachamangacorp@gmail.com?subject=Feedback for Milestone App"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.favorite_rounded, color: Colors.red),
                title: const Text("Donate"),
                subtitle: const Text("Support the development"),
                onTap: () => _launchURL(
                    "[https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing](https://drive.google.com/file/d/1b2s0u5msfpqn7finiw8Vx1ELgbWUrbW9/view?usp=sharing)"),
              ),
            ),
            Card(
              child: ListTile(
                leading: const Icon(Icons.code_rounded),
                title: const Text("Contribute"),
                subtitle: const Text("Help improve the app on GitHub"),
                onTap: () => _launchURL(
                    "[https://github.com/MossesRoss/trackit/edit/main/main.dart](https://github.com/MossesRoss/trackit/edit/main/main.dart)"),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class TimerFocusPage extends StatefulWidget {
  final Milestone milestone;
  final Function(Duration) onSessionComplete;
  const TimerFocusPage(
      {super.key, required this.milestone, required this.onSessionComplete});

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
    showFocusNotification(widget.milestone.title);
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
    cancelFocusNotification();
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

  Future<bool> _showExitConfirmation() async {
    _timer?.cancel();
    final result = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text("End Focus Session?"),
        content: Text(
            "You've focused for ${_formatTime(_seconds)}. Do you want to add this time to your milestone?"),
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

    if (result == true) {
      widget.onSessionComplete(Duration(seconds: _seconds));
      if (mounted) Navigator.of(context).pop();
      return false;
    } else if (result == false) {
      if (mounted) Navigator.of(context).pop();
      return false;
    } else {
      _startTimer();
      return false;
    }
  }

  @override
  Widget build(BuildContext context) {
    return WillPopScope(
      onWillPop: _showExitConfirmation,
      child: Scaffold(
        backgroundColor: Theme.of(context).scaffoldBackgroundColor,
        body: GestureDetector(
          onLongPress: () => _showExitConfirmation(),
          child: Stack(
            children: [
              Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Text("Focusing on:",
                        style: TextStyle(
                            fontSize: 20, color: Colors.grey.shade500)),
                    const SizedBox(height: 8),
                    Text(
                      widget.milestone.title,
                      style: TextStyle(
                          fontSize: 28,
                          fontWeight: FontWeight.bold,
                          color: Theme.of(context).colorScheme.primary),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 40),
                    Text(_formatTime(_seconds),
                        style: const TextStyle(
                            fontSize: 72,
                            fontWeight: FontWeight.bold,
                            fontFamily: 'monospace')),
                  ],
                ),
              ),
              Positioned(
                bottom: 40,
                left: 20,
                right: 20,
                child: Text(
                    "Long-press or use back button to end session",
                    textAlign: TextAlign.center,
                    style: TextStyle(color: Colors.grey.shade500)),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

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
              titleStyle: const TextStyle(
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                  color: Colors.white)),
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

class GoalSetterCard extends StatefulWidget {
  final Function(String) onSetGoal;
  final bool isNewGoal;
  const GoalSetterCard(
      {super.key, required this.onSetGoal, this.isNewGoal = false});

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
              const Text("Previous Goal Achieved!",
                  style: TextStyle(
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                      color: Colors.green)),
            const SizedBox(height: 8),
            Text(
                widget.isNewGoal
                    ? "What's your next big goal?"
                    : "What is your main goal?",
                style:
                    const TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
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

class MilestoneNode extends StatelessWidget {
  final Milestone milestone;
  final bool isFirst;
  final bool isLast;
  final Function(Milestone, String) onToggleCheckpoint;
  final VoidCallback onDelete;
  final bool editMode;

  const MilestoneNode(
      {super.key,
      required this.milestone,
      required this.isFirst,
      required this.isLast,
      required this.onToggleCheckpoint,
      required this.onDelete,
      required this.editMode});

  String _formatDuration(Duration duration) {
    if (duration.inMinutes == 0) return "${duration.inSeconds}s";
    if (duration.inHours == 0)
      return "${duration.inMinutes}m ${duration.inSeconds.remainder(60)}s";
    return "${duration.inHours}h ${duration.inMinutes.remainder(60)}m";
  }

  Future<void> _confirmToggle(
      BuildContext context, Checkpoint checkpoint) async {
    if (editMode) {
      onToggleCheckpoint(milestone, checkpoint.id);
      return;
    }
    final confirm = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: Text(milestone.completedCheckpointIds.contains(checkpoint.id)
            ? "Mark as Incomplete?"
            : "Mark as Complete?"),
        content:
            const Text("Are you sure you want to change the status of this task?"),
        actions: [
          TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text("Cancel")),
          TextButton(
              onPressed: () => Navigator.of(context).pop(true),
              child: const Text("Confirm")),
        ],
      ),
    );
    if (confirm == true) {
      onToggleCheckpoint(milestone, checkpoint.id);
    }
  }

  void _confirmDelete(BuildContext context) {
    showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('Delete Milestone?'),
        content: Text(
            "Are you sure you want to delete '${milestone.title}'? This action cannot be undone."),
        actions: <Widget>[
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child: const Text('Cancel'),
          ),
          TextButton(
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('Delete', style: TextStyle(color: Colors.red)),
          ),
        ],
      ),
    ).then((confirmed) {
      if (confirmed == true) {
        onDelete();
      }
    });
  }

  @override
  Widget build(BuildContext context) {
    final Color primaryColor = milestone.isCompleted
        ? Colors.green
        : milestone.isUnlocked
            ? Theme.of(context).colorScheme.primary
            : Colors.grey;
    final Color lightColor = milestone.isCompleted
        ? Colors.green.shade100
        : milestone.isUnlocked
            ? Theme.of(context).colorScheme.primary.withOpacity(0.1)
            : Colors.grey.shade200;

    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        SizedBox(
          width: 40,
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              CustomPaint(
                size: const Size(2, 80),
                painter: LinePainter(isFirst: isFirst, isLast: isLast),
              ),
              Container(
                width: 20,
                height: 20,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: primaryColor,
                ),
                child: Icon(
                  milestone.isCompleted
                      ? Icons.check_rounded
                      : milestone.isUnlocked
                          ? Icons.flag_rounded
                          : Icons.lock_rounded,
                  color: Colors.white,
                  size: 12,
                ),
              ),
            ],
          ),
        ),
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
                title: Text(milestone.title,
                    style: TextStyle(
                        fontWeight: FontWeight.bold,
                        color: milestone.isUnlocked ? null : Colors.grey)),
                subtitle: Row(
                  children: [
                    Text('Due: ${DateFormat.yMMMd().format(milestone.deadline)}'),
                    const Spacer(),
                    if (milestone.timeSpent > Duration.zero) ...[
                      Icon(Icons.timer_outlined,
                          size: 14, color: Colors.grey.shade600),
                      const SizedBox(width: 4),
                      Text(_formatDuration(milestone.timeSpent),
                          style: TextStyle(color: Colors.grey.shade600)),
                    ]
                  ],
                ),
                trailing:
                    milestone.isUnlocked ? null : const SizedBox.shrink(),
                children: [
                  Padding(
                    padding: const EdgeInsets.all(16.0).copyWith(top: 0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        if (milestone.checkpoints.isNotEmpty) ...[
                          LinearProgressIndicator(
                            value: milestone.progress,
                            backgroundColor: Colors.grey.shade300,
                            valueColor:
                                AlwaysStoppedAnimation<Color>(primaryColor),
                          ),
                          const SizedBox(height: 16),
                        ],
                        Column(
                          children: milestone.checkpoints
                              .map((task) => CheckboxListTile(
                                    value: milestone.completedCheckpointIds
                                        .contains(task.id),
                                    title: Text(task.title,
                                        style: TextStyle(
                                            decoration: milestone
                                                    .completedCheckpointIds
                                                    .contains(task.id)
                                                ? TextDecoration.lineThrough
                                                : null)),
                                    onChanged: milestone.isUnlocked
                                        ? (val) =>
                                            _confirmToggle(context, task)
                                        : null,
                                    dense: true,
                                    contentPadding: EdgeInsets.zero,
                                    activeColor: primaryColor,
                                  ))
                              .toList(),
                        ),
                        if (editMode)
                          Align(
                            alignment: Alignment.centerRight,
                            child: TextButton(
                              onPressed: () => _confirmDelete(context),
                              child: const Text("Delete",
                                  style: TextStyle(color: Colors.red)),
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
    );
  }
}

class LinePainter extends CustomPainter {
  final bool isFirst;
  final bool isLast;
  LinePainter({required this.isFirst, required this.isLast});

  @override
  void paint(Canvas canvas, Size size) {
    final paint = Paint()
      ..color = Colors.grey.shade300
      ..strokeWidth = 2;
    
    if (!isFirst) {
      canvas.drawLine(Offset(size.width / 2, 0), Offset(size.width / 2, size.height / 2 - 10), paint);
    }
    if (!isLast) {
      canvas.drawLine(Offset(size.width / 2, size.height / 2 + 10), Offset(size.width / 2, size.height), paint);
    }
  }

  @override
  bool shouldRepaint(covariant CustomPainter oldDelegate) => false;
}


class AddMilestoneForm extends StatefulWidget {
  final Function(Milestone) onAdd;
  final String goalTitle;
  const AddMilestoneForm(
      {super.key, required this.onAdd, required this.goalTitle});

  @override
  State<AddMilestoneForm> createState() => _AddMilestoneFormState();
}

class _AddMilestoneFormState extends State<AddMilestoneForm> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _tasksController = TextEditingController();
  DateTime? _selectedDate;
  bool _dateSubmittedOnce = false;
  bool _isSuggestingTasks = false;

  Future<void> _pickDate() async {
    final pickedDate = await showDatePicker(
      context: context,
      initialDate: _selectedDate ?? DateTime.now(),
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (pickedDate != null && pickedDate != _selectedDate) {
      setState(() {
        _selectedDate = pickedDate;
      });
    }
  }

  Future<void> _getTaskSuggestions() async {
    if (_titleController.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text("Please enter a milestone title first."),
        backgroundColor: Colors.orange,
      ));
      return;
    }
    setState(() => _isSuggestingTasks = true);
    final suggestions = await SuggestionService.getTaskSuggestions(
        widget.goalTitle, _titleController.text.trim());
    if (mounted) {
      setState(() {
        if (suggestions.isNotEmpty) {
          _tasksController.text = suggestions.join('\n');
        } else {
          ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Could not get suggestions. Please check your connection or API key."),
            backgroundColor: Colors.red,
          ));
        }
        _isSuggestingTasks = false;
      });
    }
  }

  void _submit() {
    setState(() {
      _dateSubmittedOnce = true;
    });

    if (!_formKey.currentState!.validate() || _selectedDate == null) {
      return;
    }
    
    _createMilestone();
  }

  void _createMilestone() {
    final checkpoints = _tasksController.text
        .split('\n')
        .where((s) => s.trim().isNotEmpty)
        .map((title) => Checkpoint(title: title))
        .toList();

    final newMilestone = Milestone(
      title: _titleController.text,
      deadline: _selectedDate!,
      checkpoints: checkpoints,
    );
    widget.onAdd(newMilestone);
    Navigator.pop(context);
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
            const Text("New Milestone",
                style: TextStyle(fontSize: 20, fontWeight: FontWeight.bold)),
            const SizedBox(height: 20),
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                  labelText: 'Title', border: OutlineInputBorder()),
              validator: (value) => value == null || value.isEmpty
                  ? 'Please enter a title'
                  : null,
            ),
            const SizedBox(height: 16),
            TextFormField(
              controller: _tasksController,
              decoration: const InputDecoration(
                  labelText: 'Tasks (one per line)',
                  border: OutlineInputBorder()),
              maxLines: 3,
            ),
            Align(
              alignment: Alignment.centerRight,
              child: _isSuggestingTasks
                  ? const Padding(
                      padding: EdgeInsets.all(8.0),
                      child: SizedBox(
                          height: 20,
                          width: 20,
                          child: CircularProgressIndicator(strokeWidth: 2)),
                    )
                  : TextButton.icon(
                      onPressed: _getTaskSuggestions,
                      icon: const Icon(Icons.auto_awesome_rounded, size: 16),
                      label: const Text("Suggest Tasks"),
                    ),
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                Expanded(
                  child: Text(
                    _selectedDate == null
                        ? 'No date chosen'
                        : 'Due: ${DateFormat.yMMMd().format(_selectedDate!)}',
                    style: TextStyle(
                      color: _selectedDate == null && _dateSubmittedOnce
                          ? Colors.red
                          : null,
                    ),
                  ),
                ),
                TextButton(
                    onPressed: _pickDate, child: const Text('Choose Date')),
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

